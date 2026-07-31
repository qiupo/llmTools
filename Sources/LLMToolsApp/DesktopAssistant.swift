import AppKit
import SwiftUI
import LLMToolsCore

private struct AssistantBackgroundTimeout: LocalizedError {
    var errorDescription: String? { "Desktop assistant local model timed out." }
}

private struct AssistantQualificationTimeout: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

fileprivate enum AssistantVisualAnalysisOutcome {
    case consumed
    case retryableFailure
    case retryableContention
    case skipped
}

private actor AssistantTimeoutRace<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        guard self.result == nil else { return false }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
        return true
    }
}

struct DesktopAssistantBridgeStatusPayload: Codable {
    var diagnosticSchemaVersion: Int
    var diagnosticSnapshotAt: Date
    var enabled: Bool
    var lifecycleMode: String
    var lifecycleVisible: Bool
    var observationAllowed: Bool
    var pauseUntil: Date?
    var foregroundObserverRunning: Bool
    var clipboardObserverRunning: Bool
    var permissionObserverRunning: Bool
    var userActivityObserverRunning: Bool
    var visualCaptureObserverRunning: Bool
    var visualCaptureTaskRunning: Bool
    var lastVisualCaptureAttemptAt: Date?
    var lastVisualCaptureAt: Date?
    var nextVisualCaptureAt: Date?
    var visualAnalysisRunning: Bool
    var contextAggregationRunning: Bool
    var contextTriggerBucketCount: Int
    var currentJudgmentPattern: String?
    var assistantWorking: Bool
    var userPresent: Bool
    var lastUserActivityAt: Date?
    var recentActivity: [AssistantDiagnosticEvent]
    var selectionSourceEnabled: Bool
    var accessibilityAuthorized: Bool
    var screenCaptureAuthorized: Bool
    var shortTermEventCount: Int
    var sourceLastUse: [String: Date]
    var behaviorStoreStatus: String
    var behaviorRecordCount: Int
    var behaviorSchemaVersion: Int
    var cardCount: Int
    var unreadCount: Int
    var candidateQueueCount: Int
    var configuredProactivity: String
    var effectiveProactivity: String
    var judgmentConfidenceThreshold: Double
    var judgmentConfidenceThresholdIsCustom: Bool
    var judgmentModelReady: Bool
    var qualifiedJudgmentModelCount: Int
    var qualificationPhase: String
    var qualificationPromptVersion: Int
    var qualificationFixtureVersion: Int
    var qualificationCacheEntryCount: Int
    var judgmentRunning: Bool
    var qualificationRunning: Bool
    var translationRunning: Bool
    var temporaryTranslationActive: Bool
    var temporaryTranslationRemainingSeconds: Int
    var userModelWorkActive: Bool
    var backgroundRecoveryPending: Bool
    var orbVisible: Bool
    var toolbarVisible: Bool
    var peekVisible: Bool
    var onboardingVisible: Bool
    var dropTargetActive: Bool
    var orbWidth: Double
    var orbHeight: Double
    var screenCount: Int
    var reduceMotionEnabled: Bool
}

enum AssistantPanelContent: Equatable {
    case none
    case inquiry
    case recent
    case card(UUID)
    case ephemeralInquiry
    case clipboard
    case dropTasks
}

@MainActor
final class AssistantContextCoordinator: ObservableObject {
    @Published private(set) var lifecycle = AssistantLifecycleMachine(preferences: .init())
    @Published private(set) var cards: [AssistantCard] = []
    @Published private(set) var panelContent: AssistantPanelContent = .none
    @Published private(set) var isInquiryRunning = false
    @Published private(set) var inquiryError: String?
    @Published var inquiryText = ""
    @Published var includeClipboardContext = false
    @Published var includeCurrentCardContext = false
    @Published var accessoryPlacement: AssistantAccessoryPlacement = .left
    @Published private(set) var toolbarKeyboardFocusToken = 0
    @Published var onboardingStep = 0
    @Published var onboardingIsReenableConfirmation = false
    @Published var draftForegroundApplicationEnabled = true
    @Published var draftEnhancedWindowContextEnabled = false
    @Published var draftSelectionContextEnabled = true
    @Published var draftClipboardAuthorization: AssistantClipboardAuthorization = .undecided
    @Published var draftUseBehaviorHistory = true
    @Published private(set) var dropClassification: AssistantDropClassification?
    @Published private(set) var pendingDropPayload: AssistantDropPayload?
    @Published private(set) var lastSourceUse: [AssistantSource: Date] = [:]
    @Published fileprivate(set) var accessibilityAuthorized = AXIsProcessTrusted()
    @Published fileprivate(set) var screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
    @Published private(set) var behaviorSummary = AssistantBehaviorStoreSummary(
        status: .ready,
        recordCount: 0,
        earliestDate: nil,
        latestDate: nil,
        byteCount: 0,
        schemaVersion: AssistantBehaviorStore.currentSchemaVersion
    )
    @Published private(set) var pendingProactivity: AssistantProactivity?
    @Published private(set) var qualificationProgress = AssistantQualificationProgress()
    @Published private(set) var assistantLocalTextModels: [ModelDescriptor] = []
    @Published private(set) var qualifiedJudgmentModels: [ModelDescriptor] = []
    @Published private(set) var qualificationStates: [UUID: AssistantQualificationState] = [:]
    @Published private(set) var currentJudgmentModelID: UUID?
    @Published private(set) var currentJudgmentModelName: String?
    @Published private(set) var sessionProactivityWasDowngraded = false
    @Published private(set) var proactiveSuggestionsPaused = false
    @Published private(set) var temporaryTranslationExpiresAt: Date?
    @Published private(set) var patternDisableUndo: AssistantPatternType?
    @Published private(set) var diagnosticSnapshot: DesktopAssistantBridgeStatusPayload?
    @Published private(set) var diagnosticExportMessage: String?
    @Published private(set) var activeDiagnosticStages = Set<AssistantDiagnosticStage>()
    @Published private(set) var userIsPresent = false
    @Published private(set) var lastUserActivityAt: Date?

    let appState: AppState
    weak var windowController: FloatingAssistantWindowController?
    var onOpenQuickAction: ((String?) -> Void)?
    var onOpenQuickActionTask: ((String, TaskKind) -> Void)?
    var onReturnToWorkbench: ((AssistantWorkbenchRoute) -> Void)?
    var onRunDroppedText: ((AssistantDropPayload, TaskKind) -> Bool)?
    var onOpenDroppedImage: ((URL, OCRMode) -> Bool)?
    var onOpenDroppedMedia: ((URL, SubtitleDisplayMode) -> Bool)?
    var onOpenSettings: (() -> Void)?
    var onOpenModelSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let cardStore = AssistantCardStore()
    private let contextBuffer = AssistantContextBuffer()
    private let fingerprintStore = AssistantFingerprintStore()
    private let patternDetector = AssistantPatternDetector()
    private lazy var behaviorStore = AssistantBehaviorStore(fingerprintStore: fingerprintStore)
    private lazy var activityObserver = AssistantActivityObserver(coordinator: self)
    private var inquiryTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var behaviorLoadTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var contextMaintenanceTask: Task<Void, Never>?
    private var cardClearTask: Task<Void, Never>?
    private var judgmentTask: Task<Void, Never>?
    private var qualificationTask: Task<Void, Never>?
    private var qualificationRefreshTask: Task<Bool, Never>?
    private var proactivityRequestTask: Task<Void, Never>?
    private var contextOpportunityTask: Task<Void, Never>?
    private var contextOpportunityDebounceStartedAt: Date?
    private var pendingContextOpportunityBatch = AssistantContextOpportunityBatch()
    private var contextOpportunityGeneration: UInt64 = 0
    private var peekTimeoutTask: Task<Void, Never>?
    private var pendingPresentationTask: Task<Void, Never>?
    private var pendingPresentationGeneration: UInt64 = 0
    private var translationTask: Task<Void, Never>?
    private var translationExpiryTask: Task<Void, Never>?
    private var patternUndoTask: Task<Void, Never>?
    private var backgroundRecoveryTask: Task<Void, Never>?
    private var backgroundWorkArbiter = AssistantBackgroundWorkArbiter()
    private var backgroundOperationCounts: [UUID: Int] = [:]
    private var finishedBackgroundWorkflows = Set<UUID>()
    private var timedOutBackgroundOperationIDs = Set<UUID>()
    private var diagnosticTimeline = AssistantDiagnosticTimeline()
    private var visualAnalysisRunning = false
    private var contextEpoch: UInt64 = 0
    private var behaviorEpoch: UInt64 = 0
    private var cardEpoch: UInt64 = 0
    private var maintenanceGeneration: UInt64 = 0
    private var hasBootstrapped = false
    private var ephemeralInquiryCard: AssistantCard?
    private var ephemeralInquiryHandoff: String?
    private var isStageAPreview = false
    private var appliedPreferences = DesktopAssistantPreferences()
    private var candidateQueue = AssistantCandidateQueue()
    private var candidateBehaviorEpochs: [UUID: UInt64] = [:]
    private var candidateContextEpochs: [UUID: UInt64] = [:]
    private var candidateCardEpochs: [UUID: UInt64] = [:]
    private var candidatesToBadgeAfterPreemption = Set<UUID>()
    private var sessionProactivity = AssistantSessionProactivityState(configured: .moderate)
    private var currentQualificationSummaries: [UUID: AssistantQualificationSummary] = [:]
    private var qualificationRun: AssistantQualificationRun?
    private var qualificationPauseRequested = false
    private var qualificationGeneration: UInt64 = 0
    private var qualificationStateRevision: UInt64 = 0
    private var userModelWorkIsActive = false
    private var proactivePresentationDates: [Date] = []
    private var badgeGroupDates: [Date] = []
    private var cardRawContextReferences: [UUID: UUID] = [:]
    private var workbenchRoutesByRawContext: [UUID: AssistantWorkbenchRoute] = [:]
    private var cardWorkbenchRoutes: [UUID: AssistantWorkbenchRoute] = [:]
    private var cardForeignLanguages: [UUID: String] = [:]
    private var cardOpportunityQuotes: [UUID: String] = [:]
    private var cardOpportunityTasks: [UUID: TaskKind] = [:]
    private var cardAppIdentities: [UUID: String] = [:]
    private var cardBehaviorRecordIDs: [UUID: UUID] = [:]
    private var cardsIncludingJoke = Set<UUID>()
    private var proactivelyPresentedCardIDs = Set<UUID>()
    private var proactiveOriginCardIDs = Set<UUID>()
    private var settledSessionFeedbackByCard: [UUID: AssistantFeedback] = [:]
    private var currentProactiveCardID: UUID?
    private var currentJudgmentCandidate: AssistantPatternCandidate?
    private var pendingPresentations: [String: AssistantPendingPresentation] = [:]
    private var temporaryTranslationSession = AssistantTemporaryTranslationSession()
    private var pendingTranslations: [AssistantPendingTranslation] = []
    private var activeTranslation: AssistantPendingTranslation?
    private var deferredFullscreenTranslationCardID: UUID?
    private var temporaryTranslationOriginRecordID: UUID?
    private var observedClipboardChangeCount: Int?
    private var observedClipboardSensitivity: AssistantSensitivity = .sensitive
    private var qualificationProactivityState = AssistantQualificationProactivityState()
    private var lastVisionAnalysisAt = Date.distantPast

    private struct AssistantQualificationRun {
        var id: UUID
        var model: ModelDescriptor
        var modelFingerprint: String
        var samples: [AssistantQualificationSample]
    }

    private struct AssistantPendingTranslation {
        var text: String
        var language: String
        var occurredAt: Date
        var expiresAt: Date
        var rawContextReference: UUID
        var requiresActiveSession: Bool
        var sourceCardID: UUID?
    }

    private struct AssistantPendingPresentation {
        var candidate: AssistantPatternCandidate
        var presentation: AssistantPresentation
        var actionIDs: [AssistantActionID]
        var judgmentModelID: UUID?
        var judgmentConfidence: Double?
        var lockedEvidenceQuote: String?
        var suggestedTask: TaskKind?
        var comment: String
    }

    init(appState: AppState) {
        self.appState = appState
    }

    var language: AppLanguage { appState.preferences.appLanguage }
    var preferences: DesktopAssistantPreferences { appState.preferences.desktopAssistant }
    var unreadCount: Int {
        cards.lazy.filter { $0.state == .unread && $0.requiresUserAction }.count
    }
    var assistantIsWorking: Bool {
        isInquiryRunning || !activeDiagnosticStages.isEmpty
    }
    fileprivate var backgroundAssistantRoundIsRunning: Bool {
        judgmentTask != nil
            || candidateQueue.count > 0
            || backgroundWorkArbiter.activeLease != nil
            || backgroundRecoveryTask != nil
            || !timedOutBackgroundOperationIDs.isEmpty
            || userModelWorkIsActive
            || maintenanceTask != nil
    }
    fileprivate var visualContextAnalysisIsEnabled: Bool {
        currentJudgmentModelID != nil
            && hasUsableDesktopAssistantVisionModel
            && (effectiveProactivity == .moderate || effectiveProactivity == .active)
    }
    private var visualContextAnalysisDisableReason: String {
        if currentJudgmentModelID == nil { return "no-qualified-model" }
        if !hasUsableDesktopAssistantVisionModel { return "no-vision-model" }
        if proactiveSuggestionsPaused { return "proactivity-paused" }
        if sessionProactivityWasDowngraded { return "proactivity-session-downgraded" }
        return "proactivity-inactive"
    }
    private var hasUsableDesktopAssistantVisionModel: Bool {
        appState.models.contains { model in
            model.isAvailableForUse
                && !model.isRemoteProvider
                && model.format == .mlx
                && model.capabilities.supportsText
                && model.capabilities.supportsImage
                && !ModelDetection.isGLMOCRModel(at: model.resolvedPath ?? model.sourcePath)
        }
    }
    var selectedCard: AssistantCard? {
        if case .ephemeralInquiry = panelContent { return ephemeralInquiryCard }
        guard case .card(let id) = panelContent else { return nil }
        return cards.first { $0.id == id }
    }
    var selectedCardUsesSpeechBubble: Bool {
        selectedCard?.prefersSpeechBubblePresentation == true
    }
    var preferredPeekSize: CGSize {
        CGSize(
            width: selectedCardUsesSpeechBubble ? AssistantWindowGeometry.speechBubbleWidth : 320,
            height: preferredPeekHeight
        )
    }
    var preferredPeekHeight: CGFloat {
        switch panelContent {
        case .none:
            return 166
        case .inquiry:
            let contextHeight: CGFloat = canAttachClipboard || canAttachCurrentCard ? 22 : 0
            let errorHeight: CGFloat = inquiryError == nil ? 0 : 20
            return min(220, 166 + contextHeight + errorHeight)
        case .card, .ephemeralInquiry:
            guard let card = selectedCard else { return 166 }
            if card.prefersSpeechBubblePresentation {
                let charactersPerLine = language == .chinese ? 15 : 30
                let lineCount = max(1, Int(ceil(Double(card.comment.count) / Double(charactersPerLine))))
                return min(
                    AssistantWindowGeometry.speechBubbleMaximumHeight,
                    max(
                        AssistantWindowGeometry.speechBubbleMinimumHeight,
                        36 + CGFloat(lineCount) * 20
                    )
                )
            }
            let body = card.source == .inquiry ? (card.detailText ?? card.comment) : card.comment
            let bodyLines = max(1, Int(ceil(Double(body.count) / 34)))
            let evidenceHeight: CGFloat = card.source == .inquiry || card.evidenceSummary?.isEmpty != false ? 0 : 16
            return min(220, max(154, 120 + CGFloat(bodyLines) * 17 + evidenceHeight))
        case .clipboard:
            return 176
        case .dropTasks:
            return 200
        case .recent:
            return 220
        }
    }
    var canAttachCurrentCard: Bool {
        attachableCurrentCard != nil
    }
    var canAttachClipboard: Bool {
        guard let value = NSPasteboard.general.string(forType: .string) else { return false }
        return clipboardIsSafeForExplicitUse(value)
    }
    var effectiveProactivity: AssistantProactivity {
        if proactiveSuggestionsPaused { return .quiet }
        let sessionValue = sessionProactivity.effective
        if sessionValue == .moderate || sessionValue == .active {
            return currentJudgmentModelID == nil ? .quiet : sessionValue
        }
        return sessionValue
    }
    var temporaryTranslationIsActive: Bool {
        guard let expiresAt = temporaryTranslationExpiresAt else { return false }
        return expiresAt > .now
    }

    func bridgeStatusPayload() async -> DesktopAssistantBridgeStatusPayload {
        let observer = activityObserver.diagnosticStatus
        let window = windowController?.diagnosticStatus
        let qualificationPhase: String = switch qualificationProgress.phase {
        case .idle: "idle"
        case .preparing: "preparing"
        case .running: "running"
        case .paused: "paused"
        case .qualified: "qualified"
        case .unqualified: "unqualified"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
        return DesktopAssistantBridgeStatusPayload(
            diagnosticSchemaVersion: 4,
            diagnosticSnapshotAt: .now,
            enabled: preferences.isEnabled,
            lifecycleMode: lifecycle.mode.rawValue,
            lifecycleVisible: lifecycle.isVisible,
            observationAllowed: lifecycle.observationIsAllowed,
            pauseUntil: lifecycle.pauseUntil,
            foregroundObserverRunning: observer.foreground,
            clipboardObserverRunning: observer.clipboard,
            permissionObserverRunning: observer.permission,
            userActivityObserverRunning: observer.userActivity,
            visualCaptureObserverRunning: observer.visualCapture,
            visualCaptureTaskRunning: observer.visualCaptureTaskRunning,
            lastVisualCaptureAttemptAt: observer.lastVisualCaptureAttemptAt,
            lastVisualCaptureAt: observer.lastVisualCaptureAt,
            nextVisualCaptureAt: observer.nextVisualCaptureAt,
            visualAnalysisRunning: visualAnalysisRunning,
            contextAggregationRunning: contextOpportunityTask != nil,
            contextTriggerBucketCount: pendingContextOpportunityBatch.count,
            currentJudgmentPattern: currentJudgmentCandidate?.patternType.rawValue,
            assistantWorking: assistantIsWorking,
            userPresent: userIsPresent,
            lastUserActivityAt: lastUserActivityAt,
            recentActivity: diagnosticTimeline.events,
            selectionSourceEnabled: observer.selection,
            accessibilityAuthorized: accessibilityAuthorized,
            screenCaptureAuthorized: screenCaptureAuthorized,
            shortTermEventCount: await contextBuffer.snapshot().count,
            sourceLastUse: Dictionary(uniqueKeysWithValues: lastSourceUse.map { ($0.key.rawValue, $0.value) }),
            behaviorStoreStatus: behaviorSummary.status.rawValue,
            behaviorRecordCount: behaviorSummary.recordCount,
            behaviorSchemaVersion: behaviorSummary.schemaVersion,
            cardCount: cards.count,
            unreadCount: unreadCount,
            candidateQueueCount: candidateQueue.count,
            configuredProactivity: preferences.proactivity.rawValue,
            effectiveProactivity: effectiveProactivity.rawValue,
            judgmentConfidenceThreshold: AssistantJudgmentContract.minimumConfidence(
                for: effectiveProactivity,
                override: preferences.judgmentConfidenceThresholdOverride
            ),
            judgmentConfidenceThresholdIsCustom: preferences.judgmentConfidenceThresholdOverride != nil,
            judgmentModelReady: currentJudgmentModelID != nil,
            qualifiedJudgmentModelCount: qualifiedJudgmentModels.count,
            qualificationPhase: qualificationPhase,
            qualificationPromptVersion: AssistantJudgmentContract.promptVersion,
            qualificationFixtureVersion: AssistantJudgmentFixtures.version,
            qualificationCacheEntryCount: preferences.qualificationCache.count,
            judgmentRunning: judgmentTask != nil,
            qualificationRunning: qualificationTask != nil,
            translationRunning: translationTask != nil,
            temporaryTranslationActive: temporaryTranslationIsActive,
            temporaryTranslationRemainingSeconds: max(0, Int(temporaryTranslationExpiresAt?.timeIntervalSinceNow ?? 0)),
            userModelWorkActive: userModelWorkIsActive,
            backgroundRecoveryPending: backgroundRecoveryTask != nil || !timedOutBackgroundOperationIDs.isEmpty,
            orbVisible: window?.orbVisible ?? false,
            toolbarVisible: window?.toolbarVisible ?? false,
            peekVisible: window?.peekVisible ?? false,
            onboardingVisible: window?.onboardingVisible ?? false,
            dropTargetActive: window?.dropTargetActive ?? false,
            orbWidth: Double(window?.orbSize.width ?? 0),
            orbHeight: Double(window?.orbSize.height ?? 0),
            screenCount: NSScreen.screens.count,
            reduceMotionEnabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    fileprivate func recordDiagnosticActivity(
        stage: AssistantDiagnosticStage,
        state: AssistantDiagnosticState,
        detail: String
    ) {
        if state == .scheduled {
            diagnosticTimeline.refreshScheduled(stage: stage, detail: detail)
        } else {
            diagnosticTimeline.append(stage: stage, state: state, detail: detail)
        }
        guard [.capture, .vision, .judgment, .comment].contains(stage) else { return }
        var stages = activeDiagnosticStages
        switch state {
        case .running:
            stages.insert(stage)
        case .succeeded, .skipped, .failed, .cancelled:
            stages.remove(stage)
        case .scheduled, .queued:
            break
        }
        if stages != activeDiagnosticStages { activeDiagnosticStages = stages }
    }

    private func skipVisualAnalysis(_ detail: String) -> AssistantVisualAnalysisOutcome {
        recordDiagnosticActivity(stage: .vision, state: .skipped, detail: detail)
        return .skipped
    }

    func refreshDiagnosticSnapshot() async {
        diagnosticSnapshot = await bridgeStatusPayload()
    }

    func exportDiagnosticJSON() async {
        let payload = await bridgeStatusPayload()
        diagnosticSnapshot = payload
        do {
            let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? AppPaths.applicationSupportDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("llmtools-assistant-diagnostics-\(timestamp).json")
            try diagnosticExportData(payload).write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            diagnosticExportMessage = text(
                "已导出（含最近活动 \(payload.recentActivity.count) 条）到 \(url.path)",
                "Exported with \(payload.recentActivity.count) recent activities to \(url.path)"
            )
        } catch {
            diagnosticExportMessage = error.localizedDescription
        }
    }

    private func diagnosticExportData(_ payload: DesktopAssistantBridgeStatusPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(payload)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw EncodingError.invalidValue(
                payload,
                .init(codingPath: [], debugDescription: "Desktop assistant diagnostics did not encode as an object.")
            )
        }
        let timestamp = ISO8601DateFormatter()
        // 保留 recentActivity 机器字段，另附界面同款的可读解释，方便人工排查又不影响脚本解析。
        object["recentActivityDescriptions"] = payload.recentActivity.map { event in
            [
                "occurredAt": timestamp.string(from: event.occurredAt),
                "stage": event.stage.localizedName(language: language),
                "state": event.state.localizedName(language: language),
                "explanation": event.localizedExplanation(language: language) ?? event.detail,
                "machineDetail": event.detail
            ]
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private var privacyPolicy: AssistantPrivacyPolicy {
        AssistantPrivacyPolicy(excludedApplicationBundleIDs: preferences.excludedApplicationBundleIDs)
    }

    func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }

    func refreshPermissionStatus() {
        accessibilityAuthorized = AXIsProcessTrusted()
        screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
    }

    func bootstrap() async {
        lifecycle = AssistantLifecycleMachine(preferences: preferences)
        sessionProactivity = AssistantSessionProactivityState(configured: preferences.proactivity)
        appliedPreferences = preferences
        windowController?.applyPreferences(preferences)
        if lifecycle.isVisible {
            windowController?.showOrb()
        } else {
            windowController?.hideAllAssistantWindows()
        }
        if preferences.isEnabled, preferences.hasCompletedCurrentOnboarding {
            // 首次完成引导即准备 0600 指纹密钥，不等待第一条观察内容到达。
            try? await fingerprintStore.ensureKey()
            _ = await behaviorStore.load()
            behaviorSummary = await behaviorStore.summary()
        }
        userModelWorkIsActive = appState.assistantUserModelWorkIsActive
        _ = await recomputeQualificationStates()
        hasBootstrapped = true
        if preferences.isEnabled, preferences.hasCompletedCurrentOnboarding {
            let usesEnhancedWindowContext = preferences.foregroundApplicationContextEnabled
                && preferences.enhancedWindowContextEnabled
            SelectedTextService.showPermissionGuideIfNeeded(
                requiresAccessibility: usesEnhancedWindowContext || preferences.selectionContextEnabled,
                requiresScreenRecording: usesEnhancedWindowContext
            )
        }
        refreshObservation(loadBehaviorStore: false)
    }

    func preferencesDidChange(_ preferences: DesktopAssistantPreferences) {
        let previous = appliedPreferences
        let previouslyUsedEnhancedWindowContext = previous.foregroundApplicationContextEnabled
            && previous.enhancedWindowContextEnabled
        let nowUsesEnhancedWindowContext = preferences.foregroundApplicationContextEnabled
            && preferences.enhancedWindowContextEnabled
        let newlyExcluded = Set(preferences.excludedApplicationBundleIDs)
            .subtracting(appliedPreferences.excludedApplicationBundleIDs)
        if !newlyExcluded.isEmpty {
            observedClipboardChangeCount = nil
            observedClipboardSensitivity = .sensitive
            newlyExcluded.forEach(clearContext(appIdentity:))
            cancelCandidateJudgment(discardQueue: true)
            stopTemporaryTranslation()
            Task { await patternDetector.clear() }
        }
        if previous.clipboardAuthorization == .allowed,
           preferences.clipboardAuthorization != .allowed {
            clearContext(source: .clipboard)
        }
        if hasBootstrapped {
            SelectedTextService.showPermissionGuideIfNeeded(
                requiresAccessibility: !previouslyUsedEnhancedWindowContext && nowUsesEnhancedWindowContext
                    || !appliedPreferences.selectionContextEnabled && preferences.selectionContextEnabled,
                requiresScreenRecording: !previouslyUsedEnhancedWindowContext && nowUsesEnhancedWindowContext
            )
        }
        appliedPreferences = preferences
        if previous.proactivity != preferences.proactivity {
            sessionProactivity.updateConfigured(preferences.proactivity)
            sessionProactivityWasDowngraded = false
        }
        if !visualContextAnalysisIsEnabled {
            activityObserver.cancelPendingVisualCapture(reason: visualContextAnalysisDisableReason)
        }
        if previous.repeatedFailureEnabled, !preferences.repeatedFailureEnabled {
            cancelCandidateJudgment(discardQueue: true)
            discardAllCandidateTracking()
            Task { await patternDetector.clear(pattern: .repeatedFailure) }
        }
        if previous.foreignClipboardEnabled, !preferences.foreignClipboardEnabled {
            cancelCandidateJudgment(discardQueue: true)
            discardAllCandidateTracking()
            stopTemporaryTranslation()
            Task { await patternDetector.clear(pattern: .foreignClipboard) }
        }
        if previous.judgmentModelID != preferences.judgmentModelID
            || previous.qualificationCache != preferences.qualificationCache {
            refreshQualificationStates()
        }
        windowController?.applyPreferences(preferences)
        guard !isStageAPreview else { return }
        if !preferences.isEnabled, lifecycle.mode != .disabled, lifecycle.mode != .onboarding {
            lifecycle.apply(.disable)
            stopObservationAndClearContext()
            windowController?.hideAllAssistantWindows()
        }
        // @Published 在 willSet 阶段发送新值；必须直接使用回调参数，避免观察器配置落后一拍。
        refreshObservation(loadBehaviorStore: false, preferences: preferences)
    }

    func requestEnable() {
        if preferences.hasCompletedCurrentOnboarding {
            prepareReenableConfirmation()
        } else {
            lifecycle.apply(.requestEnable)
            prepareFirstOnboarding()
        }
        windowController?.showOnboarding()
    }

    func prepareFirstOnboarding() {
        onboardingIsReenableConfirmation = false
        onboardingStep = 0
        draftForegroundApplicationEnabled = true
        draftEnhancedWindowContextEnabled = false
        draftSelectionContextEnabled = true
        draftClipboardAuthorization = .undecided
        draftUseBehaviorHistory = true
    }

    func prepareReenableConfirmation() {
        onboardingIsReenableConfirmation = true
        onboardingStep = 0
        draftForegroundApplicationEnabled = preferences.foregroundApplicationContextEnabled
        draftEnhancedWindowContextEnabled = preferences.enhancedWindowContextEnabled
        draftSelectionContextEnabled = preferences.selectionContextEnabled
        draftClipboardAuthorization = preferences.clipboardAuthorization
        draftUseBehaviorHistory = preferences.useBehaviorHistory
    }

    func useManualOnlyPreset() {
        draftForegroundApplicationEnabled = false
        draftEnhancedWindowContextEnabled = false
        draftSelectionContextEnabled = false
        draftClipboardAuthorization = .denied
        onboardingStep = 2
    }

    func finishOnboarding() {
        guard draftClipboardAuthorization != .undecided else { return }
        let usesManualOnly = !draftForegroundApplicationEnabled
            && !draftSelectionContextEnabled
            && draftClipboardAuthorization != .allowed
        let initialProactivity: AssistantProactivity = usesManualOnly ? .manual : .moderate
        lifecycle.apply(.finishOnboarding)
        appState.updatePreferences { preferences in
            preferences.desktopAssistant.isEnabled = true
            preferences.desktopAssistant.completedOnboardingVersion = DesktopAssistantPreferences.currentOnboardingVersion
            preferences.desktopAssistant.foregroundApplicationContextEnabled = self.draftForegroundApplicationEnabled
            preferences.desktopAssistant.enhancedWindowContextEnabled = self.draftEnhancedWindowContextEnabled
            preferences.desktopAssistant.selectionContextEnabled = self.draftSelectionContextEnabled
            preferences.desktopAssistant.clipboardAuthorization = self.draftClipboardAuthorization
            preferences.desktopAssistant.useBehaviorHistory = self.draftUseBehaviorHistory
            preferences.desktopAssistant.proactivity = initialProactivity
        }
        windowController?.closeOnboarding()
        windowController?.showOrb()
        requestAccessibilityForDraftSourcesIfNeeded()
        refreshObservation(loadBehaviorStore: true)
        if initialProactivity == .moderate {
            // 引导已明确说明本地 24 项检查；异步执行，失败或无模型时实际档位仍保持安静。
            requestProactivity(.moderate, automaticallyStartQualification: true)
        }
    }

    func confirmReenable() {
        appState.updatePreferences { $0.desktopAssistant.isEnabled = true }
        lifecycle = AssistantLifecycleMachine(preferences: {
            var value = preferences
            value.isEnabled = true
            return value
        }())
        windowController?.closeOnboarding()
        windowController?.showOrb()
        requestAccessibilityForDraftSourcesIfNeeded()
        refreshObservation(loadBehaviorStore: true)
    }

    func cancelOnboarding() {
        if !onboardingIsReenableConfirmation {
            lifecycle.apply(.cancelOnboarding)
        }
        windowController?.closeOnboarding()
    }

    func show() {
        guard preferences.isEnabled else {
            requestEnable()
            return
        }
        lifecycle.apply(.show)
        windowController?.showOrb()
    }

    func hide() {
        inquiryTask?.cancel()
        peekTimeoutTask?.cancel()
        if let id = currentProactiveCardID {
            proactivelyPresentedCardIDs.remove(id)
            let expectedCardEpoch = cardEpoch
            Task {
                let storedCards = await cardStore.update(id: id, state: .unread)
                commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            }
        }
        currentProactiveCardID = nil
        lifecycle.apply(.hide)
        clearPanelEphemera()
        windowController?.hideAllAssistantWindows()
    }

    func disable() {
        inquiryTask?.cancel()
        pauseTask?.cancel()
        cancelStageCWork(cancelQualification: true)
        lifecycle.apply(.disable)
        clearPanelEphemera()
        appState.updatePreferences { $0.desktopAssistant.isEnabled = false }
        stopObservationAndClearContext()
        windowController?.hideAllAssistantWindows()
    }

    func pause(until: Date) {
        cancelCandidateJudgment(discardQueue: true)
        lifecycle.apply(.pause(until: until))
        stopObservationAndClearContext()
        scheduleResume(at: until)
    }

    func resume() {
        pauseTask?.cancel()
        lifecycle.apply(.resume)
        refreshObservation(loadBehaviorStore: false)
    }

    func togglePrivacy() {
        lifecycle.apply(.setPrivacy(lifecycle.mode != .privacy))
        if lifecycle.mode == .privacy {
            cancelCandidateJudgment(discardQueue: true)
            stopObservationAndClearContext()
        } else {
            refreshObservation(loadBehaviorStore: false)
        }
    }

    func openInquiry() {
        inquiryError = nil
        inquiryText = ""
        includeClipboardContext = false
        includeCurrentCardContext = false
        panelContent = .inquiry
        windowController?.hideToolbar()
        windowController?.showPeek(activating: true)
    }

    func openRecent() {
        panelContent = .recent
        windowController?.hideToolbar()
        windowController?.showPeek(activating: false)
    }

    func openClipboardSuggestion() {
        panelContent = .clipboard
        windowController?.hideToolbar()
        windowController?.showPeek(activating: false)
    }

    func beginDropTarget(_ classification: AssistantDropClassification) {
        dropClassification = classification
    }

    func cancelDropTarget() {
        dropClassification = nil
    }

    func acceptDrop(_ classification: AssistantDropClassification) {
        guard let payload = classification.payload else { return }
        dropClassification = nil
        pendingDropPayload = payload
        panelContent = .dropTasks
        windowController?.hideToolbar()
        windowController?.showPeek(activating: false)
        let contentType: AssistantContentType = switch classification.kind {
        case .text, .textFile: .text
        case .image: .image
        case .media: .media
        case .url: .url
        case .unsupported, .multipleItems: .file
        }
        let epoch = contextEpoch
        Task {
            guard lifecycle.observationIsAllowed,
                  await contextBuffer.appendIfCurrent(AssistantActivityEvent(
                type: .fileDropped,
                source: .droppedFile,
                contentType: contentType
            ), expectedEpoch: epoch) != nil,
            epoch == contextEpoch,
            lifecycle.observationIsAllowed else { return }
            lastSourceUse[.droppedFile] = .now
        }
    }

    func runDroppedTextTask(_ task: TaskKind) {
        guard let pendingDropPayload else { return }
        guard onRunDroppedText?(pendingDropPayload, task) == true else { return }
        finishDropRouting()
    }

    func openDroppedImage(mode: OCRMode) {
        guard let pendingDropPayload,
              case .file(let url, .image) = pendingDropPayload else { return }
        guard onOpenDroppedImage?(url, mode) == true else { return }
        finishDropRouting()
    }

    func openDroppedMedia(mode: SubtitleDisplayMode) {
        guard let pendingDropPayload,
              case .file(let url, .media) = pendingDropPayload else { return }
        guard onOpenDroppedMedia?(url, mode) == true else { return }
        finishDropRouting()
    }

    func performDroppedURLAction(open: Bool) {
        guard let pendingDropPayload,
              case .url(let url) = pendingDropPayload else { return }
        if open {
            NSWorkspace.shared.open(url)
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
            markAssistantClipboardWrite(changeCount: pasteboard.changeCount)
        }
        finishDropRouting()
    }

    func handleOrbClick() {
        windowController?.hideToolbar()
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.snapshot()
            guard commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch) else { return }
            if let unread = cards.first(where: { $0.state == .unread && $0.requiresUserAction }) {
                presentCard(id: unread.id)
            } else {
                openInquiry()
            }
        }
    }

    func dismissPanel() {
        // 用户关闭面板即撤销本次显式询问，避免敏感问题在后台完成后重新弹出。
        inquiryTask?.cancel()
        peekTimeoutTask?.cancel()
        currentProactiveCardID = nil
        clearPanelEphemera()
        windowController?.hidePeek()
    }

    func dismissSpeechBubble() {
        guard let card = selectedCard, card.prefersSpeechBubblePresentation else {
            dismissPanel()
            return
        }
        // 点击对白只是收起，不等同于用户明确关闭或负反馈。
        proactivelyPresentedCardIDs.remove(card.id)
        dismissPanel()
    }

    private func clearPanelEphemera() {
        // 敏感显式询问和拖入正文只属于当前可见面板，隐藏或停用时立即释放。
        panelContent = .none
        inquiryText = ""
        inquiryError = nil
        includeClipboardContext = false
        includeCurrentCardContext = false
        ephemeralInquiryCard = nil
        ephemeralInquiryHandoff = nil
        pendingDropPayload = nil
    }

    func requestToolbarKeyboardFocus() {
        toolbarKeyboardFocusToken &+= 1
    }

    func presentCard(id: UUID) {
        peekTimeoutTask?.cancel()
        currentProactiveCardID = nil
        proactivelyPresentedCardIDs.remove(id)
        panelContent = .card(id)
        guard windowController?.showPeek(activating: false) == true else {
            panelContent = .none
            return
        }
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.markViewed(id: id)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            if let recordID = cardBehaviorRecordIDs[id] {
                _ = await behaviorStore.update(id: recordID, outcome: .viewed)
                behaviorSummary = await behaviorStore.summary()
            }
        }
        applySessionInteraction(.positive)
    }

