import Foundation

public enum AssistantProactivity: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case manual
    case quiet
    case moderate
    case active

    public var id: String { rawValue }

    public var requiresQualifiedJudgment: Bool {
        self == .moderate || self == .active
    }

    public var hourlyPresentationLimit: Int {
        switch self {
        case .manual: 0
        case .quiet: 1
        case .moderate: 2
        case .active: 4
        }
    }
}

public enum AssistantPersonality: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case professional
    case gentle
    case lightTeasing

    public var id: String { rawValue }
}

public enum AssistantToolbarTrigger: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case hover
    case click

    public var id: String { rawValue }
}

public enum AssistantClipboardAuthorization: String, Codable, Sendable, CaseIterable, Hashable {
    case undecided
    case allowed
    case denied
}

public enum AssistantPatternType: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case repeatedFailure
    case foreignClipboard
    case contextualOpportunity

    public var id: String { rawValue }

    /// P-06 没有模型确认就不存在可展示的事实，因此不能像固定模式一样降级成徽标。
    public var conservativeFallbackPresentation: AssistantPresentation {
        self == .contextualOpportunity ? .silent : .badge
    }
}

public enum AssistantSource: String, Codable, Sendable, CaseIterable, Hashable {
    case foregroundApplication
    case windowContext
    case clipboard
    case selection
    case droppedFile
    case llmToolsTask
    case inquiry
}

public enum AssistantSensitivity: String, Codable, Sendable, CaseIterable, Hashable {
    case normal
    case sensitive
    case excludedApplication
}

public enum AssistantPresentation: String, Codable, Sendable, CaseIterable, Hashable {
    case silent
    case badge
    case peek
}

public enum AssistantCardState: String, Codable, Sendable, CaseIterable, Hashable {
    case unread
    case viewed
    case acted
    case dismissed
    case suppressed
    case expired
}

public enum AssistantRemoteWorkbenchDisclosure {
    public static func requiresConfirmation(
        isAssistantHandoff: Bool,
        isRemoteModel: Bool,
        alreadyAcknowledged: Bool,
        localOnly: Bool
    ) -> Bool {
        isAssistantHandoff && isRemoteModel && !alreadyAcknowledged && !localOnly
    }
}

public enum AssistantFeedback: String, Codable, Sendable, CaseIterable, Hashable {
    case useful
    case irrelevant
    case unfunny
    case explicitlyClosed
}

public enum AssistantActionID: String, Codable, Sendable, CaseIterable, Hashable {
    case deepenInquiry
    case explainError
    case returnToWorkbench
    case enableClipboardTranslation
    case translateCurrentClipboard
    case detailedTranslation
    case copyTranslation
    case openQuickAction
    case openSettings
}

public struct AssistantQuietHours: Codable, Sendable, Hashable {
    public var isEnabled: Bool
    public var startMinute: Int
    public var endMinute: Int

    public init(isEnabled: Bool = false, startMinute: Int = 22 * 60, endMinute: Int = 8 * 60) {
        self.isEnabled = isEnabled
        self.startMinute = min(max(startMinute, 0), 1_439)
        self.endMinute = min(max(endMinute, 0), 1_439)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if startMinute <= endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}

public struct AssistantWindowPosition: Codable, Sendable, Hashable {
    public var xRatio: Double
    public var yRatio: Double

    public init(xRatio: Double, yRatio: Double) {
        self.xRatio = min(max(xRatio, 0), 1)
        self.yRatio = min(max(yRatio, 0), 1)
    }
}

public enum AssistantQualificationState: String, Codable, Sendable, CaseIterable, Hashable {
    case unchecked
    case qualified
    case unqualified
    case unavailable
}

public struct AssistantQualificationSummary: Codable, Sendable, Hashable {
    public var modelID: UUID
    public var modelFingerprint: String
    public var promptVersion: Int
    public var fixtureVersion: Int
    public var state: AssistantQualificationState
    public var validJSONCount: Int
    public var positivePassCount: Int
    public var negativeFalsePositiveCount: Int
    public var hardFailureCount: Int
    public var maximumLatencyMilliseconds: Int
    public var checkedAt: Date
    public var message: String

