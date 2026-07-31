import CryptoKit
import Foundation

public struct AssistantQualificationProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case preparing
        case running
        case paused
        case qualified
        case unqualified
        case failed
        case cancelled
    }

    public var modelID: UUID?
    public var modelName: String?
    public var completedCount: Int
    public var totalCount: Int
    public var phase: Phase
    public var message: String?

    public init(
        modelID: UUID? = nil,
        modelName: String? = nil,
        completedCount: Int = 0,
        totalCount: Int = AssistantJudgmentFixtures.all.count,
        phase: Phase = .idle,
        message: String? = nil
    ) {
        self.modelID = modelID
        self.modelName = modelName
        self.completedCount = min(max(0, completedCount), max(0, totalCount))
        self.totalCount = max(0, totalCount)
        self.phase = phase
        self.message = message
    }

    // 资格检查的暂停与续跑只经过这些转换，避免 UI 状态和实际进度分叉。
    public mutating func start(modelID: UUID, modelName: String) {
        self = AssistantQualificationProgress(modelID: modelID, modelName: modelName, phase: .preparing)
    }

    public mutating func beginRunning() {
        guard phase == .preparing || phase == .paused else { return }
        phase = .running
        message = completedCount == 0 ? nil : "\(completedCount)/\(totalCount)"
    }

    public mutating func prepare() {
        guard phase == .preparing || phase == .paused else { return }
        phase = .preparing
    }

    public mutating func pause(message: String) {
        guard phase == .preparing || phase == .running else { return }
        phase = .paused
        self.message = message
    }

    public mutating func recordCompleted(_ count: Int) {
        guard phase == .running else { return }
        completedCount = min(max(completedCount, count), totalCount)
        message = "\(completedCount)/\(totalCount)"
    }

    public mutating func finish(state: AssistantQualificationState, message: String?) {
        completedCount = totalCount
        phase = state == .qualified ? .qualified : .unqualified
        self.message = message
    }

    public mutating func fail(modelID: UUID? = nil, message: String) {
        if let modelID { self.modelID = modelID }
        phase = .failed
        self.message = message
    }

    public mutating func cancel(message: String) {
        phase = .cancelled
        self.message = message
    }
}

public struct AssistantQualificationProactivityState: Sendable, Equatable {
    public private(set) var pendingProactivity: AssistantProactivity?
    public private(set) var runningProactivity: AssistantProactivity?
    public private(set) var runID: UUID?

    public init(pendingProactivity: AssistantProactivity? = nil) {
        self.pendingProactivity = pendingProactivity
    }

    @discardableResult
    public mutating func request(
        _ value: AssistantProactivity,
        hasQualifiedJudgment: Bool
    ) -> AssistantProactivity {
        guard value.requiresQualifiedJudgment, !hasQualifiedJudgment else {
            pendingProactivity = nil
            if runID != nil { runningProactivity = nil }
            return value
        }
        pendingProactivity = value
        // 检查期间切档时更新同一个运行目标，结束后不能复活旧选择。
        if runID != nil { runningProactivity = value }
        return .quiet
    }

    @discardableResult
    public mutating func beginRun(pendingProactivity: AssistantProactivity? = nil) -> UUID {
        if let pendingProactivity { self.pendingProactivity = pendingProactivity }
        let id = UUID()
        runID = id
        runningProactivity = self.pendingProactivity
        return id
    }

    public mutating func cancelRun(clearPendingProactivity: Bool) {
        runID = nil
        runningProactivity = nil
        if clearPendingProactivity { pendingProactivity = nil }
    }

    public mutating func finishRun(
        id: UUID,
        state: AssistantQualificationState
    ) -> AssistantProactivity? {
        guard runID == id else { return nil }
        let requested = runningProactivity
        runID = nil
        runningProactivity = nil
        pendingProactivity = nil
        guard let requested else { return nil }
        return state == .qualified ? requested : .quiet
    }
}

public struct AssistantPatternCandidate: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var createdAt: Date
    public var expiresAt: Date
    public var patternType: AssistantPatternType
    public var source: AssistantSource
    public var sourceTypes: [AssistantSource]
    public var appIdentity: String?
    public var appCategory: String?
    public var evidenceSummary: String
    public var evidenceCount: Int
    public var durationSeconds: Int
    public var contentFingerprint: String?
    public var rawContextReference: UUID?
    public var evidenceContextReferences: [UUID]
    public var language: String?
    public var confidence: Double
    public var actionIDs: [AssistantActionID]
    public var availableTaskKinds: [TaskKind]
    public var workbenchIsRecoverable: Bool
    /// 混合来源候选中仍可回到 llmTools 工作台的原始上下文引用。
    public var workbenchContextReference: UUID?
    public var decisionKey: String
    public var surfaceID: String?
    public var surfaceRevision: UInt64
    public var anchorGeneration: UInt64
    public var sceneSignal: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        expiresAt: Date,
        patternType: AssistantPatternType,
        source: AssistantSource,
        sourceTypes: [AssistantSource]? = nil,
        appIdentity: String? = nil,
        appCategory: String? = nil,
        evidenceSummary: String,
        evidenceCount: Int,
        durationSeconds: Int,
        contentFingerprint: String? = nil,
        rawContextReference: UUID? = nil,
        evidenceContextReferences: [UUID] = [],
        language: String? = nil,
        confidence: Double,
        actionIDs: [AssistantActionID],
        availableTaskKinds: [TaskKind] = [],
        workbenchIsRecoverable: Bool = false,
        workbenchContextReference: UUID? = nil,
        decisionKey: String? = nil,
        surfaceID: String? = nil,
        surfaceRevision: UInt64 = 0,
        anchorGeneration: UInt64 = 0,
        sceneSignal: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.patternType = patternType
        self.source = source
        self.sourceTypes = Array(Set(sourceTypes ?? [source])).sorted { $0.rawValue < $1.rawValue }
        self.appIdentity = appIdentity
        self.appCategory = appCategory
        self.evidenceSummary = String(evidenceSummary.prefix(240))
        self.evidenceCount = max(1, evidenceCount)
        self.durationSeconds = max(0, durationSeconds)
        self.contentFingerprint = contentFingerprint
        self.rawContextReference = rawContextReference
        self.evidenceContextReferences = Array(
            NSOrderedSet(array: evidenceContextReferences.isEmpty
                ? rawContextReference.map { [$0] } ?? []
                : evidenceContextReferences).array.compactMap { $0 as? UUID }.prefix(5)
        )
        self.language = language
        self.confidence = min(max(confidence, 0), 1)
        self.actionIDs = Array(NSOrderedSet(array: actionIDs).array.compactMap { $0 as? AssistantActionID }.prefix(3))
        self.availableTaskKinds = Array(Set(availableTaskKinds)).sorted { $0.rawValue < $1.rawValue }
        self.workbenchIsRecoverable = workbenchIsRecoverable
        self.workbenchContextReference = workbenchContextReference
        self.decisionKey = decisionKey ?? "\(patternType.rawValue)|\(contentFingerprint ?? language ?? id.uuidString)"
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.anchorGeneration = anchorGeneration
        self.sceneSignal = sceneSignal
    }

    public var isTaskFailure: Bool {
        patternType == .repeatedFailure && sourceTypes.contains(.llmToolsTask)
    }

    public var priority: Int {
        switch patternType {
        case .repeatedFailure: return 300
        case .foreignClipboard: return 250
        case .contextualOpportunity:
            if sourceTypes.contains(.selection) || sourceTypes.contains(.clipboard) { return 180 }
            if ["blocked", "deadline", "waiting"].contains(sceneSignal) { return 150 }
            if sceneSignal == "success" { return 110 }
            return 80
        }
    }
}