    func viewEvidence(for card: AssistantCard) {
        peekTimeoutTask?.cancel()
        currentProactiveCardID = nil
        if proactivelyPresentedCardIDs.remove(card.id) != nil {
            applySessionInteraction(.positive)
        }
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.markViewed(id: card.id)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            if let recordID = cardBehaviorRecordIDs[card.id] {
                _ = await behaviorStore.update(id: recordID, outcome: .viewed)
                behaviorSummary = await behaviorStore.summary()
            }
        }
    }

    func showAdjacentCard(offset: Int) {
        guard let current = selectedCard,
              let index = cards.firstIndex(where: { $0.id == current.id }),
              cards.indices.contains(index + offset) else { return }
        presentCard(id: cards[index + offset].id)
    }

    func markAllViewed() {
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.markAllViewed()
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
        }
    }

    func clearCards() {
        cardEpoch &+= 1
        let epoch = cardEpoch
        cancelCandidateJudgment(discardQueue: true)
        discardAllCandidateTracking()
        inquiryTask?.cancel()
        peekTimeoutTask?.cancel()
        cardClearTask?.cancel()
        cardClearTask = Task { [weak self] in
            guard let self else { return }
            await cardStore.clear()
            guard epoch == cardEpoch else { return }
            cards = []
            pruneCardMetadata()
            dismissPanel()
            cardClearTask = nil
        }
    }

    @discardableResult
    private func commitCardSnapshot(_ storedCards: [AssistantCard], expectedEpoch: UInt64) -> Bool {
        // 所有跨 actor 的卡片写回都经过会话 epoch，避免“清除提示”后旧快照复活 UI。
        guard expectedEpoch == cardEpoch else { return false }
        cards = storedCards
        pruneCardMetadata()
        return true
    }

    func submitInquiry() {
        let question = inquiryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isInquiryRunning else { return }
        let explicitContext = selectedExplicitContext()
        let inquirySensitivity: AssistantSensitivity = if privacyPolicy.sensitivity(
            text: question,
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ) != .normal || explicitContext.map(AssistantPrivacyPolicy.looksSensitive) == true {
            .sensitive
        } else {
            .normal
        }
        inquiryTask?.cancel()
        let expectedCardEpoch = cardEpoch
        isInquiryRunning = true
        inquiryError = nil
        // 显式询问优先于后台资格检查、价值判断和临时翻译，避免本地模型争用。
        userModelActivityDidChange(true)
        inquiryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isInquiryRunning = false
                inquiryTask = nil
                userModelActivityDidChange(appState.assistantUserModelWorkIsActive)
            }
            do {
                // 用户显式询问等待已取消的后台 operation 真正收束，避免两个本地模型同时占用内存。
                guard await waitForBackgroundWorkToSettle(timeout: 5) else {
                    if Task.isCancelled { throw CancellationError() }
                    inquiryError = text(
                        "本地模型仍在收尾，请稍后再试。",
                        "The local model is still finishing previous work. Try again shortly."
                    )
                    return
                }
                try Task.checkCancellation()
                let result = try await appState.runDesktopAssistantInquiry(
                    question: question,
                    explicitContext: explicitContext
                )
                try Task.checkCancellation()
                if let cardClearTask { await cardClearTask.value }
                guard expectedCardEpoch == cardEpoch else { return }
                let card = AssistantCard(
                    source: .inquiry,
                    presentation: .peek,
                    comment: result.text,
                    evidenceSummary: inquirySensitivity == .normal
                        ? question
                        : text("敏感显式询问仅在当前面板显示", "Sensitive explicit inquiry is shown only in this panel"),
                    evidence: AssistantCardEvidence(
                        sources: [.inquiry],
                        usedLocalModel: true,
                        rawContextAvailable: explicitContext != nil,
                        capability: "local-inquiry"
                    ),
                    actionIDs: [.deepenInquiry],
                    sensitivity: inquirySensitivity,
                    state: .viewed,
                    detailText: result.text
                )
                if inquirySensitivity == .normal {
                    let storedCards = await cardStore.add(card)
                    guard expectedCardEpoch == cardEpoch else {
                        let rollbackEpoch = cardEpoch
                        let rolledBackCards = await cardStore.remove(id: card.id)
                        commitCardSnapshot(rolledBackCards, expectedEpoch: rollbackEpoch)
                        return
                    }
                    cards = storedCards
                    pruneCardMetadata()
                    panelContent = .card(card.id)
                } else {
                    ephemeralInquiryCard = card
                    ephemeralInquiryHandoff = """
                    \(text("问题", "Question"))：\(question)

                    \(text("桌面助手回答", "Desktop assistant answer"))：\(result.text)
                    """
                    panelContent = .ephemeralInquiry
                }
                // 用户已经显式进入输入区，结果卡保留键盘能力，便于 Esc 或继续 Tab 导航。
                windowController?.showPeek(activating: true)
            } catch is CancellationError {
                return
            } catch {
                inquiryError = error.localizedDescription
            }
        }
    }

    func perform(action: AssistantActionID, for card: AssistantCard) {
        guard actionIsAvailable(action, for: card) else { return }
        peekTimeoutTask?.cancel()
        currentProactiveCardID = nil
        switch action {
        case .deepenInquiry:
            let content: String
            if ephemeralInquiryCard?.id == card.id, let ephemeralInquiryHandoff {
                content = ephemeralInquiryHandoff
            } else {
                content = """
                \(text("问题", "Question"))：\(card.evidenceSummary ?? "")

                \(text("桌面助手回答", "Desktop assistant answer"))：\(card.detailText ?? card.comment)
                """
            }
            onOpenQuickAction?(content)
            dismissPanel()
            finishAction(action, card: card, succeeded: true)
        case .openQuickAction:
            if card.patternType == .contextualOpportunity,
               let quote = cardOpportunityQuotes[card.id],
               let task = cardOpportunityTasks[card.id] {
                onOpenQuickActionTask?(quote, task)
            } else {
                onOpenQuickAction?(card.detailText ?? card.evidenceSummary)
            }
            dismissPanel()
            finishAction(action, card: card, succeeded: true)
        case .explainError:
            openRawContext(card: card, task: .explain, action: action)
        case .returnToWorkbench:
            guard let route = cardWorkbenchRoutes[card.id] else { return }
            onReturnToWorkbench?(route)
            dismissPanel()
            finishAction(action, card: card, succeeded: true)
        case .enableClipboardTranslation:
            guard let language = cardForeignLanguages[card.id] else { return }
            startTemporaryTranslation(language: language)
            dismissPanel()
            finishAction(action, card: card, succeeded: true)
        case .translateCurrentClipboard:
            translateCardSourceOnce(card)
        case .detailedTranslation:
            openRawContext(card: card, task: .translate, action: action)
        case .copyTranslation:
            guard let translation = card.detailText, !translation.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(translation, forType: .string) else {
                finishAction(action, card: card, succeeded: false)
                return
            }
            markAssistantClipboardWrite(changeCount: pasteboard.changeCount)
            finishAction(action, card: card, succeeded: true)
        case .openSettings:
            if card.evidence.capability == "local-translation-unavailable" {
                onOpenModelSettings?()
            } else {
                onOpenSettings?()
            }
            finishAction(action, card: card, succeeded: true)
        }
    }

    func setFeedback(_ feedback: AssistantFeedback, for card: AssistantCard) {
        guard card.feedback != feedback else { return }
        peekTimeoutTask?.cancel()
        currentProactiveCardID = nil
        let previous = settledSessionFeedbackByCard[card.id] ?? card.feedback
        let transition = AssistantFeedbackTransition.resolve(
            wasProactivelyPresented: proactiveOriginCardIDs.contains(card.id),
            previous: previous,
            new: feedback
        )
        if feedback != .unfunny {
            settledSessionFeedbackByCard[card.id] = feedback
            proactivelyPresentedCardIDs.remove(card.id)
        }
        if let interaction = transition.interaction {
            applySessionInteraction(interaction)
        }
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.update(id: card.id, feedback: feedback)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            if let recordID = cardBehaviorRecordIDs[card.id] {
                _ = await behaviorStore.update(id: recordID, feedback: feedback)
                behaviorSummary = await behaviorStore.summary()
            }
        }
    }

    func closePanelFromUser() {
        if let card = selectedCard, proactivelyPresentedCardIDs.contains(card.id) {
            setFeedback(.explicitlyClosed, for: card)
            let expectedCardEpoch = cardEpoch
            Task {
                let storedCards = await cardStore.update(id: card.id, state: .dismissed, feedback: .explicitlyClosed)
                commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
                if let recordID = cardBehaviorRecordIDs[card.id] {
                    _ = await behaviorStore.update(id: recordID, feedback: .explicitlyClosed, outcome: .dismissed)
                    behaviorSummary = await behaviorStore.summary()
                }
            }
        }
        dismissPanel()
    }

    func disablePattern(for card: AssistantCard) {
        guard let pattern = card.patternType else { return }
        let wasProactivelyPresented = proactivelyPresentedCardIDs.remove(card.id) != nil
        switch pattern {
        case .repeatedFailure:
            appState.updatePreferences { $0.desktopAssistant.repeatedFailureEnabled = false }
        case .foreignClipboard:
            appState.updatePreferences { $0.desktopAssistant.foreignClipboardEnabled = false }
        case .contextualOpportunity:
            return
        }
        patternDisableUndo = pattern
        patternUndoTask?.cancel()
        patternUndoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.patternDisableUndo = nil
        }
        if wasProactivelyPresented { applySessionInteraction(.explicitNegative) }
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.update(id: card.id, state: .dismissed)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            if let recordID = cardBehaviorRecordIDs[card.id] {
                _ = await behaviorStore.update(id: recordID, outcome: .dismissed)
                behaviorSummary = await behaviorStore.summary()
            }
        }
    }

    func undoPatternDisable() {
        guard let pattern = patternDisableUndo else { return }
        switch pattern {
        case .repeatedFailure:
            appState.updatePreferences { $0.desktopAssistant.repeatedFailureEnabled = true }
        case .foreignClipboard:
            appState.updatePreferences { $0.desktopAssistant.foreignClipboardEnabled = true }
        case .contextualOpportunity:
            return
        }
        patternUndoTask?.cancel()
        patternDisableUndo = nil
        applySessionInteraction(.positive)
    }

    func suppressForeignLanguage(for card: AssistantCard) {
        guard let language = cardForeignLanguages[card.id] else { return }
        appState.updatePreferences { preferences in
            if !preferences.desktopAssistant.suppressedForeignLanguages.contains(language) {
                preferences.desktopAssistant.suppressedForeignLanguages.append(language)
                preferences.desktopAssistant.suppressedForeignLanguages.sort()
            }
        }
        stopTemporaryTranslation()
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.update(id: card.id, state: .dismissed)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            if let recordID = cardBehaviorRecordIDs[card.id] {
                _ = await behaviorStore.update(id: recordID, outcome: .dismissed)
                behaviorSummary = await behaviorStore.summary()
            }
        }
    }

    func installStageAPreview() {
        isStageAPreview = true
        var previewPreferences = preferences
        previewPreferences.isEnabled = true
        previewPreferences.completedOnboardingVersion = DesktopAssistantPreferences.currentOnboardingVersion
        lifecycle = AssistantLifecycleMachine(preferences: previewPreferences)
        let fixture = AssistantCard(
            source: .windowContext,
            patternType: .contextualOpportunity,
            presentation: .peek,
            comment: text("这次先不弹工具按钮，算我克制。", "No tool buttons this time. I am showing restraint."),
            evidenceSummary: text("阶段 A 对白气泡预览，不启动观察器", "Stage A speech-bubble preview; observers are not running"),
            evidence: AssistantCardEvidence(sources: [.windowContext], capability: "stage-a-preview"),
            state: .viewed
        )
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.add(fixture)
            guard commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch) else { return }
            panelContent = .card(fixture.id)
            windowController?.showOrb()
            windowController?.showPeek(activating: false)
        }
    }

    func shutdown() async {
        isStageAPreview = false
        let tasks = [
            inquiryTask, pauseTask, behaviorLoadTask, judgmentTask, qualificationTask,
            proactivityRequestTask, contextOpportunityTask, peekTimeoutTask, pendingPresentationTask, translationTask,
            translationExpiryTask, patternUndoTask, maintenanceTask, cardClearTask, contextMaintenanceTask,
            backgroundRecoveryTask
        ].compactMap { $0 }
        tasks.forEach { $0.cancel() }
        cancelStageCWork(cancelQualification: true)
        qualificationRefreshTask?.cancel()
        activityObserver.stop()
        contextMaintenanceTask?.cancel()
        contextMaintenanceTask = nil
        contextEpoch &+= 1
        await contextBuffer.advanceEpochAndClear(to: contextEpoch)
        await patternDetector.clear()
        // 模型任务可能卡在底层同步加载；最多等待 5 秒后继续统一 unload，退出不能无限阻塞。
        _ = await waitForBackgroundWorkToSettle(timeout: 5)
        maintenanceTask = nil
        cardClearTask = nil
        backgroundRecoveryTask = nil
        timedOutBackgroundOperationIDs.removeAll()
        userModelWorkIsActive = false
        clearPanelEphemera()
        windowController?.closeAll()
    }

    func recordApplicationActivation(bundleID: String) {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              preferences.foregroundApplicationContextEnabled else { return }
        let policy = privacyPolicy
        guard policy.sensitivity(text: nil, bundleID: bundleID) != .excludedApplication else { return }
        let epoch = contextEpoch
        Task {
            guard await contextBuffer.appendIfCurrent(AssistantActivityEvent(
                type: .applicationActivated,
                source: .foregroundApplication,
                appIdentity: bundleID,
                contentType: .metadata
            ), expectedEpoch: epoch) != nil else { return }
            lastSourceUse[.foregroundApplication] = .now
        }
    }

    func recordWindowContext(
        bundleID: String,
        title: String,
        observedAt: Date,
        surfaceID: String?,
        surfaceRevision: UInt64,
        anchorGeneration: UInt64
    ) {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              preferences.foregroundApplicationContextEnabled,
              preferences.enhancedWindowContextEnabled,
              AXIsProcessTrusted() else { return }
        let policy = privacyPolicy
        guard policy.sensitivity(text: nil, bundleID: bundleID) != .excludedApplication,
              let summary = policy.sanitizeWindowTitle(title) else { return }
        let epoch = contextEpoch
        Task {
            let fingerprint = try? await fingerprintStore.fingerprint(text: summary)
            guard !Task.isCancelled,
                  let event = await contextBuffer.appendIfCurrent(
                    AssistantActivityEvent(
                        occurredAt: observedAt,
                        type: .windowContextChanged,
                        source: .windowContext,
                        appIdentity: bundleID,
                        contentType: .metadata,
                        sanitizedSummary: summary,
                        contentFingerprint: fingerprint,
                        surfaceID: surfaceID,
                        surfaceRevision: surfaceRevision,
                        anchorGeneration: anchorGeneration,
                        provenance: .observed
                    ),
                    rawText: summary,
                    expectedEpoch: epoch
                  ) else { return }
            lastSourceUse[.windowContext] = .now
            await collectContextOpportunity(event, expectedContextEpoch: epoch)
        }
    }

    fileprivate func recordScreenSnapshot(
        _ image: OCRImageInput,
        bundleID: String,
        capturedAt: Date,
        surfaceID: String?,
        surfaceRevision: UInt64,
        anchorGeneration: UInt64
    ) async -> AssistantVisualAnalysisOutcome {
        guard lifecycle.observationIsAllowed else { return skipVisualAnalysis("observation-disabled") }
        guard userIsPresent else { return skipVisualAnalysis("user-absent") }
        guard preferences.foregroundApplicationContextEnabled,
              preferences.enhancedWindowContextEnabled else { return skipVisualAnalysis("enhanced-context-disabled") }
        guard let judgmentModelID = currentJudgmentModelID else {
            return skipVisualAnalysis("no-qualified-model")
        }
        guard hasUsableDesktopAssistantVisionModel else { return skipVisualAnalysis("no-vision-model") }
        guard effectiveProactivity == .moderate || effectiveProactivity == .active else {
            return skipVisualAnalysis(visualContextAnalysisDisableReason)
        }
        guard !userModelWorkIsActive else { return skipVisualAnalysis("user-model-busy") }
        guard !Self.userIsActivelyTyping else { return skipVisualAnalysis("user-typing") }
        guard Date.now.timeIntervalSince(lastVisionAnalysisAt) >= 15 else {
            return skipVisualAnalysis("vision-cooldown")
        }
        guard privacyPolicy.sensitivity(text: nil, bundleID: bundleID) == .normal else {
            return skipVisualAnalysis("excluded-application")
        }
        guard image.byteCount <= appState.preferences.ocr.maximumImageBytes else {
            return skipVisualAnalysis("image-byte-limit")
        }
        guard (image.pixelWidth ?? 0) * (image.pixelHeight ?? 0) <= appState.preferences.ocr.maximumPixelCount else {
            return skipVisualAnalysis("image-pixel-limit")
        }
        guard let lease = backgroundWorkArbiter.claim(.vision) else {
            recordDiagnosticActivity(stage: .vision, state: .skipped, detail: "background-resource-busy")
            return .retryableContention
        }

        let epoch = contextEpoch
        lastVisionAnalysisAt = .now
        visualAnalysisRunning = true
        let startedAt = Date.now
        recordDiagnosticActivity(stage: .vision, state: .running, detail: "local-vlm")
        defer {
            visualAnalysisRunning = false
            finishBackgroundWorkflow(lease)
        }
        let summary: AssistantSceneSummary
        do {
            summary = try await withBackgroundTimeout(lease: lease, seconds: 15) { [appState, image, judgmentModelID] in
                try await appState.runDesktopAssistantVision(image: image, modelID: judgmentModelID)
            }
        } catch is CancellationError {
            let elapsed = Int(Date.now.timeIntervalSince(startedAt) * 1_000)
            recordDiagnosticActivity(
                stage: .vision,
                state: .cancelled,
                detail: "vision-cancelled elapsed=\(elapsed)ms"
            )
            return .skipped
        } catch is AssistantBackgroundTimeout {
            let elapsed = Int(Date.now.timeIntervalSince(startedAt) * 1_000)
            recordDiagnosticActivity(
                stage: .vision,
                state: .failed,
                detail: "vision-timeout limit=15s elapsed=\(elapsed)ms"
            )
            return .retryableFailure
        } catch {
            let elapsed = Int(Date.now.timeIntervalSince(startedAt) * 1_000)
            recordDiagnosticActivity(
                stage: .vision,
                state: .failed,
                detail: "vision-model-error elapsed=\(elapsed)ms"
            )
            return .retryableFailure
        }

        guard !Task.isCancelled,
              epoch == contextEpoch,
              lifecycle.observationIsAllowed else {
            recordDiagnosticActivity(
                stage: .vision,
                state: Task.isCancelled ? .cancelled : .skipped,
                detail: "invalid-sensitive-or-stale-summary"
            )
            return .skipped
        }
        guard activityObserver.surfaceIsCurrent(
            id: surfaceID,
            revision: surfaceRevision,
            anchorGeneration: anchorGeneration
        ) else {
            recordDiagnosticActivity(stage: .vision, state: .skipped, detail: "stale-visual-surface")
            return .retryableContention
        }
        guard
              let contextText = privacyPolicy.sanitizeModelEvidence(summary.contextText),
              !contextText.isEmpty,
              !AssistantPrivacyPolicy.looksSensitive(contextText) else {
            recordDiagnosticActivity(
                stage: .vision,
                state: Task.isCancelled ? .cancelled : .skipped,
                detail: "invalid-sensitive-or-stale-summary"
            )
            return .skipped
        }
        let fingerprint = try? await fingerprintStore.fingerprint(text: image.contentHash)
        guard !Task.isCancelled,
              epoch == contextEpoch,
              let event = await contextBuffer.appendIfCurrent(
                  AssistantActivityEvent(
                      occurredAt: capturedAt,
                      type: .windowContextChanged,
                      source: .windowContext,
                      appIdentity: bundleID,
                      contentType: .image,
                      sanitizedSummary: String(contextText.prefix(240)),
                      contentFingerprint: fingerprint,
                      confidence: summary.confidence,
                      surfaceID: surfaceID,
                      surfaceRevision: surfaceRevision,
                      anchorGeneration: anchorGeneration,
                      provenance: .observed,
                      sceneSignal: summary.signal
                  ),
                  rawText: contextText,
                  expectedEpoch: epoch
              ) else { return .skipped }
        lastSourceUse[.windowContext] = .now
        screenCaptureAuthorized = true
        let elapsed = Int(Date.now.timeIntervalSince(startedAt) * 1_000)
        recordDiagnosticActivity(
            stage: .vision,
            state: .succeeded,
            detail: "context-recorded confidence=\(String(format: "%.2f", summary.confidence)) elapsed=\(elapsed)ms"
        )
        await collectContextOpportunity(event, expectedContextEpoch: epoch)
        return .consumed
    }

    func recordSelection(_ text: String, bundleID: String?) {
        guard lifecycle.observationIsAllowed,
              preferences.selectionContextEnabled else { return }
        if let bundleID,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID {
            // AX/服务回调可能晚于应用切换；已知来源不再位于前台时不能把旧选区挂到新窗口。
            return
        }
        // 划词本身就是明确的用户输入，先刷新在场状态，避免空闲边界吞掉本次选区。
        activityObserver.noteExplicitUserActivity()
        guard userIsPresent else { return }
        let surface = activityObserver.explicitSurfaceSnapshot(bundleID: bundleID)
        ingestText(
            text,
            type: .selectionCaptured,
            source: .selection,
            bundleID: bundleID,
            removeErrorNoise: true,
            observedAt: .now,
            surfaceID: surface.0,
            surfaceRevision: surface.1,
            anchorGeneration: surface.2
        )
    }

    func recordTaskFailure(
        _ text: String,
        workbenchIsRecoverable: Bool = true,
        workbenchRoute: AssistantWorkbenchRoute
    ) {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              !preferences.isManualOnly else { return }
        ingestText(
            text,
            type: .taskFailed,
            source: .llmToolsTask,
            bundleID: nil,
            removeErrorNoise: true,
            workbenchIsRecoverable: workbenchIsRecoverable,
            workbenchRoute: workbenchRoute,
            observedAt: .now,
            provenance: .explicit
        )
    }

    func recordClipboardText(
        _ text: String,
        bundleID: String?,
        possibleBundleIDs: [String],
        observedAt: Date,
        surfaceID: String?,
        surfaceRevision: UInt64,
        anchorGeneration: UInt64,
        provenance: AssistantEvidenceProvenance
    ) async {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              preferences.clipboardAuthorization == .allowed else { return }
        let policy = privacyPolicy
        guard possibleBundleIDs.allSatisfy({
            policy.sensitivity(text: nil, bundleID: $0) != .excludedApplication
        }) else { return }
        let sensitivity = policy.sensitivity(text: text, bundleID: nil)
        guard sensitivity == .normal else {
            let epoch = contextEpoch
            let suppressionEpoch = behaviorEpoch
            guard await contextBuffer.appendIfCurrent(AssistantActivityEvent(
                occurredAt: observedAt,
                type: .clipboardChanged,
                source: .clipboard,
                contentType: .text,
                sensitivity: .sensitive,
                surfaceID: surfaceID,
                surfaceRevision: surfaceRevision,
                anchorGeneration: anchorGeneration,
                provenance: provenance
            ), expectedEpoch: epoch) != nil else { return }
            cancelContextOpportunityAggregation()
            await patternDetector.clearContextOpportunitySamples()
            await persistSensitiveSuppression(expectedEpoch: suppressionEpoch)
            lastSourceUse[.clipboard] = .now
            return
        }
        let epoch = contextEpoch
        let fingerprint = try? await fingerprintStore.fingerprint(text: text)
        guard !Task.isCancelled,
              let event = await contextBuffer.appendIfCurrent(
                AssistantActivityEvent(
                    occurredAt: observedAt,
                    type: .clipboardChanged,
                    source: .clipboard,
                    appIdentity: preferences.foregroundApplicationContextEnabled ? bundleID : nil,
                    contentType: AssistantPrivacyPolicy.looksLikeURL(text) ? .url : .text,
                    contentFingerprint: fingerprint,
                    surfaceID: surfaceID,
                    surfaceRevision: surfaceRevision,
                    anchorGeneration: anchorGeneration,
                    provenance: provenance
                ),
                rawText: text,
                expectedEpoch: epoch
              ) else { return }
        lastSourceUse[.clipboard] = .now
        let looksLikeError = AssistantPatternRules.looksLikeError(text)
        if provenance != .observed,
           preferences.proactivity != .manual,
           preferences.repeatedFailureEnabled,
           looksLikeError,
           let errorFingerprint = try? await fingerprintStore.fingerprint(text: text, removeErrorNoise: true) {
            guard !Task.isCancelled,
                  epoch == contextEpoch,
                  lifecycle.observationIsAllowed,
                  preferences.clipboardAuthorization == .allowed else { return }
            var failureEvent = event
            failureEvent.contentFingerprint = errorFingerprint
            if let candidate = await patternDetector.ingestFailure(failureEvent) {
                handlePatternCandidate(candidate, expectedContextEpoch: epoch)
            }
        }

        var isForeignClipboard = false
        let effectiveCharacterCount = text.filter { !$0.isWhitespace }.count
        let canDetectForeign = provenance != .observed
            && preferences.foreignClipboardEnabled
            && effectiveCharacterCount >= AssistantPatternDetector.foreignClipboardMinimumCharacterCount
            && !AssistantPrivacyPolicy.looksLikeURL(text)
            && !AssistantPrivacyPolicy.looksLikeCode(text)
        if canDetectForeign,
           let result = try? await appState.detectDesktopAssistantLanguage(text: String(text.prefix(4_000))),
           !Task.isCancelled,
           let language = result.language,
           result.isReliable,
           result.confidence >= AssistantPatternDetector.foreignClipboardMinimumConfidence,
           !Self.languagesMatch(language, appState.preferences.defaultTranslationTarget),
           contextEpoch == epoch,
           lifecycle.observationIsAllowed,
           preferences.clipboardAuthorization == .allowed {
            isForeignClipboard = true
            let languageIsAllowed = !preferences.suppressedForeignLanguages.contains("*")
                && !preferences.suppressedForeignLanguages.contains(where: { Self.languagesMatch($0, language) })
            if languageIsAllowed,
               let foreignEvent = await contextBuffer.appendIfCurrent(
                   AssistantActivityEvent(
                       occurredAt: event.occurredAt,
                       type: .foreignTextDetected,
                       source: .clipboard,
                       appIdentity: event.appIdentity,
                       contentType: .text,
                       sanitizedSummary: "language=\(language)",
                       contentFingerprint: fingerprint,
                       confidence: result.confidence,
                       surfaceID: event.surfaceID,
                       surfaceRevision: event.surfaceRevision,
                       anchorGeneration: event.anchorGeneration,
                       provenance: event.provenance
                   ),
                   rawText: text,
                   expectedEpoch: epoch
               ) {
                handleDetectedForeignClipboard(
                    text: text,
                    language: language,
                    event: foreignEvent,
                    effectiveCharacterCount: effectiveCharacterCount
                )
                if event.occurrenceCount == 1,
                   preferences.proactivity != .manual,
                   let candidate = await patternDetector.ingestForeignClipboard(
                       foreignEvent,
                       language: language,
                       effectiveCharacterCount: effectiveCharacterCount
                   ) {
                    handlePatternCandidate(candidate, expectedContextEpoch: epoch)
                }
            }
        }

        // 专用模式拥有各自意图，P-06 不能用一次错误或一次外语复制绕过 P-01/P-03 阈值。
        if provenance != .observed, !looksLikeError, !isForeignClipboard {
            await collectContextOpportunity(event, expectedContextEpoch: epoch)
        }
    }

    func recordClipboardType(_ contentType: AssistantContentType, bundleID: String?) {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              preferences.clipboardAuthorization == .allowed,
              privacyPolicy.sensitivity(text: nil, bundleID: bundleID) != .excludedApplication else { return }
        let epoch = contextEpoch
        Task {
            guard await contextBuffer.appendIfCurrent(AssistantActivityEvent(
                type: .clipboardChanged,
                source: .clipboard,
                appIdentity: preferences.foregroundApplicationContextEnabled ? bundleID : nil,
                contentType: contentType
            ), expectedEpoch: epoch) != nil else { return }
            lastSourceUse[.clipboard] = .now
        }
    }

    func noteClipboardProvenance(
        changeCount: Int,
        text: String?,
        possibleBundleIDs: [String]
    ) {
        observedClipboardChangeCount = changeCount
        let applicationsAreAllowed = possibleBundleIDs.allSatisfy {
            privacyPolicy.sensitivity(text: nil, bundleID: $0) != .excludedApplication
        }
        observedClipboardSensitivity = applicationsAreAllowed
            ? privacyPolicy.sensitivity(text: text, bundleID: nil)
            : .excludedApplication
    }

    func clearContext(source: AssistantSource) {
        contextEpoch &+= 1
        cancelContextOpportunityAggregation()
        let epoch = contextEpoch
        Task { await contextBuffer.advanceEpochAndClear(to: epoch, source: source) }
        cancelCandidateJudgment(discardQueue: true)
        discardAllCandidateTracking()
        clearCardRawContext(for: source)
        if source == .clipboard {
            // 撤销剪贴板授权时，候选、临时翻译和仍持有原文的队列必须一起失效。
            stopTemporaryTranslation()
            observedClipboardChangeCount = nil
            observedClipboardSensitivity = .sensitive
            Task {
                await patternDetector.clear(pattern: .foreignClipboard)
                await patternDetector.clear(pattern: .repeatedFailure)
                await patternDetector.clearContextOpportunitySamples()
            }
        } else if source == .selection {
            Task {
                await patternDetector.clear(pattern: .repeatedFailure)
                await patternDetector.clearContextOpportunitySamples()
            }
        } else if source == .windowContext || source == .foregroundApplication {
            Task { await patternDetector.clearContextOpportunitySamples() }
        }
        lastSourceUse.removeValue(forKey: source)
    }

    func clearShortTermContext() {
        contextEpoch &+= 1
        cancelContextOpportunityAggregation()
        let epoch = contextEpoch
        Task { await contextBuffer.advanceEpochAndClear(to: epoch) }
        Task { await patternDetector.clear() }
        candidateQueue.clear()
        discardAllCandidateTracking()
        cardRawContextReferences.removeAll()
        workbenchRoutesByRawContext.removeAll()
        cardWorkbenchRoutes.removeAll()
        cardForeignLanguages.removeAll()
        cardOpportunityQuotes.removeAll()
        cardOpportunityTasks.removeAll()
        cardAppIdentities.removeAll()
        stopTemporaryTranslation()
        lastSourceUse.removeAll()
    }

    func clearBehaviorRecords(resetLearning: Bool) {
        behaviorEpoch &+= 1
        discardAllCandidateTracking()
        cancelCandidateJudgment(discardQueue: true)
        maintenanceGeneration &+= 1
        let generation = maintenanceGeneration
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            // 隐私删除不能被不响应取消的底层模型无限阻塞；epoch 会拦截迟到写入。
            _ = await waitForBackgroundWorkToSettle(timeout: 5)
            guard !Task.isCancelled else { return }
            if resetLearning {
                _ = await behaviorStore.deleteAllFilesAndRotateKey()
            } else {
                _ = await behaviorStore.clearDetailedRecords(clearAggregatePreferences: false)
            }
            behaviorSummary = await behaviorStore.summary()
            guard generation == maintenanceGeneration else { return }
            maintenanceTask = nil
            scheduleDeferredBackgroundWork()
        }
    }

    func disableSourceAndClearHistory(_ source: AssistantSource) {
        let sources: Set<AssistantSource> = source == .foregroundApplication
            ? [.foregroundApplication, .windowContext]
            : [source]
        appState.updatePreferences { preferences in
            switch source {
            case .foregroundApplication:
                preferences.desktopAssistant.foregroundApplicationContextEnabled = false
            case .windowContext:
                preferences.desktopAssistant.enhancedWindowContextEnabled = false
            case .clipboard:
                preferences.desktopAssistant.clipboardAuthorization = .denied
            case .selection:
                preferences.desktopAssistant.selectionContextEnabled = false
            case .droppedFile, .llmToolsTask, .inquiry:
                break
            }
        }
        clearBehaviorRecords(sources: sources)
    }

    private func clearBehaviorRecords(sources: Set<AssistantSource>) {
        behaviorEpoch &+= 1
        discardAllCandidateTracking()
        cancelCandidateJudgment(discardQueue: true)
        maintenanceGeneration &+= 1
        let generation = maintenanceGeneration
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            // 来源撤销必须及时兑现；迟到候选受 behavior epoch 和存储层共同拦截。
            _ = await waitForBackgroundWorkToSettle(timeout: 5)
            guard !Task.isCancelled, generation == maintenanceGeneration else { return }
            for source in sources {
                _ = await behaviorStore.clearDetailedRecords(source: source)
            }
            behaviorSummary = await behaviorStore.summary()
            guard generation == maintenanceGeneration else { return }
            maintenanceTask = nil
            scheduleDeferredBackgroundWork()
        }
    }

    func restoreDefaultPosition() {
        appState.updatePreferences {
            $0.desktopAssistant.positionsByDisplay.removeAll()
            $0.desktopAssistant.lastDisplayID = nil
        }
        windowController?.resetToDefaultPosition()
    }

    func markAssistantClipboardWrite(changeCount: Int) {
        observedClipboardChangeCount = nil
        observedClipboardSensitivity = .sensitive
        SelectedTextService.noteInternalPasteboardWrite(changeCount: changeCount)
        activityObserver.markAssistantClipboardWrite(changeCount: changeCount)
    }

    func requestProactivity(
        _ value: AssistantProactivity,
        automaticallyStartQualification: Bool = false
    ) {
        proactivityRequestTask?.cancel()
        proactivityRequestTask = nil
        proactiveSuggestionsPaused = false
        if !value.requiresQualifiedJudgment {
            if qualificationTask != nil || qualificationRun != nil {
                cancelQualification(clearPendingProactivity: true)
            } else {
                qualificationProactivityState.cancelRun(clearPendingProactivity: true)
                syncPendingProactivity()
            }
            appState.updatePreferences { $0.desktopAssistant.proactivity = value }
            return
        }
        proactivityRequestTask = Task { [weak self] in
            guard let self else { return }
            var committed = false
            repeat {
                committed = await recomputeQualificationStates()
            } while !committed && !Task.isCancelled
            guard committed, !Task.isCancelled else { return }
            proactivityRequestTask = nil
            let resolved = qualificationProactivityState.request(
                value,
                hasQualifiedJudgment: currentJudgmentModelID != nil
            )
            syncPendingProactivity()
            appState.updatePreferences { $0.desktopAssistant.proactivity = resolved }
            if automaticallyStartQualification, pendingProactivity != nil {
                startPendingQualification()
            }
        }
    }

    func keepQuietInsteadOfQualification() {
        cancelQualification(clearPendingProactivity: true)
        appState.updatePreferences { $0.desktopAssistant.proactivity = .quiet }
    }

    func pauseProactiveSuggestions() {
        proactiveSuggestionsPaused = true
        activityObserver.cancelPendingVisualCapture(reason: visualContextAnalysisDisableReason)
        cancelContextOpportunityAggregation()
        cancelPendingPresentations()
        cancelCandidateJudgment(discardQueue: true)
        Task { await patternDetector.clearContextOpportunitySamples() }
    }

    func resumeProactiveSuggestions() {
        proactiveSuggestionsPaused = false
    }

    func restoreSessionProactivity() {
        proactiveSuggestionsPaused = false
        sessionProactivity.updateConfigured(preferences.proactivity)
        sessionProactivityWasDowngraded = false
    }

    func startPendingQualification() {
        guard let model = recommendedQualificationModel else {
            qualificationProgress.fail(message: text("没有可检查的本地文本模型。", "No usable local text model is available to test."))
            return
        }
        startQualification(modelID: model.id, pendingProactivity: pendingProactivity)
    }

    func startQualification(modelID: UUID, pendingProactivity: AssistantProactivity? = nil) {
        guard let model = assistantLocalTextModels.first(where: { $0.id == modelID && $0.isAvailableForUse }) else {
            qualificationProgress.fail(
                modelID: modelID,
                message: text("模型文件或本地运行时不可用。", "The model files or local runtime are unavailable.")
            )
            return
        }
        cancelQualification(clearPendingProactivity: false)
        let generation = qualificationGeneration
        let runID = qualificationProactivityState.beginRun(pendingProactivity: pendingProactivity)
        syncPendingProactivity()
        qualificationProgress.start(modelID: model.id, modelName: model.name)
        qualificationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fingerprint = try await Task.detached(priority: .utility) {
                    try AssistantModelFingerprint.fingerprint(for: model)
                }.value
                guard !Task.isCancelled, generation == qualificationGeneration else { return }
                qualificationRun = AssistantQualificationRun(
                    id: runID,
                    model: model,
                    modelFingerprint: fingerprint,
                    samples: []
                )
                qualificationTask = nil
                resumeQualificationIfNeeded()
            } catch is CancellationError {
                handleQualificationCancellation(generation: generation)
            } catch {
                finishQualificationFailure(
                    model: model,
                    fingerprint: "",
                    error: error,
                    generation: generation,
                    runID: runID
                )
            }
        }
    }

    func cancelQualification(clearPendingProactivity: Bool = true) {
        qualificationGeneration &+= 1
        qualificationPauseRequested = false
        qualificationTask?.cancel()
        qualificationTask = nil
        qualificationRun = nil
        qualificationProgress.cancel(message: text("检查已取消，主动程度保持安静。", "The check was cancelled; proactivity remains Quiet."))
        qualificationProactivityState.cancelRun(clearPendingProactivity: clearPendingProactivity)
        syncPendingProactivity()
    }

    func setJudgmentModelID(_ id: UUID?) {
        guard id == nil || qualifiedJudgmentModels.contains(where: { $0.id == id }) else { return }
        appState.updatePreferences { $0.desktopAssistant.judgmentModelID = id }
    }

    fileprivate func userPresenceDidChange(_ present: Bool, lastActivityAt: Date?) {
        self.lastUserActivityAt = lastActivityAt
        guard userIsPresent != present else { return }
        userIsPresent = present
        guard !present else { return }

        // 人离开后只暂停主动链路；用户明确发起的问答和模型任务不在这里被误杀。
        cancelContextOpportunityAggregation()
        cancelCandidateJudgment(discardQueue: true)
        cancelPendingPresentations()
        discardAllCandidateTracking()
        activeDiagnosticStages.removeAll()
        Task { await patternDetector.clearContextOpportunitySamples() }
    }

    func refreshQualificationStates() {
        _ = beginQualificationStateRefresh()
    }

    func userModelActivityDidChange(_ active: Bool) {
        guard userModelWorkIsActive != active else { return }
        userModelWorkIsActive = active
        if active {
            activityObserver.cancelPendingVisualCapture()
            qualificationPauseRequested = qualificationTask != nil
            // 指纹计算不可取消且尚无续跑点；让它结束后在检查入口暂停。
            if qualificationRun != nil { qualificationTask?.cancel() }
            if let currentJudgmentCandidate {
                candidatesToBadgeAfterPreemption.insert(currentJudgmentCandidate.id)
            }
            cancelCandidateJudgment()
            if let activeTranslation {
                pendingTranslations.insert(activeTranslation, at: 0)
                translationTask?.cancel()
            }
        } else {
            if timedOutBackgroundOperationIDs.isEmpty {
                scheduleDeferredBackgroundWork()
                activityObserver.resumeDeferredVisualCaptureIfPossible()
            } else {
                scheduleBackgroundModelRecovery()
            }
        }
    }

    private func finishBackgroundWorkflow(_ lease: AssistantBackgroundWorkLease) {
        finishedBackgroundWorkflows.insert(lease.id)
        guard backgroundOperationCounts[lease.id, default: 0] == 0 else { return }
        releaseBackgroundWorkflow(lease)
    }

    private func backgroundOperationDidSettle(_ lease: AssistantBackgroundWorkLease) {
        let remaining = max(0, backgroundOperationCounts[lease.id, default: 0] - 1)
        if remaining == 0 {
            backgroundOperationCounts.removeValue(forKey: lease.id)
        } else {
            backgroundOperationCounts[lease.id] = remaining
        }
        if remaining == 0, finishedBackgroundWorkflows.contains(lease.id) {
            releaseBackgroundWorkflow(lease)
        }
    }

    private func releaseBackgroundWorkflow(_ lease: AssistantBackgroundWorkLease) {
        guard backgroundWorkArbiter.release(lease) else { return }
        finishedBackgroundWorkflows.remove(lease.id)
        backgroundOperationCounts.removeValue(forKey: lease.id)
        scheduleDeferredBackgroundWork()
        activityObserver.resumeDeferredVisualCaptureIfPossible()
    }

    private func scheduleDeferredBackgroundWork() {
        guard backgroundWorkArbiter.activeLease == nil,
              !userModelWorkIsActive,
              backgroundRecoveryTask == nil,
              timedOutBackgroundOperationIDs.isEmpty,
              maintenanceTask == nil else { return }
        if !pendingTranslations.isEmpty {
            startNextTranslationIfNeeded()
        } else if qualificationRun != nil {
            resumeQualificationIfNeeded()
        } else if candidateQueue.count > 0 {
            startNextCandidateIfNeeded()
        }
    }

    private func waitForBackgroundWorkToSettle(timeout: TimeInterval? = nil) async -> Bool {
        let deadline = timeout.map { Date.now.addingTimeInterval(max(0, $0)) }
        while backgroundWorkArbiter.activeLease != nil {
            guard !Task.isCancelled, deadline.map({ $0 > .now }) ?? true else { return false }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return true
    }

    private func scheduleBackgroundModelRecovery() {
        guard backgroundRecoveryTask == nil,
              !timedOutBackgroundOperationIDs.isEmpty,
              !userModelWorkIsActive else { return }
        backgroundRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                backgroundRecoveryTask = nil
                return
            }
            guard !timedOutBackgroundOperationIDs.isEmpty else {
                backgroundRecoveryTask = nil
                scheduleDeferredBackgroundWork()
                activityObserver.resumeDeferredVisualCaptureIfPossible()
                return
            }
            guard !userModelWorkIsActive else {
                backgroundRecoveryTask = nil
                return
            }
            let recovered = await appState.recoverDesktopAssistantModelsAfterTimeout()
            backgroundRecoveryTask = nil
            guard !Task.isCancelled else { return }
            if recovered {
                timedOutBackgroundOperationIDs.removeAll()
            } else {
                scheduleBackgroundModelRecovery()
                return
            }
            scheduleDeferredBackgroundWork()
            activityObserver.resumeDeferredVisualCaptureIfPossible()
        }
    }

    private func withBackgroundTimeout<T: Sendable>(
        lease: AssistantBackgroundWorkLease,
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        backgroundOperationCounts[lease.id, default: 0] += 1
        let operationID = UUID()
        let race = AssistantTimeoutRace<T>()
        let operationTask = Task { [weak self] in
            let result: Result<T, Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            await race.resolve(result)
            await MainActor.run {
                self?.timedOutBackgroundOperationIDs.remove(operationID)
                self?.backgroundOperationDidSettle(lease)
            }
        }
        // 超时钟必须脱离 MainActor；本地模型冷启动不能拖住计时器本身。
        let timeoutTask = Task.detached { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            } catch {
                return
            }
            operationTask.cancel()
            guard await race.resolve(.failure(AssistantBackgroundTimeout())) else {
                return
            }
            await MainActor.run {
                guard let self,
                      self.backgroundOperationCounts[lease.id, default: 0] > 0 else { return }
                self.timedOutBackgroundOperationIDs.insert(operationID)
                // 底层模型若不响应取消，也不能永久占住助手唯一的后台租约。
                self.backgroundOperationDidSettle(lease)
                self.scheduleBackgroundModelRecovery()
            }
        }
        return try await withTaskCancellationHandler {
            defer { timeoutTask.cancel() }
            return try await race.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task { @MainActor [weak self] in
                self?.timedOutBackgroundOperationIDs.insert(operationID)
                guard await race.resolve(.failure(CancellationError())) else {
                    self?.timedOutBackgroundOperationIDs.remove(operationID)
                    return
                }
                self?.backgroundOperationDidSettle(lease)
                self?.scheduleBackgroundModelRecovery()
            }
        }
    }

    private var recommendedQualificationModel: ModelDescriptor? {
        assistantLocalTextModels
            .filter(\.isAvailableForUse)
            .sorted {
                let left = Self.initialQualificationRoleRank($0.role)
                let right = Self.initialQualificationRoleRank($1.role)
                if left != right { return left > right }
                return Self.modelSizeValue($0.sizeClass) > Self.modelSizeValue($1.sizeClass)
            }
            .first
    }

    private func recomputeQualificationStates() async -> Bool {
        var request = beginQualificationStateRefresh()
        while !Task.isCancelled {
            let committed = await request.task.value
            if committed, request.revision == qualificationStateRevision { return true }
            guard request.revision != qualificationStateRevision,
                  let latestTask = qualificationRefreshTask else { return false }
            // 被更新的偏好抢占时等待最新 single-flight，不再创建新 revision 互相取消。
            request = (qualificationStateRevision, latestTask)
        }
        return false
    }

    private func beginQualificationStateRefresh() -> (revision: UInt64, task: Task<Bool, Never>) {
        qualificationStateRevision &+= 1
        let revision = qualificationStateRevision
        qualificationRefreshTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return false }
            return await recomputeQualificationStates(revision: revision)
        }
        qualificationRefreshTask = task
        return (revision, task)
    }

    private func recomputeQualificationStates(revision: UInt64) async -> Bool {
        let models = appState.models.filter {
            $0.enabled
                && !$0.isRemoteProvider
                && ($0.format == .gguf || $0.format == .mlx)
                && $0.capabilities.supportsText
        }
        var states: [UUID: AssistantQualificationState] = [:]
        var summaries: [UUID: AssistantQualificationSummary] = [:]
        for model in models {
            guard !Task.isCancelled, revision == qualificationStateRevision else { return false }
            guard model.isAvailableForUse else {
                states[model.id] = .unavailable
                continue
            }
            do {
                let fingerprint = try await Task.detached(priority: .utility) {
                    try AssistantModelFingerprint.fingerprint(for: model)
                }.value
                if let summary = preferences.qualification(for: model.id),
                   summary.matchesCurrentCacheKey(modelFingerprint: fingerprint) {
                    states[model.id] = summary.state
                    summaries[model.id] = summary
                } else {
                    states[model.id] = .unchecked
                }
            } catch {
                states[model.id] = .unavailable
            }
        }
        let qualified = models.filter { states[$0.id] == .qualified }
        let automatic = qualified.sorted { lhs, rhs in
            guard let left = summaries[lhs.id], let right = summaries[rhs.id] else { return lhs.name < rhs.name }
            if left.positivePassCount != right.positivePassCount { return left.positivePassCount > right.positivePassCount }
            if left.negativeFalsePositiveCount != right.negativeFalsePositiveCount {
                return left.negativeFalsePositiveCount < right.negativeFalsePositiveCount
            }
            if left.maximumLatencyMilliseconds != right.maximumLatencyMilliseconds {
                return left.maximumLatencyMilliseconds < right.maximumLatencyMilliseconds
            }
            return Self.modelSizeValue(lhs.sizeClass) < Self.modelSizeValue(rhs.sizeClass)
        }
        // 指纹计算跨越 await；只有最后一次刷新可以提交，避免旧缓存把失败模型重新选中。
        guard !Task.isCancelled, revision == qualificationStateRevision else { return false }
        assistantLocalTextModels = models
        qualificationStates = states
        currentQualificationSummaries = summaries
        qualifiedJudgmentModels = automatic
        let selected: ModelDescriptor?
        if let configured = preferences.judgmentModelID,
           let manual = automatic.first(where: { $0.id == configured }) {
            selected = manual
        } else {
            selected = automatic.first
        }
        currentJudgmentModelID = selected?.id
        currentJudgmentModelName = selected?.name
        if !visualContextAnalysisIsEnabled {
            activityObserver.cancelPendingVisualCapture(reason: visualContextAnalysisDisableReason)
        }
        if selected == nil,
           preferences.hasCompletedCurrentOnboarding,
           preferences.proactivity.requiresQualifiedJudgment,
           pendingProactivity == nil {
            // 缓存键或模型状态失效后，适中/活跃必须重新显式检查，当前实际档位立即回到安静。
            let resolved = qualificationProactivityState.request(
                preferences.proactivity,
                hasQualifiedJudgment: false
            )
            syncPendingProactivity()
            appState.updatePreferences { $0.desktopAssistant.proactivity = resolved }
        }
        return true
    }

    private func continueQualification(
        generation: UInt64,
        lease: AssistantBackgroundWorkLease
    ) async {
        guard generation == qualificationGeneration, var run = qualificationRun else { return }
        if userModelWorkIsActive {
            qualificationTask = nil
            qualificationProgress.pause(message: text("正在让位于用户任务，空闲后继续。", "Paused for a user task; the check will resume when resources are free."))
            return
        }
        do {
            qualificationProgress.prepare()
            // 模型加载和首次 Metal/提示词编译不计入冻结的 5 秒热模型单例生成门槛。
            do {
                try await withBackgroundTimeout(lease: lease, seconds: 120) { [appState, modelID = run.model.id] in
                    try await appState.warmUpDesktopAssistantJudgmentModel(id: modelID)
                }
            } catch is AssistantBackgroundTimeout {
                throw AssistantQualificationTimeout(message: text(
                    "模型加载超过 120 秒，尚未进入 24 项热推理检查。",
                    "Model loading exceeded 120 seconds before the 24 hot-inference fixtures started."
                ))
            }
            guard generation == qualificationGeneration else { return }
            if let warmupInput = AssistantJudgmentFixtures.all.first?.input {
                do {
                    _ = try await withBackgroundTimeout(lease: lease, seconds: 30) { [appState, modelID = run.model.id] in
                        try await appState.runDesktopAssistantJudgment(input: warmupInput, modelID: modelID)
                    }
                } catch is AssistantBackgroundTimeout {
                    throw AssistantQualificationTimeout(message: text(
                        "首次编译或生成超过 30 秒，尚未进入热推理检查。",
                        "The first compilation or generation exceeded 30 seconds before hot-inference checks started."
                    ))
                }
            }
            guard generation == qualificationGeneration else { return }
            qualificationProgress.beginRunning()
            while run.samples.count < AssistantJudgmentFixtures.all.count {
                try Task.checkCancellation()
                guard !userModelWorkIsActive else {
                    qualificationRun = run
                    qualificationTask = nil
                    qualificationProgress.pause(message: text("正在让位于用户任务，空闲后继续。", "Paused for a user task; the check will resume when resources are free."))
                    return
                }
                let fixture = AssistantJudgmentFixtures.all[run.samples.count]
                let startedAt = ContinuousClock.now
                let output: String?
                do {
                    output = try await withBackgroundTimeout(lease: lease, seconds: 5) { [appState, modelID = run.model.id, input = fixture.input] in
                        try await appState.runDesktopAssistantJudgment(input: input, modelID: modelID)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch is AssistantBackgroundTimeout {
                    guard !Task.isCancelled,
                          generation == qualificationGeneration,
                          qualificationRun?.id == run.id else { throw CancellationError() }
                    let elapsed = ContinuousClock.now - startedAt
                    let latency = max(
                        5_000,
                        Int(elapsed.components.seconds * 1_000)
                            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                    )
                    run.samples.append(AssistantQualificationSample(
                        fixtureID: fixture.id,
                        output: nil,
                        latencyMilliseconds: latency
                    ))
                    qualificationRun = run
                    qualificationProgress.recordCompleted(run.samples.count)
                    throw AssistantQualificationTimeout(message: text(
                        "热推理样例 \(run.samples.count)/\(AssistantJudgmentFixtures.all.count) 超过 5 秒。",
                        "Hot-inference fixture \(run.samples.count)/\(AssistantJudgmentFixtures.all.count) exceeded 5 seconds."
                    ))
                } catch {
                    output = nil
                }
                guard generation == qualificationGeneration else { return }
                let elapsed = ContinuousClock.now - startedAt
                let latency = Int(elapsed.components.seconds * 1_000)
                    + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                run.samples.append(AssistantQualificationSample(
                    fixtureID: fixture.id,
                    output: output,
                    latencyMilliseconds: latency
                ))
                qualificationRun = run
                qualificationProgress.recordCompleted(run.samples.count)
            }
            let summary = AssistantQualificationEvaluator.evaluate(
                modelID: run.model.id,
                modelFingerprint: run.modelFingerprint,
                samples: run.samples
            )
            guard generation == qualificationGeneration else { return }
            appState.updatePreferences { $0.desktopAssistant.setQualification(summary) }
            var committed = false
            repeat {
                committed = await recomputeQualificationStates()
            } while !committed && !Task.isCancelled && generation == qualificationGeneration
            guard committed,
                  generation == qualificationGeneration,
                  qualificationRun?.id == run.id else { return }
            let committedState = qualificationStates[run.model.id] ?? .unavailable
            let resolved = qualificationProactivityState.finishRun(id: run.id, state: committedState)
            syncPendingProactivity()
            if let resolved {
                appState.updatePreferences { $0.desktopAssistant.proactivity = resolved }
            }
            qualificationRun = nil
            qualificationProgress.finish(
                state: committedState,
                message: currentQualificationSummaries[run.model.id]?.message ?? summary.message
            )
        } catch is CancellationError {
            guard generation == qualificationGeneration else { return }
            qualificationRun = run
            handleQualificationCancellation(generation: generation)
        } catch {
            finishQualificationFailure(
                model: run.model,
                fingerprint: run.modelFingerprint,
                error: error,
                generation: generation,
                runID: run.id
            )
        }
    }

    private func handleQualificationCancellation(generation: UInt64) {
        guard generation == qualificationGeneration else { return }
        qualificationTask = nil
        if qualificationPauseRequested, qualificationRun != nil {
            qualificationProgress.pause(message: text("正在让位于用户任务，空闲后继续。", "Paused for a user task; the check will resume when resources are free."))
        }
    }

    private func resumeQualificationIfNeeded() {
        guard qualificationRun != nil,
              qualificationTask == nil,
              !userModelWorkIsActive,
              let lease = backgroundWorkArbiter.claim(.qualification) else { return }
        qualificationPauseRequested = false
        let generation = qualificationGeneration
        qualificationTask = Task { [weak self] in
            guard let self else { return }
            await continueQualification(generation: generation, lease: lease)
            if generation == qualificationGeneration { qualificationTask = nil }
            finishBackgroundWorkflow(lease)
        }
    }

    private func finishQualificationFailure(
        model: ModelDescriptor,
        fingerprint: String,
        error: Error,
        generation: UInt64,
        runID: UUID
    ) {
        guard generation == qualificationGeneration else { return }
        let partial = AssistantQualificationEvaluator.evaluate(
            modelID: model.id,
            modelFingerprint: fingerprint,
            samples: qualificationRun?.id == runID ? qualificationRun?.samples ?? [] : []
        )
        var summary = partial
        summary.state = .unavailable
        summary.message = "\(partial.message); \(error.localizedDescription)"
        if !fingerprint.isEmpty {
            appState.updatePreferences { $0.desktopAssistant.setQualification(summary) }
        }
        qualificationStates[model.id] = .unavailable
        currentQualificationSummaries[model.id] = summary
        qualifiedJudgmentModels.removeAll { $0.id == model.id }
        if currentJudgmentModelID == model.id {
            let fallback = qualifiedJudgmentModels.first
            currentJudgmentModelID = fallback?.id
            currentJudgmentModelName = fallback?.name
        }
        qualificationRun = nil
        qualificationTask = nil
        qualificationProgress.fail(modelID: model.id, message: summary.message)
        let resolved = qualificationProactivityState.finishRun(id: runID, state: .unavailable)
        syncPendingProactivity()
        if let resolved {
            appState.updatePreferences { $0.desktopAssistant.proactivity = resolved }
        } else if preferences.proactivity.requiresQualifiedJudgment, currentJudgmentModelID == nil {
            appState.updatePreferences { $0.desktopAssistant.proactivity = .quiet }
        }
        refreshQualificationStates()
    }

    private func syncPendingProactivity() {
        pendingProactivity = qualificationProactivityState.pendingProactivity
    }

    private static func initialQualificationRoleRank(_ role: ModelRole) -> Int {
        switch role {
        case .quality: return 3
        case .default: return 2
        case .fast: return 1
        }
    }

    private static func modelSizeValue(_ value: String) -> Double {
        let normalized = value.lowercased().replacingOccurrences(of: "b", with: "")
        return Double(normalized) ?? 0
    }

    private func collectContextOpportunity(
        _ event: AssistantActivityEvent,
        expectedContextEpoch: UInt64
    ) async {
        guard expectedContextEpoch == contextEpoch,
              lifecycle.observationIsAllowed,
              userIsPresent,
              currentJudgmentModelID != nil,
              effectiveProactivity == .moderate || effectiveProactivity == .active,
              sourceIsCurrentlyAuthorized(event.source) else { return }
        let shouldTrigger = await patternDetector.ingestContextOpportunity(event)
        guard shouldTrigger else { return }
        scheduleContextOpportunityAggregation(trigger: event, expectedContextEpoch: expectedContextEpoch)
    }

    private func scheduleContextOpportunityAggregation(
        trigger: AssistantActivityEvent,
        expectedContextEpoch: UInt64
    ) {
        guard expectedContextEpoch == contextEpoch,
              lifecycle.observationIsAllowed,
              userIsPresent,
              currentJudgmentModelID != nil,
              effectiveProactivity == .moderate || effectiveProactivity == .active,
              sourceIsCurrentlyAuthorized(trigger.source) else { return }

        let now = Date.now
        let startedAt = contextOpportunityDebounceStartedAt ?? now
        contextOpportunityDebounceStartedAt = startedAt
        let selectedTrigger = pendingContextOpportunityBatch.insert(trigger)
        let target = min(
            now.addingTimeInterval(AssistantPatternDetector.contextOpportunityDebounce),
            startedAt.addingTimeInterval(AssistantPatternDetector.contextOpportunityMaximumDebounce)
        )
        let remaining = max(0, target.timeIntervalSince(now))
        contextOpportunityGeneration &+= 1
        let generation = contextOpportunityGeneration
        contextOpportunityTask?.cancel()
        recordDiagnosticActivity(
            stage: .context,
            state: .scheduled,
            detail: "context-debounce remaining=\(String(format: "%.1f", remaining))s source=\(selectedTrigger.source.rawValue) buckets=\(pendingContextOpportunityBatch.count)"
        )
        contextOpportunityTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  generation == contextOpportunityGeneration,
                  expectedContextEpoch == contextEpoch,
                  lifecycle.observationIsAllowed else { return }
            let triggers = pendingContextOpportunityBatch.drain()
            contextOpportunityDebounceStartedAt = nil
            for currentTrigger in triggers {
                guard expectedContextEpoch == contextEpoch,
                      lifecycle.observationIsAllowed,
                      userIsPresent,
                      currentJudgmentModelID != nil,
                      effectiveProactivity == .moderate || effectiveProactivity == .active,
                      sourceIsCurrentlyAuthorized(currentTrigger.source) else { continue }
                let result = await patternDetector.flushContextOpportunityResult(trigger: currentTrigger)
                let resultIsStillCurrent = expectedContextEpoch == contextEpoch
                    && lifecycle.observationIsAllowed
                    && userIsPresent
                    && currentJudgmentModelID != nil
                    && (effectiveProactivity == .moderate || effectiveProactivity == .active)
                    && sourceIsCurrentlyAuthorized(currentTrigger.source)
                switch result {
                case .candidate(let candidate):
                    guard resultIsStillCurrent else {
                        await patternDetector.settle(candidate, delivered: false)
                        continue
                    }
                    recordDiagnosticActivity(
                        stage: .context,
                        state: .succeeded,
                        detail: "evidence-ready count=\(candidate.evidenceCount)"
                    )
                    handlePatternCandidate(candidate, expectedContextEpoch: expectedContextEpoch)
                case .noEvidence:
                    recordDiagnosticActivity(
                        stage: .context,
                        state: .skipped,
                        detail: "no-evidence-in-window"
                    )
                case .duplicateCooldown:
                    recordDiagnosticActivity(
                        stage: .context,
                        state: .skipped,
                        detail: "duplicate-context-cooldown"
                    )
                }
            }
            if generation == contextOpportunityGeneration { contextOpportunityTask = nil }
            scheduleDeferredBackgroundWork()
            activityObserver.resumeDeferredVisualCaptureIfPossible()
        }
    }

    private func cancelContextOpportunityAggregation() {
        contextOpportunityGeneration &+= 1
        contextOpportunityTask?.cancel()
        contextOpportunityTask = nil
        contextOpportunityDebounceStartedAt = nil
        pendingContextOpportunityBatch.removeAll()
    }

    fileprivate func visualCaptureRoundDidSettle() {
        scheduleDeferredBackgroundWork()
    }

    private func handlePatternCandidate(_ candidate: AssistantPatternCandidate, expectedContextEpoch: UInt64) {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              preferences.isEnabled,
              preferences.proactivity != .manual,
              candidate.expiresAt > .now,
              expectedContextEpoch == contextEpoch else {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .skipped,
                detail: "candidate-invalid-or-disabled pattern=\(candidate.patternType.rawValue)"
            )
            Task { await patternDetector.settle(candidate, delivered: false) }
            return
        }
        candidateBehaviorEpochs[candidate.id] = behaviorEpoch
        candidateContextEpochs[candidate.id] = expectedContextEpoch
        candidateCardEpochs[candidate.id] = cardEpoch
        guard candidateIsCurrentlyAllowed(candidate) else {
            Task { await patternDetector.settle(candidate, delivered: false) }
            discardCandidateTracking(candidate.id)
            return
        }
        switch effectiveProactivity {
        case .manual:
            Task { await patternDetector.settle(candidate, delivered: false) }
            discardCandidateTracking(candidate.id)
            return
        case .quiet:
            recordDiagnosticActivity(
                stage: .judgment,
                state: .skipped,
                detail: "effective-proactivity-quiet pattern=\(candidate.patternType.rawValue)"
            )
            Task { await degradeCandidate(candidate) }
        case .moderate, .active:
            guard currentJudgmentModelID != nil else {
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .skipped,
                    detail: "no-qualified-model pattern=\(candidate.patternType.rawValue)"
                )
                Task { await degradeCandidate(candidate) }
                return
            }
            if let policyVeto = decisionPolicyVetoReason(for: candidate) {
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .skipped,
                    detail: "policy-veto=\(policyVeto) pattern=\(candidate.patternType.rawValue)"
                )
                Task { await degradeCandidate(candidate) }
                return
            }
            let enqueueResult = candidateQueue.enqueueReportingRemovals(candidate)
            retireQueuedCandidates(enqueueResult.removed, replacingCandidate: candidate)
            guard enqueueResult.inserted else {
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .skipped,
                    detail: "queue-rejected pattern=\(candidate.patternType.rawValue)"
                )
                Task { await persistCandidateDecision(candidate, presentation: .silent) }
                return
            }
            recordDiagnosticActivity(
                stage: .judgment,
                state: .queued,
                detail: "pattern=\(candidate.patternType.rawValue) queue=\(candidateQueue.count)"
            )
            startNextCandidateIfNeeded()
        }
    }

    private func startNextCandidateIfNeeded() {
        guard judgmentTask == nil,
              !userModelWorkIsActive,
              lifecycle.observationIsAllowed,
              candidateQueue.count > 0,
              let lease = backgroundWorkArbiter.claim(.judgment) else { return }
        let popResult = candidateQueue.popNextReportingRemovals()
        retireQueuedCandidates(popResult.removed)
        guard let candidate = popResult.candidate else {
            finishBackgroundWorkflow(lease)
            return
        }
        currentJudgmentCandidate = candidate
        recordDiagnosticActivity(
            stage: .judgment,
            state: .running,
            detail: "pattern=\(candidate.patternType.rawValue)"
        )
        judgmentTask = Task { [weak self] in
            guard let self else { return }
            await evaluateCandidate(candidate, lease: lease)
            currentJudgmentCandidate = nil
            judgmentTask = nil
            finishBackgroundWorkflow(lease)
        }
    }

    private func evaluateCandidate(
        _ candidate: AssistantPatternCandidate,
        lease: AssistantBackgroundWorkLease
    ) async {
        guard candidateIsCurrentlyAllowed(candidate),
              let modelID = currentJudgmentModelID else {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .skipped,
                detail: "candidate-became-ineligible pattern=\(candidate.patternType.rawValue)"
            )
            await degradeCandidate(candidate)
            return
        }
        if let policyVeto = decisionPolicyVetoReason(for: candidate) {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .skipped,
                detail: "policy-veto=\(policyVeto) pattern=\(candidate.patternType.rawValue)"
            )
            await degradeCandidate(candidate)
            return
        }
        let semanticEvidence = await contextBuffer.rawTexts(for: candidate.evidenceContextReferences)
            .compactMap(privacyPolicy.sanitizeModelEvidence)
        guard !Task.isCancelled, candidateIsCurrentlyAllowed(candidate) else {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        let requiredSemanticCount = candidate.patternType == .foreignClipboard
            ? AssistantPatternDetector.foreignClipboardThreshold
            : 1
        guard semanticEvidence.count >= requiredSemanticCount else {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .skipped,
                detail: "insufficient-semantic-evidence pattern=\(candidate.patternType.rawValue)"
            )
            await degradeCandidate(candidate)
            return
        }
        let relatedRecords = preferences.useBehaviorHistory
            ? await behaviorStore.records(
                pattern: candidate.patternType,
                source: candidate.source,
                appCategory: preferences.foregroundApplicationContextEnabled ? candidate.appCategory : nil,
                limit: 5
            )
            : []
        guard !Task.isCancelled, candidateIsCurrentlyAllowed(candidate) else {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        var historicalAggregate = preferences.useBehaviorHistory
            ? await behaviorStore.aggregate(for: candidate.patternType)
            : nil
        guard !Task.isCancelled, candidateIsCurrentlyAllowed(candidate) else {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        let judgmentPersonality: AssistantPersonality = if preferences.personality == .lightTeasing,
                                                            (historicalAggregate?.unfunnyCount ?? 0) > 0 {
            .gentle
        } else {
            preferences.personality
        }
        // “不好笑”只影响表达，不允许进入主动价值权重。
        historicalAggregate?.unfunnyCount = 0
        let containsURL = semanticEvidence.contains(where: AssistantPrivacyPolicy.containsWebURL)
        let containsCode = semanticEvidence.contains(where: AssistantPrivacyPolicy.looksLikeCode)
        // P-06 遇到代码或 URL 时仍可做事实性的陪伴表达，但不能把原文直接带进 Quick Action。
        let blocksContextAction = candidate.patternType == .contextualOpportunity && (containsURL || containsCode)
        let availableActionIDs = blocksContextAction ? [] : candidate.actionIDs
        let availableTaskKinds = availableActionIDs.contains(.openQuickAction) ? candidate.availableTaskKinds : []
        let input = AssistantJudgmentInput(
            patternType: candidate.patternType,
            evidenceSummary: candidate.evidenceSummary,
            ephemeralEvidenceTexts: semanticEvidence,
            sourceTypes: candidate.sourceTypes,
            appCategory: preferences.foregroundApplicationContextEnabled ? candidate.appCategory : nil,
            evidenceCount: candidate.evidenceCount,
            durationSeconds: candidate.durationSeconds,
            languageConfidence: candidate.patternType == .foreignClipboard ? candidate.confidence : nil,
            sensitivity: .normal,
            evidenceSufficient: semanticEvidence.count >= requiredSemanticCount
                && (candidate.patternType == .contextualOpportunity || !availableActionIDs.isEmpty),
            containsURL: containsURL,
            containsCode: containsCode,
            userIsTyping: Self.userIsActivelyTyping,
            isFullScreen: Self.frontmostApplicationIsFullScreen,
            // V1 没有可信的投屏/会议信号，不把全屏等同于正在演示。
            isPresenting: false,
            responseLanguage: language == .chinese ? "zh-Hans" : "en",
            personality: judgmentPersonality,
            recentIrrelevantCount: relatedRecords.lazy.filter { $0.userFeedback == .irrelevant }.count,
            recentBehaviorSummaries: relatedRecords.map(Self.behaviorJudgmentSummary),
            historicalAggregate: historicalAggregate,
            proactivity: effectiveProactivity,
            hourlyPresentationCount: proactivePresentationCount,
            availableTaskKinds: availableTaskKinds,
            availableActionIDs: availableActionIDs
        )
        let minimumConfidenceOverride = preferences.judgmentConfidenceThresholdOverride
        if input.suppressesRepeatedlyIrrelevantFeedback {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .skipped,
                detail: "history-veto pattern=\(candidate.patternType.rawValue)"
            )
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        do {
            try Task.checkCancellation()
            guard candidateIsCurrentlyAllowed(candidate) else { throw CancellationError() }
            let startedAt = ContinuousClock.now
            try await withBackgroundTimeout(lease: lease, seconds: 8) { [appState] in
                try Task.checkCancellation()
                try await appState.warmUpDesktopAssistantJudgmentModel(id: modelID)
            }
            try Task.checkCancellation()
            guard candidateIsCurrentlyAllowed(candidate) else { throw CancellationError() }
            let warmupElapsed = ContinuousClock.now - startedAt
            let warmupSeconds = Double(warmupElapsed.components.seconds)
                + Double(warmupElapsed.components.attoseconds) / 1_000_000_000_000_000_000
            let generationLimit = min(5, max(0.05, 8 - warmupSeconds))
            let outputText = try await withBackgroundTimeout(lease: lease, seconds: generationLimit) { [appState] in
                try Task.checkCancellation()
                return try await appState.runDesktopAssistantJudgment(
                    input: input,
                    modelID: modelID,
                    minimumConfidenceOverride: minimumConfidenceOverride
                )
            }
            try Task.checkCancellation()
            guard let output = AssistantJudgmentContract.parse(outputText, input: input) else {
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .failed,
                    detail: "invalid-model-output pattern=\(candidate.patternType.rawValue)"
                )
                await degradeCandidate(candidate, judgmentModelID: modelID)
                return
            }
            let minimumConfidence = AssistantJudgmentContract.minimumConfidence(
                for: input.proactivity,
                override: minimumConfidenceOverride
            )
            guard AssistantJudgmentContract.permitsPeek(
                output,
                proactivity: input.proactivity,
                input: input,
                minimumConfidenceOverride: minimumConfidenceOverride
            ) else {
                let veto = if !output.isHighValue {
                    "not-high-value"
                } else if !output.evidenceSufficient {
                    "evidence-insufficient"
                } else if output.confidence < minimumConfidence {
                    "confidence"
                } else if output.recommendedPresentation != .peek {
                    "presentation"
                } else {
                    "actions"
                }
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .skipped,
                    detail: "model-veto=\(veto) pattern=\(candidate.patternType.rawValue) value=\(String(format: "%.2f", output.valueScore)) confidence=\(String(format: "%.2f", output.confidence)) threshold=\(String(format: "%.2f", minimumConfidence))"
                )
                await degradeCandidate(
                    candidate,
                    judgmentModelID: modelID,
                    judgmentConfidence: output.confidence
                )
                return
            }
            if let policyVeto = decisionPolicyVetoReason(for: candidate) {
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .skipped,
                    detail: "policy-veto=\(policyVeto) pattern=\(candidate.patternType.rawValue) confidence=\(String(format: "%.2f", output.confidence))"
                )
                await degradeCandidate(
                    candidate,
                    judgmentModelID: modelID,
                    judgmentConfidence: output.confidence
                )
                return
            }
            let lockedActions = output.suggestedActionIDs.filter(availableActionIDs.contains)
            guard !lockedActions.isEmpty || candidate.patternType == .contextualOpportunity else {
                recordDiagnosticActivity(
                    stage: .judgment,
                    state: .skipped,
                    detail: "action-mismatch pattern=\(candidate.patternType.rawValue)"
                )
                await degradeCandidate(candidate, judgmentModelID: modelID, judgmentConfidence: output.confidence)
                return
            }
            recordDiagnosticActivity(
                stage: .judgment,
                state: .succeeded,
                detail: "peek-approved pattern=\(candidate.patternType.rawValue) value=\(String(format: "%.2f", output.valueScore)) confidence=\(String(format: "%.2f", output.confidence)) threshold=\(String(format: "%.2f", minimumConfidence))"
            )
            await addCandidateCard(
                candidate,
                presentation: .peek,
                actionIDs: lockedActions,
                judgmentModelID: modelID,
                judgmentConfidence: output.confidence,
                lockedEvidenceQuote: output.lockedEvidenceQuote,
                suggestedTask: output.suggestedTask,
                lockedComment: output.reason,
                contextSummary: semanticEvidence.joined(separator: "\n")
            )
        } catch is CancellationError {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .cancelled,
                detail: "pattern=\(candidate.patternType.rawValue)"
            )
            if candidatesToBadgeAfterPreemption.remove(candidate.id) != nil,
               candidateIsCurrentlyAllowed(candidate) {
                await degradeCandidate(candidate, judgmentModelID: modelID)
            } else {
                // 任意取消都必须归还检测器 reservation；只有用户模型抢占明确转为徽标。
                await persistCandidateDecision(candidate, presentation: .silent)
            }
            return
        } catch {
            recordDiagnosticActivity(
                stage: .judgment,
                state: .failed,
                detail: "timeout-or-model-error pattern=\(candidate.patternType.rawValue)"
            )
            await degradeCandidate(candidate, judgmentModelID: modelID)
        }
    }

    private func degradeCandidate(
        _ candidate: AssistantPatternCandidate,
        judgmentModelID: UUID? = nil,
        judgmentConfidence: Double? = nil
    ) async {
        switch candidate.patternType.conservativeFallbackPresentation {
        case .silent:
            recordDiagnosticActivity(
                stage: .presentation,
                state: .skipped,
                detail: "silent-fallback pattern=\(candidate.patternType.rawValue)"
            )
            await persistCandidateDecision(
                candidate,
                presentation: .silent,
                judgmentModelID: judgmentModelID,
                judgmentConfidence: judgmentConfidence
            )
        case .badge:
            await addCandidateAsBadge(
                candidate,
                judgmentModelID: judgmentModelID,
                judgmentConfidence: judgmentConfidence
            )
        case .peek:
            assertionFailure("A conservative fallback cannot request a peek.")
            recordDiagnosticActivity(
                stage: .presentation,
                state: .failed,
                detail: "invalid-fallback-presentation"
            )
            await persistCandidateDecision(candidate, presentation: .silent)
        }
    }

    private func addCandidateAsBadge(
        _ candidate: AssistantPatternCandidate,
        judgmentModelID: UUID? = nil,
        judgmentConfidence: Double? = nil
    ) async {
        guard lifecycle.observationIsAllowed,
              candidateIsCurrentlyAllowed(candidate) else {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        prunePresentationDates()
        if unreadCount == 0, badgeGroupDates.count >= AssistantProactivity.quiet.hourlyPresentationLimit {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        if unreadCount == 0 { badgeGroupDates.append(.now) }
        await addCandidateCard(
            candidate,
            presentation: .badge,
            actionIDs: candidate.actionIDs,
            judgmentModelID: judgmentModelID,
            judgmentConfidence: judgmentConfidence
        )
    }

    private func addCandidateCard(
        _ candidate: AssistantPatternCandidate,
        presentation: AssistantPresentation,
        actionIDs: [AssistantActionID],
        judgmentModelID: UUID?,
        judgmentConfidence: Double?,
        lockedEvidenceQuote: String? = nil,
        suggestedTask: TaskKind? = nil,
        lockedComment: String? = nil,
        contextSummary: String? = nil,
        allowDeferral: Bool = true
    ) async {
        guard candidateIsCurrentlyAllowed(candidate) else {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        let wordingAggregate = preferences.useBehaviorHistory
            ? await behaviorStore.aggregate(for: candidate.patternType)
            : AssistantPatternAggregate()
        let commentPersonality: AssistantPersonality = if preferences.personality == .lightTeasing,
                                                           wordingAggregate.unfunnyCount > 0 {
            .gentle
        } else {
            preferences.personality
        }
        let commentInput = AssistantCommentInput(
            patternType: candidate.patternType,
            personality: commentPersonality,
            language: language == .chinese ? "zh-Hans" : "en",
            evidenceCount: candidate.evidenceCount,
            durationSeconds: candidate.durationSeconds,
            foreignLanguage: candidate.language,
            evidenceQuote: lockedEvidenceQuote,
            suggestedTask: suggestedTask,
            allowedActionIDs: actionIDs,
            contextSummary: contextSummary
        )
        let comment = lockedComment ?? AssistantCommentTemplates.comment(for: commentInput)
        let includesJoke = commentPersonality == .lightTeasing
        if allowDeferral,
           presentation == .peek,
           decisionPolicyVetoReason(for: candidate) == nil,
           let blockReason = transientPresentationBlockReason() {
            enqueuePendingPresentation(
                AssistantPendingPresentation(
                    candidate: candidate,
                    presentation: presentation,
                    actionIDs: actionIDs,
                    judgmentModelID: judgmentModelID,
                    judgmentConfidence: judgmentConfidence,
                    lockedEvidenceQuote: lockedEvidenceQuote,
                    suggestedTask: suggestedTask,
                    comment: comment
                ),
                reason: blockReason
            )
            return
        }
        if let cardClearTask { await cardClearTask.value }
        guard candidateIsCurrentlyAllowed(candidate) else {
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        let finalPresentation = lifecycle.resolvedPresentation(
            requested: presentation,
            hardPolicyAllowsPeek: hardPolicyAllowsPeek(for: candidate)
        )
        guard finalPresentation != .badge || !actionIDs.isEmpty else {
            // 无动作 P-06 不计徽标；暂时无法展开时宁可等待下一次可信情境，也不保存一条不可见“徽标”。
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        let card = AssistantCard(
            source: candidate.source,
            patternType: candidate.patternType,
            presentation: finalPresentation,
            comment: comment,
            evidenceSummary: evidenceText(for: candidate),
            evidence: AssistantCardEvidence(
                sources: candidate.sourceTypes,
                count: candidate.evidenceCount,
                durationSeconds: candidate.durationSeconds,
                usedLocalModel: judgmentModelID != nil,
                rawContextAvailable: candidate.rawContextReference != nil,
                capability: candidate.patternType.rawValue
            ),
            actionIDs: actionIDs,
            confidence: judgmentConfidence ?? candidate.confidence,
            expiresAt: candidate.expiresAt
        )
        let storedCards = await cardStore.add(card)
        // actor hop 期间可能切换隐私、停用或撤销来源；失效卡必须回滚，不能重新挂回原文引用。
        guard candidateIsCurrentlyAllowed(candidate) else {
            let rollbackEpoch = cardEpoch
            let rolledBackCards = await cardStore.remove(id: card.id)
            commitCardSnapshot(rolledBackCards, expectedEpoch: rollbackEpoch)
            await persistCandidateDecision(candidate, presentation: .silent)
            return
        }
        cards = storedCards
        if let reference = candidate.rawContextReference {
            cardRawContextReferences[card.id] = reference
            let workbenchReference = candidate.workbenchContextReference ?? reference
            if let route = workbenchRoutesByRawContext[workbenchReference] {
                cardWorkbenchRoutes[card.id] = route
            }
        }
        if let foreignLanguage = candidate.language {
            cardForeignLanguages[card.id] = foreignLanguage
        }
        if candidate.patternType == .contextualOpportunity,
           let lockedEvidenceQuote,
           !lockedEvidenceQuote.isEmpty,
           let suggestedTask {
            cardOpportunityQuotes[card.id] = lockedEvidenceQuote
            cardOpportunityTasks[card.id] = suggestedTask
        }
        if let appIdentity = candidate.appIdentity { cardAppIdentities[card.id] = appIdentity }
        if includesJoke { cardsIncludingJoke.insert(card.id) }
        cardBehaviorRecordIDs[card.id] = card.id
        pruneCardMetadata()
        var deliveredPresentation = finalPresentation
        if finalPresentation == .peek {
            if showProactiveCard(card.id) {
                proactivePresentationDates.append(.now)
                proactivelyPresentedCardIDs.insert(card.id)
                proactiveOriginCardIDs.insert(card.id)
            } else if actionIDs.isEmpty {
                let rollbackEpoch = cardEpoch
                let rolledBackCards = await cardStore.remove(id: card.id)
                commitCardSnapshot(rolledBackCards, expectedEpoch: rollbackEpoch)
                pruneCardMetadata()
                await persistCandidateDecision(candidate, presentation: .silent)
                return
            } else {
                deliveredPresentation = .badge
            }
        }
        await persistCandidateDecision(
            candidate,
            presentation: deliveredPresentation,
            cardID: card.id,
            judgmentModelID: judgmentModelID,
            judgmentConfidence: judgmentConfidence
        )
        recordDiagnosticActivity(
            stage: .presentation,
            state: .succeeded,
            detail: "\(deliveredPresentation.rawValue) pattern=\(candidate.patternType.rawValue) actions=\(actionIDs.count)"
        )
    }

    private func enqueuePendingPresentation(_ pending: AssistantPendingPresentation, reason: String) {
        let key = pending.candidate.decisionKey
        guard pendingPresentations[key] == nil else {
            // 同一决策只保留第一个待展示结果；它仍持有检测器预留，不能由重复项提前结算。
            discardCandidateTracking(pending.candidate.id)
            return
        }
        if pendingPresentations.count >= AssistantCandidateQueue.maximumCount,
           let lowest = pendingPresentations.min(by: {
               $0.value.candidate.priority < $1.value.candidate.priority
           }) {
            guard pending.candidate.priority > lowest.value.candidate.priority else {
                Task { await persistCandidateDecision(pending.candidate, presentation: .silent) }
                return
            }
            pendingPresentations.removeValue(forKey: lowest.key)
            Task { await persistCandidateDecision(lowest.value.candidate, presentation: .silent) }
        }
        pendingPresentations[key] = pending
        recordDiagnosticActivity(
            stage: .presentation,
            state: .scheduled,
            detail: "deferred=\(reason) pattern=\(pending.candidate.patternType.rawValue) pending=\(pendingPresentations.count)"
        )
        schedulePendingPresentations()
    }

    private func schedulePendingPresentations() {
        guard pendingPresentationTask == nil, !pendingPresentations.isEmpty else { return }
        pendingPresentationGeneration &+= 1
        let generation = pendingPresentationGeneration
        pendingPresentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await drainPendingPresentations(generation: generation)
            guard generation == pendingPresentationGeneration else { return }
            pendingPresentationTask = nil
            if !pendingPresentations.isEmpty { schedulePendingPresentations() }
        }
    }

    private func drainPendingPresentations(generation: UInt64) async {
        while !Task.isCancelled, generation == pendingPresentationGeneration {
            let invalid = pendingPresentations.values.filter { !candidateIsCurrentlyAllowed($0.candidate) }
            for item in invalid {
                pendingPresentations.removeValue(forKey: item.candidate.decisionKey)
                await persistCandidateDecision(item.candidate, presentation: .silent)
            }
            guard let next = pendingPresentations.values.max(by: {
                if $0.candidate.priority != $1.candidate.priority {
                    return $0.candidate.priority < $1.candidate.priority
                }
                return $0.candidate.createdAt > $1.candidate.createdAt
            }) else { return }

            if let veto = decisionPolicyVetoReason(for: next.candidate) {
                pendingPresentations.removeValue(forKey: next.candidate.decisionKey)
                recordDiagnosticActivity(
                    stage: .presentation,
                    state: .skipped,
                    detail: "deferred-veto=\(veto) pattern=\(next.candidate.patternType.rawValue)"
                )
                if next.actionIDs.isEmpty {
                    await persistCandidateDecision(next.candidate, presentation: .silent)
                } else {
                    await addCandidateCard(
                        next.candidate,
                        presentation: .badge,
                        actionIDs: next.actionIDs,
                        judgmentModelID: next.judgmentModelID,
                        judgmentConfidence: next.judgmentConfidence,
                        lockedEvidenceQuote: next.lockedEvidenceQuote,
                        suggestedTask: next.suggestedTask,
                        lockedComment: next.comment,
                        allowDeferral: false
                    )
                }
                continue
            }
            if transientPresentationBlockReason() != nil {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                continue
            }

            pendingPresentations.removeValue(forKey: next.candidate.decisionKey)
            await addCandidateCard(
                next.candidate,
                presentation: next.presentation,
                actionIDs: next.actionIDs,
                judgmentModelID: next.judgmentModelID,
                judgmentConfidence: next.judgmentConfidence,
                lockedEvidenceQuote: next.lockedEvidenceQuote,
                suggestedTask: next.suggestedTask,
                lockedComment: next.comment,
                allowDeferral: false
            )
        }
    }

    private func cancelPendingPresentations() {
        pendingPresentationGeneration &+= 1
        pendingPresentationTask?.cancel()
        pendingPresentationTask = nil
        let pending = Array(pendingPresentations.values)
        pendingPresentations.removeAll()
        for item in pending {
            Task { await persistCandidateDecision(item.candidate, presentation: .silent) }
        }
    }

    private func persistCandidateDecision(
        _ candidate: AssistantPatternCandidate,
        presentation: AssistantPresentation,
        cardID: UUID? = nil,
        judgmentModelID: UUID? = nil,
        judgmentConfidence: Double? = nil
    ) async {
        guard let candidateEpoch = candidateBehaviorEpochs[candidate.id] else {
            await patternDetector.settle(candidate, delivered: presentation != .silent)
            return
        }
        defer { discardCandidateTracking(candidate.id) }
        if let maintenanceTask { await maintenanceTask.value }
        guard candidateEpoch == behaviorEpoch,
              candidateIsCurrentlyAllowed(candidate) else {
            await patternDetector.settle(candidate, delivered: presentation != .silent)
            return
        }
        let outcome: AssistantBehaviorOutcome = switch presentation {
        case .silent: .suppressed
        case .badge: .badged
        case .peek: .presented
        }
        let record = AssistantBehaviorRecord(
            id: cardID ?? UUID(),
            patternType: candidate.patternType,
            sourceTypes: candidate.sourceTypes,
            appIdentity: preferences.foregroundApplicationContextEnabled ? candidate.appIdentity : nil,
            appCategory: preferences.foregroundApplicationContextEnabled ? candidate.appCategory : nil,
            evidenceFeatures: [
                "count": Double(candidate.evidenceCount),
                "durationSeconds": Double(candidate.durationSeconds),
                "confidence": candidate.confidence
            ],
            sanitizedEvidenceSummary: evidenceText(for: candidate),
            contentFingerprint: candidate.contentFingerprint,
            assistantDecision: presentation,
            judgmentModelID: judgmentModelID,
            judgmentConfidence: judgmentConfidence,
            presentationResult: outcome,
            expiresAt: .now.addingTimeInterval(AssistantBehaviorStore.retentionInterval)
        )
        _ = await behaviorStore.append(record)
        behaviorSummary = await behaviorStore.summary()
        await patternDetector.settle(candidate, delivered: presentation != .silent)
    }

    private func candidateIsCurrentlyAllowed(_ candidate: AssistantPatternCandidate) -> Bool {
        guard lifecycle.observationIsAllowed,
              userIsPresent,
              preferences.isEnabled,
              preferences.proactivity != .manual,
              candidate.expiresAt > .now,
              candidateBehaviorEpochs[candidate.id] == behaviorEpoch,
              candidateContextEpochs[candidate.id] == contextEpoch,
              candidateCardEpochs[candidate.id] == cardEpoch else { return false }
        switch candidate.patternType {
        case .repeatedFailure:
            guard preferences.repeatedFailureEnabled else { return false }
        case .foreignClipboard:
            guard preferences.foreignClipboardEnabled,
                  preferences.clipboardAuthorization == .allowed else { return false }
        case .contextualOpportunity:
            if candidate.surfaceID != nil,
               !activityObserver.surfaceIsCurrent(
                   id: candidate.surfaceID,
                   revision: candidate.surfaceRevision,
                   anchorGeneration: candidate.anchorGeneration
               ) {
                return false
            }
        }
        guard candidate.sourceTypes.allSatisfy(sourceIsCurrentlyAuthorized) else { return false }
        guard let appIdentity = candidate.appIdentity else { return true }
        return privacyPolicy.sensitivity(text: nil, bundleID: appIdentity) != .excludedApplication
    }

    @discardableResult
    private func showProactiveCard(_ id: UUID) -> Bool {
        guard lifecycle.isVisible else { return false }
        let requiresUserAction = cards.first(where: { $0.id == id })?.requiresUserAction == true
        let expectedCardEpoch = cardEpoch
        panelContent = .card(id)
        guard windowController?.showPeek(activating: false) == true else {
            panelContent = .none
            return false
        }
        currentProactiveCardID = id
        Task {
            let storedCards = await cardStore.markViewed(id: id)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
        }
        peekTimeoutTask?.cancel()
        peekTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, currentProactiveCardID == id else { return }
            currentProactiveCardID = nil
            proactivelyPresentedCardIDs.remove(id)
            // D-09：无交互收回后必须重新成为未读徽标，不能因曾经露出过就永久消失。
            let storedCards = await cardStore.update(id: id, state: .unread)
            guard commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch) else { return }
            panelContent = .none
            windowController?.hidePeek()
            if requiresUserAction {
                applySessionInteraction(.noInteractionTimeout)
            }
        }
        return true
    }

    private func hardPolicyAllowsPeek(for candidate: AssistantPatternCandidate, now: Date = .now) -> Bool {
        decisionPolicyVetoReason(for: candidate, now: now) == nil
            && transientPresentationBlockReason() == nil
    }

    private func decisionPolicyVetoReason(for candidate: AssistantPatternCandidate, now: Date = .now) -> String? {
        prunePresentationDates(now: now)
        guard lifecycle.observationIsAllowed else { return "observation-disabled" }
        guard userIsPresent else { return "user-absent" }
        guard candidate.expiresAt > now else { return "candidate-expired" }
        guard proactivePresentationCount < effectiveProactivity.hourlyPresentationLimit else { return "hourly-limit" }
        guard !preferences.quietHours.contains(now) || candidate.isTaskFailure else { return "quiet-hours" }
        guard effectiveProactivity == .moderate || effectiveProactivity == .active else {
            return "proactivity-inactive"
        }
        return nil
    }

    private func transientPresentationBlockReason() -> String? {
        guard lifecycle.isVisible else { return "assistant-hidden" }
        guard !userModelWorkIsActive else { return "user-model-busy" }
        guard !Self.userIsActivelyTyping else { return "user-typing" }
        guard preferences.showOverFullScreen || !Self.frontmostApplicationIsFullScreen else { return "fullscreen" }
        guard windowController?.assistantInteractionIsInProgress != true else { return "assistant-interaction" }
        guard panelContent == .none else { return "assistant-panel-visible" }
        guard currentProactiveCardID == nil else { return "another-peek-visible" }
        return nil
    }

    private var proactivePresentationCount: Int {
        proactivePresentationDates.lazy.filter { $0 > Date.now.addingTimeInterval(-3_600) }.count
    }

    private func prunePresentationDates(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-3_600)
        proactivePresentationDates.removeAll { $0 <= cutoff }
        badgeGroupDates.removeAll { $0 <= cutoff }
    }

    private func evidenceText(for candidate: AssistantPatternCandidate) -> String {
        let minutes = max(1, Int(ceil(Double(candidate.durationSeconds) / 60)))
        switch candidate.patternType {
        case .repeatedFailure:
            return text(
                "过去 \(minutes) 分钟检测到相同错误 \(candidate.evidenceCount) 次",
                "The same error appeared \(candidate.evidenceCount) times in \(minutes) minutes"
            )
        case .foreignClipboard:
            return text(
                "过去 \(minutes) 分钟检测到 \(candidate.evidenceCount) 条同语种外语文本",
                "Detected \(candidate.evidenceCount) foreign-language texts in \(minutes) minutes"
            )
        case .contextualOpportunity:
            return text(
                "结合当前操作与窗口状态，使用了 \(candidate.evidenceCount) 条已授权情境依据",
                "Used \(candidate.evidenceCount) authorized context items from the current action and window state"
            )
        }
    }

    private static func behaviorJudgmentSummary(_ record: AssistantBehaviorRecord) -> String {
        let feedback = record.userFeedback?.rawValue ?? "none"
        let action = record.selectedActionID?.rawValue ?? "none"
        let succeeded = record.actionSucceeded.map(String.init) ?? "unknown"
        return "decision=\(record.assistantDecision.rawValue) result=\(record.presentationResult.rawValue) feedback=\(feedback) action=\(action) succeeded=\(succeeded)"
    }

    private func cancelCandidateJudgment(discardQueue: Bool = false) {
        judgmentTask?.cancel()
        if discardQueue { retireQueuedCandidates(candidateQueue.clear()) }
    }

    private func retireQueuedCandidates(
        _ candidates: [AssistantPatternCandidate],
        replacingCandidate: AssistantPatternCandidate? = nil
    ) {
        for candidate in candidates where candidate.id != replacingCandidate?.id {
            if candidate.decisionKey == replacingCandidate?.decisionKey {
                // 新候选继承同一检测器预留；这里只清掉旧队列项的 epoch，不能提前解除预留。
                discardCandidateTracking(candidate.id)
                continue
            }
            Task { await persistCandidateDecision(candidate, presentation: .silent) }
        }
    }

    private func discardCandidateTracking(_ id: UUID) {
        candidateBehaviorEpochs.removeValue(forKey: id)
        candidateContextEpochs.removeValue(forKey: id)
        candidateCardEpochs.removeValue(forKey: id)
        candidatesToBadgeAfterPreemption.remove(id)
    }

    private func discardAllCandidateTracking() {
        candidateBehaviorEpochs.removeAll()
        candidateContextEpochs.removeAll()
        candidateCardEpochs.removeAll()
        candidatesToBadgeAfterPreemption.removeAll()
    }

    private func cancelStageCWork(cancelQualification shouldCancelQualification: Bool) {
        cancelCandidateJudgment(discardQueue: true)
        cancelContextOpportunityAggregation()
        cancelPendingPresentations()
        peekTimeoutTask?.cancel()
        patternUndoTask?.cancel()
        stopTemporaryTranslation()
        if shouldCancelQualification { cancelQualification() }
        Task { await patternDetector.clear() }
    }

    private func applySessionInteraction(_ interaction: AssistantSessionInteraction) {
        _ = sessionProactivity.apply(interaction)
        sessionProactivityWasDowngraded = sessionProactivity.didDowngrade
        if !visualContextAnalysisIsEnabled {
            activityObserver.cancelPendingVisualCapture(reason: visualContextAnalysisDisableReason)
        }
    }

    private static var userIsActivelyTyping: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1.5
    }

    fileprivate static var frontmostApplicationIsFullScreen: Bool {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        return windowList.contains { item in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
                  (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let rawBounds = item[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return false }
            return screenSizes.contains {
                abs($0.width - frame.width) <= 2 && abs($0.height - frame.height) <= 2
            }
        }
    }

    func cardIncludesJoke(_ card: AssistantCard) -> Bool {
        cardsIncludingJoke.contains(card.id)
    }

    func actionIsAvailable(_ action: AssistantActionID, for card: AssistantCard) -> Bool {
        guard card.expiresAt.map({ $0 > .now }) ?? true else { return false }
        switch action {
        case .explainError, .translateCurrentClipboard, .detailedTranslation:
            return cardRawContextReferences[card.id] != nil && cardSourcesAreCurrentlyAuthorized(card)
        case .enableClipboardTranslation:
            return preferences.clipboardAuthorization == .allowed
                && preferences.foreignClipboardEnabled
                && cardForeignLanguages[card.id] != nil
        case .returnToWorkbench:
            return cardWorkbenchRoutes[card.id] != nil
        case .openQuickAction where card.patternType == .contextualOpportunity:
            return cardOpportunityQuotes[card.id] != nil
                && cardOpportunityTasks[card.id] != nil
                && cardSourcesAreCurrentlyAuthorized(card)
        default:
            return true
        }
    }

    func cardRawContextIsAvailable(_ card: AssistantCard) -> Bool {
        card.expiresAt.map { $0 > .now } == true && cardRawContextReferences[card.id] != nil
    }

    private func openRawContext(card: AssistantCard, task: TaskKind, action: AssistantActionID) {
        guard let reference = cardRawContextReferences[card.id] else { return }
        let epoch = contextEpoch
        let expectedCardEpoch = cardEpoch
        Task {
            guard let rawText = await contextBuffer.rawText(for: reference) else {
                let storedCards = await cardStore.update(id: card.id, state: .expired)
                commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
                finishAction(action, card: card, succeeded: false)
                return
            }
            guard !Task.isCancelled,
                  epoch == contextEpoch,
                  cardRawContextReferences[card.id] == reference,
                  actionIsAvailable(action, for: card) else {
                finishAction(action, card: card, succeeded: false)
                return
            }
            onOpenQuickActionTask?(rawText, task)
            dismissPanel()
            finishAction(action, card: card, succeeded: true)
        }
    }

    private func finishAction(_ action: AssistantActionID, card: AssistantCard, succeeded: Bool) {
        let wasProactivelyPresented = proactivelyPresentedCardIDs.remove(card.id) != nil
        if succeeded, wasProactivelyPresented { applySessionInteraction(.positive) }
        guard ephemeralInquiryCard?.id != card.id else { return }
        let expectedCardEpoch = cardEpoch
        Task {
            let storedCards = await cardStore.update(id: card.id, state: succeeded ? .acted : .viewed)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
            if let recordID = cardBehaviorRecordIDs[card.id] {
                _ = await behaviorStore.update(
                    id: recordID,
                    outcome: succeeded ? .acted : .viewed,
                    selectedActionID: action,
                    actionSucceeded: succeeded
                )
                behaviorSummary = await behaviorStore.summary()
            }
        }
    }

    private func handleDetectedForeignClipboard(
        text: String,
        language: String,
        event: AssistantActivityEvent,
        effectiveCharacterCount: Int
    ) {
        guard effectiveCharacterCount >= AssistantPatternDetector.foreignClipboardMinimumCharacterCount,
              event.confidence >= AssistantPatternDetector.foreignClipboardMinimumConfidence,
              let reference = event.ephemeralContextReference else { return }
        let now = Date.now
        guard temporaryTranslationSession.accepts(language: language, occurredAt: event.occurredAt, now: now) else {
            if let expiresAt = temporaryTranslationExpiresAt, expiresAt <= now {
                stopTemporaryTranslation()
            }
            return
        }
        enqueueTranslation(AssistantPendingTranslation(
            text: text,
            language: language,
            occurredAt: event.occurredAt,
            expiresAt: min(event.expiresAt, event.occurredAt.addingTimeInterval(AssistantContextBuffer.rawContextTTL)),
            rawContextReference: reference,
            requiresActiveSession: true,
            sourceCardID: nil
        ))
    }

    private func startTemporaryTranslation(language: String) {
        temporaryTranslationSession.start(language: language)
        temporaryTranslationExpiresAt = temporaryTranslationSession.expiresAt
        temporaryTranslationOriginRecordID = selectedCard.flatMap { cardBehaviorRecordIDs[$0.id] }
        translationExpiryTask?.cancel()
        translationExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AssistantTemporaryTranslationSession.duration))
            guard !Task.isCancelled else { return }
            self?.stopTemporaryTranslation()
        }
    }

    private func translateCardSourceOnce(_ card: AssistantCard) {
        guard let reference = cardRawContextReferences[card.id],
              let language = cardForeignLanguages[card.id] else { return }
        let epoch = contextEpoch
        let expectedCardEpoch = cardEpoch
        Task {
            guard let rawText = await contextBuffer.rawText(for: reference) else {
                let storedCards = await cardStore.update(id: card.id, state: .expired)
                commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
                finishAction(.translateCurrentClipboard, card: card, succeeded: false)
                return
            }
            guard !Task.isCancelled,
                  epoch == contextEpoch,
                  cardRawContextReferences[card.id] == reference,
                  cardForeignLanguages[card.id] == language,
                  actionIsAvailable(.translateCurrentClipboard, for: card) else {
                finishAction(.translateCurrentClipboard, card: card, succeeded: false)
                return
            }
            enqueueTranslation(AssistantPendingTranslation(
                text: rawText,
                language: language,
                occurredAt: .now,
                expiresAt: min(card.expiresAt ?? .now.addingTimeInterval(AssistantContextBuffer.rawContextTTL), .now.addingTimeInterval(AssistantContextBuffer.rawContextTTL)),
                rawContextReference: reference,
                requiresActiveSession: false,
                sourceCardID: card.id
            ))
            dismissPanel()
        }
    }

    private func enqueueTranslation(_ translation: AssistantPendingTranslation) {
        guard translation.expiresAt > .now else { return }
        if translation.sourceCardID != nil {
            pendingTranslations.insert(translation, at: 0)
            // 显式翻译是用户任务：资格检查保留进度，价值判断按各模式的保守策略让位。
            qualificationPauseRequested = qualificationTask != nil
            if qualificationRun != nil { qualificationTask?.cancel() }
            if let currentJudgmentCandidate {
                candidatesToBadgeAfterPreemption.insert(currentJudgmentCandidate.id)
                judgmentTask?.cancel()
            }
        } else {
            pendingTranslations.append(translation)
        }
        // 原文队列同时受 10 分钟 TTL 和数量上限约束，不能跟随 30 分钟会话延长留存。
        if pendingTranslations.count > 20 {
            pendingTranslations.removeFirst(pendingTranslations.count - 20)
        }
        startNextTranslationIfNeeded()
    }

    private func startNextTranslationIfNeeded() {
        pendingTranslations.removeAll { $0.expiresAt <= .now }
        guard translationTask == nil,
              !userModelWorkIsActive,
              !pendingTranslations.isEmpty,
              let lease = backgroundWorkArbiter.claim(.translation) else { return }
        let item = pendingTranslations.removeFirst()
        if item.requiresActiveSession,
           !temporaryTranslationSession.accepts(language: item.language, occurredAt: item.occurredAt) {
            finishBackgroundWorkflow(lease)
            return
        }
        activeTranslation = item
        let expectedCardEpoch = cardEpoch
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await appState.runDesktopAssistantLocalTranslation(
                    text: item.text,
                    sourceLanguage: item.language,
                    targetLanguage: appState.preferences.defaultTranslationTarget
                )
                try Task.checkCancellation()
                guard expectedCardEpoch == cardEpoch,
                      preferences.clipboardAuthorization == .allowed,
                      item.expiresAt > .now,
                      await contextBuffer.rawText(for: item.rawContextReference) != nil else {
                    throw CancellationError()
                }
                await showTranslationResult(result.text, item: item, expectedCardEpoch: expectedCardEpoch)
                if let sourceCardID = item.sourceCardID,
                   let sourceCard = cards.first(where: { $0.id == sourceCardID }) {
                    finishAction(.translateCurrentClipboard, card: sourceCard, succeeded: true)
                }
            } catch is CancellationError {
                activeTranslation = nil
                translationTask = nil
                finishBackgroundWorkflow(lease)
                return
            } catch {
                guard expectedCardEpoch == cardEpoch,
                      preferences.clipboardAuthorization == .allowed,
                      item.expiresAt > .now,
                      await contextBuffer.rawText(for: item.rawContextReference) != nil else {
                    activeTranslation = nil
                    translationTask = nil
                    finishBackgroundWorkflow(lease)
                    return
                }
                await showTranslationFailure(item: item, expectedCardEpoch: expectedCardEpoch)
            }
            activeTranslation = nil
            translationTask = nil
            finishBackgroundWorkflow(lease)
        }
    }

    private func showTranslationResult(
        _ translation: String,
        item: AssistantPendingTranslation,
        expectedCardEpoch: UInt64
    ) async {
        let isFullScreen = Self.frontmostApplicationIsFullScreen
        let cardID: UUID
        if isFullScreen {
            cardID = deferredFullscreenTranslationCardID ?? UUID()
            deferredFullscreenTranslationCardID = cardID
        } else {
            cardID = UUID()
            deferredFullscreenTranslationCardID = nil
        }
        let card = AssistantCard(
            id: cardID,
            source: .clipboard,
            patternType: .foreignClipboard,
            presentation: .peek,
            comment: translation,
            evidenceSummary: "\(item.language) -> \(appState.preferences.defaultTranslationTarget)",
            evidence: AssistantCardEvidence(
                sources: [.clipboard],
                usedLocalModel: true,
                rawContextAvailable: true,
                capability: "temporary-clipboard-translation"
            ),
            actionIDs: [.copyTranslation, .detailedTranslation],
            // 12 秒是窗口展示时长；原文与未读卡仍按短期上下文 TTL 保留。
            expiresAt: .now.addingTimeInterval(AssistantContextBuffer.rawContextTTL),
            detailText: translation
        )
        let storedCards = await cardStore.add(card)
        let rawContextIsStillAvailable = await contextBuffer.rawText(for: item.rawContextReference) != nil
        // 剪贴板授权可能在 card store actor hop 期间被撤销，不能让迟到译文恢复会话原文引用。
        guard expectedCardEpoch == cardEpoch,
              lifecycle.observationIsAllowed,
              preferences.clipboardAuthorization == .allowed,
              item.expiresAt > .now,
              rawContextIsStillAvailable else {
            let rollbackEpoch = cardEpoch
            let rolledBackCards = await cardStore.remove(id: card.id)
            commitCardSnapshot(rolledBackCards, expectedEpoch: rollbackEpoch)
            return
        }
        cards = storedCards
        cardRawContextReferences[card.id] = item.rawContextReference
        cardForeignLanguages[card.id] = item.language
        if let sourceCardID = item.sourceCardID,
           let recordID = cardBehaviorRecordIDs[sourceCardID] {
            cardBehaviorRecordIDs[card.id] = recordID
        } else if let temporaryTranslationOriginRecordID {
            cardBehaviorRecordIDs[card.id] = temporaryTranslationOriginRecordID
        }
        pruneCardMetadata()
        guard !isFullScreen else { return }
        showExplicitResultCard(card.id)
    }

    private func showTranslationFailure(
        item: AssistantPendingTranslation,
        expectedCardEpoch: UInt64
    ) async {
        if item.requiresActiveSession {
            guard !temporaryTranslationSession.hasFailed else { return }
            temporaryTranslationSession.fail()
            temporaryTranslationExpiresAt = nil
            pendingTranslations.removeAll()
            translationExpiryTask?.cancel()
            translationExpiryTask = nil
        }
        let card = AssistantCard(
            source: .clipboard,
            patternType: .foreignClipboard,
            presentation: .peek,
            comment: item.requiresActiveSession
                ? text(
                    "本地翻译能力当前不可用，临时翻译已停止。",
                    "Local translation is unavailable, so the temporary session stopped."
                )
                : text(
                    "本地翻译能力当前不可用，未能翻译这条内容。",
                    "Local translation is unavailable for this item."
                ),
            evidenceSummary: text("未发送到远程服务", "Nothing was sent to a remote service"),
            evidence: AssistantCardEvidence(sources: [.clipboard], capability: "local-translation-unavailable"),
            actionIDs: [.openSettings],
            expiresAt: .now.addingTimeInterval(AssistantContextBuffer.rawContextTTL)
        )
        let storedCards = await cardStore.add(card)
        guard expectedCardEpoch == cardEpoch,
              lifecycle.observationIsAllowed,
              preferences.clipboardAuthorization == .allowed,
              item.expiresAt > .now else {
            let rollbackEpoch = cardEpoch
            let rolledBackCards = await cardStore.remove(id: card.id)
            commitCardSnapshot(rolledBackCards, expectedEpoch: rollbackEpoch)
            return
        }
        cards = storedCards
        if let sourceCardID = item.sourceCardID,
           let sourceCard = cards.first(where: { $0.id == sourceCardID }) {
            finishAction(.translateCurrentClipboard, card: sourceCard, succeeded: false)
        }
        pruneCardMetadata()
        if Self.frontmostApplicationIsFullScreen { return }
        showExplicitResultCard(card.id)
    }

    private func showExplicitResultCard(_ id: UUID) {
        guard lifecycle.isVisible else { return }
        let expectedCardEpoch = cardEpoch
        peekTimeoutTask?.cancel()
        currentProactiveCardID = nil
        panelContent = .card(id)
        guard windowController?.showPeek(activating: false) == true else {
            panelContent = .none
            return
        }
        Task {
            let storedCards = await cardStore.markViewed(id: id)
            commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
        }
        peekTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, panelContent == .card(id) else { return }
            panelContent = .none
            windowController?.hidePeek()
        }
    }

    private func stopTemporaryTranslation() {
        temporaryTranslationSession.stop()
        temporaryTranslationExpiresAt = nil
        temporaryTranslationOriginRecordID = nil
        pendingTranslations.removeAll()
        activeTranslation = nil
        translationTask?.cancel()
        translationTask = nil
        translationExpiryTask?.cancel()
        translationExpiryTask = nil
    }

    private func pruneCardMetadata() {
        let activeIDs = Set(cards.map(\.id))
        let contextActiveIDs = Set(cards.lazy.filter { $0.expiresAt.map { $0 > .now } ?? true }.map(\.id))
        // 历史卡可保留 30 天，但原文引用和深度操作路由只能活到短期上下文 TTL。
        cardRawContextReferences = cardRawContextReferences.filter { contextActiveIDs.contains($0.key) }
        cardWorkbenchRoutes = cardWorkbenchRoutes.filter { contextActiveIDs.contains($0.key) }
        cardForeignLanguages = cardForeignLanguages.filter { contextActiveIDs.contains($0.key) }
        cardOpportunityQuotes = cardOpportunityQuotes.filter { contextActiveIDs.contains($0.key) }
        cardOpportunityTasks = cardOpportunityTasks.filter { contextActiveIDs.contains($0.key) }
        let liveRawReferences = Set(cardRawContextReferences.values)
        workbenchRoutesByRawContext = workbenchRoutesByRawContext.filter { liveRawReferences.contains($0.key) }
        cardAppIdentities = cardAppIdentities.filter { activeIDs.contains($0.key) }
        cardBehaviorRecordIDs = cardBehaviorRecordIDs.filter { activeIDs.contains($0.key) }
        cardsIncludingJoke.formIntersection(activeIDs)
        proactivelyPresentedCardIDs.formIntersection(activeIDs)
        proactiveOriginCardIDs.formIntersection(activeIDs)
        settledSessionFeedbackByCard = settledSessionFeedbackByCard.filter { activeIDs.contains($0.key) }
        if let currentProactiveCardID, !activeIDs.contains(currentProactiveCardID) {
            self.currentProactiveCardID = nil
        }
        if let deferredFullscreenTranslationCardID, !activeIDs.contains(deferredFullscreenTranslationCardID) {
            self.deferredFullscreenTranslationCardID = nil
        }
    }

    private func selectedExplicitContext() -> String? {
        var sections: [String] = []
        if includeClipboardContext,
           let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           clipboardIsSafeForExplicitUse(clipboard) {
            sections.append("[clipboard]\n\(String(clipboard.prefix(12_000)))")
        }
        if includeCurrentCardContext,
           let card = attachableCurrentCard {
            sections.append("[current-card]\n\(card.comment)")
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private var attachableCurrentCard: AssistantCard? {
        if let selectedCard, selectedCard.isAvailableForExplicitContext() { return selectedCard }
        return cards.first { $0.isAvailableForExplicitContext() }
    }

    private func clipboardIsSafeForExplicitUse(_ value: String) -> Bool {
        observedClipboardChangeCount == NSPasteboard.general.changeCount
            && observedClipboardSensitivity == .normal
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && privacyPolicy.sensitivity(text: value, bundleID: nil) == .normal
    }

    private func cardSourcesAreCurrentlyAuthorized(_ card: AssistantCard) -> Bool {
        card.evidence.sources.allSatisfy(sourceIsCurrentlyAuthorized)
    }

    private func sourceIsCurrentlyAuthorized(_ source: AssistantSource) -> Bool {
        guard lifecycle.observationIsAllowed else { return false }
        switch source {
        case .clipboard:
            return preferences.clipboardAuthorization == .allowed
        case .selection:
            return preferences.selectionContextEnabled && AXIsProcessTrusted()
        case .foregroundApplication:
            return preferences.foregroundApplicationContextEnabled
        case .windowContext:
            return preferences.foregroundApplicationContextEnabled
                && preferences.enhancedWindowContextEnabled
                && (AXIsProcessTrusted() || CGPreflightScreenCaptureAccess())
        case .inquiry, .droppedFile, .llmToolsTask:
            return true
        }
    }

    private func finishDropRouting() {
        pendingDropPayload = nil
        panelContent = .none
        windowController?.hidePeek()
    }

    private func scheduleResume(at date: Date) {
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.lifecycle.apply(.tick(.now))
            self?.refreshObservation(loadBehaviorStore: false)
        }
    }

    private func ingestText(
        _ text: String,
        type: AssistantActivityType,
        source: AssistantSource,
        bundleID: String?,
        removeErrorNoise: Bool,
        workbenchIsRecoverable: Bool = false,
        workbenchRoute: AssistantWorkbenchRoute? = nil,
        observedAt: Date = .now,
        surfaceID: String? = nil,
        surfaceRevision: UInt64 = 0,
        anchorGeneration: UInt64 = 0,
        provenance: AssistantEvidenceProvenance = .explicit
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard userIsPresent, !value.isEmpty else { return }
        let policy = privacyPolicy
        let sensitivity = policy.sensitivity(text: value, bundleID: bundleID)
        guard sensitivity != .excludedApplication else { return }
        let epoch = contextEpoch
        let suppressionEpoch = behaviorEpoch
        Task {
            let fingerprint = sensitivity == .normal
                ? try? await fingerprintStore.fingerprint(text: value, removeErrorNoise: removeErrorNoise)
                : nil
            guard let event = await contextBuffer.appendIfCurrent(
                AssistantActivityEvent(
                    occurredAt: observedAt,
                    type: type,
                    source: source,
                    appIdentity: sensitivity == .normal && preferences.foregroundApplicationContextEnabled ? bundleID : nil,
                    contentType: .text,
                    contentFingerprint: fingerprint,
                    sensitivity: sensitivity,
                    surfaceID: surfaceID,
                    surfaceRevision: surfaceRevision,
                    anchorGeneration: anchorGeneration,
                    provenance: provenance
                ),
                rawText: sensitivity == .normal ? value : nil,
                expectedEpoch: epoch
            ) else { return }
            lastSourceUse[source] = .now
            if sensitivity == .sensitive {
                await persistSensitiveSuppression(expectedEpoch: suppressionEpoch)
                return
            }
            if let reference = event.ephemeralContextReference, let workbenchRoute {
                workbenchRoutesByRawContext[reference] = workbenchRoute
            }
            let looksLikeError = AssistantPatternRules.looksLikeError(value)
            if sensitivity == .normal, !looksLikeError {
                await collectContextOpportunity(event, expectedContextEpoch: epoch)
            }
            guard sensitivity == .normal,
                  !Task.isCancelled,
                  epoch == contextEpoch,
                  sourceIsCurrentlyAuthorized(source),
                  preferences.proactivity != .manual,
                  preferences.repeatedFailureEnabled,
                  looksLikeError,
                  let candidate = await patternDetector.ingestFailure(
                      event,
                      workbenchIsRecoverable: workbenchIsRecoverable
                  ) else { return }
            handlePatternCandidate(candidate, expectedContextEpoch: epoch)
        }
    }

    private func persistSensitiveSuppression(expectedEpoch: UInt64) async {
        if let maintenanceTask { await maintenanceTask.value }
        guard expectedEpoch == behaviorEpoch else { return }
        let record = AssistantBehaviorRecord(
            patternType: nil,
            sourceTypes: [],
            sensitivity: .sensitive,
            assistantDecision: .silent,
            presentationResult: .suppressed,
            suppressionReason: .sensitiveContent
        )
        _ = await behaviorStore.append(record)
        behaviorSummary = await behaviorStore.summary()
    }

    private func refreshObservation(
        loadBehaviorStore: Bool,
        preferences: DesktopAssistantPreferences? = nil
    ) {
        let preferences = preferences ?? self.preferences
        guard !isStageAPreview else { return }
        updateContextMaintenance()
        guard loadBehaviorStore,
              preferences.isEnabled,
              preferences.hasCompletedCurrentOnboarding else {
            activityObserver.apply(preferences: preferences, lifecycle: lifecycle)
            return
        }
        activityObserver.stop()
        behaviorLoadTask?.cancel()
        behaviorLoadTask = Task {
            try? await fingerprintStore.ensureKey()
            _ = await behaviorStore.load()
            guard !Task.isCancelled, lifecycle.observationIsAllowed else { return }
            behaviorSummary = await behaviorStore.summary()
            behaviorLoadTask = nil
            activityObserver.apply(preferences: preferences, lifecycle: lifecycle)
        }
    }

    private func stopObservationAndClearContext() {
        activityObserver.stop()
        contextMaintenanceTask?.cancel()
        contextMaintenanceTask = nil
        behaviorLoadTask?.cancel()
        clearShortTermContext()
        lastSourceUse.removeAll()
    }

    private func updateContextMaintenance() {
        guard lifecycle.observationIsAllowed else {
            contextMaintenanceTask?.cancel()
            contextMaintenanceTask = nil
            return
        }
        guard contextMaintenanceTask == nil else { return }
        contextMaintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self, lifecycle.observationIsAllowed else { return }
                // 空闲时也要兑现 10/60 分钟 TTL，并同步卡片未读和 30 天磁盘保留。
                _ = await contextBuffer.snapshot()
                let expectedCardEpoch = cardEpoch
                let storedCards = await cardStore.snapshot()
                commitCardSnapshot(storedCards, expectedEpoch: expectedCardEpoch)
                pendingTranslations.removeAll { $0.expiresAt <= .now }
                if activeTranslation?.expiresAt ?? .distantFuture <= .now {
                    translationTask?.cancel()
                }
                behaviorSummary = await behaviorStore.summary()
            }
        }
    }

    private func clearContext(appIdentity: String) {
        contextEpoch &+= 1
        cancelContextOpportunityAggregation()
        let epoch = contextEpoch
        Task { await contextBuffer.advanceEpochAndClear(to: epoch, appIdentity: appIdentity) }
        cancelCandidateJudgment(discardQueue: true)
        discardAllCandidateTracking()
        let cardIDs = Set(cardAppIdentities.compactMap {
            $0.value.caseInsensitiveCompare(appIdentity) == .orderedSame ? $0.key : nil
        })
        clearCardRawContext(cardIDs: cardIDs)
        Task { await patternDetector.clearContextOpportunitySamples() }
    }

    private func clearCardRawContext(for source: AssistantSource) {
        clearCardRawContext(cardIDs: Set(cards.lazy.filter { $0.evidence.sources.contains(source) }.map(\.id)))
    }

    private func clearCardRawContext(cardIDs: Set<UUID>) {
        let references = Set(cardIDs.compactMap { cardRawContextReferences[$0] })
        cardIDs.forEach {
            cardRawContextReferences.removeValue(forKey: $0)
            cardWorkbenchRoutes.removeValue(forKey: $0)
            cardForeignLanguages.removeValue(forKey: $0)
            cardOpportunityQuotes.removeValue(forKey: $0)
            cardOpportunityTasks.removeValue(forKey: $0)
            cardAppIdentities.removeValue(forKey: $0)
        }
        references.forEach { workbenchRoutesByRawContext.removeValue(forKey: $0) }
    }

    private func requestAccessibilityForDraftSourcesIfNeeded() {
        let usesEnhancedWindowContext = draftForegroundApplicationEnabled && draftEnhancedWindowContextEnabled
        SelectedTextService.showPermissionGuideIfNeeded(
            requiresAccessibility: usesEnhancedWindowContext || draftSelectionContextEnabled,
            requiresScreenRecording: usesEnhancedWindowContext
        )
    }

    private static func languagesMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = LanguageCodeNormalizer.normalizedBCP47(lhs),
              let right = LanguageCodeNormalizer.normalizedBCP47(rhs) else { return false }
        if left == right { return true }
        return left.split(separator: "-").first == right.split(separator: "-").first
    }
}