    public init(
        modelID: UUID,
        modelFingerprint: String,
        promptVersion: Int,
        fixtureVersion: Int,
        state: AssistantQualificationState,
        validJSONCount: Int,
        positivePassCount: Int,
        negativeFalsePositiveCount: Int,
        hardFailureCount: Int,
        maximumLatencyMilliseconds: Int,
        checkedAt: Date = .now,
        message: String
    ) {
        self.modelID = modelID
        self.modelFingerprint = modelFingerprint
        self.promptVersion = promptVersion
        self.fixtureVersion = fixtureVersion
        self.state = state
        self.validJSONCount = validJSONCount
        self.positivePassCount = positivePassCount
        self.negativeFalsePositiveCount = negativeFalsePositiveCount
        self.hardFailureCount = hardFailureCount
        self.maximumLatencyMilliseconds = maximumLatencyMilliseconds
        self.checkedAt = checkedAt
        self.message = message
    }
}

public struct DesktopAssistantPreferences: Codable, Sendable, Hashable {
    public static let currentOnboardingVersion = 1
    public static let defaultExcludedApplicationBundleIDs = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.passwords",
        "com.apple.keychainaccess",
        "com.authy.desktop",
        "com.bitwarden.desktop"
    ]

    public var isEnabled: Bool
    public var completedOnboardingVersion: Int
    public var showOnAllSpaces: Bool
    public var showOverFullScreen: Bool
    public var toolbarTrigger: AssistantToolbarTrigger
    public var proactivity: AssistantProactivity
    public var personality: AssistantPersonality
    public var quietHours: AssistantQuietHours
    public var lateNightReminderEnabled: Bool
    public var repeatedFailureEnabled: Bool
    public var foreignClipboardEnabled: Bool
    public var foregroundApplicationContextEnabled: Bool
    public var enhancedWindowContextEnabled: Bool
    public var clipboardAuthorization: AssistantClipboardAuthorization
    public var selectionContextEnabled: Bool
    public var useBehaviorHistory: Bool
    public var excludedApplicationBundleIDs: [String]
    public var suppressedForeignLanguages: [String]
    public var judgmentModelID: UUID?
    public var commentModelID: UUID?
    public var judgmentConfidenceThresholdOverride: Double?
    public var qualificationCache: [String: AssistantQualificationSummary]
    public var positionsByDisplay: [String: AssistantWindowPosition]
    public var lastDisplayID: String?

    public init(
        isEnabled: Bool = false,
        completedOnboardingVersion: Int = 0,
        showOnAllSpaces: Bool = true,
        showOverFullScreen: Bool = false,
        toolbarTrigger: AssistantToolbarTrigger = .hover,
        proactivity: AssistantProactivity = .moderate,
        personality: AssistantPersonality = .gentle,
        quietHours: AssistantQuietHours = AssistantQuietHours(),
        lateNightReminderEnabled: Bool = false,
        repeatedFailureEnabled: Bool = true,
        foreignClipboardEnabled: Bool = true,
        foregroundApplicationContextEnabled: Bool = true,
        enhancedWindowContextEnabled: Bool = false,
        clipboardAuthorization: AssistantClipboardAuthorization = .undecided,
        selectionContextEnabled: Bool = true,
        useBehaviorHistory: Bool = true,
        excludedApplicationBundleIDs: [String] = Self.defaultExcludedApplicationBundleIDs,
        suppressedForeignLanguages: [String] = [],
        judgmentModelID: UUID? = nil,
        commentModelID: UUID? = nil,
        judgmentConfidenceThresholdOverride: Double? = nil,
        qualificationCache: [String: AssistantQualificationSummary] = [:],
        positionsByDisplay: [String: AssistantWindowPosition] = [:],
        lastDisplayID: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.completedOnboardingVersion = max(0, completedOnboardingVersion)
        self.showOnAllSpaces = showOnAllSpaces
        self.showOverFullScreen = showOverFullScreen
        self.toolbarTrigger = toolbarTrigger
        self.proactivity = proactivity
        self.personality = personality
        self.quietHours = quietHours
        self.lateNightReminderEnabled = lateNightReminderEnabled
        self.repeatedFailureEnabled = repeatedFailureEnabled
        self.foreignClipboardEnabled = foreignClipboardEnabled
        self.foregroundApplicationContextEnabled = foregroundApplicationContextEnabled
        self.enhancedWindowContextEnabled = enhancedWindowContextEnabled
        self.clipboardAuthorization = clipboardAuthorization
        self.selectionContextEnabled = selectionContextEnabled
        self.useBehaviorHistory = useBehaviorHistory
        self.excludedApplicationBundleIDs = Self.normalizedBundleIDs(excludedApplicationBundleIDs)
        self.suppressedForeignLanguages = Self.normalizedStrings(suppressedForeignLanguages)
        self.judgmentModelID = judgmentModelID
        self.commentModelID = commentModelID
        self.judgmentConfidenceThresholdOverride = judgmentConfidenceThresholdOverride
        self.qualificationCache = qualificationCache
        self.positionsByDisplay = positionsByDisplay
        self.lastDisplayID = lastDisplayID
    }

    public var hasCompletedCurrentOnboarding: Bool {
        completedOnboardingVersion >= Self.currentOnboardingVersion
    }