public actor AssistantPatternDetector {
    public static let evidenceWindow: TimeInterval = 10 * 60
    public static let repeatedFailureThreshold = 3
    public static let repeatedFailureCooldown: TimeInterval = 30 * 60
    public static let foreignClipboardThreshold = 3
    public static let foreignClipboardMinimumCharacterCount = 20
    public static let foreignClipboardMinimumConfidence = 0.80
    public static let foreignClipboardCooldown: TimeInterval = 60 * 60
    public static let contextOpportunityDebounce: TimeInterval = 0.8
    public static let contextOpportunityMaximumDebounce: TimeInterval = 2
    public static let contextOpportunityEvidenceFreshness: TimeInterval = 60
    public static let contextOpportunityVisualFreshness: TimeInterval = 30
    public static let contextOpportunityClipboardBridge: TimeInterval = 30
    public static let contextOpportunityCooldown: TimeInterval = 10 * 60
    public static let activeCompanionInterval: TimeInterval = 5 * 60
    public static let candidateReservationTTL: TimeInterval = AssistantContextBuffer.rawContextTTL

    private struct FailureSample: Sendable {
        var occurredAt: Date
        var source: AssistantSource
        var appIdentity: String?
        var rawContextReference: UUID?
        var workbenchIsRecoverable: Bool
    }

    private struct ClipboardSample: Sendable {
        var occurredAt: Date
        var rawContextReference: UUID?
    }

    private struct ContextOpportunitySample: Sendable {
        var event: AssistantActivityEvent
        var fingerprint: String
    }

    private var failuresByFingerprint: [String: [FailureSample]] = [:]
    private var clipboardByLanguage: [String: [String: ClipboardSample]] = [:]
    private var failureCooldowns: [String: Date] = [:]
    private var languageCooldowns: [String: Date] = [:]
    private var failureReservations: [String: Date] = [:]
    private var languageReservations: [String: Date] = [:]
    private var contextOpportunitySamples: [String: ContextOpportunitySample] = [:]
    private var contextOpportunityCooldowns: [String: Date] = [:]
    private var contextOpportunityReservations: [String: Date] = [:]
    private var nextActiveCompanionAt = Date.distantPast

    public init() {}

    public func ingestFailure(
        _ event: AssistantActivityEvent,
        workbenchIsRecoverable: Bool = false,
        now: Date = .now
    ) -> AssistantPatternCandidate? {
        guard event.sensitivity == .normal,
              [.taskFailed, .selectionCaptured, .clipboardChanged].contains(event.type),
              [.llmToolsTask, .selection, .clipboard].contains(event.source),
              let fingerprint = event.contentFingerprint,
              let rawContextReference = event.ephemeralContextReference,
              event.expiresAt > now else { return nil }

        prune(now: now)
        var samples = failuresByFingerprint[fingerprint] ?? []
        samples.append(FailureSample(
            occurredAt: event.occurredAt,
            source: event.source,
            appIdentity: event.appIdentity,
            rawContextReference: rawContextReference,
            workbenchIsRecoverable: workbenchIsRecoverable
        ))
        samples = samples.filter { $0.occurredAt >= now.addingTimeInterval(-Self.evidenceWindow) }
        failuresByFingerprint[fingerprint] = samples
        guard samples.count >= Self.repeatedFailureThreshold,
              failureCooldowns[fingerprint, default: .distantPast] <= now,
              failureReservations[fingerprint, default: .distantPast] <= now else { return nil }

        failureReservations[fingerprint] = now.addingTimeInterval(Self.candidateReservationTTL)
        let first = samples.map(\.occurredAt).min() ?? now
        let latest = samples.max { $0.occurredAt < $1.occurredAt } ?? samples[samples.count - 1]
        let recoverableWorkbenchSample = samples
            .filter { $0.source == .llmToolsTask && $0.workbenchIsRecoverable }
            .max { $0.occurredAt < $1.occurredAt }
        var actions: [AssistantActionID] = [.explainError]
        if recoverableWorkbenchSample != nil {
            actions.append(.returnToWorkbench)
        }
        return AssistantPatternCandidate(
            createdAt: now,
            expiresAt: min(event.expiresAt, event.occurredAt.addingTimeInterval(AssistantContextBuffer.rawContextTTL)),
            patternType: .repeatedFailure,
            source: latest.source,
            sourceTypes: samples.map(\.source),
            appIdentity: latest.appIdentity,
            appCategory: latest.appIdentity.map(AssistantPrivacyPolicy.appCategory),
            evidenceSummary: "same-error-signature count=\(samples.count) window=\(Int(now.timeIntervalSince(first)))s",
            evidenceCount: samples.count,
            durationSeconds: Int(max(0, now.timeIntervalSince(first))),
            contentFingerprint: fingerprint,
            rawContextReference: latest.rawContextReference,
            evidenceContextReferences: samples.compactMap(\.rawContextReference),
            confidence: 1,
            actionIDs: actions,
            workbenchIsRecoverable: recoverableWorkbenchSample != nil,
            workbenchContextReference: recoverableWorkbenchSample?.rawContextReference,
            decisionKey: "repeatedFailure|\(fingerprint)"
        )
    }

    public func ingestForeignClipboard(
        _ event: AssistantActivityEvent,
        language: String,
        effectiveCharacterCount: Int,
        now: Date = .now
    ) -> AssistantPatternCandidate? {
        guard event.type == .foreignTextDetected,
              event.source == .clipboard,
              event.sensitivity == .normal,
              event.confidence >= Self.foreignClipboardMinimumConfidence,
              effectiveCharacterCount >= Self.foreignClipboardMinimumCharacterCount,
              let fingerprint = event.contentFingerprint,
              let rawContextReference = event.ephemeralContextReference,
              event.expiresAt > now,
              let normalizedLanguage = LanguageCodeNormalizer.normalizedBCP47(language) else { return nil }

        prune(now: now)
        var samples = clipboardByLanguage[normalizedLanguage] ?? [:]
        samples[fingerprint] = ClipboardSample(occurredAt: event.occurredAt, rawContextReference: rawContextReference)
        samples = samples.filter { $0.value.occurredAt >= now.addingTimeInterval(-Self.evidenceWindow) }
        clipboardByLanguage[normalizedLanguage] = samples
        guard samples.count >= Self.foreignClipboardThreshold,
              languageCooldowns[normalizedLanguage, default: .distantPast] <= now,
              languageReservations[normalizedLanguage, default: .distantPast] <= now else { return nil }

        languageReservations[normalizedLanguage] = now.addingTimeInterval(Self.candidateReservationTTL)
        let first = samples.values.map(\.occurredAt).min() ?? now
        return AssistantPatternCandidate(
            createdAt: now,
            expiresAt: min(event.expiresAt, event.occurredAt.addingTimeInterval(AssistantContextBuffer.rawContextTTL)),
            patternType: .foreignClipboard,
            source: .clipboard,
            appIdentity: event.appIdentity,
            appCategory: event.appIdentity.map(AssistantPrivacyPolicy.appCategory),
            evidenceSummary: "same-language=\(normalizedLanguage) distinct=\(samples.count) window=\(Int(now.timeIntervalSince(first)))s",
            evidenceCount: samples.count,
            durationSeconds: Int(max(0, now.timeIntervalSince(first))),
            contentFingerprint: fingerprint,
            rawContextReference: rawContextReference,
            evidenceContextReferences: samples.values
                .sorted { $0.occurredAt < $1.occurredAt }
                .compactMap(\.rawContextReference),
            language: normalizedLanguage,
            confidence: event.confidence,
            actionIDs: [.enableClipboardTranslation, .translateCurrentClipboard],
            decisionKey: "foreignClipboard|\(normalizedLanguage)"
        )
    }

    @discardableResult
    public func ingestContextOpportunity(
        _ event: AssistantActivityEvent,
        activeCompanionMode: Bool = false,
        now: Date = .now
    ) -> Bool {
        guard event.sensitivity == .normal,
              [.clipboardChanged, .selectionCaptured, .windowContextChanged].contains(event.type),
              [.clipboard, .selection, .windowContext].contains(event.source),
              let fingerprint = event.contentFingerprint,
              event.ephemeralContextReference != nil,
              event.expiresAt > now else { return false }
        prune(now: now)
        let key = "\(event.source.rawValue)|\(event.contentType?.rawValue ?? "none")|\(event.surfaceID ?? "global")|\(fingerprint)"
        if event.source == .windowContext, event.contentType == .image {
            // 同一操作只保留最新视觉状态，旧页面截图不能继续作为当前画面的支持证据。
            contextOpportunitySamples = contextOpportunitySamples.filter { _, sample in
                let existing = sample.event
                return existing.source != .windowContext
                    || existing.contentType != .image
                    || existing.surfaceID != event.surfaceID
                    || existing.surfaceRevision != event.surfaceRevision
                    || existing.anchorGeneration != event.anchorGeneration
            }
        }
        contextOpportunitySamples[key] = ContextOpportunitySample(event: event, fingerprint: fingerprint)
        if [.clipboard, .selection].contains(event.source), event.provenance != .observed {
            return true
        }
        guard event.source == .windowContext,
              event.contentType == .image,
              let sceneSignal = event.sceneSignal else { return false }
        if sceneSignal != "none" { return true }
        guard activeCompanionMode, nextActiveCompanionAt <= now else { return false }
        // 活跃档允许普通但具体的桌面场景参与判断；五分钟节流避免持续截图变成持续推理。
        nextActiveCompanionAt = now.addingTimeInterval(Self.activeCompanionInterval)
        return true
    }

    public enum ContextOpportunityFlushResult: Sendable {
        case candidate(AssistantPatternCandidate)
        case noEvidence
        case duplicateCooldown
    }

    public func flushContextOpportunityResult(
        trigger: AssistantActivityEvent? = nil,
        now: Date = .now
    ) -> ContextOpportunityFlushResult {
        prune(now: now)
        guard let trigger else { return .noEvidence }
        let samples = contextOpportunitySamples.values
            .filter { sample in
                let event = sample.event
                guard event.expiresAt > now,
                      event.occurredAt <= now,
                      now.timeIntervalSince(event.occurredAt) <= Self.contextOpportunityEvidenceFreshness else {
                    return false
                }
                if event.id == trigger.id { return true }
                if event.surfaceID == trigger.surfaceID,
                   event.surfaceRevision == trigger.surfaceRevision {
                    if event.contentType == .image {
                        return event.anchorGeneration == trigger.anchorGeneration
                            && now.timeIntervalSince(event.occurredAt) <= Self.contextOpportunityVisualFreshness
                    }
                    if event.contentType == .metadata { return true }
                    return event.anchorGeneration == trigger.anchorGeneration
                }
                return event.source == .clipboard
                    && event.provenance != .observed
                    && now.timeIntervalSince(event.occurredAt) <= Self.contextOpportunityClipboardBridge
            }
            .sorted { $0.event.occurredAt > $1.event.occurredAt }
        guard !samples.isEmpty else { return .noEvidence }

        // 主锚点优先，支持证据按新旧排序；相同正文跨选区/剪贴板只保留一份。
        var selected: [ContextOpportunitySample] = []
        var fingerprints = Set<String>()
        if let primary = samples.first(where: { $0.event.id == trigger.id }) {
            selected.append(primary)
            fingerprints.insert(primary.fingerprint)
        }
        for sample in samples where !fingerprints.contains(sample.fingerprint) {
            selected.append(sample)
            fingerprints.insert(sample.fingerprint)
            if selected.count == 5 { break }
        }
        guard !selected.isEmpty else { return .noEvidence }
        let primary = selected[0]
        let decisionIdentity: String
        if trigger.anchorGeneration > 0 {
            decisionIdentity = "anchor:\(trigger.anchorGeneration)"
        } else {
            decisionIdentity = "content:\(trigger.contentFingerprint ?? primary.fingerprint)"
        }
        let decisionKeyMaterial = [
            trigger.surfaceID ?? trigger.appIdentity ?? "global",
            "revision:\(trigger.surfaceRevision)",
            decisionIdentity
        ].joined(separator: "|")
        let decisionHash = SHA256.hash(data: Data(decisionKeyMaterial.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let decisionKey = "contextualOpportunity|\(decisionHash)"
        let cooldownKeyMaterial = [
            trigger.surfaceID ?? trigger.appIdentity ?? "global",
            trigger.contentFingerprint ?? primary.fingerprint
        ].joined(separator: "|")
        let cooldownKey = SHA256.hash(data: Data(cooldownKeyMaterial.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard contextOpportunityCooldowns[cooldownKey, default: .distantPast] <= now else {
            return .duplicateCooldown
        }
        guard contextOpportunityReservations[decisionKey, default: .distantPast] <= now else {
            return .duplicateCooldown
        }
        contextOpportunityReservations[decisionKey] = now.addingTimeInterval(Self.candidateReservationTTL)

        let events = selected.map(\.event)
        let latest = events.max { $0.occurredAt < $1.occurredAt } ?? trigger
        let appIdentities = Set(events.compactMap(\.appIdentity))
        let appIdentity = appIdentities.count == 1 ? appIdentities.first : nil
        let references = events.compactMap(\.ephemeralContextReference)
        return .candidate(AssistantPatternCandidate(
            createdAt: now,
            expiresAt: events.map(\.occurredAt).min()!.addingTimeInterval(AssistantContextBuffer.rawContextTTL),
            patternType: .contextualOpportunity,
            source: latest.source,
            sourceTypes: events.map(\.source),
            appIdentity: appIdentity,
            appCategory: appIdentity.map(AssistantPrivacyPolicy.appCategory),
            evidenceSummary: "authorized-context count=\(events.count) anchor=\(trigger.source.rawValue)",
            evidenceCount: events.count,
            durationSeconds: Int(max(0, now.timeIntervalSince(events.first?.occurredAt ?? now))),
            contentFingerprint: cooldownKey,
            rawContextReference: trigger.ephemeralContextReference ?? latest.ephemeralContextReference,
            evidenceContextReferences: references,
            confidence: 1,
            actionIDs: [.clipboard, .selection].contains(trigger.source) ? [.openQuickAction] : [],
            availableTaskKinds: [.clipboard, .selection].contains(trigger.source) ? TaskKind.interactiveCases : [],
            decisionKey: decisionKey,
            surfaceID: trigger.surfaceID,
            surfaceRevision: trigger.surfaceRevision,
            anchorGeneration: trigger.anchorGeneration,
            sceneSignal: trigger.sceneSignal
        ))
    }

    public func flushContextOpportunity(trigger: AssistantActivityEvent? = nil, now: Date = .now) -> AssistantPatternCandidate? {
        guard case .candidate(let candidate) = flushContextOpportunityResult(trigger: trigger, now: now) else {
            return nil
        }
        return candidate
    }

    public func clear() {
        failuresByFingerprint.removeAll()
        clipboardByLanguage.removeAll()
        failureCooldowns.removeAll()
        languageCooldowns.removeAll()
        failureReservations.removeAll()
        languageReservations.removeAll()
        contextOpportunitySamples.removeAll()
        contextOpportunityCooldowns.removeAll()
        contextOpportunityReservations.removeAll()
        nextActiveCompanionAt = .distantPast
    }

    public func clear(pattern: AssistantPatternType) {
        switch pattern {
        case .repeatedFailure:
            failuresByFingerprint.removeAll()
            failureCooldowns.removeAll()
            failureReservations.removeAll()
        case .foreignClipboard:
            clipboardByLanguage.removeAll()
            languageCooldowns.removeAll()
            languageReservations.removeAll()
        case .contextualOpportunity:
            contextOpportunitySamples.removeAll()
            contextOpportunityCooldowns.removeAll()
            contextOpportunityReservations.removeAll()
            nextActiveCompanionAt = .distantPast
        }
    }

    public func clearContextOpportunitySamples() {
        contextOpportunitySamples.removeAll()
    }

    public func settle(_ candidate: AssistantPatternCandidate, delivered: Bool, now: Date = .now) {
        switch candidate.patternType {
        case .repeatedFailure:
            guard let key = candidate.contentFingerprint else { return }
            failureReservations.removeValue(forKey: key)
            if delivered { failureCooldowns[key] = now.addingTimeInterval(Self.repeatedFailureCooldown) }
        case .foreignClipboard:
            guard let key = candidate.language else { return }
            languageReservations.removeValue(forKey: key)
            if delivered { languageCooldowns[key] = now.addingTimeInterval(Self.foreignClipboardCooldown) }
        case .contextualOpportunity:
            if delivered {
                // 同一操作的慢截图可能稍后到达；已展示过就继续占住该锚点，避免第二个气泡。
                contextOpportunityReservations[candidate.decisionKey] = now.addingTimeInterval(Self.contextOpportunityCooldown)
                let consumedReferences = Set(candidate.evidenceContextReferences)
                contextOpportunitySamples = contextOpportunitySamples.filter { _, sample in
                    guard sample.event.provenance != .observed,
                          let reference = sample.event.ephemeralContextReference else { return true }
                    return !consumedReferences.contains(reference)
                }
            } else {
                contextOpportunityReservations.removeValue(forKey: candidate.decisionKey)
            }
            guard let cooldownKey = candidate.contentFingerprint else { return }
            if delivered {
                contextOpportunityCooldowns[cooldownKey] = now.addingTimeInterval(Self.contextOpportunityCooldown)
            }
        }
    }

    private func prune(now: Date) {
        let oldest = now.addingTimeInterval(-Self.evidenceWindow)
        failuresByFingerprint = failuresByFingerprint.compactMapValues { samples in
            let current = samples.filter { $0.occurredAt >= oldest }
            return current.isEmpty ? nil : current
        }
        clipboardByLanguage = clipboardByLanguage.compactMapValues { samples in
            let current = samples.filter { $0.value.occurredAt >= oldest }
            return current.isEmpty ? nil : current
        }
        failureCooldowns = failureCooldowns.filter { $0.value > now }
        languageCooldowns = languageCooldowns.filter { $0.value > now }
        failureReservations = failureReservations.filter { $0.value > now }
        languageReservations = languageReservations.filter { $0.value > now }
        let contextOldest = now.addingTimeInterval(-Self.contextOpportunityEvidenceFreshness)
        contextOpportunitySamples = contextOpportunitySamples.filter {
            $0.value.event.expiresAt > now && $0.value.event.occurredAt >= contextOldest
        }
        contextOpportunityCooldowns = contextOpportunityCooldowns.filter { $0.value > now }
        contextOpportunityReservations = contextOpportunityReservations.filter { $0.value > now }
    }
}

public enum AssistantPatternRules {
    public static func looksLikeError(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 8, value.count <= AssistantContextBuffer.maximumClipboardTextLength else { return false }
        let lower = value.lowercased()
        let markers = [
            "error", "exception", "failed", "failure", "fatal", "traceback", "panic",
            "错误", "失败", "异常", "崩溃", "无法", "不能"
        ]
        return markers.contains(where: lower.contains)
            || value.range(of: #"\b(?:[A-Z][A-Za-z]+Error|E\d{3,5})\b"#, options: .regularExpression) != nil
    }
}

public struct AssistantCandidateQueue: Sendable, Hashable {
    public static let maximumCount = 3
    private var candidates: [AssistantPatternCandidate] = []

    public init() {}

    public var count: Int { candidates.count }

    @discardableResult
    public mutating func enqueue(_ candidate: AssistantPatternCandidate, now: Date = .now) -> Bool {
        enqueueReportingRemovals(candidate, now: now).inserted
    }

    public mutating func enqueueReportingRemovals(
        _ candidate: AssistantPatternCandidate,
        now: Date = .now
    ) -> (inserted: Bool, removed: [AssistantPatternCandidate]) {
        var removed = candidates.filter { $0.expiresAt <= now || $0.id == candidate.id }
        candidates.removeAll { $0.expiresAt <= now || $0.id == candidate.id }
        guard candidate.expiresAt > now else { return (false, removed) }
        if let matchingIndex = candidates.firstIndex(where: { $0.decisionKey == candidate.decisionKey }) {
            removed.append(candidates.remove(at: matchingIndex))
        }
        if candidates.count >= Self.maximumCount {
            guard let index = candidates.indices.min(by: {
                if candidates[$0].priority != candidates[$1].priority {
                    return candidates[$0].priority < candidates[$1].priority
                }
                return candidates[$0].createdAt < candidates[$1].createdAt
            }), candidate.priority > candidates[index].priority else {
                return (false, removed)
            }
            removed.append(candidates.remove(at: index))
        }
        candidates.append(candidate)
        return (true, removed)
    }

    public mutating func popNext(now: Date = .now) -> AssistantPatternCandidate? {
        popNextReportingRemovals(now: now).candidate
    }

    public mutating func popNextReportingRemovals(
        now: Date = .now
    ) -> (candidate: AssistantPatternCandidate?, removed: [AssistantPatternCandidate]) {
        let removed = candidates.filter { $0.expiresAt <= now }
        candidates.removeAll { $0.expiresAt <= now }
        guard !candidates.isEmpty else { return (nil, removed) }
        let index = candidates.indices.min { lhs, rhs in
            let left = candidates[lhs]
            let right = candidates[rhs]
            if left.priority != right.priority { return left.priority > right.priority }
            return left.createdAt < right.createdAt
        } ?? candidates.startIndex
        return (candidates.remove(at: index), removed)
    }

    @discardableResult
    public mutating func clear() -> [AssistantPatternCandidate] {
        let removed = candidates
        candidates.removeAll()
        return removed
    }
}

public enum AssistantSessionInteraction: Sendable, Hashable {
    case explicitNegative
    case noInteractionTimeout
    case positive
    case unfunny
    case unopenedBadge
}

public enum AssistantBackgroundWorkKind: String, Sendable, Hashable {
    case qualification
    case judgment
    case translation
    case vision
}

public struct AssistantBackgroundWorkLease: Sendable, Hashable {
    public var id: UUID
    public var kind: AssistantBackgroundWorkKind

    public init(id: UUID, kind: AssistantBackgroundWorkKind) {
        self.id = id
        self.kind = kind
    }
}

public struct AssistantBackgroundWorkArbiter: Sendable, Hashable {
    public private(set) var activeLease: AssistantBackgroundWorkLease?

    public init() {}

    public mutating func claim(_ kind: AssistantBackgroundWorkKind) -> AssistantBackgroundWorkLease? {
        guard activeLease == nil else { return nil }
        let lease = AssistantBackgroundWorkLease(id: UUID(), kind: kind)
        activeLease = lease
        return lease
    }

    @discardableResult
    public mutating func release(_ lease: AssistantBackgroundWorkLease) -> Bool {
        guard activeLease == lease else { return false }
        activeLease = nil
        return true
    }
}

public struct AssistantFeedbackTransition: Sendable, Hashable {
    public var interaction: AssistantSessionInteraction?
    public var retainsProactiveAttribution: Bool

    public static func resolve(
        wasProactivelyPresented: Bool,
        previous: AssistantFeedback?,
        new: AssistantFeedback
    ) -> Self {
        guard wasProactivelyPresented else {
            return Self(interaction: new == .unfunny ? .unfunny : nil, retainsProactiveAttribution: false)
        }
        if new == .unfunny {
            return Self(interaction: .unfunny, retainsProactiveAttribution: true)
        }
        guard previous != new else {
            return Self(interaction: nil, retainsProactiveAttribution: false)
        }
        let interaction: AssistantSessionInteraction = new == .useful ? .positive : .explicitNegative
        return Self(interaction: interaction, retainsProactiveAttribution: false)
    }
}

public struct AssistantSessionProactivityState: Sendable, Hashable {
    public private(set) var configured: AssistantProactivity
    public private(set) var effective: AssistantProactivity
    public private(set) var explicitNegativeCount = 0
    public private(set) var noInteractionCount = 0
    public private(set) var didDowngrade = false

    public init(configured: AssistantProactivity) {
        self.configured = configured
        self.effective = configured
    }

    public mutating func updateConfigured(_ value: AssistantProactivity) {
        configured = value
        effective = value
        explicitNegativeCount = 0
        noInteractionCount = 0
        didDowngrade = false
    }

    @discardableResult
    public mutating func apply(_ interaction: AssistantSessionInteraction) -> Bool {
        switch interaction {
        case .explicitNegative:
            explicitNegativeCount += 1
            noInteractionCount = 0
        case .noInteractionTimeout:
            noInteractionCount += 1
            explicitNegativeCount = 0
        case .positive:
            explicitNegativeCount = 0
            noInteractionCount = 0
            return false
        case .unfunny, .unopenedBadge:
            return false
        }
        guard explicitNegativeCount >= 2 || noInteractionCount >= 3 else { return false }
        explicitNegativeCount = 0
        noInteractionCount = 0
        let previous = effective
        switch effective {
        case .active: effective = .moderate
        case .moderate: effective = .quiet
        case .manual, .quiet: break
        }
        didDowngrade = didDowngrade || effective != previous
        return effective != previous
    }
}

public struct AssistantJudgmentInput: Codable, Sendable, Hashable {
    public var patternType: AssistantPatternType
    public var evidenceSummary: String
    public var ephemeralEvidenceTexts: [String]
    public var allowedEvidenceQuotes: [String]
    public var sourceTypes: [AssistantSource]
    public var appCategory: String?
    public var evidenceCount: Int
    public var durationSeconds: Int
    public var languageConfidence: Double?
    public var sensitivity: AssistantSensitivity
    public var evidenceSufficient: Bool
    public var containsURL: Bool
    public var containsCode: Bool
    public var userIsTyping: Bool
    public var isFullScreen: Bool
    public var isPresenting: Bool
    public var responseLanguage: String
    public var personality: AssistantPersonality
    public var recentIrrelevantCount: Int
    public var recentBehaviorSummaries: [String]
    public var historicalAggregate: AssistantPatternAggregate?
    public var proactivity: AssistantProactivity
    public var hourlyPresentationCount: Int
    public var availableTaskKinds: [TaskKind]
    public var availableActionIDs: [AssistantActionID]

    public init(
        patternType: AssistantPatternType,
        evidenceSummary: String,
        ephemeralEvidenceTexts: [String] = [],
        sourceTypes: [AssistantSource],
        appCategory: String? = nil,
        evidenceCount: Int,
        durationSeconds: Int,
        languageConfidence: Double? = nil,
        sensitivity: AssistantSensitivity = .normal,
        evidenceSufficient: Bool = true,
        containsURL: Bool = false,
        containsCode: Bool = false,
        userIsTyping: Bool = false,
        isFullScreen: Bool = false,
        isPresenting: Bool = false,
        responseLanguage: String = "zh-Hans",
        personality: AssistantPersonality = .gentle,
        recentIrrelevantCount: Int = 0,
        recentBehaviorSummaries: [String] = [],
        historicalAggregate: AssistantPatternAggregate? = nil,
        proactivity: AssistantProactivity = .moderate,
        hourlyPresentationCount: Int = 0,
        availableTaskKinds: [TaskKind] = [],
        availableActionIDs: [AssistantActionID]
    ) {
        self.patternType = patternType
        self.evidenceSummary = String(evidenceSummary.prefix(240))
        let privacyPolicy = AssistantPrivacyPolicy()
        self.ephemeralEvidenceTexts = ephemeralEvidenceTexts
            .compactMap(privacyPolicy.sanitizeModelEvidence)
            .prefix(5)
            .map { $0 }
        self.allowedEvidenceQuotes = patternType == .contextualOpportunity
            ? self.ephemeralEvidenceTexts.prefix(1)
                .map { String($0.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            : []
        self.sourceTypes = Array(Set(sourceTypes)).sorted { $0.rawValue < $1.rawValue }
        self.appCategory = appCategory.map { String($0.prefix(64)) }
        self.evidenceCount = max(0, evidenceCount)
        self.durationSeconds = max(0, durationSeconds)
        self.languageConfidence = languageConfidence.map { min(max($0, 0), 1) }
        self.sensitivity = sensitivity
        self.evidenceSufficient = evidenceSufficient
        self.containsURL = containsURL
        self.containsCode = containsCode
        self.userIsTyping = userIsTyping
        self.isFullScreen = isFullScreen
        self.isPresenting = isPresenting
        self.responseLanguage = String(responseLanguage.prefix(16))
        self.personality = personality
        self.recentIrrelevantCount = max(0, recentIrrelevantCount)
        self.recentBehaviorSummaries = recentBehaviorSummaries
            .compactMap(privacyPolicy.sanitizeEvidenceSummary)
            .prefix(5)
            .map { $0 }
        self.historicalAggregate = historicalAggregate
        self.proactivity = proactivity
        self.hourlyPresentationCount = max(0, hourlyPresentationCount)
        self.availableTaskKinds = Array(Set(availableTaskKinds)).sorted { $0.rawValue < $1.rawValue }
        self.availableActionIDs = Array(Set(availableActionIDs)).sorted { $0.rawValue < $1.rawValue }
    }

    /// 重复的无关反馈是确定性否决，不应依赖小模型是否正确理解历史摘要。
    public var suppressesRepeatedlyIrrelevantFeedback: Bool {
        guard let aggregate = historicalAggregate else { return false }
        return aggregate.presentedCount >= 3
            && aggregate.actedCount == 0
            && aggregate.irrelevantCount > aggregate.presentedCount / 2
    }
}

public struct AssistantJudgmentOutput: Codable, Sendable, Hashable {
    public var isHighValue: Bool
    public var valueScore: Double
    public var confidence: Double
    public var comment: String
    public var evidenceSufficient: Bool
    public var recommendedPresentation: AssistantPresentation
    public var suggestedActionIDs: [AssistantActionID]
    public var lockedEvidenceQuote: String
    public var suggestedTask: TaskKind?

    public init(
        isHighValue: Bool,
        valueScore: Double,
        confidence: Double,
        comment: String,
        evidenceSufficient: Bool,
        recommendedPresentation: AssistantPresentation,
        suggestedActionIDs: [AssistantActionID],
        lockedEvidenceQuote: String = "",
        suggestedTask: TaskKind? = nil
    ) {
        self.isHighValue = isHighValue
        self.valueScore = valueScore
        self.confidence = confidence
        self.comment = comment
        self.evidenceSufficient = evidenceSufficient
        self.recommendedPresentation = recommendedPresentation
        self.suggestedActionIDs = suggestedActionIDs
        self.lockedEvidenceQuote = lockedEvidenceQuote
        self.suggestedTask = suggestedTask
    }

    private enum CodingKeys: String, CodingKey {
        case isHighValue, valueScore, confidence, comment, evidenceSufficient
        case recommendedPresentation, suggestedActionIDs, lockedEvidenceQuote, suggestedTask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isHighValue = try container.decode(Bool.self, forKey: .isHighValue)
        valueScore = try container.decode(Double.self, forKey: .valueScore)
        confidence = try container.decode(Double.self, forKey: .confidence)
        comment = try container.decode(String.self, forKey: .comment)
        evidenceSufficient = try container.decode(Bool.self, forKey: .evidenceSufficient)
        recommendedPresentation = try container.decode(AssistantPresentation.self, forKey: .recommendedPresentation)
        suggestedActionIDs = try container.decode([AssistantActionID].self, forKey: .suggestedActionIDs)
        lockedEvidenceQuote = try container.decode(String.self, forKey: .lockedEvidenceQuote)
        suggestedTask = try container.decodeIfPresent(TaskKind.self, forKey: .suggestedTask)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isHighValue, forKey: .isHighValue)
        try container.encode(valueScore, forKey: .valueScore)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(comment, forKey: .comment)
        try container.encode(evidenceSufficient, forKey: .evidenceSufficient)
        try container.encode(recommendedPresentation, forKey: .recommendedPresentation)
        try container.encode(suggestedActionIDs, forKey: .suggestedActionIDs)
        try container.encode(lockedEvidenceQuote, forKey: .lockedEvidenceQuote)
        if let suggestedTask {
            try container.encode(suggestedTask, forKey: .suggestedTask)
        } else {
            try container.encodeNil(forKey: .suggestedTask)
        }
    }
}

public enum AssistantJudgmentContract {
    public static let promptVersion = 23
    public static let minimumActiveConfidence = 0.75
    public static let minimumModerateConfidence = 0.85
    public static let minimumAdjustableConfidence = 0.50
    public static let maximumAdjustableConfidence = 0.95
    public static let systemPrompt = """
    You are an evidence-grounded local desktop-companion value judge and bubble writer. Return exactly one JSON object, with no Markdown or prose. Use exactly these keys and types: isHighValue (boolean), valueScore (number 0...1), confidence (number 0...1), comment (string; empty for false, one sentence no longer than 80 characters for positive), evidenceSufficient (boolean), recommendedPresentation ("silent", "badge", or "peek"), suggestedActionIDs (at most two exact availableActionIDs), lockedEvidenceQuote (string), suggestedTask (one exact availableTaskKinds value or null).

    Mandatory veto always wins. mandatoryVetoReasons="none" means there is no veto; never invent another veto. When mandatoryVetoReasons is not "none", or historyPolicy is "suppressRepeatedlyIrrelevant", return false with comment="", recommendedPresentation="silent", suggestedActionIDs=[], lockedEvidenceQuote="", and suggestedTask=null. Every other false result uses the same five field values.

    Pattern type and evidenceSufficient are authoritative upstream facts. Never re-detect the pattern or change evidenceSufficient from true to false merely because there is no explicit request, error, or tool. Judge only whether the supplied current facts merit one brief interruption at the user's selected proactivity. For isHighValue, moderate means a salient useful interruption; active means a specific grounded companion remark is worthwhile even when no urgent task exists. userIsTyping, isFullScreen, and isPresenting describe delivery timing only; never use them as value vetoes. containsCode and containsURL are informational; availableActionIDs already excludes unsafe actions.
    A positive result needs confidence>=0.85 for moderate or >=0.75 for active and recommendedPresentation="peek". A contextualOpportunity may be a grounded social observation with no action: use suggestedActionIDs=[], lockedEvidenceQuote="", suggestedTask=null. Never force a tool merely to justify speaking.

    # Bubble voice: highest priority after safety and JSON
    For every positive result, comment is the exact bubble shown to the user. Follow the VOICE rule from the user message and these rules:
    - Speak as the user's familiar desktop companion directly to them, not as an observer, narrator, analytics report, or accessibility caption. Use second person when mentioning their activity. Never call them "用户", "the user", or "this user".
    - React to one concrete detail instead of restating or summarizing what they are doing. Begin with the concrete object, issue, choice, or milestone, never with the user's activity. Do not start with "正在...", "你正在...", "你在看...", "看到你...", "Currently...", "You are currently...", or equivalent activity narration.
    - Never explain why the interruption is appropriate, mention evidence/context/personality, or say "适合提供...", "我注意到...", "检测到...", "看来你正在...", or equivalent internal report language.
    - Sound like a natural short message. Vary between acknowledgment, encouragement, a grounded observation, a brief suggestion, and an optional question. Do not always offer help or end with a question.
    - Write one sentence in responseLanguage, usually 12-36 Chinese characters or 6-18 English words. No title, label, emoji, stage direction, URL, code, private identifier, hidden emotion, or off-screen fact.
    Style-only examples; never copy their facts: BAD "用户正在查看技术文档，适合提供温和共鸣。" GOOD gentle "这几条条件有点绕，慢慢拆，我在。" BAD "The user is comparing three options." GOOD professional "Three options are open; compare the trade-offs first."
    For every false result, comment must be exactly "".

    Use only supplied facts and only the PATTERN RECIPE in the current user message; rules and actions for other pattern types do not apply. Apply supplied vetoes strictly, then recognize the explicit positive rules without inventing extra vetoes.
    """

    public static func runtimeSystemPrompt(minimumConfidenceOverride: Double?) -> String {
        guard minimumConfidenceOverride != nil else { return systemPrompt }
        let threshold = minimumConfidence(for: .active, override: minimumConfidenceOverride)
        let defaultRule = "A positive result needs confidence>=0.85 for moderate or >=0.75 for active and recommendedPresentation=\"peek\"."
        let customRule = "A positive result needs confidence>=\(String(format: "%.2f", threshold)) and recommendedPresentation=\"peek\". This user-selected confidence floor replaces the moderate and active defaults."
        return systemPrompt.replacingOccurrences(of: defaultRule, with: customRule)
    }

    public static func userPrompt(
        for input: AssistantJudgmentInput,
        minimumConfidenceOverride: Double? = nil
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(input)) ?? Data("{}".utf8)
        // 把冻结的安全与打扰门单独列出，避免小模型在较长候选 JSON 中漏读关键布尔值。
        let mandatoryVetoReasons = mandatoryVetoReasons(for: input)
        let vetoSummary = mandatoryVetoReasons.isEmpty ? "none" : mandatoryVetoReasons.joined(separator: ",")
        let aggregate = input.historicalAggregate
        let historyIrrelevantCount = aggregate?.irrelevantCount ?? 0
        let historyActedCount = aggregate?.actedCount ?? 0
        let suppressRepeatedlyIrrelevant = input.suppressesRepeatedlyIrrelevantFeedback
        let historyPolicy = suppressRepeatedlyIrrelevant ? "suppressRepeatedlyIrrelevant" : "neutral"
        let positiveConfidence = String(
            format: "%.2f",
            minimumConfidence(for: input.proactivity, override: minimumConfidenceOverride)
        )
        let facts = "mandatoryVetoReasons=\(vetoSummary); evidenceTextCount=\(input.ephemeralEvidenceTexts.count); allowedQuoteCount=\(input.allowedEvidenceQuotes.count); historicalIrrelevantCount=\(historyIrrelevantCount); historicalActedCount=\(historyActedCount); historyPolicy=\(historyPolicy)"
        let instruction: String
        if !mandatoryVetoReasons.isEmpty {
            instruction = "MANDATORY VETO \(vetoSummary): return isHighValue=false."
        } else if suppressRepeatedlyIrrelevant {
            instruction = "HISTORY VETO: return isHighValue=false."
        } else {
            instruction = "Evaluate this candidate."
        }
        // 活跃档是用户显式选择的陪伴语义；安全硬门不变，只放宽“值得说一句”的价值定义。
        let contextualValueRule = input.proactivity == .active
            ? "ACTIVE MODE is explicit opt-in to frequent companion remarks. Treat isHighValue as worth one brief grounded comment, not as urgent or exceptional utility. Prefer positive whenever the evidence names a concrete current item, choice, change, or ongoing activity that supports a specific non-repetitive remark. Routine active reading, comparing, editing, navigating related work, and continued focused work may be positive. Return false only when evidence is generic or ambiguous, only names an app/page, is unchanged, repeats a recent remark, or is passive with no concrete current detail to mention."
            : "MODERATE MODE requires a salient timely reason to interrupt. Return positive for an imminent unresolved deadline, concrete blocker, foreign content with a stated response need, multiple blockers/tasks without owners, explicit success/fatigue/confusion, visible progress or a completed milestone, repeated focused work, or a clear transition between work stages. Return false when evidence is generic or ambiguous, only names an app/page, shows routine navigation or settings with no salient detail, is unchanged, or is ordinary passive reading with no specific current observation worth acknowledging."
        let contextualValueScore = input.proactivity == .active ? "0.50" : "0.85"
        // 模式和证据充分性来自确定性预筛；模型只评价是否值得打扰，不能重新分类上游事实。
        let patternRecipe: String = switch input.patternType {
        case .repeatedFailure:
            "PATTERN RECIPE repeatedFailure: evidenceCount, not evidenceTextCount, is the repetition count. explainError and returnToWorkbench are recovery actions when present in availableActionIDs. Return positive for a concrete unresolved error with evidenceCount>=3 and either supplied recovery action. Return false when evidence explicitly describes an intentional tutorial/example, expected output, or successful result. POSITIVE SHAPE: isHighValue=true, valueScore>=0.85, confidence>=\(positiveConfidence), evidenceSufficient=true, recommendedPresentation=\"peek\", lockedEvidenceQuote=\"\", suggestedTask=null; suggestedActionIDs contains only exact supplied recovery IDs; comment is the final user-facing bubble."
        case .foreignClipboard:
            "PATTERN RECIPE foreignClipboard: upstream detection already proved the language is foreign; English may be foreign, so do not re-detect language. Decide only topic coherence. Sections of one document or workflow are coherent even when details differ, for example installation, configuration, validation, and troubleshooting. Clearly different domains such as weather, software news, and cooking are unrelated. Absence of a translation request is not a refusal. NEGATIVE OVERRIDE: passive media or evidence saying \"no translation task was requested\" MUST be false. POSITIVE SHAPE: isHighValue=true, valueScore>=0.85, confidence>=\(positiveConfidence), evidenceSufficient=true, recommendedPresentation=\"peek\", lockedEvidenceQuote=\"\", suggestedTask=null; suggestedActionIDs contains enableClipboardTranslation, translateCurrentClipboard, or both when supplied; comment is the final user-facing bubble."
        case .contextualOpportunity:
            "PATTERN RECIPE contextualOpportunity: evidenceSufficient=true means evidence is concrete and current; do not require an explicit request, error, tool, or next step. \(contextualValueRule) DEFAULT POSITIVE SHAPE: isHighValue=true, valueScore>=\(contextualValueScore), confidence>=\(positiveConfidence), evidenceSufficient=true, recommendedPresentation=\"peek\", suggestedActionIDs=[], lockedEvidenceQuote=\"\", suggestedTask=null, comment is the final grounded user-facing bubble. Use openQuickAction only when clearly useful, never use an action from another pattern. Never infer hidden emotion or off-screen facts."
        }
        let falseInvariant = "FALSE RECIPE: for every false result copy these exact field values: comment=\"\", recommendedPresentation=\"silent\", suggestedActionIDs=[], lockedEvidenceQuote=\"\", suggestedTask=null."
        let finalRecipe = mandatoryVetoReasons.isEmpty && !suppressRepeatedlyIrrelevant
            ? "\(instruction) \(patternRecipe) \(falseInvariant)"
            : "\(instruction) \(falseInvariant)"
        return "FACTS: \(facts)\nVOICE: \(input.personality.promptGuidance)\nINPUT: \(String(decoding: data, as: UTF8.self))\nFINAL: \(finalRecipe) Return JSON only."
    }

    public static func parse(_ text: String, input: AssistantJudgmentInput) -> AssistantJudgmentOutput? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set([
                  "isHighValue", "valueScore", "confidence", "comment", "evidenceSufficient",
                  "recommendedPresentation", "suggestedActionIDs", "lockedEvidenceQuote", "suggestedTask"
              ]),
              var output = try? JSONDecoder().decode(AssistantJudgmentOutput.self, from: data),
              output.valueScore.isFinite,
              (0...1).contains(output.valueScore),
              output.confidence.isFinite,
              (0...1).contains(output.confidence),
              output.comment == output.comment.trimmingCharacters(in: .whitespacesAndNewlines),
              !AssistantPrivacyPolicy.looksSensitive(output.comment),
              output.suggestedActionIDs.count <= 2,
              Set(output.suggestedActionIDs).isSubset(of: Set(input.availableActionIDs)) else { return nil }
        if output.isHighValue {
            guard !output.comment.isEmpty,
                  output.comment.count <= 80,
                  !output.comment.contains("\n"),
                  !AssistantPrivacyPolicy.containsWebURL(output.comment),
                  !AssistantPrivacyPolicy.looksLikeCode(output.comment),
                  isDirectBubbleComment(output.comment) else { return nil }
        }
        // 安全门由运行时再次执行，不能只相信模型遵守提示词。
        guard !output.isHighValue
            || (mandatoryVetoReasons(for: input).isEmpty && !input.suppressesRepeatedlyIrrelevantFeedback) else {
            return nil
        }
        if !output.isHighValue {
            guard output.comment.isEmpty,
                  output.recommendedPresentation == .silent,
                  output.suggestedActionIDs.isEmpty,
                  output.suggestedTask == nil else { return nil }
            if !output.lockedEvidenceQuote.isEmpty {
                guard input.allowedEvidenceQuotes.contains(output.lockedEvidenceQuote)
                    || input.ephemeralEvidenceTexts.contains(where: { $0.contains(output.lockedEvidenceQuote) }) else { return nil }
                // false 结果不会展示或执行；仅丢弃来自输入的冗余引文片段，编造内容仍视为非法。
                output.lockedEvidenceQuote = ""
            }
        }
        if input.patternType == .contextualOpportunity, output.isHighValue {
            if output.suggestedActionIDs.isEmpty {
                // 无动作结果不会展示或执行引文与任务；仅容忍来自当前输入的冗余字段并立即归零。
                if !output.lockedEvidenceQuote.isEmpty {
                    let quote = output.lockedEvidenceQuote
                    guard input.ephemeralEvidenceTexts.contains(where: {
                        $0.contains(quote)
                    }) else { return nil }
                    output.lockedEvidenceQuote = ""
                }
                if let suggestedTask = output.suggestedTask {
                    guard input.availableTaskKinds.contains(suggestedTask) else { return nil }
                    output.suggestedTask = nil
                }
            } else {
                if !input.allowedEvidenceQuotes.contains(output.lockedEvidenceQuote),
                   let canonicalQuote = zip(input.ephemeralEvidenceTexts, input.allowedEvidenceQuotes)
                       .first(where: { fullText, quote in
                           fullText == output.lockedEvidenceQuote
                               || (fullText.hasPrefix(output.lockedEvidenceQuote)
                                   && output.lockedEvidenceQuote.hasPrefix(quote))
                       })?.1 {
                    // 模型可能补全 80 字符边界处的单词；只接受同一原文的锚定前缀并收敛到冻结短引文。
                    output.lockedEvidenceQuote = canonicalQuote
                }
                guard input.allowedEvidenceQuotes.contains(output.lockedEvidenceQuote),
                      output.lockedEvidenceQuote.count <= 80,
                      !AssistantPrivacyPolicy.looksSensitive(output.lockedEvidenceQuote),
                      let suggestedTask = output.suggestedTask,
                      input.availableTaskKinds.contains(suggestedTask),
                      output.suggestedActionIDs == [.openQuickAction] else { return nil }
            }
        } else {
            if !output.lockedEvidenceQuote.isEmpty {
                let quote = output.lockedEvidenceQuote
                guard input.ephemeralEvidenceTexts.contains(where: {
                    $0 == quote || $0.hasPrefix(quote) || quote.hasPrefix($0)
                }) else { return nil }
                // P-01/P-03 的事实和动作由既有候选锁定；模型重复完整原证据时直接丢弃，不进入卡片。
                output.lockedEvidenceQuote = ""
            }
            guard output.suggestedTask == nil else { return nil }
        }
        return output
    }

    /// 小模型偶尔会把内部审核理由写进气泡；这里兜底拒绝第三人称播报和价值评语。
    public static func isDirectBubbleComment(_ comment: String) -> Bool {
        let lowercased = comment.lowercased()
        let forbiddenFragments = [
            "用户正在", "用户正", "用户似乎", "用户当前", "用户在查看", "该用户",
            "观察到用户", "检测到用户", "看到你在", "我看到你", "适合提供", "适合进行",
            "the user is", "the user appears", "the user seems", "this user is",
            "appropriate to provide", "worth interrupting"
        ]
        let forbiddenPrefixes = [
            "正在", "你正在", "你在看", "当前正在", "看来你", "看到你",
            "currently ", "you are currently ", "you're currently ", "it looks like you ", "i see you "
        ]
        return !forbiddenFragments.contains { lowercased.contains($0) }
            && !forbiddenPrefixes.contains { lowercased.hasPrefix($0) }
    }

    private static func mandatoryVetoReasons(for input: AssistantJudgmentInput) -> [String] {
        var reasons: [String] = []
        if input.sensitivity != .normal { reasons.append("sensitivity") }
        if !input.evidenceSufficient { reasons.append("evidenceSufficient") }
        if input.ephemeralEvidenceTexts.isEmpty { reasons.append("emptyEvidence") }
        if input.patternType == .contextualOpportunity,
           input.sourceTypes.allSatisfy({ ![AssistantSource.clipboard, .selection, .windowContext].contains($0) }) {
            reasons.append("ineligibleSourceTypes")
        }
        return reasons
    }

    public static func permitsPeek(
        _ output: AssistantJudgmentOutput?,
        proactivity: AssistantProactivity = .active,
        input: AssistantJudgmentInput? = nil,
        minimumConfidenceOverride: Double? = nil
    ) -> Bool {
        guard let output else { return false }
        let minimumConfidence = minimumConfidence(
            for: proactivity,
            override: minimumConfidenceOverride
        )
        return output.isHighValue
            && output.evidenceSufficient
            && output.confidence >= minimumConfidence
            && output.recommendedPresentation == .peek
            && (!output.suggestedActionIDs.isEmpty || input?.patternType == .contextualOpportunity)
    }

    public static func minimumConfidence(
        for proactivity: AssistantProactivity,
        override: Double? = nil
    ) -> Double {
        if let override, override.isFinite {
            // JSON 可被用户直接编辑；运行时仍把自定义值约束在设置页公开的安全范围内。
            return min(max(override, minimumAdjustableConfidence), maximumAdjustableConfidence)
        }
        return proactivity == .moderate ? minimumModerateConfidence : minimumActiveConfidence
    }

}

public struct AssistantJudgmentFixture: Sendable, Identifiable, Hashable {
    public var id: String
    public var input: AssistantJudgmentInput
    public var expectsPeek: Bool
    public var isHardNegative: Bool

    public init(id: String, input: AssistantJudgmentInput, expectsPeek: Bool, isHardNegative: Bool = false) {
        self.id = id
        self.input = input
        self.expectsPeek = expectsPeek
        self.isHardNegative = isHardNegative
    }
}

public enum AssistantJudgmentFixtures {
    public static let version = 12

    public static let all: [AssistantJudgmentFixture] = {
        let p01Actions: [AssistantActionID] = [.explainError, .returnToWorkbench]
        let p03Actions: [AssistantActionID] = [.enableClipboardTranslation, .translateCurrentClipboard]
        let p06Actions: [AssistantActionID] = [.openQuickAction]
        let p06Tasks = TaskKind.interactiveCases
        let positives: [AssistantJudgmentFixture] = [
            fixture("p01-port", .repeatedFailure, "same-error-signature count=3 window=180s", ["Address already in use: port 8080"], 3, 180, [.llmToolsTask], p01Actions, appCategory: "development"),
            fixture("p01-module", .repeatedFailure, "same-error-signature count=4 window=420s", ["ModuleNotFoundError: No module named local_runtime"], 4, 420, [.selection], [.explainError], appCategory: "development"),
            fixture("p01-build", .repeatedFailure, "same-error-signature count=3 window=540s", ["Swift build failed: missing argument for parameter modelID"], 3, 540, [.clipboard], [.explainError], appCategory: "development"),
            fixture("p01-ocr", .repeatedFailure, "same-error-signature count=5 window=360s recoverable=true", ["OCR task failed because the local model could not be loaded"], 5, 360, [.llmToolsTask], p01Actions, appCategory: "other"),
            fixture("p03-en", .foreignClipboard, "same-language=en distinct=3 window=240s", ["The installation guide explains how to configure the local runtime.", "The next section describes model validation and health checks.", "Troubleshooting covers the most common startup failures."], 3, 240, [.clipboard], p03Actions, confidence: 0.98, appCategory: "browser"),
            fixture("p03-ja", .foreignClipboard, "same-language=ja distinct=4 window=360s", ["この章ではローカルモデルの設定方法を説明します。", "次の章では翻訳結果の確認方法を説明します。", "最後に一般的な問題の解決方法を紹介します。"], 4, 360, [.clipboard], p03Actions, confidence: 0.96, appCategory: "browser"),
            fixture("p03-de", .foreignClipboard, "same-language=de distinct=3 window=480s", ["Die Anleitung beschreibt die lokale Installation der Anwendung.", "Danach werden die verfügbaren Einstellungen erklärt.", "Zum Schluss folgt eine Liste häufiger Fehler."], 3, 480, [.clipboard], p03Actions, confidence: 0.93, appCategory: "browser"),
            fixture("p03-es", .foreignClipboard, "same-language=es distinct=5 window=300s", ["El documento explica el flujo de trabajo de traducción local.", "La siguiente sección presenta las opciones de privacidad.", "Al final se describen los pasos de verificación."], 5, 300, [.clipboard], p03Actions, confidence: 0.97, appCategory: "productivity"),
            fixture("p06-summary", .contextualOpportunity, "authorized-context count=2 window=8s", ["Five release-note items are still unresolved, and review begins in ten minutes.", "Release checklist"], 2, 6, [.clipboard, .windowContext], p06Actions, appCategory: "productivity", tasks: p06Tasks),
            fixture("p06-explain", .contextualOpportunity, "authorized-context count=1 window=8s", ["The local signing check keeps rejecting this package with an entitlement mismatch; the release is blocked."], 1, 0, [.selection], p06Actions, appCategory: "development", tasks: p06Tasks),
            fixture("p06-progress", .contextualOpportunity, "authorized-context count=1 anchor=windowContext", ["activity=coding; signal=success; observation=The build panel shows all 24 checks passing beside the current editor; visibleText=24/24 passed"], 1, 0, [.windowContext], [], appCategory: "development"),
            fixture("p06-active-companion", .contextualOpportunity, "authorized-context count=1 anchor=windowContext", ["activity=research; signal=none; observation=正在阅读 ViewModel 刷新触发条件的技术文档; visibleText=ViewModel 刷新触发条件"], 1, 0, [.windowContext], [], appCategory: "productivity", proactivity: .active)
        ]
        let negatives: [AssistantJudgmentFixture] = [
            fixture("n-sensitive", .contextualOpportunity, "sensitive content suppressed", ["password=do-not-send"], 1, 0, [.clipboard], p06Actions, sensitivity: .sensitive, tasks: p06Tasks, expected: false, hard: true),
            fixture("n-excluded", .contextualOpportunity, "excluded application", ["Summarize this private vault entry."], 1, 0, [.clipboard], p06Actions, sensitivity: .excludedApplication, tasks: p06Tasks, expected: false, hard: true),
            fixture("n-fullscreen", .contextualOpportunity, "ordinary full-screen playback", ["A full-screen video is playing without a deadline, blocker, or completed milestone."], 1, 0, [.windowContext], [], fullScreen: true, expected: false),
            fixture("n-insufficient", .contextualOpportunity, "window metadata only", [], 1, 0, [.windowContext], p06Actions, evidenceSufficient: false, tasks: p06Tasks, expected: false, hard: true),
            fixture("n-benign-error-text", .repeatedFailure, "same-error-signature count=3 window=180s", ["The tutorial intentionally prints the word error as a successful example."], 3, 180, [.clipboard], [.explainError], appCategory: "browser", expected: false),
            fixture("n-unrelated-foreign", .foreignClipboard, "same-language=en distinct=3 window=180s", ["Tomorrow will be sunny with light wind.", "A new software release was announced today.", "Bake the bread until the crust turns golden."], 3, 180, [.clipboard], p03Actions, confidence: 0.99, appCategory: "browser", expected: false),
            fixture("n-code-copy", .contextualOpportunity, "routine code and URL context", ["func load() async throws { return try await runner.generate() } // https://example.com/runner"], 1, 0, [.clipboard], [], code: true, expected: false),
            fixture("n-typing", .contextualOpportunity, "unfinished draft while typing", ["A draft is mid-sentence without a completed request, blocker, deadline, or milestone."], 1, 0, [.selection], p06Actions, typing: true, tasks: p06Tasks, expected: false),
            fixture("n-watching-video", .foreignClipboard, "watching a training video", ["These copied captions are notes from a video being watched; no translation task was requested."], 3, 540, [.clipboard], p03Actions, confidence: 0.96, appCategory: "media", expected: false),
            fixture("n-history-irrelevant", .contextualOpportunity, "normal long reading with repeated irrelevant feedback", ["The user is reading a long documentation chapter without asking for an operation."], 1, 540, [.clipboard], p06Actions, appCategory: "browser", historicalAggregate: AssistantPatternAggregate(detectedCount: 8, presentedCount: 6, actedCount: 0, irrelevantCount: 5), tasks: p06Tasks, expected: false),
            fixture("n-normal-app-switch", .contextualOpportunity, "normal IDE browser terminal switching", [], 3, 180, [.foregroundApplication], p06Actions, appCategory: "development", evidenceSufficient: false, tasks: p06Tasks, expected: false, hard: true),
            fixture("n-passive-reading", .contextualOpportunity, "ordinary passive reading", ["The chapter describes the history of release engineering and several past launch decisions."], 1, 0, [.clipboard], p06Actions, appCategory: "other", tasks: p06Tasks, expected: false)
        ]
        return positives + negatives
    }()

    private static func fixture(
        _ id: String,
        _ pattern: AssistantPatternType,
        _ summary: String,
        _ evidenceTexts: [String],
        _ count: Int,
        _ duration: Int,
        _ sources: [AssistantSource],
        _ actions: [AssistantActionID],
        confidence: Double? = nil,
        appCategory: String? = nil,
        sensitivity: AssistantSensitivity = .normal,
        evidenceSufficient: Bool = true,
        fullScreen: Bool = false,
        typing: Bool = false,
        presenting: Bool = false,
        code: Bool = false,
        historicalAggregate: AssistantPatternAggregate? = nil,
        tasks: [TaskKind] = [],
        proactivity: AssistantProactivity = .moderate,
        expected: Bool = true,
        hard: Bool = false
    ) -> AssistantJudgmentFixture {
        AssistantJudgmentFixture(
            id: id,
            input: AssistantJudgmentInput(
                patternType: pattern,
                evidenceSummary: summary,
                ephemeralEvidenceTexts: evidenceTexts,
                sourceTypes: sources,
                appCategory: appCategory,
                evidenceCount: count,
                durationSeconds: duration,
                languageConfidence: confidence,
                sensitivity: sensitivity,
                evidenceSufficient: evidenceSufficient,
                containsURL: evidenceTexts.contains(where: AssistantPrivacyPolicy.containsWebURL),
                containsCode: code,
                userIsTyping: typing,
                isFullScreen: fullScreen,
                isPresenting: presenting,
                historicalAggregate: historicalAggregate,
                proactivity: proactivity,
                availableTaskKinds: tasks,
                availableActionIDs: actions
            ),
            expectsPeek: expected,
            isHardNegative: hard
        )
    }
}

public struct AssistantQualificationSample: Sendable, Hashable {
    public var fixtureID: String
    public var output: String?
    public var latencyMilliseconds: Int

    public init(fixtureID: String, output: String?, latencyMilliseconds: Int) {
        self.fixtureID = fixtureID
        self.output = output
        self.latencyMilliseconds = max(0, latencyMilliseconds)
    }
}

public enum AssistantQualificationEvaluator {
    public static let maximumFixtureLatencyMilliseconds = 10_000

    public static func evaluate(
        modelID: UUID,
        modelFingerprint: String,
        samples: [AssistantQualificationSample],
        checkedAt: Date = .now
    ) -> AssistantQualificationSummary {
        let fixturesByID = Dictionary(uniqueKeysWithValues: AssistantJudgmentFixtures.all.map { ($0.id, $0) })
        var seen = Set<String>()
        var validJSONCount = 0
        var positivePassCount = 0
        var negativeFalsePositiveCount = 0
        var hardFailureCount = 0
        var actionViolationCount = 0
        var contextualOpportunityPassCount = 0
        var maximumLatency = 0

        for sample in samples {
            maximumLatency = max(maximumLatency, sample.latencyMilliseconds)
            guard seen.insert(sample.fixtureID).inserted,
                  let fixture = fixturesByID[sample.fixtureID],
                  let outputText = sample.output else { continue }
            guard let output = AssistantJudgmentContract.parse(
                      outputText,
                      input: fixture.input
                  ) else {
                // parser 会直接拒绝硬门违规；资格报告仍记录模型曾企图主动展示，便于定位模型退化。
                if fixture.isHardNegative,
                   let data = outputText.data(using: .utf8),
                   let rawOutput = try? JSONDecoder().decode(AssistantJudgmentOutput.self, from: data),
                   AssistantJudgmentContract.permitsPeek(
                       rawOutput,
                       proactivity: fixture.input.proactivity,
                       input: fixture.input
                   ) {
                    hardFailureCount += 1
                }
                continue
            }
            validJSONCount += 1
            let permitsPeek = AssistantJudgmentContract.permitsPeek(
                output,
                proactivity: fixture.input.proactivity,
                input: fixture.input
            )
            if fixture.expectsPeek {
                if permitsPeek {
                    positivePassCount += 1
                    if fixture.input.patternType == .contextualOpportunity {
                        contextualOpportunityPassCount += 1
                    }
                }
            } else if permitsPeek {
                negativeFalsePositiveCount += 1
                if fixture.isHardNegative { hardFailureCount += 1 }
            }
            if !Set(output.suggestedActionIDs).isSubset(of: Set(fixture.input.availableActionIDs)) {
                actionViolationCount += 1
            }
        }

        let complete = samples.count == AssistantJudgmentFixtures.all.count
            && seen == Set(fixturesByID.keys)
        let qualified = complete
            && validJSONCount == AssistantJudgmentFixtures.all.count
            && positivePassCount >= 9
            && negativeFalsePositiveCount <= 1
            && hardFailureCount == 0
            && actionViolationCount == 0
            && contextualOpportunityPassCount >= 3
            && maximumLatency <= maximumFixtureLatencyMilliseconds
        let state: AssistantQualificationState = qualified ? .qualified : .unqualified
        let message = "JSON \(validJSONCount)/24, positive \(positivePassCount)/12, P06 \(contextualOpportunityPassCount)/4, false positive \(negativeFalsePositiveCount)/12, hard \(hardFailureCount), max \(maximumLatency)ms"
        return AssistantQualificationSummary(
            modelID: modelID,
            modelFingerprint: modelFingerprint,
            promptVersion: AssistantJudgmentContract.promptVersion,
            fixtureVersion: AssistantJudgmentFixtures.version,
            state: state,
            validJSONCount: validJSONCount,
            positivePassCount: positivePassCount,
            negativeFalsePositiveCount: negativeFalsePositiveCount,
            hardFailureCount: hardFailureCount + actionViolationCount,
            maximumLatencyMilliseconds: maximumLatency,
            checkedAt: checkedAt,
            message: message
        )
    }
}

public enum AssistantModelFingerprint {
    public static func fingerprint(for model: ModelDescriptor) throws -> String {
        guard !model.isRemoteProvider, model.format == .gguf || model.format == .mlx else {
            throw RunnerError.unsupportedConfiguration("Assistant judgment requires a local GGUF or MLX text model.")
        }
        return try fingerprint(at: model.resolvedPath ?? model.sourcePath)
    }

    public static func fingerprint(at root: URL) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let files: [URL]
        if isDirectory.boolValue {
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            files = (FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )?.allObjects as? [URL] ?? []).filter {
                (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true
            }.sorted { $0.path < $1.path }
        } else {
            files = [root]
        }

        var hasher = SHA256()
        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let relativePath = isDirectory.boolValue
                ? String(file.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : file.lastPathComponent
            let metadata = "\(relativePath)\u{0}\(values.fileSize ?? 0)\u{0}\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)\u{0}"
            hasher.update(data: Data(metadata.utf8))
            // 模型可能有数 GB；采样首尾内容并结合完整文件元数据，避免资格缓存校验本身扫描全部权重。
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let size = UInt64(max(0, values.fileSize ?? 0))
            hasher.update(data: try handle.read(upToCount: 4_096) ?? Data())
            if size > 4_096 {
                try handle.seek(toOffset: max(0, size - 4_096))
                hasher.update(data: try handle.read(upToCount: 4_096) ?? Data())
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public extension AssistantQualificationSummary {
    func matchesCurrentCacheKey(modelFingerprint: String) -> Bool {
        self.modelFingerprint == modelFingerprint
            && promptVersion == AssistantJudgmentContract.promptVersion
            && fixtureVersion == AssistantJudgmentFixtures.version
    }

    func isCurrent(modelFingerprint: String) -> Bool {
        state == .qualified && matchesCurrentCacheKey(modelFingerprint: modelFingerprint)
    }
}

public struct AssistantCommentInput: Codable, Sendable, Hashable {
    public var patternType: AssistantPatternType
    public var personality: AssistantPersonality
    public var language: String
    public var evidenceCount: Int
    public var durationSeconds: Int
    public var foreignLanguage: String?
    public var evidenceQuote: String?
    public var suggestedTask: TaskKind?
    public var allowedActionIDs: [AssistantActionID]
    public var contextSummary: String?

    public init(
        patternType: AssistantPatternType,
        personality: AssistantPersonality,
        language: String,
        evidenceCount: Int,
        durationSeconds: Int,
        foreignLanguage: String? = nil,
        evidenceQuote: String? = nil,
        suggestedTask: TaskKind? = nil,
        allowedActionIDs: [AssistantActionID],
        contextSummary: String? = nil
    ) {
        self.patternType = patternType
        self.personality = personality
        self.language = language
        self.evidenceCount = max(1, evidenceCount)
        self.durationSeconds = max(0, durationSeconds)
        self.foreignLanguage = foreignLanguage
        self.evidenceQuote = evidenceQuote.flatMap { AssistantPrivacyPolicy().sanitizeModelEvidence($0) }
            .map { String($0.prefix(80)) }
        self.suggestedTask = suggestedTask
        self.allowedActionIDs = Array(Set(allowedActionIDs)).sorted { $0.rawValue < $1.rawValue }
        self.contextSummary = contextSummary
            .flatMap { AssistantPrivacyPolicy().sanitizeModelEvidence($0) }
            .map { String($0.prefix(500)) }
    }
}

public struct AssistantCommentOutput: Codable, Sendable, Hashable {
    public var comment: String
    public var suggestedActionIDs: [AssistantActionID]
    public var includesJoke: Bool

    public init(comment: String, suggestedActionIDs: [AssistantActionID], includesJoke: Bool) {
        self.comment = comment
        self.suggestedActionIDs = suggestedActionIDs
        self.includesJoke = includesJoke
    }
}

public enum AssistantCommentContract {
    public static let systemPrompt = """
    Return exactly one JSON object with keys comment, suggestedActionIDs, includesJoke. suggestedActionIDs must exactly preserve allowedActionIDs. includesJoke must be true only for lightTeasing. When allowedActionIDs is not empty, select exactly one supplied allowedCommentOption without changing it. When allowedActionIDs is empty and contextSummary is supplied, write one natural sentence no longer than 80 characters in the requested language and follow voiceGuidance. Speak directly to the user as their desktop companion; never call them "用户", "the user", or describe why speaking is appropriate. React to one concrete detail instead of summarizing their activity. Ground every factual phrase in contextSummary; light teasing must target the situation, never the person. Never add names, URLs, commands, diagnoses, hidden emotions, completed actions, or off-screen facts.
    """

    public static func userPrompt(for input: AssistantCommentInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(input)) ?? Data("{}".utf8)
        let optionData = (try? encoder.encode(AssistantCommentTemplates.options(for: input))) ?? Data("[]".utf8)
        return "Return JSON only.\nvoiceGuidance=\(input.personality.promptGuidance)\ninput=\(String(decoding: data, as: UTF8.self))\nallowedCommentOptions=\(String(decoding: optionData, as: UTF8.self))"
    }

    public static func parse(_ text: String, input: AssistantCommentInput) -> AssistantCommentOutput? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["comment", "suggestedActionIDs", "includesJoke"]),
              let output = try? JSONDecoder().decode(AssistantCommentOutput.self, from: data),
              Set(output.suggestedActionIDs) == Set(input.allowedActionIDs),
              output.suggestedActionIDs.count == input.allowedActionIDs.count,
              output.includesJoke == (input.personality == .lightTeasing) else { return nil }
        let allowedOptions = AssistantCommentTemplates.options(for: input)
        if allowedOptions.contains(output.comment) { return output }
        let comment = output.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.allowedActionIDs.isEmpty,
              input.contextSummary?.isEmpty == false,
              comment == output.comment,
              !comment.isEmpty,
              comment.count <= 80,
              !comment.contains("\n"),
              !AssistantPrivacyPolicy.looksSensitive(comment),
              !AssistantPrivacyPolicy.containsWebURL(comment),
              !AssistantPrivacyPolicy.looksLikeCode(comment),
              AssistantJudgmentContract.isDirectBubbleComment(comment) else { return nil }
        return output
    }
}

public enum AssistantCommentTemplates {
    public static func options(for input: AssistantCommentInput) -> [String] {
        [comment(for: input), alternateComment(for: input)]
    }

    public static func comment(for input: AssistantCommentInput) -> String {
        let english = input.language.lowercased().hasPrefix("en")
        if input.allowedActionIDs.isEmpty, input.suggestedTask == nil {
            return switch (input.personality, english) {
            case (.professional, false): "先看眼前这一步，重点出来后再往下走。"
            case (.gentle, false): "慢慢来，我在这儿陪你把这一段看完。"
            case (.lively, false): "这一段有点东西，继续，我跟上了！"
            case (.calm, false): "不急，先把眼前这一步看清。"
            case (.lightTeasing, false): "这段内容挺会藏重点，看看它还要绕多久。"
            case (.professional, true): "Stay with this step; move on when the key point is clear."
            case (.gentle, true): "Take your time. I am right here with you."
            case (.lively, true): "There is something here. Keep going, I am with you!"
            case (.calm, true): "No rush. Keep the next step clear."
            case (.lightTeasing, true): "This section is hiding the point well. Let us see how long it lasts."
            }
        }
        switch (input.patternType, input.personality, english) {
        case (.repeatedFailure, .professional, false):
            return "同一错误已经出现 \(input.evidenceCount) 次，先查根因，别再盲目重试。"
        case (.repeatedFailure, .gentle, false):
            return "它又卡在同一处了。先停一下，我们一起找根因？"
        case (.repeatedFailure, .lively, false):
            return "同一个错误第 \(input.evidenceCount) 次登场了，换条路查根因吧！"
        case (.repeatedFailure, .calm, false):
            return "第 \(input.evidenceCount) 次是同一处报错。先收住，查根因。"
        case (.repeatedFailure, .lightTeasing, false):
            return "这条错误第 \(input.evidenceCount) 次来打卡了，先查根因再放它走？"
        case (.foreignClipboard, .professional, false):
            return "你连续复制了几段外语内容，要开启 30 分钟剪贴板翻译吗？"
        case (.foreignClipboard, .gentle, false):
            return "外语内容有点多，要不要让我陪你翻 30 分钟？"
        case (.foreignClipboard, .lively, false):
            return "外语内容排上队了！开 30 分钟剪贴板翻译？"
        case (.foreignClipboard, .calm, false):
            return "还在处理外语内容。需要的话，翻译可以临时开 30 分钟。"
        case (.foreignClipboard, .lightTeasing, false):
            return "这门外语今天挺勤快。开 30 分钟剪贴板翻译收拾它？"
        case (.contextualOpportunity, .professional, false):
            return "这段内容可以直接\(taskName(input.suggestedTask, english: false))，要在 Quick Action 里继续吗？"
        case (.contextualOpportunity, .gentle, false):
            return "这段内容正好可以\(taskName(input.suggestedTask, english: false))。要不要我接着处理？"
        case (.contextualOpportunity, .lively, false):
            return "重点已经到齐了！要不要马上\(taskName(input.suggestedTask, english: false))？"
        case (.contextualOpportunity, .calm, false):
            return "材料够了。要\(taskName(input.suggestedTask, english: false))，现在就可以。"
        case (.contextualOpportunity, .lightTeasing, false):
            return "这段内容把“\(taskName(input.suggestedTask, english: false))”写在脸上了，要我接手？"
        case (.repeatedFailure, .professional, true):
            return "The same error appeared \(input.evidenceCount) times. Check the root cause before retrying."
        case (.repeatedFailure, .gentle, true):
            return "This error came back. Want help checking the root cause before another retry?"
        case (.repeatedFailure, .lively, true):
            return "Round \(input.evidenceCount) for the same error. Let us try a new angle!"
        case (.repeatedFailure, .calm, true):
            return "Same error, attempt \(input.evidenceCount). Pause and check the root cause."
        case (.repeatedFailure, .lightTeasing, true):
            return "This error just clocked in for visit \(input.evidenceCount). Check the root cause?"
        case (.foreignClipboard, .professional, true):
            return "You copied several foreign-language passages. Enable translation for 30 minutes?"
        case (.foreignClipboard, .gentle, true):
            return "That is a lot of foreign-language text. Want me to translate for 30 minutes?"
        case (.foreignClipboard, .lively, true):
            return "The foreign-language queue is growing! Turn on translation for 30 minutes?"
        case (.foreignClipboard, .calm, true):
            return "Still working through foreign-language text. Translation can stay on for 30 minutes."
        case (.foreignClipboard, .lightTeasing, true):
            return "That language is working overtime. Give translation 30 minutes?"
        case (.contextualOpportunity, .professional, true):
            return "This is ready to \(taskName(input.suggestedTask, english: true)) in Quick Action. Continue?"
        case (.contextualOpportunity, .gentle, true):
            return "This is ready to \(taskName(input.suggestedTask, english: true)). Want me to continue?"
        case (.contextualOpportunity, .lively, true):
            return "The key pieces are here! Ready to \(taskName(input.suggestedTask, english: true))?"
        case (.contextualOpportunity, .calm, true):
            return "There is enough here to \(taskName(input.suggestedTask, english: true))."
        case (.contextualOpportunity, .lightTeasing, true):
            return "This is practically asking to be \(taskName(input.suggestedTask, english: true)). Take it?"
        }
    }

    private static func alternateComment(for input: AssistantCommentInput) -> String {
        let english = input.language.lowercased().hasPrefix("en")
        if input.allowedActionIDs.isEmpty, input.suggestedTask == nil {
            return switch (input.personality, english) {
            case (.professional, false): "先把这一段理清，不必急着切到工具。"
            case (.gentle, false): "按你的节奏来，不用把每一步都变成任务。"
            case (.lively, false): "先继续看，等重点冒头我们再出手！"
            case (.calm, false): "先看清楚，再决定要不要动手。"
            case (.lightTeasing, false): "这次先不弹工具按钮，算我克制。"
            case (.professional, true): "Clarify this part first; no tool is needed yet."
            case (.gentle, true): "Go at your pace. Not every step needs to become a task."
            case (.lively, true): "Keep going. We will jump in when the key point appears!"
            case (.calm, true): "See it clearly first, then decide whether to act."
            case (.lightTeasing, true): "No tool button this time. A rare show of restraint."
            }
        }
        switch (input.patternType, input.personality, english) {
        case (.repeatedFailure, .professional, false):
            return "同一处已失败 \(input.evidenceCount) 次，先定位根因再继续。"
        case (.repeatedFailure, .gentle, false):
            return "同一处又卡住了。需要我陪你先看看错误根因吗？"
        case (.repeatedFailure, .lively, false):
            return "它又在同一处拦路了，换个角度把根因揪出来！"
        case (.repeatedFailure, .calm, false):
            return "还是同一处。停一下，先确认根因。"
        case (.repeatedFailure, .lightTeasing, false):
            return "这条错误第 \(input.evidenceCount) 次来敲门了。先看看根因再放它进来？"
        case (.foreignClipboard, .professional, false):
            return "你在连续处理外语文本，可开启 30 分钟本地剪贴板翻译。"
        case (.foreignClipboard, .gentle, false):
            return "这些外语内容交给我一会儿？翻译可以开 30 分钟。"
        case (.foreignClipboard, .lively, false):
            return "又来一段外语！把 30 分钟翻译打开吧？"
        case (.foreignClipboard, .calm, false):
            return "外语内容还在继续。要用翻译，就临时开 30 分钟。"
        case (.foreignClipboard, .lightTeasing, false):
            return "外语内容排起队了。要开启 30 分钟剪贴板翻译吗？"
        case (.contextualOpportunity, .professional, false):
            return "信息已经够了，可以在 Quick Action 中\(taskName(input.suggestedTask, english: false))。"
        case (.contextualOpportunity, .gentle, false):
            return "这一段可以直接\(taskName(input.suggestedTask, english: false))，需要我接着来吗？"
        case (.contextualOpportunity, .lively, false):
            return "线索齐了，接下来直接\(taskName(input.suggestedTask, english: false))吧！"
        case (.contextualOpportunity, .calm, false):
            return "条件够了。下一步可以\(taskName(input.suggestedTask, english: false))。"
        case (.contextualOpportunity, .lightTeasing, false):
            return "这段内容已经把“\(taskName(input.suggestedTask, english: false))”写在脸上了。继续？"
        case (.repeatedFailure, .professional, true):
            return "The same failure occurred \(input.evidenceCount) times. Identify the root cause before retrying."
        case (.repeatedFailure, .gentle, true):
            return "The same issue came back. Want to look at the root cause before trying again?"
        case (.repeatedFailure, .lively, true):
            return "It blocked the same spot again. Let us pull out the root cause!"
        case (.repeatedFailure, .calm, true):
            return "Same point again. Pause and confirm the root cause."
        case (.repeatedFailure, .lightTeasing, true):
            return "This error is knocking for visit \(input.evidenceCount). Check the root cause first?"
        case (.foreignClipboard, .professional, true):
            return "You are handling more foreign-language text. Enable local translation for 30 minutes?"
        case (.foreignClipboard, .gentle, true):
            return "Want to hand me these passages for a while? Translation can run for 30 minutes."
        case (.foreignClipboard, .lively, true):
            return "Another foreign-language passage! Turn on translation for 30 minutes?"
        case (.foreignClipboard, .calm, true):
            return "The foreign-language text continues. Translation can run for 30 minutes."
        case (.foreignClipboard, .lightTeasing, true):
            return "The foreign-language queue is growing. Enable clipboard translation for 30 minutes?"
        case (.contextualOpportunity, .professional, true):
            return "There is enough here to \(taskName(input.suggestedTask, english: true)) in Quick Action."
        case (.contextualOpportunity, .gentle, true):
            return "This can go straight to \(taskName(input.suggestedTask, english: true)). Want me to continue?"
        case (.contextualOpportunity, .lively, true):
            return "The pieces line up. Let us \(taskName(input.suggestedTask, english: true)) next!"
        case (.contextualOpportunity, .calm, true):
            return "The next step is clear: \(taskName(input.suggestedTask, english: true))."
        case (.contextualOpportunity, .lightTeasing, true):
            return "This has \(taskName(input.suggestedTask, english: true)) written all over it. Continue?"
        }
    }

    private static func taskName(_ task: TaskKind?, english: Bool) -> String {
        switch (task, english) {
        case (.translate, false): "翻译"
        case (.polish, false): "润色"
        case (.summarize, false): "总结"
        case (.explain, false): "解释"
        case (.extractTodos, false): "提取待办"
        case (.translate, true): "translate"
        case (.polish, true): "polish"
        case (.summarize, true): "summarize"
        case (.explain, true): "explain"
        case (.extractTodos, true): "extract todos from"
        case (_, false): "处理"
        case (_, true): "process"
        }
    }
}

public struct AssistantTemporaryTranslationSession: Sendable, Hashable {
    public static let duration: TimeInterval = 30 * 60
    public private(set) var language: String?
    public private(set) var startedAt: Date?
    public private(set) var expiresAt: Date?
    public private(set) var hasFailed = false

    public init() {}

    public mutating func start(language: String, now: Date = .now) {
        self.language = LanguageCodeNormalizer.normalizedBCP47(language)
        startedAt = now
        expiresAt = now.addingTimeInterval(Self.duration)
        hasFailed = false
    }

    public mutating func accepts(language: String, occurredAt: Date, now: Date = .now) -> Bool {
        guard !hasFailed,
              let sessionLanguage = self.language,
              let startedAt,
              let expiresAt,
              now < expiresAt,
              occurredAt >= startedAt,
              let candidateLanguage = LanguageCodeNormalizer.normalizedBCP47(language) else {
            if let expiresAt, now >= expiresAt { stop() }
            return false
        }
        return sessionLanguage == candidateLanguage
            || sessionLanguage.split(separator: "-").first == candidateLanguage.split(separator: "-").first
    }

    public mutating func fail() {
        hasFailed = true
        language = nil
        startedAt = nil
        expiresAt = nil
    }

    public mutating func stop() {
        language = nil
        startedAt = nil
        expiresAt = nil
        hasFailed = false
    }
}