@MainActor
private final class AssistantActivityObserver: NSObject {
    private struct SurfaceSnapshot {
        var id: String?
        var revision: UInt64
        var anchorGeneration: UInt64
    }

    private struct ClipboardSnapshot {
        var changeCount: Int
        var observedAt: Date
        var bundleID: String?
        var possibleBundleIDs: [String]
        var surface: SurfaceSnapshot
        var userInitiated: Bool
        var sourceIsReliable: Bool
        var kind: AssistantClipboardObservationKind
        var text: String?
    }

    private enum VisualCaptureTrigger: String {
        case userInteraction = "user-interaction"
        case applicationActivated = "application-activated"
    }

    private static let userIdleTimeout: TimeInterval = 60
    private static let visualCaptureDebounce: TimeInterval = 3
    private static let minimumVisualCaptureInterval: TimeInterval = 15
    private static let failedVisualCaptureRetryInterval: TimeInterval = 30

    private weak var coordinator: AssistantContextCoordinator?
    private var workspaceObserverInstalled = false
    private var presenceObserverInstalled = false
    private var clipboardTimer: Timer?
    private var permissionTimer: Timer?
    private var userActivityTimer: Timer?
    private var userIdleTask: Task<Void, Never>?
    private var visualCaptureTask: Task<Void, Never>?
    private var deferredVisualCaptureTrigger: VisualCaptureTrigger?
    private var activeVisualCaptureTrigger: VisualCaptureTrigger?
    private var visualCaptureGeneration: UInt64 = 0
    private var clipboardStabilityTasks: [Int: Task<Void, Never>] = [:]
    private var clipboardProcessingTasks: [Int: Task<Void, Never>] = [:]
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private var assistantClipboardChangeCount: Int?
    private var foregroundEnabled = false
    private var clipboardEnabled = false
    private var enhancedWindowContextEnabled = false
    private var selectionEnabled = false
    private var lastAccessibilityAuthorized = AXIsProcessTrusted()
    private var lastApplicationActivationAt = Date.distantPast
    private var previousApplicationBundleID: String?
    private var currentApplicationBundleID: String?
    private var lastUserActivitySignalAt = Date.distantPast
    private var lastUserActivityAt: Date?
    private var userIsPresent = false
    private var sessionIsActive = true
    private var lastWindowContextKey: String?
    private var currentSurfaceID: String?
    private var currentSurfaceRevision: UInt64 = 0
    private var currentSurfaceContentKey: String?
    private var anchorGeneration: UInt64 = 0
    private var lastAnchorAt = Date.distantPast
    private var lastVisualCaptureHash: String?
    private var lastVisualCaptureAttemptAt: Date?
    private var lastVisualCaptureAt: Date?
    private var nextVisualCaptureAt: Date?
    private var visualCaptureNeedsBackoff = false