    public var hasAnyBackgroundSource: Bool {
        foregroundApplicationContextEnabled
            || clipboardAuthorization == .allowed
            || selectionContextEnabled
    }

    public var isManualOnly: Bool {
        !hasAnyBackgroundSource
    }

    public func qualification(for modelID: UUID) -> AssistantQualificationSummary? {
        qualificationCache[modelID.uuidString]
    }

    public func qualification(for modelID: UUID, modelFingerprint: String) -> AssistantQualificationSummary? {
        guard let summary = qualification(for: modelID), summary.isCurrent(modelFingerprint: modelFingerprint) else {
            return nil
        }
        return summary
    }

    public mutating func setQualification(_ summary: AssistantQualificationSummary) {
        qualificationCache[summary.modelID.uuidString] = summary
    }

    public mutating func removeQualification(for modelID: UUID) {
        qualificationCache.removeValue(forKey: modelID.uuidString)
    }

    private static func normalizedStrings(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private static func normalizedBundleIDs(_ values: [String]) -> [String] {
        normalizedStrings(values).map { $0.lowercased() }
    }
}

public enum AssistantLifecycleMode: String, Sendable, Hashable {
    case disabled
    case onboarding
    case idle
    case paused
    case privacy
}

public enum AssistantLifecycleEvent: Sendable, Hashable {
    case requestEnable
    case finishOnboarding
    case cancelOnboarding
    case show
    case hide
    case pause(until: Date)
    case resume
    case setPrivacy(Bool)
    case disable
    case tick(Date)
}

public struct AssistantLifecycleMachine: Sendable, Hashable {
    public private(set) var mode: AssistantLifecycleMode
    public private(set) var isVisible: Bool
    public private(set) var pauseUntil: Date?
    public private(set) var hasCompletedOnboarding: Bool
    public private(set) var modeBeforePrivacy: AssistantLifecycleMode?

    public init(preferences: DesktopAssistantPreferences, now: Date = .now) {
        hasCompletedOnboarding = preferences.hasCompletedCurrentOnboarding
        pauseUntil = nil
        modeBeforePrivacy = nil
        if preferences.isEnabled && hasCompletedOnboarding {
            mode = .idle
            isVisible = true
        } else {
            mode = .disabled
            isVisible = false
        }
        apply(.tick(now))
    }

    public var isEnabled: Bool {
        mode != .disabled && mode != .onboarding
    }

    public var observationIsAllowed: Bool {
        mode == .idle
    }

    public func allowsSelectionCapture(preferences: DesktopAssistantPreferences) -> Bool {
        observationIsAllowed && preferences.selectionContextEnabled
    }

    public func resolvedPresentation(
        requested: AssistantPresentation,
        hardPolicyAllowsPeek: Bool
    ) -> AssistantPresentation {
        // 隐藏只停止界面，不停止观察；后台产生的主动展开必须降为未读徽标。
        requested == .peek && (!isVisible || !hardPolicyAllowsPeek) ? .badge : requested
    }

    public func allowsWindowPresentation(
        showOverFullScreen: Bool,
        frontmostApplicationIsFullScreen: Bool
    ) -> Bool {
        isVisible && (showOverFullScreen || !frontmostApplicationIsFullScreen)
    }

    // 窗口可见性和观察状态分开维护：用户隐藏悬浮球时，已授权的后台观察仍可继续。
    public mutating func apply(_ event: AssistantLifecycleEvent) {
        switch event {
        case .requestEnable:
            if hasCompletedOnboarding {
                mode = .idle
                isVisible = true
            } else {
                mode = .onboarding
                isVisible = false
            }
        case .finishOnboarding:
            hasCompletedOnboarding = true
            mode = .idle
            isVisible = true
        case .cancelOnboarding:
            mode = .disabled
            isVisible = false
        case .show:
            if mode != .disabled && mode != .onboarding {
                isVisible = true
            }
        case .hide:
            isVisible = false
        case .pause(let until):
            guard mode != .disabled && mode != .onboarding else { return }
            pauseUntil = until
            mode = .paused
        case .resume:
            guard mode == .paused || mode == .privacy else { return }
            pauseUntil = nil
            modeBeforePrivacy = nil
            mode = .idle
        case .setPrivacy(let enabled):
            guard mode != .disabled && mode != .onboarding else { return }
            if enabled, mode != .privacy {
                modeBeforePrivacy = mode
                mode = .privacy
            } else if !enabled, mode == .privacy {
                mode = modeBeforePrivacy == .paused && pauseUntil != nil ? .paused : .idle
                modeBeforePrivacy = nil
            }
        case .disable:
            pauseUntil = nil
            modeBeforePrivacy = nil
            mode = .disabled
            isVisible = false
        case .tick(let now):
            if mode == .paused, let pauseUntil, pauseUntil <= now {
                self.pauseUntil = nil
                mode = .idle
            } else if mode == .privacy, let pauseUntil, pauseUntil <= now {
                self.pauseUntil = nil
                if modeBeforePrivacy == .paused {
                    modeBeforePrivacy = .idle
                }
            }
        }
    }
}

public struct AssistantCardEvidence: Codable, Sendable, Hashable {
    public var sources: [AssistantSource]
    public var count: Int
    public var durationSeconds: Int
    public var usedLocalModel: Bool
    public var rawContextAvailable: Bool
    public var capability: String

    public init(
        sources: [AssistantSource],
        count: Int = 1,
        durationSeconds: Int = 0,
        usedLocalModel: Bool = false,
        rawContextAvailable: Bool = false,
        capability: String
    ) {
        self.sources = Array(Set(sources)).sorted { $0.rawValue < $1.rawValue }
        self.count = max(0, count)
        self.durationSeconds = max(0, durationSeconds)
        self.usedLocalModel = usedLocalModel
        self.rawContextAvailable = rawContextAvailable
        self.capability = capability
    }
}

public struct AssistantCard: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var createdAt: Date
    public var source: AssistantSource
    public var patternType: AssistantPatternType?
    public var presentation: AssistantPresentation
    public var comment: String
    public var evidenceSummary: String?
    public var evidence: AssistantCardEvidence
    public var actionIDs: [AssistantActionID]
    public var sensitivity: AssistantSensitivity
    public var confidence: Double
    public var expiresAt: Date?
    public var state: AssistantCardState
    public var feedback: AssistantFeedback?
    public var detailText: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: AssistantSource,
        patternType: AssistantPatternType? = nil,
        presentation: AssistantPresentation = .badge,
        comment: String,
        evidenceSummary: String? = nil,
        evidence: AssistantCardEvidence,
        actionIDs: [AssistantActionID] = [],
        sensitivity: AssistantSensitivity = .normal,
        confidence: Double = 1,
        expiresAt: Date? = nil,
        state: AssistantCardState = .unread,
        feedback: AssistantFeedback? = nil,
        detailText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.patternType = patternType
        self.presentation = presentation
        self.comment = comment
        self.evidenceSummary = evidenceSummary
        self.evidence = evidence
        self.actionIDs = Array(actionIDs.prefix(3))
        self.sensitivity = sensitivity
        self.confidence = min(max(confidence, 0), 1)
        self.expiresAt = expiresAt
        self.state = state
        self.feedback = feedback
        self.detailText = detailText
    }

    /// 只有不带工具入口的情境表达才像助手说话；可操作提示继续使用完整卡片。
    public var prefersSpeechBubblePresentation: Bool {
        patternType == .contextualOpportunity && actionIDs.isEmpty
    }

    /// 只有带动作入口的卡片才需要用户回到助手处理；纯表达仍保留在最近记录，但不制造待办感。
    public var requiresUserAction: Bool {
        !actionIDs.isEmpty
    }

    public func isAvailableForExplicitContext(now: Date = .now) -> Bool {
        sensitivity == .normal
            && state != .expired
            && (expiresAt.map { $0 > now } ?? true)
    }
}