    var diagnosticStatus: (
        foreground: Bool,
        clipboard: Bool,
        permission: Bool,
        userActivity: Bool,
        visualCapture: Bool,
        visualCaptureTaskRunning: Bool,
        lastVisualCaptureAttemptAt: Date?,
        lastVisualCaptureAt: Date?,
        nextVisualCaptureAt: Date?,
        selection: Bool
    ) {
        return (
            workspaceObserverInstalled && foregroundEnabled,
            clipboardTimer != nil && clipboardEnabled,
            permissionTimer != nil,
            userActivityTimer != nil,
            permissionTimer != nil && enhancedWindowContextEnabled,
            visualCaptureTask != nil,
            lastVisualCaptureAttemptAt,
            lastVisualCaptureAt,
            nextVisualCaptureAt,
            selectionEnabled
        )
    }

    fileprivate var visualCaptureTaskIsActive: Bool { visualCaptureTask != nil }

    init(coordinator: AssistantContextCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func apply(preferences: DesktopAssistantPreferences, lifecycle: AssistantLifecycleMachine) {
        let shouldObserve = preferences.isEnabled
            && preferences.hasCompletedCurrentOnboarding
            && lifecycle.observationIsAllowed
        let shouldUseEnhancedWindowContext = preferences.foregroundApplicationContextEnabled
            && preferences.enhancedWindowContextEnabled
        if enhancedWindowContextEnabled, !shouldUseEnhancedWindowContext {
            coordinator?.clearContext(source: .windowContext)
            lastWindowContextKey = nil
        }
        if foregroundEnabled, !preferences.foregroundApplicationContextEnabled {
            coordinator?.clearContext(source: .foregroundApplication)
            coordinator?.clearContext(source: .windowContext)
        }
        if clipboardEnabled, preferences.clipboardAuthorization != .allowed {
            coordinator?.clearContext(source: .clipboard)
        }
        if selectionEnabled, !preferences.selectionContextEnabled {
            coordinator?.clearContext(source: .selection)
        }
        guard shouldObserve else {
            stop()
            return
        }

        let needsAccessibility = shouldUseEnhancedWindowContext || preferences.selectionContextEnabled
        if needsAccessibility {
            startPermissionTimerIfNeeded()
        } else {
            stopPermissionTimer()
        }
        enhancedWindowContextEnabled = shouldUseEnhancedWindowContext
        startPresenceObserverIfNeeded()
        if shouldUseEnhancedWindowContext {
            coordinator?.screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
        } else {
            stopVisualCapture()
        }

        let shouldObserveClipboard = preferences.clipboardAuthorization == .allowed
        let needsWorkspaceObserver = preferences.foregroundApplicationContextEnabled
            || shouldObserveClipboard
        if needsWorkspaceObserver {
            startWorkspaceObserverIfNeeded()
        } else {
            stopWorkspaceObserver()
        }
        foregroundEnabled = preferences.foregroundApplicationContextEnabled

        if shouldObserveClipboard {
            startClipboardTimerIfNeeded()
        } else {
            stopClipboardTimer()
        }
        clipboardEnabled = shouldObserveClipboard

        selectionEnabled = preferences.selectionContextEnabled
    }

    func stop() {
        stopWorkspaceObserver()
        stopClipboardTimer()
        stopPermissionTimer()
        stopVisualCapture()
        stopPresenceObserver()
        foregroundEnabled = false
        clipboardEnabled = false
        selectionEnabled = false
        lastWindowContextKey = nil
        currentSurfaceID = nil
        currentSurfaceContentKey = nil
    }

    func markAssistantClipboardWrite(changeCount: Int) {
        assistantClipboardChangeCount = changeCount
        lastClipboardChangeCount = changeCount
    }

    func cancelPendingVisualCapture(reason: String = "user-model-preemption") {
        let preservedTrigger = reason == "user-model-preemption"
            ? deferredVisualCaptureTrigger ?? activeVisualCaptureTrigger
            : nil
        if visualCaptureTask != nil {
            coordinator?.recordDiagnosticActivity(
                stage: .capture,
                state: .cancelled,
                detail: reason
            )
        }
        visualCaptureGeneration &+= 1
        visualCaptureTask?.cancel()
        visualCaptureTask = nil
        activeVisualCaptureTrigger = nil
        deferredVisualCaptureTrigger = preservedTrigger
        nextVisualCaptureAt = nil
    }

    fileprivate func resumeDeferredVisualCaptureIfPossible() {
        guard let trigger = deferredVisualCaptureTrigger,
              visualCaptureTask == nil,
              enhancedWindowContextEnabled,
              userIsPresent,
              sessionIsActive,
              coordinator?.visualContextAnalysisIsEnabled == true,
              coordinator?.backgroundAssistantRoundIsRunning != true else { return }
        deferredVisualCaptureTrigger = nil
        scheduleVisualCapture(after: Self.visualCaptureDebounce, trigger: trigger)
    }

    fileprivate func noteExplicitUserActivity() {
        pollUserActivity()
    }

    private func startPresenceObserverIfNeeded() {
        startUserActivityTimerIfNeeded()
        guard !presenceObserverInstalled else { return }
        let center = NSWorkspace.shared.notificationCenter
        [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification
        ].forEach {
            center.addObserver(self, selector: #selector(handleSessionBecameInactive), name: $0, object: nil)
        }
        [
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification
        ].forEach {
            center.addObserver(self, selector: #selector(handleSessionBecameActive), name: $0, object: nil)
        }
        presenceObserverInstalled = true

        sessionIsActive = !Self.screenIsLocked
        let idleSeconds = Self.secondsSinceLastUserInput
        if sessionIsActive, idleSeconds < Self.userIdleTimeout {
            lastUserActivityAt = .now.addingTimeInterval(-idleSeconds)
            lastUserActivitySignalAt = lastUserActivityAt ?? .distantPast
            userIsPresent = true
            coordinator?.userPresenceDidChange(true, lastActivityAt: lastUserActivityAt)
            scheduleUserIdleTimeout()
        } else {
            userIsPresent = false
            coordinator?.userPresenceDidChange(false, lastActivityAt: lastUserActivityAt)
        }
    }

    private func stopPresenceObserver() {
        userActivityTimer?.invalidate()
        userActivityTimer = nil
        userIdleTask?.cancel()
        userIdleTask = nil
        if presenceObserverInstalled {
            let center = NSWorkspace.shared.notificationCenter
            [
                NSWorkspace.sessionDidResignActiveNotification,
                NSWorkspace.screensDidSleepNotification,
                NSWorkspace.willSleepNotification,
                NSWorkspace.sessionDidBecomeActiveNotification,
                NSWorkspace.screensDidWakeNotification,
                NSWorkspace.didWakeNotification
            ].forEach { center.removeObserver(self, name: $0, object: nil) }
        }
        presenceObserverInstalled = false
        userIsPresent = false
        coordinator?.userPresenceDidChange(false, lastActivityAt: lastUserActivityAt)
    }

    private func noteUserActivity(trigger: VisualCaptureTrigger, occurredAt: Date = .now) {
        guard sessionIsActive, !Self.screenIsLocked else { return }
        guard occurredAt.timeIntervalSince(lastUserActivitySignalAt) >= 0.2 else { return }
        lastUserActivitySignalAt = occurredAt
        lastUserActivityAt = occurredAt
        userIsPresent = true
        coordinator?.userPresenceDidChange(true, lastActivityAt: occurredAt)
        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let windowID = DesktopAssistantScreenCapture.frontmostWindowID(
               processIdentifier: application.processIdentifier
           ) {
            _ = updateSurface(
                processIdentifier: application.processIdentifier,
                windowID: windowID,
                incrementAnchor: true
            )
        }
        scheduleUserIdleTimeout()
        scheduleVisualCapture(after: Self.visualCaptureDebounce, trigger: trigger)
    }

    private func startUserActivityTimerIfNeeded() {
        guard userActivityTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollUserActivity() }
        }
        RunLoop.main.add(timer, forMode: .common)
        userActivityTimer = timer
    }

    private func pollUserActivity() {
        guard sessionIsActive, !Self.screenIsLocked else {
            markUserAbsent(reason: "session-inactive")
            return
        }
        let idleSeconds = Self.secondsSinceLastUserInput
        guard idleSeconds < Self.userIdleTimeout else {
            markUserAbsent(reason: "idle-timeout")
            return
        }
        resumeDeferredVisualCaptureIfPossible()
        // 只比较系统最后输入时间，不读取按键、坐标或事件正文；时间戳未前进就绝不安排截图。
        noteUserActivity(
            trigger: .userInteraction,
            occurredAt: .now.addingTimeInterval(-idleSeconds)
        )
    }

    private func scheduleUserIdleTimeout() {
        userIdleTask?.cancel()
        guard let activityAt = lastUserActivityAt else { return }
        userIdleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = max(0, Self.userIdleTimeout - Date.now.timeIntervalSince(activityAt))
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, lastUserActivityAt == activityAt else { return }
            markUserAbsent(reason: "idle-timeout")
        }
    }