public actor AssistantCardStore {
    public static let maximumCardCount = 20

    private var cards: [AssistantCard] = []

    public init() {}

    @discardableResult
    public func add(_ card: AssistantCard, now: Date = .now) -> [AssistantCard] {
        expireCards(now: now)
        // 敏感显式问答只能作为当前瞬时结果展示，不能进入“最近提示”内容历史。
        guard card.sensitivity == .normal else { return snapshot(now: now) }
        cards.removeAll { $0.id == card.id }
        cards.append(card)
        // 优先淘汰已处理卡片；若全部未读，才淘汰最早的一张，确保上限恒定为 20。
        while cards.count > Self.maximumCardCount {
            let removableIndex = cards.firstIndex {
                $0.state == .viewed || $0.state == .dismissed || $0.state == .expired
            } ?? 0
            cards.remove(at: removableIndex)
        }
        return snapshot(now: now)
    }

    public func snapshot(now: Date = .now) -> [AssistantCard] {
        expireCards(now: now)
        return cards.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func remove(id: UUID, now: Date = .now) -> [AssistantCard] {
        expireCards(now: now)
        cards.removeAll { $0.id == id }
        return snapshot(now: now)
    }

    public func markViewed(id: UUID, now: Date = .now) -> [AssistantCard] {
        expireCards(now: now)
        if let index = cards.firstIndex(where: { $0.id == id && $0.state == .unread }) {
            cards[index].state = .viewed
        }
        return snapshot(now: now)
    }

    public func markAllViewed(now: Date = .now) -> [AssistantCard] {
        expireCards(now: now)
        for index in cards.indices where cards[index].state == .unread {
            cards[index].state = .viewed
        }
        return snapshot(now: now)
    }

    public func update(
        id: UUID,
        state: AssistantCardState? = nil,
        feedback: AssistantFeedback? = nil,
        now: Date = .now
    ) -> [AssistantCard] {
        expireCards(now: now)
        if let index = cards.firstIndex(where: { $0.id == id }) {
            if let state { cards[index].state = state }
            if let feedback { cards[index].feedback = feedback }
        }
        return snapshot(now: now)
    }

    public func clear() {
        cards.removeAll()
    }

    public func unreadCount(now: Date = .now) -> Int {
        expireCards(now: now)
        return cards.lazy.filter { $0.state == .unread && $0.requiresUserAction }.count
    }

    public func latestUnread(now: Date = .now) -> AssistantCard? {
        expireCards(now: now)
        return cards
            .filter { $0.state == .unread && $0.requiresUserAction }
            .max { $0.createdAt < $1.createdAt }
    }

    private func expireCards(now: Date) {
        for index in cards.indices {
            if let expiresAt = cards[index].expiresAt,
               expiresAt <= now,
               cards[index].state == .unread {
                cards[index].state = .expired
            }
        }
    }
}

public enum AssistantDiagnosticStage: String, Codable, Sendable, Hashable {
    case capture
    case vision
    case context
    case judgment
    case comment
    case presentation
}

public enum AssistantDiagnosticState: String, Codable, Sendable, Hashable {
    case scheduled
    case queued
    case running
    case succeeded
    case skipped
    case failed
    case cancelled
}

public struct AssistantDiagnosticEvent: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var occurredAt: Date
    public var stage: AssistantDiagnosticStage
    public var state: AssistantDiagnosticState
    public var detail: String

    public init(
        id: UUID = UUID(),
        occurredAt: Date = .now,
        stage: AssistantDiagnosticStage,
        state: AssistantDiagnosticState,
        detail: String
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.stage = stage
        self.state = state
        // 诊断详情只能由调用方传入机器原因码；这里再限制长度，避免意外形成第二份内容日志。
        self.detail = String(detail.prefix(160))
    }

    public func localizedSummary(language: AppLanguage) -> String {
        "\(stage.localizedName(language: language)) · \(state.localizedName(language: language)) · \(localizedExplanation(language: language) ?? detail)"
    }

    public func localizedExplanation(language: AppLanguage) -> String? {
        let localize: (String, String) -> String = { chinese, english in
            language == .chinese ? chinese : english
        }
        // 机器原因码继续作为稳定调试接口；这里只生成不含观察正文的人类可读解释。
        if stage == .capture, state == .scheduled,
           let delay = diagnosticToken("delay") {
            let includesCooldown = detail.contains("cooldown=true")
            let interval = diagnosticToken("interval") ?? "15s"
            if detail.contains("reset=true") {
                return localize(
                    "检测到新操作，截图倒计时已重置为 \(delay)\(includesCooldown ? "（含 \(interval) 间隔）" : "")",
                    "New activity reset the capture countdown to \(delay)\(includesCooldown ? " (includes the \(interval) interval)" : "")"
                )
            }
            return localize(
                "操作结束后等待 \(delay) 再截图\(includesCooldown ? "（含 \(interval) 间隔）" : "")",
                "Capture waits \(delay) after activity\(includesCooldown ? " (includes the \(interval) interval)" : "")"
            )
        }
        switch detail {
        case "no-eligible-frontmost-window":
            return localize(
                "前台是 llmTools、桌面或没有普通窗口，本轮截图结束",
                "llmTools, the desktop, or no regular window is frontmost; capture ended"
            )
        case "frontmost-window-changed":
            return localize(
                "截图期间前台窗口已变化，旧画面已丢弃",
                "The frontmost window changed during capture, so the stale frame was discarded"
            )
        case "unchanged-frame":
            return localize(
                "画面与上一帧相同，不重复理解，本轮结束",
                "The frame is unchanged; visual analysis was not repeated and the round ended"
            )
        case "excluded-application":
            return localize(
                "前台应用被隐私规则排除，本轮结束",
                "The frontmost app is excluded by privacy rules; the round ended"
            )
        case "permission-or-window-error":
            return localize(
                "没有屏幕录制权限或窗口在截图时消失",
                "Screen Recording permission is unavailable or the window disappeared"
            )
        case "user-typing":
            return localize(
                "截图后检测到仍在输入，为避免分析过时画面，本轮视觉理解结束",
                "Typing resumed after capture, so stale visual analysis was skipped"
            )
        case "proactivity-inactive":
            return localize(
                "当前实际主动程度为安静，本轮不调用视觉模型",
                "Effective proactivity is Quiet, so the vision model was not called"
            )
        case "proactivity-paused":
            return localize(
                "主动提示已手动暂停，本轮不调用视觉模型",
                "Proactive suggestions are paused, so the vision model was not called"
            )
        case "proactivity-session-downgraded":
            return localize(
                "本次会话已自动降为安静，可在助手设置中恢复",
                "This session was automatically reduced to Quiet and can be restored in Assistant settings"
            )
        case "no-qualified-model":
            return localize(
                "没有通过主动判断资格检查的本地模型，本轮结束",
                "No local model has passed proactive-judgment qualification; the round ended"
            )
        case "no-vision-model":
            return localize(
                "没有可用于情境截图理解的本地视觉模型，本轮结束",
                "No local vision model is available for screenshot understanding; the round ended"
            )
        case "background-resource-busy":
            return localize(
                "本地模型资源刚被另一轮占用，保留触发并稍后重试",
                "Local model resources were claimed by another round; the trigger was kept for retry"
            )
        case "stale-visual-surface":
            return localize(
                "视觉理解完成前当前操作已变化，旧结果已丢弃并等待重试",
                "The current operation changed before visual analysis finished; the stale result was discarded for retry"
            )
        case "vision-cooldown":
            return localize(
                "距离上次视觉理解不足 15 秒，本轮结束",
                "Less than 15 seconds passed since the last visual analysis; the round ended"
            )
        case "no-evidence-in-window":
            return localize(
                "当前触发已没有可用的同情境语义证据，本轮结束",
                "No current same-context semantic evidence remained for this trigger; the round ended"
            )
        case "duplicate-context-cooldown":
            return localize(
                "相同情境在 10 分钟内已经判断过，去重后本轮结束",
                "The same context was judged within 10 minutes; the duplicate round ended"
            )
        default:
            break
        }
        if detail == "local-vlm" {
            return localize("本地视觉模型正在理解当前窗口", "The local vision model is understanding the current window")
        }
        if detail.hasPrefix("frame-ready ") {
            return localize("前台窗口截图已就绪，准备视觉理解", "The frontmost-window capture is ready for visual analysis")
        }
        if detail.hasPrefix("context-recorded ") {
            return localize("已得到可用的场景语义，写入当前窗口的短期证据池", "Usable scene semantics were added to the current window's short-term evidence pool")
        }
        if detail.hasPrefix("vision-timeout ") {
            let limit = diagnosticToken("limit") ?? "15s"
            return localize(
                "本地视觉模型超过 \(limit) 时限，已结束并等待重试",
                "The local vision model exceeded the \(limit) limit and will retry later"
            )
        }
        if detail.hasPrefix("vision-cancelled ") {
            return localize("本轮视觉理解因状态变化而取消", "Visual analysis was cancelled because the assistant state changed")
        }
        if detail.hasPrefix("vision-model-error ") {
            return localize("本地视觉模型运行失败，已进入重试等待", "The local vision model failed and will retry later")
        }
        if detail.hasPrefix("context-debounce ") {
            let remaining = diagnosticToken("remaining") ?? "0.8s"
            return localize(
                "等待短防抖合并同一操作的并发证据，剩余 \(remaining)",
                "A short debounce is merging concurrent evidence for this operation; \(remaining) remains"
            )
        }
        if detail.hasPrefix("evidence-ready ") {
            return localize("本轮证据已合并，进入价值判断", "This round's evidence is merged and ready for value judgment")
        }
        if detail.hasPrefix("pattern="), stage == .judgment, state == .queued {
            return localize("本轮证据已进入价值判断队列", "This round's evidence entered the value-judgment queue")
        }
        if detail.hasPrefix("pattern="), stage == .judgment, state == .running {
            return localize("正在判断是否值得打断，以及是否需要功能入口", "Judging whether interruption is worthwhile and whether an action is useful")
        }
        if detail.hasPrefix("model-veto=not-high-value ") {
            return localize("价值模型认为当前不值得打断，选择静默", "The value model decided this was not worth an interruption and chose silence")
        }
        if detail.hasPrefix("model-veto=confidence ") {
            return localize("模型倾向展示，但置信度没达到当前门槛", "The model leaned toward showing this, but its confidence was below the current threshold")
        }
        if detail.hasPrefix("deferred=") {
            let reason = diagnosticToken("deferred") ?? "busy"
            return localize(
                "判断已完成；当前因 \(reason) 延迟展示，条件恢复后继续",
                "Judgment finished; presentation is deferred for \(reason) and will resume when clear"
            )
        }
        if detail.hasPrefix("history-veto ") {
            return localize("同类提示近期多次被标记为不相关，本轮选择静默", "Similar suggestions were recently marked irrelevant, so this round stayed silent")
        }
        if detail.hasPrefix("silent-fallback ") {
            return localize("不展示气泡，本轮静默结束", "No bubble was shown; this round ended silently")
        }
        if detail.hasPrefix("peek-approved ") {
            return localize("价值判断与文案已通过，准备展示", "Value judgment and final wording passed; preparing presentation")
        }
        return nil
    }

    private func diagnosticToken(_ name: String) -> String? {
        let prefix = "\(name)="
        guard let token = detail.split(separator: " ").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(token.dropFirst(prefix.count))
    }
}

public extension AssistantDiagnosticStage {
    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .capture: language == .chinese ? "截图" : "capture"
        case .vision: language == .chinese ? "视觉理解" : "vision"
        case .context: language == .chinese ? "情境整合" : "context fusion"
        case .judgment: language == .chinese ? "价值判断" : "judgment"
        case .comment: language == .chinese ? "性格表达" : "comment"
        case .presentation: language == .chinese ? "展示" : "presentation"
        }
    }
}

public extension AssistantDiagnosticState {
    func localizedName(language: AppLanguage) -> String {
        switch self {
        case .scheduled: language == .chinese ? "已计划" : "scheduled"
        case .queued: language == .chinese ? "排队" : "queued"
        case .running: language == .chinese ? "运行中" : "running"
        case .succeeded: language == .chinese ? "成功" : "succeeded"
        case .skipped: language == .chinese ? "跳过" : "skipped"
        case .failed: language == .chinese ? "失败" : "failed"
        case .cancelled: language == .chinese ? "已取消" : "cancelled"
        }
    }
}

public struct AssistantDiagnosticTimeline: Sendable {
    public static let maximumEventCount = 24
    public private(set) var events: [AssistantDiagnosticEvent] = []

    public init() {}

    public mutating func append(
        stage: AssistantDiagnosticStage,
        state: AssistantDiagnosticState,
        detail: String,
        occurredAt: Date = .now
    ) {
        events.insert(AssistantDiagnosticEvent(
            occurredAt: occurredAt,
            stage: stage,
            state: state,
            detail: detail
        ), at: 0)
        if events.count > Self.maximumEventCount { events.removeLast() }
    }