    private func markUserAbsent(reason: String) {
        guard userIsPresent else { return }
        userIsPresent = false
        userIdleTask?.cancel()
        userIdleTask = nil
        cancelPendingVisualCapture(reason: reason)
        lastVisualCaptureHash = nil
        coordinator?.userPresenceDidChange(false, lastActivityAt: lastUserActivityAt)
        coordinator?.recordDiagnosticActivity(
            stage: .capture,
            state: .skipped,
            detail: "presence-paused reason=\(reason)"
        )
    }

    @objc private func handleSessionBecameInactive() {
        sessionIsActive = false
        markUserAbsent(reason: "session-inactive")
    }

    @objc private func handleSessionBecameActive() {
        sessionIsActive = !Self.screenIsLocked
        guard sessionIsActive, Self.secondsSinceLastUserInput < 5 else { return }
        noteUserActivity(trigger: .userInteraction)
    }

    private static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true
    }

    private static var secondsSinceLastUserInput: TimeInterval {
        let eventTypes: [CGEventType] = [
            .keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func startWorkspaceObserverIfNeeded() {
        guard !workspaceObserverInstalled else { return }
        currentApplicationBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceObserverInstalled = true
    }

    private func stopWorkspaceObserver() {
        guard workspaceObserverInstalled else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceObserverInstalled = false
    }

    @objc private func handleApplicationActivation(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = application.bundleIdentifier,
              Self.secondsSinceLastUserInput < 2 else { return }
        previousApplicationBundleID = currentApplicationBundleID
        currentApplicationBundleID = bundleID
        noteUserActivity(trigger: .applicationActivated)
        lastApplicationActivationAt = .now
        coordinator?.recordApplicationActivation(bundleID: bundleID)
        recordWindowContextIfChanged(application: application)
    }

    private func startClipboardTimerIfNeeded() {
        guard clipboardTimer == nil else { return }
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollClipboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clipboardTimer = timer
    }

    private func stopClipboardTimer() {
        clipboardStabilityTasks.values.forEach { $0.cancel() }
        clipboardStabilityTasks.removeAll()
        clipboardProcessingTasks.values.forEach { $0.cancel() }
        clipboardProcessingTasks.removeAll()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func startPermissionTimerIfNeeded() {
        guard permissionTimer == nil else { return }
        lastAccessibilityAuthorized = AXIsProcessTrusted()
        coordinator?.accessibilityAuthorized = lastAccessibilityAuthorized
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollAccessibilityPermission()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func stopPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        lastWindowContextKey = nil
    }

    private func stopVisualCapture() {
        if visualCaptureTask != nil {
            coordinator?.recordDiagnosticActivity(
                stage: .capture,
                state: .cancelled,
                detail: "observer-stopped"
            )
        }
        visualCaptureGeneration &+= 1
        visualCaptureTask?.cancel()
        visualCaptureTask = nil
        activeVisualCaptureTrigger = nil
        deferredVisualCaptureTrigger = nil
        lastVisualCaptureHash = nil
        visualCaptureNeedsBackoff = false
        nextVisualCaptureAt = nil
    }

    private func scheduleVisualCapture(after delay: TimeInterval, trigger: VisualCaptureTrigger) {
        guard enhancedWindowContextEnabled,
              userIsPresent,
              sessionIsActive,
              coordinator?.visualContextAnalysisIsEnabled == true else { return }
        // 未授权时不能进入 ScreenCaptureKit，否则后台观察会再次触发系统权限弹窗。
        guard CGPreflightScreenCaptureAccess() else {
            coordinator?.screenCaptureAuthorized = false
            return
        }
        let captureIsRunning = visualCaptureTask != nil && nextVisualCaptureAt == nil
        guard !captureIsRunning,
              coordinator?.backgroundAssistantRoundIsRunning != true else {
            deferredVisualCaptureTrigger = trigger
            return
        }
        deferredVisualCaptureTrigger = nil
        let cooldownInterval = visualCaptureNeedsBackoff
            ? Self.failedVisualCaptureRetryInterval
            : Self.minimumVisualCaptureInterval
        let cooldown = lastVisualCaptureAttemptAt.map {
            max(0, cooldownInterval - Date.now.timeIntervalSince($0))
        } ?? 0
        let effectiveDelay = max(delay, cooldown)
        // 连续操作只重置同一轮防抖；诊断同步刷新这一条计划的真实起算时间。
        let captureWasPending = visualCaptureTask != nil && nextVisualCaptureAt != nil
        visualCaptureGeneration &+= 1
        let generation = visualCaptureGeneration
        visualCaptureTask?.cancel()
        activeVisualCaptureTrigger = trigger
        nextVisualCaptureAt = .now.addingTimeInterval(effectiveDelay)
        coordinator?.recordDiagnosticActivity(
            stage: .capture,
            state: .scheduled,
            detail: "trigger=\(trigger.rawValue) delay=\(String(format: "%.1f", effectiveDelay))s reset=\(captureWasPending) cooldown=\(cooldown > delay) interval=\(Int(cooldownInterval))s"
        )
        visualCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if generation == visualCaptureGeneration {
                    visualCaptureTask = nil
                    activeVisualCaptureTrigger = nil
                    nextVisualCaptureAt = nil
                    coordinator?.visualCaptureRoundDidSettle()
                    resumeDeferredVisualCaptureIfPossible()
                }
            }
            if effectiveDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(effectiveDelay))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  generation == visualCaptureGeneration,
                  userIsPresent,
                  sessionIsActive,
                  let coordinator else { return }
            guard !coordinator.backgroundAssistantRoundIsRunning else {
                deferredVisualCaptureTrigger = trigger
                return
            }
            lastVisualCaptureAttemptAt = .now
            nextVisualCaptureAt = nil
            coordinator.recordDiagnosticActivity(
                stage: .capture,
                state: .running,
                detail: "trigger=\(trigger.rawValue)"
            )
            do {
                guard let capture = try await DesktopAssistantScreenCapture.captureFrontmostWindow() else {
                    coordinator.recordDiagnosticActivity(
                        stage: .capture,
                        state: .skipped,
                        detail: "no-eligible-frontmost-window"
                    )
                    return
                }
                guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
                      frontmostApplication.processIdentifier == capture.processIdentifier,
                      DesktopAssistantScreenCapture.frontmostWindowID(
                          processIdentifier: capture.processIdentifier
                      ) == capture.windowID else {
                    coordinator.recordDiagnosticActivity(
                        stage: .capture,
                        state: .skipped,
                        detail: "frontmost-window-changed"
                    )
                    return
                }
                guard AssistantPrivacyPolicy(
                    excludedApplicationBundleIDs: coordinator.preferences.excludedApplicationBundleIDs
                ).sensitivity(text: nil, bundleID: capture.bundleID) == .normal else {
                    coordinator.recordDiagnosticActivity(
                        stage: .capture,
                        state: .skipped,
                        detail: "excluded-application"
                    )
                    return
                }
                guard capture.image.contentHash != lastVisualCaptureHash else {
                    coordinator.recordDiagnosticActivity(
                        stage: .capture,
                        state: .skipped,
                        detail: "unchanged-frame"
                    )
                    return
                }
                lastVisualCaptureAt = .now
                coordinator.recordDiagnosticActivity(
                    stage: .capture,
                    state: .succeeded,
                    detail: "frame-ready \(capture.image.pixelWidth ?? 0)x\(capture.image.pixelHeight ?? 0)"
                )
                coordinator.screenCaptureAuthorized = true
                let surface = updateSurface(
                    processIdentifier: capture.processIdentifier,
                    windowID: capture.windowID
                )
                let outcome = await coordinator.recordScreenSnapshot(
                    capture.image,
                    bundleID: capture.bundleID,
                    capturedAt: capture.capturedAt,
                    surfaceID: surface.id,
                    surfaceRevision: surface.revision,
                    anchorGeneration: surface.anchorGeneration
                )
                switch outcome {
                case .consumed:
                    visualCaptureNeedsBackoff = false
                    lastVisualCaptureHash = capture.image.contentHash
                case .retryableFailure:
                    visualCaptureNeedsBackoff = true
                    deferredVisualCaptureTrigger = trigger
                case .retryableContention:
                    visualCaptureNeedsBackoff = false
                    lastVisualCaptureAttemptAt = nil
                    deferredVisualCaptureTrigger = trigger
                case .skipped:
                    visualCaptureNeedsBackoff = false
                }
            } catch {
                // 未授予屏幕录制权限或窗口已消失时保持安静，下一次场景变化会自然重试。
                coordinator.screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
                coordinator.recordDiagnosticActivity(
                    stage: .capture,
                    state: .failed,
                    detail: "permission-or-window-error"
                )
                visualCaptureNeedsBackoff = coordinator.screenCaptureAuthorized
                if coordinator.screenCaptureAuthorized {
                    deferredVisualCaptureTrigger = trigger
                }
            }
        }
    }

    private func pollAccessibilityPermission() {
        let authorized = AXIsProcessTrusted()
        if enhancedWindowContextEnabled {
            coordinator?.screenCaptureAuthorized = CGPreflightScreenCaptureAccess()
        }
        if authorized != lastAccessibilityAuthorized {
            let wasAuthorized = lastAccessibilityAuthorized
            lastAccessibilityAuthorized = authorized
            coordinator?.accessibilityAuthorized = authorized
            if wasAuthorized, !authorized {
                lastWindowContextKey = nil
                coordinator?.clearContext(source: .windowContext)
                coordinator?.clearContext(source: .selection)
            }
        }
        guard authorized else { return }
        recordWindowContextIfChanged(application: NSWorkspace.shared.frontmostApplication)
    }

    private func recordWindowContextIfChanged(application: NSRunningApplication?) {
        guard userIsPresent,
              enhancedWindowContextEnabled,
              AXIsProcessTrusted(),
              let application,
              let bundleID = application.bundleIdentifier,
              let title = Self.focusedWindowTitle(processIdentifier: application.processIdentifier),
              let sanitizedTitle = AssistantPrivacyPolicy().sanitizeWindowTitle(title) else { return }
        let key = "\(bundleID)|\(sanitizedTitle)"
        guard key != lastWindowContextKey else { return }
        lastWindowContextKey = key
        let surface = updateSurface(
            processIdentifier: application.processIdentifier,
            windowID: DesktopAssistantScreenCapture.frontmostWindowID(processIdentifier: application.processIdentifier),
            contentKey: sanitizedTitle
        )
        coordinator?.recordWindowContext(
            bundleID: bundleID,
            title: sanitizedTitle,
            observedAt: .now,
            surfaceID: surface.id,
            surfaceRevision: surface.revision,
            anchorGeneration: surface.anchorGeneration
        )
    }

    private func updateSurface(
        processIdentifier: pid_t,
        windowID: CGWindowID?,
        contentKey: String? = nil,
        incrementAnchor: Bool = false
    ) -> SurfaceSnapshot {
        let surfaceID = windowID.map { "\(processIdentifier):\($0)" }
        let surfaceChanged = currentSurfaceID != surfaceID
        if surfaceChanged {
            currentSurfaceID = surfaceID
            currentSurfaceRevision &+= 1
            currentSurfaceContentKey = contentKey
        } else if let contentKey, contentKey != currentSurfaceContentKey {
            currentSurfaceContentKey = contentKey
            currentSurfaceRevision &+= 1
        }
        if incrementAnchor {
            let now = Date.now
            if surfaceChanged
                || now.timeIntervalSince(lastAnchorAt) > AssistantPatternDetector.contextOpportunityMaximumDebounce {
                anchorGeneration &+= 1
            }
            lastAnchorAt = now
        }
        return SurfaceSnapshot(
            id: currentSurfaceID,
            revision: currentSurfaceRevision,
            anchorGeneration: anchorGeneration
        )
    }

    fileprivate func explicitSurfaceSnapshot(bundleID: String?) -> (String?, UInt64, UInt64) {
        guard let application = NSWorkspace.shared.frontmostApplication,
              bundleID == nil || application.bundleIdentifier == bundleID else {
            let now = Date.now
            if now.timeIntervalSince(lastAnchorAt) > AssistantPatternDetector.contextOpportunityMaximumDebounce {
                anchorGeneration &+= 1
            }
            lastAnchorAt = now
            return (nil, currentSurfaceRevision, anchorGeneration)
        }
        let surface = updateSurface(
            processIdentifier: application.processIdentifier,
            windowID: DesktopAssistantScreenCapture.frontmostWindowID(processIdentifier: application.processIdentifier),
            incrementAnchor: true
        )
        return (surface.id, surface.revision, surface.anchorGeneration)
    }

    fileprivate func surfaceIsCurrent(id: String?, revision: UInt64, anchorGeneration: UInt64) -> Bool {
        currentSurfaceID == id
            && currentSurfaceRevision == revision
            && self.anchorGeneration == anchorGeneration
    }

    private func pollClipboard() {
        pollUserActivity()
        let pasteboard = NSPasteboard.general
        let observedAt = Date.now
        let changeCount = pasteboard.changeCount
        guard changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = changeCount
        if assistantClipboardChangeCount == changeCount {
            assistantClipboardChangeCount = nil
            return
        }
        guard !SelectedTextService.shouldIgnorePasteboardChange(changeCount) else { return }
        guard userIsPresent else { return }
        let application = NSWorkspace.shared.frontmostApplication
        let bundleID = application?.bundleIdentifier
        let types = pasteboard.pasteboardItems?.flatMap(\.types) ?? pasteboard.types ?? []
        let kind = AssistantClipboardClassifier.classify(typeIdentifiers: types.map(\.rawValue))
        let sourceIsReliable = observedAt.timeIntervalSince(lastApplicationActivationAt) >= 0.75
        let possibleBundleIDs = Array(Set(
            ([bundleID] + (sourceIsReliable ? [] : [previousApplicationBundleID])).compactMap { $0 }
        ))
        let userInitiated = Self.secondsSinceLastUserInput < 2
        let surface: SurfaceSnapshot
        if let application {
            surface = updateSurface(
                processIdentifier: application.processIdentifier,
                windowID: DesktopAssistantScreenCapture.frontmostWindowID(processIdentifier: application.processIdentifier),
                incrementAnchor: userInitiated
            )
        } else {
            if userInitiated {
                if observedAt.timeIntervalSince(lastAnchorAt) > AssistantPatternDetector.contextOpportunityMaximumDebounce {
                    anchorGeneration &+= 1
                }
                lastAnchorAt = observedAt
            }
            surface = SurfaceSnapshot(
                id: currentSurfaceID,
                revision: currentSurfaceRevision,
                anchorGeneration: anchorGeneration
            )
        }
        // 切换应用后的短暂歧义同时校验前后两个来源；正文仍只在内存停留，任一来源被排除就整条丢弃。
        let snapshot = ClipboardSnapshot(
            changeCount: changeCount,
            observedAt: observedAt,
            bundleID: sourceIsReliable ? bundleID : nil,
            possibleBundleIDs: possibleBundleIDs,
            surface: surface,
            userInitiated: userInitiated,
            sourceIsReliable: sourceIsReliable,
            kind: kind,
            text: kind == .plainText ? pasteboard.string(forType: .string) : nil
        )
        coordinator?.noteClipboardProvenance(
            changeCount: changeCount,
            text: sourceIsReliable ? snapshot.text : nil,
            possibleBundleIDs: possibleBundleIDs
        )
        guard clipboardEnabled else { return }
        if !sourceIsReliable {
            // 快速切到应用后立即复制很常见；等待来源稳定并按 changeCount 独立处理，不能吞掉连续复制。
            scheduleStableClipboardProcessing(snapshot)
            return
        }
        processStableClipboard(snapshot)
    }

    private func scheduleStableClipboardProcessing(_ snapshot: ClipboardSnapshot) {
        clipboardStabilityTasks[snapshot.changeCount]?.cancel()
        let remaining = max(0.05, 0.75 - Date.now.timeIntervalSince(lastApplicationActivationAt))
        clipboardStabilityTasks[snapshot.changeCount] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            clipboardStabilityTasks.removeValue(forKey: snapshot.changeCount)
            processStableClipboard(snapshot)
        }
    }

    private func processStableClipboard(_ snapshot: ClipboardSnapshot) {
        guard clipboardEnabled else { return }
        if NSPasteboard.general.changeCount == snapshot.changeCount {
            coordinator?.noteClipboardProvenance(
                changeCount: snapshot.changeCount,
                text: snapshot.text,
                possibleBundleIDs: snapshot.possibleBundleIDs
            )
        }
        switch snapshot.kind {
        case .plainText:
            guard let text = snapshot.text,
                  clipboardProcessingTasks[snapshot.changeCount] == nil else { return }
            clipboardProcessingTasks[snapshot.changeCount] = Task { @MainActor [weak self, weak coordinator] in
                guard !Task.isCancelled else { return }
                await coordinator?.recordClipboardText(
                    text,
                    bundleID: snapshot.bundleID,
                    possibleBundleIDs: snapshot.possibleBundleIDs,
                    observedAt: snapshot.observedAt,
                    surfaceID: snapshot.surface.id,
                    surfaceRevision: snapshot.surface.revision,
                    anchorGeneration: snapshot.surface.anchorGeneration,
                    provenance: snapshot.userInitiated
                        ? (snapshot.sourceIsReliable ? .explicit : .uncertain)
                        : .observed
                )
                self?.clipboardProcessingTasks.removeValue(forKey: snapshot.changeCount)
            }
        case .file:
            coordinator?.recordClipboardType(.file, bundleID: snapshot.bundleID)
        case .image:
            coordinator?.recordClipboardType(.image, bundleID: snapshot.bundleID)
        case .richText, .other:
            coordinator?.recordClipboardType(.metadata, bundleID: snapshot.bundleID)
        }
    }

    // 只在明确启用增强上下文且 AX 已授权时读取当前聚焦标题；不读取窗口正文或扫描窗口树。
    private static func focusedWindowTitle(processIdentifier: pid_t) -> String? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
              let focusedWindow else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        ) == .success else { return nil }
        return title as? String
    }
}

final class AssistantPanel: NSPanel {
    var allowsKeyboardInput = false
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { allowsKeyboardInput }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            if let textView = firstResponder as? NSTextView, textView.hasMarkedText() {
                super.sendEvent(event)
                return
            }
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}

final class AssistantOnboardingWindow: NSWindow {
    var onUserClose: (() -> Void)?

    override func close() {
        onUserClose?()
    }
}

@MainActor
final class FloatingAssistantWindowController: NSObject {
    private let coordinator: AssistantContextCoordinator
    private let orbPanel: AssistantPanel
    private let toolbarPanel: AssistantPanel
    private let peekPanel: AssistantPanel
    private let orbHost: AssistantOrbHostingView
    private let toolbarHost: AssistantTrackingHostingView
    private var onboardingWindow: AssistantOnboardingWindow?
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?
    private var dragLocalMonitor: Any?
    private var dragGlobalMonitor: Any?
    private var dragStart = CGPoint.zero
    private var dragPointerOffset = CGPoint.zero
    private var dragClickCount = 0
    private var dragDidMove = false
    private var dropOriginalFrame: CGRect?
    private var activeDropClassification: AssistantDropClassification?
    private var toolbarVisible = false
    private var screenObserver: Any?
    private var workspaceVisibilityObservers: [NSObjectProtocol] = []
    private var fullScreenVisibilityTask: Task<Void, Never>?
    private var appliedPreferences: DesktopAssistantPreferences
    private var hasRestoredInitialPosition = false