    public mutating func refreshScheduled(
        stage: AssistantDiagnosticStage,
        detail: String,
        occurredAt: Date = .now
    ) {
        guard let index = events.firstIndex(where: { $0.stage == stage }),
              events[index].state == .scheduled else {
            append(stage: stage, state: .scheduled, detail: detail, occurredAt: occurredAt)
            return
        }
        // 同一阶段仍在等待时只刷新这一条，时间即代表最后一次真正重置倒计时的操作。
        let id = events[index].id
        events.remove(at: index)
        events.insert(AssistantDiagnosticEvent(
            id: id,
            occurredAt: occurredAt,
            stage: stage,
            state: .scheduled,
            detail: detail
        ), at: 0)
    }
}

public enum AssistantAccessoryPlacement: String, Codable, Sendable, CaseIterable, Hashable {
    case left
    case right
    case above
    case below
}

public struct AssistantAccessoryLayout: Sendable, Hashable {
    public var placement: AssistantAccessoryPlacement
    public var toolbarFrame: CGRect
    public var peekFrame: CGRect

    public init(placement: AssistantAccessoryPlacement, toolbarFrame: CGRect, peekFrame: CGRect) {
        self.placement = placement
        self.toolbarFrame = toolbarFrame
        self.peekFrame = peekFrame
    }
}

public enum AssistantWindowGeometry {
    public static let orbDiameter: CGFloat = 48
    public static let dropTargetDiameter: CGFloat = 120
    public static let toolbarHorizontalSize = CGSize(width: 88, height: 40)
    public static let toolbarVerticalSize = CGSize(width: 40, height: 88)
    public static let peekSize = CGSize(width: 320, height: 220)
    public static let speechBubbleWidth: CGFloat = 280
    public static let speechBubbleMinimumHeight: CGFloat = 68
    public static let speechBubbleMaximumHeight: CGFloat = 180
    public static let safeInset: CGFloat = 8
    public static let accessoryGap: CGFloat = 8

    public static func allowsPassiveToolbar(peekIsVisible: Bool, dropTargetIsActive: Bool) -> Bool {
        !peekIsVisible && !dropTargetIsActive
    }

    public static func defaultOrbFrame(in visibleFrame: CGRect) -> CGRect {
        let origin = CGPoint(
            x: visibleFrame.maxX - orbDiameter - 56,
            y: visibleFrame.minY + visibleFrame.height * 0.36
        )
        return clampedOrbFrame(
            CGRect(origin: origin, size: CGSize(width: orbDiameter, height: orbDiameter)),
            in: visibleFrame
        )
    }