    var assistantInteractionIsInProgress: Bool {
        dragLocalMonitor != nil || dragGlobalMonitor != nil || dropOriginalFrame != nil
    }

    var diagnosticStatus: (
        orbVisible: Bool,
        toolbarVisible: Bool,
        peekVisible: Bool,
        onboardingVisible: Bool,
        dropTargetActive: Bool,
        orbSize: CGSize
    ) {
        (
            orbPanel.isVisible,
            toolbarPanel.isVisible,
            peekPanel.isVisible,
            onboardingWindow?.isVisible == true,
            dropOriginalFrame != nil,
            orbPanel.frame.size
        )
    }

    init(coordinator: AssistantContextCoordinator) {
        self.coordinator = coordinator
        appliedPreferences = coordinator.preferences
        orbPanel = Self.makePanel(frame: CGRect(x: 0, y: 0, width: 48, height: 48), shadow: true)
        toolbarPanel = Self.makePanel(frame: CGRect(x: 0, y: 0, width: 88, height: 40), shadow: true)
        peekPanel = Self.makePanel(frame: CGRect(x: 0, y: 0, width: 320, height: 220), shadow: true)
        orbHost = AssistantOrbHostingView(rootView: AnyView(AssistantOrbView(coordinator: coordinator)))
        toolbarHost = AssistantTrackingHostingView(rootView: AnyView(AssistantToolbarView(coordinator: coordinator)))
        super.init()

        coordinator.windowController = self
        orbHost.owner = self
        orbHost.registerForDraggedTypes([.fileURL, .string])
        orbHost.sizingOptions = []
        toolbarHost.sizingOptions = []
        toolbarHost.onEnter = { [weak self] in self?.cancelToolbarClose() }
        toolbarHost.onExit = { [weak self] in self?.scheduleToolbarClose() }
        orbPanel.contentView = orbHost
        toolbarPanel.contentView = toolbarHost
        toolbarPanel.allowsKeyboardInput = true
        toolbarPanel.onEscape = { [weak self] in self?.hideToolbar() }
        let peekHost = AssistantPeekHostingView(rootView: AnyView(AssistantPeekView(coordinator: coordinator)))
        peekHost.sizingOptions = []
        peekPanel.contentView = peekHost
        orbPanel.contentMinSize = CGSize(width: 48, height: 48)
        orbPanel.contentMaxSize = CGSize(width: 48, height: 48)
        peekPanel.contentMinSize = CGSize(width: 320, height: 220)
        peekPanel.contentMaxSize = CGSize(width: 320, height: 220)
        peekPanel.onEscape = { [weak coordinator] in coordinator?.dismissPanel() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restoreSafePosition()
                self?.scheduleFullScreenVisibilityRefresh()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceVisibilityObservers.append(workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleFullScreenVisibilityRefresh() }
            })
        }
    }

    func applyPreferences(_ preferences: DesktopAssistantPreferences) {
        appliedPreferences = preferences
        var behavior: NSWindow.CollectionBehavior = [.stationary]
        // AppKit 的全屏辅助窗口必须同时加入所有 Space；普通 Space 开关仍决定默认行为。
        if preferences.showOnAllSpaces || preferences.showOverFullScreen { behavior.insert(.canJoinAllSpaces) }
        if preferences.showOverFullScreen { behavior.insert(.fullScreenAuxiliary) }
        for panel in [orbPanel, toolbarPanel, peekPanel] {
            panel.collectionBehavior = behavior
        }
        placeAccessories()
        scheduleFullScreenVisibilityRefresh()
    }

    func showOrb() {
        guard currentSpaceAllowsAssistantWindows else {
            hideAllAssistantWindows()
            return
        }
        if !orbPanel.isVisible {
            restoreSafePosition()
        }
        orbPanel.orderFrontRegardless()
    }

    func resetToDefaultPosition() {
        guard let screen = orbPanel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        hasRestoredInitialPosition = true
        orbPanel.setFrame(AssistantWindowGeometry.defaultOrbFrame(in: screen.visibleFrame), display: orbPanel.isVisible)
        placeAccessories()
    }

    func hideAllAssistantWindows() {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        removeDragMonitors()
        endDropTarget()
        toolbarVisible = false
        if peekPanel.isKeyWindow { peekPanel.resignKey() }
        orbPanel.orderOut(nil)
        toolbarPanel.orderOut(nil)
        peekPanel.orderOut(nil)
    }

    @discardableResult
    func showPeek(activating: Bool) -> Bool {
        guard currentSpaceAllowsAssistantWindows else {
            hideAllAssistantWindows()
            return false
        }
        // 投放完成后悬浮球缩回会再次触发 mouseEntered；先取消旧任务，避免工具条盖住任务卡。
        hoverOpenTask?.cancel()
        cancelToolbarClose()
        toolbarVisible = false
        toolbarPanel.orderOut(nil)
        placeAccessories()
        peekPanel.allowsKeyboardInput = activating
        if !activating, peekPanel.isKeyWindow { peekPanel.resignKey() }
        // 展开询问也先保持非激活；用户点入编辑区后 NSPanel 才取得键盘焦点。
        peekPanel.orderFrontRegardless()
        return true
    }

    func hidePeek() {
        if peekPanel.isKeyWindow { peekPanel.resignKey() }
        peekPanel.orderOut(nil)
        peekPanel.allowsKeyboardInput = false
    }

    func hideToolbar() {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        toolbarVisible = false
        if toolbarPanel.isKeyWindow { toolbarPanel.resignKey() }
        toolbarPanel.orderOut(nil)
    }

    func showToolbarForKeyboardNavigation() {
        guard showToolbar() else { return }
        // 只有用户明确调用无障碍动作时才让工具条成为键盘目标，悬停仍不抢焦点。
        toolbarPanel.makeKeyAndOrderFront(nil)
        coordinator.requestToolbarKeyboardFocus()
    }

    func showOnboarding() {
        let window: AssistantOnboardingWindow
        if let onboardingWindow {
            window = onboardingWindow
        } else {
            window = AssistantOnboardingWindow(
                contentRect: CGRect(x: 0, y: 0, width: 520, height: 470),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = coordinator.text("启用桌面情境助手", "Enable Desktop Context Assistant")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AssistantOnboardingView(coordinator: coordinator))
            window.onUserClose = { [weak coordinator] in coordinator?.cancelOnboarding() }
            window.center()
            onboardingWindow = window
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeOnboarding() {
        onboardingWindow?.orderOut(nil)
    }

    func closeAll() {
        fullScreenVisibilityTask?.cancel()
        hideAllAssistantWindows()
        onboardingWindow?.orderOut(nil)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceVisibilityObservers.forEach(workspaceCenter.removeObserver)
        workspaceVisibilityObservers.removeAll()
    }

    func orbMouseEntered() {
        guard coordinator.preferences.toolbarTrigger == .hover,
              AssistantWindowGeometry.allowsPassiveToolbar(
                  peekIsVisible: peekPanel.isVisible,
                  dropTargetIsActive: dropOriginalFrame != nil
              ) else { return }
        cancelToolbarClose()
        hoverOpenTask?.cancel()
        hoverOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  let self,
                  AssistantWindowGeometry.allowsPassiveToolbar(
                      peekIsVisible: peekPanel.isVisible,
                      dropTargetIsActive: dropOriginalFrame != nil
                  ) else { return }
            showToolbar()
        }
    }

    func orbMouseExited() {
        hoverOpenTask?.cancel()
        // 点击模式同样给进入工具条留出 300ms，避免面板在悬浮球外永久停留。
        if toolbarVisible {
            scheduleToolbarClose()
        }
    }

    func orbClicked() {
        if peekPanel.isVisible {
            if coordinator.selectedCardUsesSpeechBubble {
                coordinator.dismissSpeechBubble()
            } else {
                coordinator.closePanelFromUser()
            }
            return
        }
        if coordinator.preferences.toolbarTrigger == .click, !toolbarVisible {
            showToolbar()
            return
        }
        coordinator.handleOrbClick()
    }

    func beginOrbPointerInteraction(pointerOffset: CGPoint, clickCount: Int) {
        removeDragMonitors()
        dragStart = NSEvent.mouseLocation
        dragPointerOffset = pointerOffset
        dragClickCount = clickCount
        dragDidMove = false
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        dragLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handleOrbDragEvent(event) }
            return event
        }
        dragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handleOrbDragEvent(event) }
        }
    }

    private func handleOrbDragEvent(_ event: NSEvent) {
        guard dragLocalMonitor != nil || dragGlobalMonitor != nil else { return }
        let location = NSEvent.mouseLocation
        if event.type == .leftMouseDragged {
            if hypot(location.x - dragStart.x, location.y - dragStart.y) >= 4 { dragDidMove = true }
            if dragDidMove { dragOrb(mouseLocation: location, pointerOffset: dragPointerOffset) }
            return
        }
        // 两个 monitor 只覆盖一次显式按压，松开后必须同步移除，避免形成后台鼠标观察器。
        removeDragMonitors()
        if dragDidMove {
            finishOrbDrag(mouseLocation: location, pointerOffset: dragPointerOffset)
        } else if dragClickCount == 1 {
            orbClicked()
        }
    }

    private func removeDragMonitors() {
        if let dragLocalMonitor { NSEvent.removeMonitor(dragLocalMonitor) }
        if let dragGlobalMonitor { NSEvent.removeMonitor(dragGlobalMonitor) }
        dragLocalMonitor = nil
        dragGlobalMonitor = nil
    }

    func dragOrb(mouseLocation: CGPoint, pointerOffset: CGPoint) {
        hoverOpenTask?.cancel()
        toolbarPanel.orderOut(nil)
        toolbarVisible = false
        let screen = screen(containing: mouseLocation) ?? orbPanel.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let proposed = CGRect(
            x: mouseLocation.x - pointerOffset.x,
            y: mouseLocation.y - pointerOffset.y,
            width: AssistantWindowGeometry.orbDiameter,
            height: AssistantWindowGeometry.orbDiameter
        )
        orbPanel.setFrame(AssistantWindowGeometry.clampedOrbFrame(proposed, in: visibleFrame), display: true)
        placeAccessories()
    }

    func finishOrbDrag(mouseLocation: CGPoint, pointerOffset: CGPoint) {
        guard let screen = screen(containing: mouseLocation) ?? orbPanel.screen else { return }
        let releasedFrame = CGRect(
            x: mouseLocation.x - pointerOffset.x,
            y: mouseLocation.y - pointerOffset.y,
            width: AssistantWindowGeometry.orbDiameter,
            height: AssistantWindowGeometry.orbDiameter
        )
        orbPanel.setFrame(
            AssistantWindowGeometry.clampedOrbFrame(releasedFrame, in: screen.visibleFrame),
            display: true
        )
        let key = screen.assistantDisplayID
        let position = AssistantWindowGeometry.storedPosition(for: orbPanel.frame, in: screen.visibleFrame)
        coordinator.appState.updatePreferences {
            $0.desktopAssistant.positionsByDisplay[key] = position
            $0.desktopAssistant.lastDisplayID = key
        }
        placeAccessories()
    }

    func assistantDraggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        let classification = classifyDrop(draggingInfo.draggingPasteboard)
        activeDropClassification = classification
        beginDropTarget(classification)
        return classification.isSupported ? .copy : []
    }

    func assistantDraggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        guard let activeDropClassification else {
            return assistantDraggingEntered(draggingInfo)
        }
        return activeDropClassification.isSupported ? .copy : []
    }

    func assistantDraggingExited() {
        endDropTarget()
    }

    func performAssistantDrop(_ draggingInfo: NSDraggingInfo) -> Bool {
        let classification = activeDropClassification ?? classifyDrop(draggingInfo.draggingPasteboard)
        guard classification.isSupported else {
            endDropTarget()
            return false
        }
        endDropTarget()
        coordinator.acceptDrop(classification)
        return true
    }

    func showContextMenu(event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        addMenuItem(menu, coordinator.text("打开 Quick Action", "Open Quick Action"), #selector(openQuickAction))
        addMenuItem(menu, coordinator.text("查看最近提示", "Recent Suggestions"), #selector(openRecent))
        menu.addItem(.separator())
        addMenuItem(menu, coordinator.text("暂停 1 小时", "Pause for 1 Hour"), #selector(pauseOneHour))
        addMenuItem(menu, coordinator.text("暂停到明天", "Pause Until Tomorrow"), #selector(pauseUntilTomorrow))
        if coordinator.lifecycle.mode == .paused {
            addMenuItem(menu, coordinator.text("立即恢复", "Resume Now"), #selector(resume))
        }
        let privacy = addMenuItem(menu, coordinator.text("隐私模式", "Privacy Mode"), #selector(togglePrivacy))
        privacy.state = coordinator.lifecycle.mode == .privacy ? .on : .off
        menu.addItem(.separator())
        addMenuItem(menu, coordinator.text("设置", "Settings"), #selector(openSettings))
        addMenuItem(menu, coordinator.text("隐藏悬浮球", "Hide Assistant Orb"), #selector(hideAssistant))
        addMenuItem(menu, coordinator.text("停用桌面情境助手", "Disable Desktop Context Assistant"), #selector(disableAssistant))
        menu.addItem(.separator())
        addMenuItem(menu, coordinator.text("退出 llmTools", "Quit llmTools"), #selector(quit))
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func openQuickAction() { coordinator.onOpenQuickAction?(nil) }
    @objc private func openRecent() { coordinator.openRecent() }
    @objc private func pauseOneHour() { coordinator.pause(until: .now.addingTimeInterval(3_600)) }
    @objc private func pauseUntilTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86_400)
        coordinator.pause(until: Calendar.current.startOfDay(for: tomorrow))
    }
    @objc private func resume() { coordinator.resume() }
    @objc private func togglePrivacy() { coordinator.togglePrivacy() }
    @objc private func openSettings() { coordinator.onOpenSettings?() }
    @objc private func hideAssistant() { coordinator.hide() }
    @objc private func disableAssistant() { coordinator.disable() }
    @objc private func quit() { coordinator.onQuit?() }

    @discardableResult
    private func showToolbar() -> Bool {
        guard currentSpaceAllowsAssistantWindows else {
            hideAllAssistantWindows()
            return false
        }
        cancelToolbarClose()
        hidePeek()
        placeAccessories()
        toolbarVisible = true
        toolbarPanel.orderFrontRegardless()
        return true
    }

    private var currentSpaceAllowsAssistantWindows: Bool {
        coordinator.lifecycle.allowsWindowPresentation(
            showOverFullScreen: appliedPreferences.showOverFullScreen,
            frontmostApplicationIsFullScreen: AssistantContextCoordinator.frontmostApplicationIsFullScreen
        )
    }

    private func scheduleFullScreenVisibilityRefresh() {
        fullScreenVisibilityTask?.cancel()
        refreshFullScreenVisibility()
        // Space 切换通知可能早于全屏动画结束，再核对一次以免短暂状态成为最终结果。
        fullScreenVisibilityTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            refreshFullScreenVisibility()
        }
    }

    private func refreshFullScreenVisibility() {
        if currentSpaceAllowsAssistantWindows {
            showOrb()
        } else {
            hideAllAssistantWindows()
        }
    }

    private func beginDropTarget(_ classification: AssistantDropClassification) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        toolbarPanel.orderOut(nil)
        peekPanel.orderOut(nil)
        toolbarVisible = false
        if dropOriginalFrame == nil { dropOriginalFrame = orbPanel.frame }
        guard let screen = orbPanel.screen ?? screen(withLargestIntersection: orbPanel.frame) ?? NSScreen.main else { return }
        let center = dropOriginalFrame?.center ?? CGPoint(x: orbPanel.frame.midX, y: orbPanel.frame.midY)
        let diameter = AssistantWindowGeometry.dropTargetDiameter
        let expanded = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        coordinator.beginDropTarget(classification)
        orbPanel.contentMinSize = expanded.size
        orbPanel.contentMaxSize = expanded.size
        orbPanel.setFrame(AssistantWindowGeometry.clampedOrbFrame(expanded, in: screen.visibleFrame), display: true)
    }

    private func endDropTarget() {
        guard let original = dropOriginalFrame else {
            activeDropClassification = nil
            coordinator.cancelDropTarget()
            return
        }
        let screen = screen(withLargestIntersection: original) ?? NSScreen.main
        let restored = screen.map { AssistantWindowGeometry.clampedOrbFrame(original, in: $0.visibleFrame) } ?? original
        orbPanel.contentMinSize = restored.size
        orbPanel.contentMaxSize = restored.size
        orbPanel.setFrame(restored, display: orbPanel.isVisible)
        dropOriginalFrame = nil
        activeDropClassification = nil
        coordinator.cancelDropTarget()
        placeAccessories()
    }

    private func classifyDrop(_ pasteboard: NSPasteboard) -> AssistantDropClassification {
        guard let items = pasteboard.pasteboardItems, items.count == 1, let item = items.first else {
            return AssistantDropClassifier.multipleItems
        }
        if item.types.contains(.fileURL) {
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value),
                  url.isFileURL else {
                return AssistantDropClassification(kind: .unsupported, payload: nil)
            }
            return AssistantDropClassifier.classify(fileURL: url)
        }
        guard let text = item.string(forType: .string) else {
            return AssistantDropClassification(kind: .unsupported, payload: nil)
        }
        return AssistantDropClassifier.classify(text: text)
    }

    private func scheduleToolbarClose() {
        hoverCloseTask?.cancel()
        hoverCloseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.toolbarVisible = false
            self?.toolbarPanel.orderOut(nil)
        }
    }

    private func cancelToolbarClose() {
        hoverCloseTask?.cancel()
    }

    private func placeAccessories() {
        guard let screen = orbPanel.screen ?? screen(withLargestIntersection: orbPanel.frame) ?? NSScreen.main else { return }
        let peekSize = coordinator.preferredPeekSize
        let layout = AssistantWindowGeometry.accessoryLayout(
            orbFrame: orbPanel.frame,
            visibleFrame: screen.visibleFrame,
            peekSize: peekSize
        )
        coordinator.accessoryPlacement = layout.placement
        toolbarPanel.contentMinSize = layout.toolbarFrame.size
        toolbarPanel.contentMaxSize = layout.toolbarFrame.size
        toolbarPanel.setFrame(layout.toolbarFrame, display: toolbarPanel.isVisible)
        peekPanel.contentMinSize = peekSize
        peekPanel.contentMaxSize = peekSize
        peekPanel.setFrame(layout.peekFrame, display: peekPanel.isVisible)
    }

    private func restoreSafePosition() {
        let rememberedScreen = coordinator.preferences.lastDisplayID.flatMap { displayID in
            NSScreen.screens.first { $0.assistantDisplayID == displayID }
        }
        let screen = (!hasRestoredInitialPosition ? rememberedScreen : nil)
            ?? screen(withLargestIntersection: orbPanel.frame)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let position = coordinator.preferences.positionsByDisplay[screen.assistantDisplayID]
        let frame = position.map { AssistantWindowGeometry.restoredOrbFrame(from: $0, in: screen.visibleFrame) }
            ?? AssistantWindowGeometry.defaultOrbFrame(in: screen.visibleFrame)
        hasRestoredInitialPosition = true
        orbPanel.setFrame(frame, display: orbPanel.isVisible)
        placeAccessories()
    }

    private func screen(withLargestIntersection frame: CGRect) -> NSScreen? {
        let match = NSScreen.screens
            .map { ($0, $0.frame.intersection(frame).area) }
            .max { $0.1 < $1.1 }
        guard let match, match.1 > 0 else { return nil }
        return match.0
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    @discardableResult
    private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private static func makePanel(frame: CGRect, shadow: Bool) -> AssistantPanel {
        let panel = AssistantPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = shadow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        return panel
    }

}

final class AssistantOrbHostingView: NSHostingView<AnyView> {
    weak var owner: FloatingAssistantWindowController?
    private var trackingAreaToken: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken { removeTrackingArea(trackingAreaToken) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaToken = area
    }

    override func mouseEntered(with event: NSEvent) { owner?.orbMouseEntered() }
    override func mouseExited(with event: NSEvent) { owner?.orbMouseExited() }

    override func mouseDown(with event: NSEvent) {
        owner?.beginOrbPointerInteraction(
            pointerOffset: CGPoint(x: event.locationInWindow.x, y: event.locationInWindow.y),
            clickCount: event.clickCount
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        owner?.showContextMenu(event: event, in: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.assistantDraggingEntered(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.assistantDraggingUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        owner?.assistantDraggingExited()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        owner?.assistantDraggingExited()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        owner?.performAssistantDrop(sender) ?? false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

}

final class AssistantPeekHostingView: NSHostingView<AnyView> {
    // borderless NSPanel 不应把标题栏安全区留给 SwiftUI，否则内容会整体下移。
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

final class AssistantTrackingHostingView: NSHostingView<AnyView> {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var trackingAreaToken: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken { removeTrackingArea(trackingAreaToken) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaToken = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct AssistantOrbView: View {
    @ObservedObject var coordinator: AssistantContextCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        if coordinator.isInquiryRunning { return "ellipsis" }
        switch coordinator.lifecycle.mode {
        case .paused: return "pause.fill"
        case .privacy: return "hand.raised.fill"
        default: return "sparkles"
        }
    }

    private var ringColor: Color {
        switch coordinator.lifecycle.mode {
        case .paused: return .orange
        case .privacy: return .blue
        default: return .mint
        }
    }

    @ViewBuilder
    private var statusRing: some View {
        if coordinator.assistantIsWorking {
            if reduceMotion {
                Circle().strokeBorder(
                    AngularGradient(colors: [.mint, .cyan, .yellow, .pink, .mint], center: .center),
                    lineWidth: 3
                )
            } else {
                // 小尺寸圆环 15 FPS 已足够连贯，避免模型运行时额外触发 30 FPS 的 SwiftUI 重绘。
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: [.mint, .cyan, .yellow, .pink, .mint], center: .center),
                            lineWidth: 3
                        )
                        .rotationEffect(.degrees(
                            context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 2) * 180
                        ))
                }
            }
        } else {
            Circle().strokeBorder(ringColor.opacity(0.85), lineWidth: 2)
        }
    }

    private var dropTitle: String {
        guard let classification = coordinator.dropClassification else { return "" }
        if classification.kind == .multipleItems {
            return coordinator.text("一次仅支持一个文件", "One item at a time")
        }
        guard classification.isSupported else {
            return coordinator.text("不支持此类型", "Unsupported type")
        }
        return coordinator.text("松开选择任务", "Drop to choose a task")
    }

    private var dropSymbol: String {
        switch coordinator.dropClassification?.kind {
        case .text, .textFile: return "doc.text"
        case .image: return "photo"
        case .media: return "waveform"
        case .url: return "link"
        case .multipleItems: return "doc.on.doc"
        default: return "nosign"
        }
    }

    var body: some View {
        Group {
            if coordinator.dropClassification != nil {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(Circle().strokeBorder(
                            coordinator.dropClassification?.isSupported == true ? Color.accentColor : Color.red,
                            lineWidth: 3
                        ))
                        .padding(3)
                    VStack(spacing: 7) {
                        Image(systemName: dropSymbol).font(.system(size: 23, weight: .semibold))
                        Text(dropTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 88)
                    }
                }
                .frame(width: 120, height: 120)
                .accessibilityLabel(dropTitle)
            } else {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(statusRing)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .padding(3)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .symbolEffect(.pulse, isActive: coordinator.assistantIsWorking && !reduceMotion)
                    if coordinator.unreadCount > 0 {
                        Text(coordinator.unreadCount > 9 ? "9+" : "\(coordinator.unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.red, in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .offset(x: -1, y: 1)
                            .accessibilityLabel(coordinator.text("未读提示", "Unread suggestions"))
                            .accessibilityValue(coordinator.unreadCount > 9 ? "9+" : "\(coordinator.unreadCount)")
                    }
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(coordinator.text("桌面情境助手", "Desktop Context Assistant"))
                .accessibilityValue(coordinator.assistantIsWorking
                    ? coordinator.text("正在工作", "Working")
                    : coordinator.text("空闲", "Idle"))
                .accessibilityHint(coordinator.text("单击询问或查看最新未读提示，拖动可移动", "Click to ask or view the latest unread suggestion; drag to move"))
                .accessibilityAction { coordinator.windowController?.orbClicked() }
                .accessibilityAction(named: Text(coordinator.text("打开工具条", "Open Toolbar"))) {
                    coordinator.windowController?.showToolbarForKeyboardNavigation()
                }
            }
        }
    }
}

private struct AssistantToolbarView: View {
    private enum Action: Hashable {
        case recent
        case clipboard
    }

    @ObservedObject var coordinator: AssistantContextCoordinator
    @FocusState private var focusedAction: Action?

    var body: some View {
        Group {
            if coordinator.accessoryPlacement == .left || coordinator.accessoryPlacement == .right {
                HStack(spacing: 4) { actions }
            } else {
                VStack(spacing: 4) { actions }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(
            width: coordinator.accessoryPlacement == .left || coordinator.accessoryPlacement == .right ? 88 : 40,
            height: coordinator.accessoryPlacement == .left || coordinator.accessoryPlacement == .right ? 40 : 88
        )
        .onChange(of: coordinator.toolbarKeyboardFocusToken) { _, _ in
            focusedAction = .recent
        }
    }

    @ViewBuilder
    private var actions: some View {
        toolbarButton(
            symbol: "clock.arrow.circlepath",
            title: coordinator.text("最近提示", "Recent Suggestions"),
            focus: .recent,
            action: coordinator.openRecent
        )
        toolbarButton(
            symbol: "doc.on.clipboard",
            title: coordinator.text("剪贴板", "Clipboard"),
            focus: .clipboard,
            action: coordinator.openClipboardSuggestion
        )
    }

    private func toolbarButton(
        symbol: String,
        title: String,
        focus: Action,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedAction, equals: focus)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct AssistantPeekView: View {
    @ObservedObject var coordinator: AssistantContextCoordinator
    @State private var patternDisableCard: AssistantCard?
    @State private var evidenceCard: AssistantCard?

    var body: some View {
        Group {
            switch coordinator.panelContent {
            case .none:
                EmptyView()
            case .inquiry:
                inquiry
            case .recent:
                recent
            case .card, .ephemeralInquiry:
                card
            case .clipboard:
                clipboard
            case .dropTasks:
                dropTasks
            }
        }
        .frame(
            width: coordinator.preferredPeekSize.width,
            height: coordinator.preferredPeekSize.height,
            alignment: .topLeading
        )
        .background {
            if coordinator.selectedCardUsesSpeechBubble {
                AssistantSpeechBubbleShape(placement: coordinator.accessoryPlacement)
                    .fill(.regularMaterial)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
            }
        }
        .overlay {
            if !coordinator.selectedCardUsesSpeechBubble {
                RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25))
            }
        }
        .confirmationDialog(
            coordinator.text("关闭这类模式？", "Disable This Pattern?"),
            isPresented: Binding(
                get: { patternDisableCard != nil },
                set: { if !$0 { patternDisableCard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(coordinator.text("关闭整个模式", "Disable Pattern"), role: .destructive) {
                if let card = patternDisableCard { coordinator.disablePattern(for: card) }
                patternDisableCard = nil
            }
            Button(coordinator.text("取消", "Cancel"), role: .cancel) { patternDisableCard = nil }
        } message: {
            Text(coordinator.text("可在 Assistant 设置中重新开启；当前面板会提供 10 秒撤销。", "You can re-enable it in Assistant Settings; this panel offers a 10-second undo."))
        }
    }

    private var inquiry: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(coordinator.text("快问", "Quick Ask"), symbol: "questionmark.bubble")
            EditableTextView(text: $coordinator.inquiryText, onSubmit: coordinator.submitInquiry, autoFocus: false)
                .frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 6) {
                if coordinator.canAttachClipboard {
                    contextToggle(
                        title: coordinator.text("当前剪贴板", "Clipboard"),
                        symbol: "doc.on.clipboard",
                        isOn: $coordinator.includeClipboardContext
                    )
                }
                if coordinator.canAttachCurrentCard {
                    contextToggle(
                        title: coordinator.text("当前提示", "Current Suggestion"),
                        symbol: "sparkles.rectangle.stack",
                        isOn: $coordinator.includeCurrentCardContext
                    )
                }
                Spacer()
            }
            if let error = coordinator.inquiryError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            HStack {
                Spacer()
                if coordinator.isInquiryRunning { ProgressView().controlSize(.small) }
                Button(action: coordinator.submitInquiry) {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(coordinator.inquiryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isInquiryRunning)
                .help(coordinator.text("发送", "Send"))
                .accessibilityLabel(coordinator.text("发送", "Send"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(coordinator.text("最近提示", "Recent Suggestions"), symbol: "clock.arrow.circlepath")
            if coordinator.cards.isEmpty {
                Spacer()
                Text(coordinator.text("当前会话还没有提示", "No suggestions in this session"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(coordinator.cards) { card in
                            Button { coordinator.presentCard(id: card.id) } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(card.state == .unread && card.requiresUserAction ? Color.accentColor : Color.clear)
                                        .frame(width: 6, height: 6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sourceTitle(card.source)).font(.caption2).foregroundStyle(.secondary)
                                        Text(card.comment).font(.caption).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(card.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Button(coordinator.text("全部已读", "Mark All Read"), action: coordinator.markAllViewed)
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(coordinator.unreadCount == 0)
                Spacer()
                Button(role: .destructive, action: coordinator.clearCards) {
                    Label(coordinator.text("清除提示", "Clear"), systemImage: "trash")
                }
                .buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var card: some View {
        if let card = coordinator.selectedCard {
            if card.prefersSpeechBubblePresentation {
                Text(card.comment)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .padding(speechBubbleInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: coordinator.dismissSpeechBubble)
                    .accessibilityLabel(card.comment)
                    .accessibilityHint(coordinator.text("点击收起", "Click to dismiss"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(sourceTitle(card.source), systemImage: sourceSymbol(card.source))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    whyButton(card)
                    Button { coordinator.showAdjacentCard(offset: -1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).help(coordinator.text("上一条", "Previous"))
                        .accessibilityLabel(coordinator.text("上一条", "Previous"))
                    Button { coordinator.showAdjacentCard(offset: 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).help(coordinator.text("下一条", "Next"))
                        .accessibilityLabel(coordinator.text("下一条", "Next"))
                    closeButton
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.source == .inquiry ? (card.detailText ?? card.comment) : card.comment)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if card.source != .inquiry,
                           let evidence = card.evidenceSummary,
                           !evidence.isEmpty {
                            Text(evidence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    ForEach(Array(card.actionIDs.prefix(2)), id: \.self) { action in
                        Button {
                            coordinator.perform(action: action, for: card)
                        } label: {
                            Text(actionTitle(action))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                            .controlSize(.small)
                            .disabled(!coordinator.actionIsAvailable(action, for: card))
                    }
                    Spacer()
                    moreMenu(card)
                }
                HStack(spacing: 10) {
                    feedbackButton("hand.thumbsup", coordinator.text("有用", "Useful"), .useful, card)
                    feedbackMenu(card)
                    Spacer()
                    if coordinator.patternDisableUndo != nil {
                        Button(coordinator.text("撤销关闭模式", "Undo Pattern Disable"), action: coordinator.undoPatternDisable)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                }
                .padding(12)
            }
        }
    }

    private var speechBubbleInsets: EdgeInsets {
        switch coordinator.accessoryPlacement {
        case .left:
            EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 26)
        case .right:
            EdgeInsets(top: 14, leading: 26, bottom: 14, trailing: 16)
        case .above:
            EdgeInsets(top: 14, leading: 16, bottom: 26, trailing: 16)
        case .below:
            EdgeInsets(top: 26, leading: 16, bottom: 14, trailing: 16)
        }
    }

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(coordinator.text("剪贴板", "Clipboard"), symbol: "doc.on.clipboard")
            if coordinator.canAttachClipboard {
                Text(coordinator.text("剪贴板中有可处理的文本。为避免暴露敏感内容，这里不直接显示全文。", "The clipboard contains text that can be processed. Its full contents are not shown here."))
                    .font(.body)
                Text(coordinator.text("可在快问中显式附带，或带入 Quick Action。", "Attach it explicitly in Quick Ask or open it in Quick Action."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Button(coordinator.text("询问并附带", "Ask with Clipboard")) {
                        coordinator.openInquiry()
                        coordinator.includeClipboardContext = true
                    }
                    Button(coordinator.text("打开 Quick Action", "Open Quick Action")) {
                        coordinator.onOpenQuickAction?(NSPasteboard.general.string(forType: .string))
                        coordinator.dismissPanel()
                    }
                    Spacer()
                }
                .controlSize(.small)
            } else {
                Spacer()
                Text(coordinator.text("剪贴板里没有可处理的文本", "No processable text in the clipboard"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var dropTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(coordinator.text("选择任务", "Choose a Task"), symbol: dropSymbol)
            if let name = dropDisplayName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                switch dropKind {
                case .text, .textFile:
                    dropButton(coordinator.text("翻译", "Translate"), "character.book.closed") { coordinator.runDroppedTextTask(.translate) }
                    dropButton(coordinator.text("总结", "Summarize"), "text.alignleft") { coordinator.runDroppedTextTask(.summarize) }
                    dropButton(coordinator.text("解释", "Explain"), "questionmark.bubble") { coordinator.runDroppedTextTask(.explain) }
                    dropButton(coordinator.text("提取待办", "Extract TODOs"), "checklist") { coordinator.runDroppedTextTask(.extractTodos) }
                case .image:
                    dropButton("OCR", "text.viewfinder") { coordinator.openDroppedImage(mode: .plainText) }
                    dropButton(coordinator.text("结构化提取", "Structured"), "tablecells") { coordinator.openDroppedImage(mode: .structured) }
                    dropButton(coordinator.text("翻译图片", "Translate Image"), "character.book.closed") { coordinator.openDroppedImage(mode: .extractThenTranslate) }
                    dropButton(coordinator.text("解释图片", "Explain Image"), "photo.badge.magnifyingglass") { coordinator.openDroppedImage(mode: .explainImage) }
                case .media:
                    dropButton(coordinator.text("转写", "Transcribe"), "waveform") { coordinator.openDroppedMedia(mode: .original) }
                    dropButton(coordinator.text("翻译字幕", "Translate Subtitles"), "captions.bubble") { coordinator.openDroppedMedia(mode: .bilingual) }
                case .url:
                    dropButton(coordinator.text("复制链接", "Copy URL"), "doc.on.doc") { coordinator.performDroppedURLAction(open: false) }
                    dropButton(coordinator.text("在浏览器打开", "Open in Browser"), "safari") { coordinator.performDroppedURLAction(open: true) }
                default:
                    EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var dropKind: AssistantDropKind? {
        guard let payload = coordinator.pendingDropPayload else { return nil }
        switch payload {
        case .text: return .text
        case .file(_, let kind): return kind
        case .url: return .url
        }
    }

    private var dropDisplayName: String? {
        guard let payload = coordinator.pendingDropPayload else { return nil }
        switch payload {
        case .text(let value):
            return coordinator.text("文本 · \(value.count) 字符", "Text · \(value.count) characters")
        case .file(let url, _):
            return url.lastPathComponent
        case .url(let url):
            return url.absoluteString
        }
    }

    private var dropSymbol: String {
        switch dropKind {
        case .text, .textFile: return "doc.text"
        case .image: return "photo"
        case .media: return "waveform"
        case .url: return "link"
        default: return "arrow.down.doc"
        }
    }

    private func dropButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .help(title)
    }

    private func header(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.headline)
            Spacer()
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: coordinator.closePanelFromUser) { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .help(coordinator.text("关闭", "Close"))
            .accessibilityLabel(coordinator.text("关闭", "Close"))
    }

    private func contextToggle(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Label(title, systemImage: symbol) }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }

    private func feedbackButton(_ symbol: String, _ title: String, _ feedback: AssistantFeedback, _ card: AssistantCard) -> some View {
        Button { coordinator.setFeedback(feedback, for: card) } label: {
            Image(systemName: card.feedback == feedback ? "\(symbol).fill" : symbol)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func feedbackMenu(_ card: AssistantCard) -> some View {
        Menu {
            Button {
                coordinator.setFeedback(.irrelevant, for: card)
            } label: {
                Label(coordinator.text("不相关", "Irrelevant"), systemImage: "hand.thumbsdown")
            }
            if coordinator.cardIncludesJoke(card) {
                Button {
                    coordinator.setFeedback(.unfunny, for: card)
                } label: {
                    Label(coordinator.text("不好笑", "Unfunny"), systemImage: "face.smiling.inverse")
                }
            }
        } label: {
            Image(systemName: card.feedback == .irrelevant || card.feedback == .unfunny ? "bubble.left.fill" : "bubble.left")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(coordinator.text("反馈", "Feedback"))
        .accessibilityLabel(coordinator.text("反馈", "Feedback"))
    }

    private func moreMenu(_ card: AssistantCard) -> some View {
        Menu {
            ForEach(Array(card.actionIDs.dropFirst(2)), id: \.self) { action in
                Button(actionTitle(action)) { coordinator.perform(action: action, for: card) }
                    .disabled(!coordinator.actionIsAvailable(action, for: card))
            }
            if card.patternType == .foreignClipboard {
                Button {
                    coordinator.onOpenModelSettings?()
                } label: {
                    Label(coordinator.text("翻译设置", "Translation Settings"), systemImage: "slider.horizontal.3")
                }
                Button {
                    coordinator.suppressForeignLanguage(for: card)
                } label: {
                    Label(coordinator.text("以后不建议该语言", "Stop Suggesting This Language"), systemImage: "character.book.closed.fill")
                }
            }
            if card.patternType != nil {
                Divider()
                Button {
                    coordinator.pauseProactiveSuggestions()
                } label: {
                    Label(coordinator.text("暂停主动提示", "Pause Proactive Suggestions"), systemImage: "pause.circle")
                }
                if card.patternType != .contextualOpportunity {
                    Button(role: .destructive) {
                        patternDisableCard = card
                    } label: {
                        Label(coordinator.text("不要再提醒这类内容", "Stop This Type of Suggestion"), systemImage: "nosign")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(coordinator.text("更多", "More"))
        .accessibilityLabel(coordinator.text("更多", "More"))
    }

    private func whyButton(_ card: AssistantCard) -> some View {
        Button {
            coordinator.viewEvidence(for: card)
            evidenceCard = card
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .popover(item: $evidenceCard, arrowEdge: .top) { evidence in
            VStack(alignment: .leading, spacing: 8) {
                Text(coordinator.text("为什么出现", "Why This Appeared")).font(.headline)
                Divider()
                Text(coordinator.text("模式：\(patternTitle(evidence.patternType))", "Pattern: \(patternTitle(evidence.patternType))"))
                Text(coordinator.text("次数：\(evidence.evidence.count)", "Count: \(evidence.evidence.count)"))
                Text(coordinator.text("时间范围：\(evidence.evidence.durationSeconds) 秒", "Window: \(evidence.evidence.durationSeconds) seconds"))
                Text(evidence.evidence.usedLocalModel
                ? coordinator.text("已使用本地判断模型", "Local judgment model used")
                : coordinator.text("未使用判断模型", "No judgment model used"))
                Text(coordinator.cardRawContextIsAvailable(evidence)
                ? coordinator.text("原始内容仍为短期内存引用", "Raw content has a short-term memory reference")
                : coordinator.text("没有原始内容引用", "No raw-content reference"))
                Divider()
                Button {
                    evidenceCard = nil
                    coordinator.onOpenSettings?()
                } label: {
                    Label(coordinator.text("管理观察来源", "Manage Observation Sources"), systemImage: "gearshape")
                }
            }
            .font(.caption)
            .padding(12)
            .frame(width: 280, alignment: .leading)
        }
        .help(coordinator.text("为什么出现", "Why This Appeared"))
        .accessibilityLabel(coordinator.text("为什么出现", "Why This Appeared"))
    }

    private func patternTitle(_ pattern: AssistantPatternType?) -> String {
        switch pattern {
        case .repeatedFailure: return coordinator.text("重复失败", "Repeated Failure")
        case .foreignClipboard: return coordinator.text("连续外语复制", "Foreign Clipboard Sequence")
        case .contextualOpportunity: return coordinator.text("情境机会", "Context Opportunity")
        case nil: return coordinator.text("显式操作", "Explicit Action")
        }
    }

    private func actionTitle(_ action: AssistantActionID) -> String {
        switch action {
        case .deepenInquiry: return coordinator.text("深入处理", "Go Deeper")
        case .openQuickAction: return "Quick Action"
        case .explainError: return coordinator.text("解释错误", "Explain Error")
        case .returnToWorkbench: return coordinator.text("返回工作台", "Return to Workbench")
        case .detailedTranslation: return coordinator.text("详细翻译", "Detailed Translation")
        case .copyTranslation: return coordinator.text("复制译文", "Copy Translation")
        case .openSettings: return coordinator.text("设置", "Settings")
        case .enableClipboardTranslation: return coordinator.text("开启 30 分钟", "Enable for 30 Minutes")
        case .translateCurrentClipboard: return coordinator.text("只翻译这条", "Translate This Only")
        }
    }

    private func sourceTitle(_ source: AssistantSource) -> String {
        switch source {
        case .inquiry: return coordinator.text("询问", "Inquiry")
        case .clipboard: return coordinator.text("剪贴板", "Clipboard")
        case .selection: return coordinator.text("选区", "Selection")
        case .droppedFile: return coordinator.text("拖入内容", "Dropped Content")
        case .llmToolsTask: return "llmTools"
        case .foregroundApplication: return coordinator.text("应用", "Application")
        case .windowContext: return coordinator.text("窗口", "Window")
        }
    }

    private func sourceSymbol(_ source: AssistantSource) -> String {
        switch source {
        case .inquiry: return "questionmark.bubble"
        case .clipboard: return "doc.on.clipboard"
        case .selection: return "selection.pin.in.out"
        case .droppedFile: return "arrow.down.doc"
        case .llmToolsTask: return "sparkles.rectangle.stack"
        case .foregroundApplication: return "app"
        case .windowContext: return "macwindow"
        }
    }
}

private struct AssistantSpeechBubbleShape: Shape {
    var placement: AssistantAccessoryPlacement

    func path(in rect: CGRect) -> Path {
        let tailDepth: CGFloat = 10
        let tailHalfWidth: CGFloat = 7
        var body = rect
        switch placement {
        case .left:
            body.size.width -= tailDepth
        case .right:
            body.origin.x += tailDepth
            body.size.width -= tailDepth
        case .above:
            body.size.height -= tailDepth
        case .below:
            body.origin.y += tailDepth
            body.size.height -= tailDepth
        }

        var path = Path()
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 14, height: 14))
        switch placement {
        case .left:
            path.move(to: CGPoint(x: body.maxX - 1, y: body.midY - tailHalfWidth))
            path.addLine(to: CGPoint(x: rect.maxX, y: body.midY))
            path.addLine(to: CGPoint(x: body.maxX - 1, y: body.midY + tailHalfWidth))
        case .right:
            path.move(to: CGPoint(x: body.minX + 1, y: body.midY - tailHalfWidth))
            path.addLine(to: CGPoint(x: rect.minX, y: body.midY))
            path.addLine(to: CGPoint(x: body.minX + 1, y: body.midY + tailHalfWidth))
        case .above:
            path.move(to: CGPoint(x: body.midX - tailHalfWidth, y: body.maxY - 1))
            path.addLine(to: CGPoint(x: body.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: body.midX + tailHalfWidth, y: body.maxY - 1))
        case .below:
            path.move(to: CGPoint(x: body.midX - tailHalfWidth, y: body.minY + 1))
            path.addLine(to: CGPoint(x: body.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: body.midX + tailHalfWidth, y: body.minY + 1))
        }
        path.closeSubpath()
        return path
    }
}

private struct AssistantOnboardingView: View {
    @ObservedObject var coordinator: AssistantContextCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if coordinator.onboardingIsReenableConfirmation {
                reenableConfirmation
            } else {
                stepIndicator
                Group {
                    switch coordinator.onboardingStep {
                    case 0: scopeStep
                    case 1: sourcesStep
                    default: storageStep
                    }
                }
                Spacer(minLength: 0)
                navigation
            }
        }
        .padding(24)
        .frame(width: 520, height: 470)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == coordinator.onboardingStep ? Color.accentColor : Color.secondary.opacity(0.22))
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(coordinator.text("第 \(index + 1) 步", "Step \(index + 1)"))
            }
            Spacer()
            Text("\(coordinator.onboardingStep + 1) / 3").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(coordinator.text("先说明边界", "Know the Boundaries"), systemImage: "hand.raised.square")
                .font(.title2.bold())
            Text(coordinator.text(
                "助手只读取你授权的应用元数据、主动选区和剪贴板文本，并在本机形成短期上下文。它不记录按键或鼠标轨迹，不读取屏幕，也不会把后台观察内容发送给远程 provider。",
                "The assistant reads only authorized app metadata, explicit selections, and clipboard text, keeping short-lived context on this Mac. It does not log keys or pointer trails, read the screen, or send observed content to remote providers."
            ))
            .fixedSize(horizontal: false, vertical: true)
            Label(coordinator.text("快问与单项拖入始终是显式输入", "Quick Ask and single-item drops are always explicit"), systemImage: "cursorarrow.click")
            Label(coordinator.text("系统权限只在真正使用对应来源时申请", "System permissions are requested only when a source needs them"), systemImage: "checkmark.shield")
        }
    }

    private var sourcesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coordinator.text("选择上下文来源", "Choose Context Sources")).font(.title2.bold())
            Toggle(coordinator.text("前台应用元数据（标识、类别、激活时间）", "Foreground app metadata (identity, category, activation time)"), isOn: $coordinator.draftForegroundApplicationEnabled)
            Toggle(coordinator.text("增强窗口上下文（标题 + 本地截图理解）", "Enhanced window context (title + local screenshot understanding)"), isOn: $coordinator.draftEnhancedWindowContextEnabled)
                .disabled(!coordinator.draftForegroundApplicationEnabled)
            Toggle(coordinator.text("接入主动触发的选中文字", "Use explicitly triggered text selections"), isOn: $coordinator.draftSelectionContextEnabled)
            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.text("剪贴板观察必须明确选择", "Clipboard observation requires an explicit choice")).font(.headline)
                Picker("", selection: $coordinator.draftClipboardAuthorization) {
                    Text(coordinator.text("允许观察", "Allow")).tag(AssistantClipboardAuthorization.allowed)
                    Text(coordinator.text("暂不允许", "Don't Allow")).tag(AssistantClipboardAuthorization.denied)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(coordinator.text("文本最多在短期上下文中保留 10 分钟；敏感内容会被过滤。", "Text remains in short-term context for at most 10 minutes; sensitive content is filtered."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(coordinator.text("仅手动使用", "Manual Use Only"), action: coordinator.useManualOnlyPreset)
        }
    }

    private var storageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(coordinator.text("本地记录与默认行为", "Local Records and Defaults"), systemImage: "internaldrive")
                .font(.title2.bold())
            Toggle(coordinator.text("使用行为记录优化助手", "Use behavior records to improve the assistant"), isOn: $coordinator.draftUseBehaviorHistory)
            Text(coordinator.text(
                "记录只保存在本机，最长 30 天，并受 5,000 条与 10MB 上限约束。原始短期上下文不会写入行为记录。",
                "Records stay on this Mac for up to 30 days and are limited to 5,000 entries and 10 MB. Raw short-term context is not written to behavior records."
            ))
            HStack(spacing: 18) {
                Label(
                    draftIsManualOnly
                        ? coordinator.text("主动程度：手动", "Proactivity: Manual")
                        : coordinator.text("主动程度：适中", "Proactivity: Moderate"),
                    systemImage: draftIsManualOnly ? "hand.tap" : "speaker.wave.2"
                )
                Label(coordinator.text("性格：温和搭档", "Personality: Gentle"), systemImage: "person.crop.circle.badge.checkmark")
            }
            .font(.callout)
            Text(draftIsManualOnly
                ? coordinator.text(
                    "手动模式不启动后台观察或主动判断；快问和单项拖入仍可使用。",
                    "Manual mode starts no background observation or proactive judgment; Quick Ask and single-item drops remain available."
                )
                : coordinator.text(
                    "启用后会自动运行 24 项本地资格检查；检查通过后适中档才会主动展开高价值提示，检查期间、失败或无可用本地模型时保持安静。",
                    "After enabling, a 24-fixture local qualification runs automatically. Moderate mode expands only high-value suggestions after it passes; the assistant stays Quiet during the check, on failure, or without an eligible local model."
                ))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var draftIsManualOnly: Bool {
        !coordinator.draftForegroundApplicationEnabled
            && !coordinator.draftSelectionContextEnabled
            && coordinator.draftClipboardAuthorization != .allowed
    }

    private var navigation: some View {
        HStack {
            Button(coordinator.text("取消", "Cancel"), action: coordinator.cancelOnboarding)
            Spacer()
            if coordinator.onboardingStep > 0 {
                Button(coordinator.text("上一步", "Back")) { coordinator.onboardingStep -= 1 }
            }
            if coordinator.onboardingStep < 2 {
                Button(coordinator.text("继续", "Continue")) { coordinator.onboardingStep += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(coordinator.text("启用助手", "Enable Assistant"), action: coordinator.finishOnboarding)
                    .keyboardShortcut(.defaultAction)
                    .disabled(coordinator.draftClipboardAuthorization == .undecided)
            }
        }
    }

    private var reenableConfirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(coordinator.text("重新启用桌面情境助手", "Re-enable Desktop Context Assistant"), systemImage: "sparkles")
                .font(.title2.bold())
            Text(coordinator.text("将恢复以下已保存来源：", "The following saved sources will resume:"))
            sourceSummary(coordinator.draftForegroundApplicationEnabled, coordinator.text("前台应用元数据", "Foreground app metadata"))
            sourceSummary(
                coordinator.draftForegroundApplicationEnabled && coordinator.draftEnhancedWindowContextEnabled,
                coordinator.text("增强窗口上下文与截图理解", "Enhanced window context and screenshot understanding")
            )
            sourceSummary(coordinator.draftSelectionContextEnabled, coordinator.text("主动选区", "Explicit selections"))
            sourceSummary(coordinator.draftClipboardAuthorization == .allowed, coordinator.text("剪贴板观察", "Clipboard observation"))
            if !coordinator.draftForegroundApplicationEnabled,
               !coordinator.draftSelectionContextEnabled,
               coordinator.draftClipboardAuthorization != .allowed {
                Label(coordinator.text("仅手动使用", "Manual use only"), systemImage: "hand.tap")
            }
            Spacer()
            HStack {
                Button(coordinator.text("取消", "Cancel"), action: coordinator.cancelOnboarding)
                Spacer()
                Button(coordinator.text("启用", "Enable"), action: coordinator.confirmReenable)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func sourceSummary(_ enabled: Bool, _ title: String) -> some View {
        Label(title, systemImage: enabled ? "checkmark.circle.fill" : "minus.circle")
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension NSScreen {
    var assistantDisplayID: String {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
            ?? localizedName
    }
}