    public static func clampedOrbFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        var result = frame
        let maximumX = max(visibleFrame.minX + safeInset, visibleFrame.maxX - frame.width - safeInset)
        let maximumY = max(visibleFrame.minY + safeInset, visibleFrame.maxY - frame.height - safeInset)
        result.origin.x = min(max(frame.minX, visibleFrame.minX + safeInset), maximumX)
        result.origin.y = min(max(frame.minY, visibleFrame.minY + safeInset), maximumY)
        return result
    }

    public static func storedPosition(for orbFrame: CGRect, in visibleFrame: CGRect) -> AssistantWindowPosition {
        // 只持久化显示器内的相对中心点，分辨率或排列变化后仍可恢复到可见区域。
        let width = max(visibleFrame.width, 1)
        let height = max(visibleFrame.height, 1)
        return AssistantWindowPosition(
            xRatio: (orbFrame.midX - visibleFrame.minX) / width,
            yRatio: (orbFrame.midY - visibleFrame.minY) / height
        )
    }

    public static func restoredOrbFrame(
        from position: AssistantWindowPosition,
        in visibleFrame: CGRect,
        diameter: CGFloat = orbDiameter
    ) -> CGRect {
        let center = CGPoint(
            x: visibleFrame.minX + visibleFrame.width * position.xRatio,
            y: visibleFrame.minY + visibleFrame.height * position.yRatio
        )
        return clampedOrbFrame(
            CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter),
            in: visibleFrame
        )
    }

    public static func accessoryLayout(
        orbFrame: CGRect,
        visibleFrame: CGRect,
        peekSize: CGSize = Self.peekSize
    ) -> AssistantAccessoryLayout {
        // 工具条和瞥见卡共用同一方向决策，并在菜单栏、Dock 与屏幕边缘内二次夹取。
        let leftSpace = orbFrame.minX - visibleFrame.minX
        let rightSpace = visibleFrame.maxX - orbFrame.maxX
        let belowSpace = orbFrame.minY - visibleFrame.minY
        let aboveSpace = visibleFrame.maxY - orbFrame.maxY
        let placement: AssistantAccessoryPlacement
        if max(leftSpace, rightSpace) >= max(aboveSpace, belowSpace) {
            placement = rightSpace >= leftSpace ? .right : .left
        } else {
            placement = aboveSpace >= belowSpace ? .above : .below
        }

        let toolbarSize = placement == .left || placement == .right
            ? toolbarHorizontalSize
            : toolbarVerticalSize
        let toolbarOrigin: CGPoint
        switch placement {
        case .left:
            toolbarOrigin = CGPoint(x: orbFrame.minX - accessoryGap - toolbarSize.width, y: orbFrame.midY - toolbarSize.height / 2)
        case .right:
            toolbarOrigin = CGPoint(x: orbFrame.maxX + accessoryGap, y: orbFrame.midY - toolbarSize.height / 2)
        case .above:
            toolbarOrigin = CGPoint(x: orbFrame.midX - toolbarSize.width / 2, y: orbFrame.maxY + accessoryGap)
        case .below:
            toolbarOrigin = CGPoint(x: orbFrame.midX - toolbarSize.width / 2, y: orbFrame.minY - accessoryGap - toolbarSize.height)
        }
        let toolbarFrame = clampedFrame(CGRect(origin: toolbarOrigin, size: toolbarSize), in: visibleFrame)

        let peekOrigin: CGPoint
        switch placement {
        case .left:
            peekOrigin = CGPoint(x: orbFrame.minX - accessoryGap - peekSize.width, y: orbFrame.midY - peekSize.height / 2)
        case .right:
            peekOrigin = CGPoint(x: orbFrame.maxX + accessoryGap, y: orbFrame.midY - peekSize.height / 2)
        case .above:
            peekOrigin = CGPoint(x: orbFrame.midX - peekSize.width / 2, y: orbFrame.maxY + accessoryGap)
        case .below:
            peekOrigin = CGPoint(x: orbFrame.midX - peekSize.width / 2, y: orbFrame.minY - accessoryGap - peekSize.height)
        }
        let peekFrame = clampedFrame(CGRect(origin: peekOrigin, size: peekSize), in: visibleFrame)
        return AssistantAccessoryLayout(placement: placement, toolbarFrame: toolbarFrame, peekFrame: peekFrame)
    }

    private static func clampedFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(
            max(frame.minX, visibleFrame.minX + safeInset),
            max(visibleFrame.minX + safeInset, visibleFrame.maxX - frame.width - safeInset)
        )
        result.origin.y = min(
            max(frame.minY, visibleFrame.minY + safeInset),
            max(visibleFrame.minY + safeInset, visibleFrame.maxY - frame.height - safeInset)
        )
        return result
    }
}
