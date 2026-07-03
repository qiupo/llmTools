import Foundation

public enum ModelFormat: String, Codable, Sendable, CaseIterable {
    case gguf
    case mlx
    case openAICompatible = "openai-compatible"
    case anthropicMessages = "anthropic-messages"
    case unknown
}

public enum ModelRole: String, Codable, Sendable, CaseIterable {
    case fast
    case `default`
    case quality
}

public enum ModelValidationState: String, Codable, Sendable, CaseIterable {
    case unknown
    case valid
    case invalid
    case loading
    case ready
    case failed
}

public struct ModelDescriptor: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sourcePath: URL
    public var resolvedPath: URL?
    public var format: ModelFormat
    public var sizeClass: String
    public var role: ModelRole
    public var contextLength: Int
    public var enabled: Bool
    public var validationState: ModelValidationState
    public var lastErrorMessage: String?
    public var providerConfiguration: ProviderConfiguration?

    public init(
        id: UUID = UUID(),
        name: String,
        sourcePath: URL,
        resolvedPath: URL? = nil,
        format: ModelFormat,
        sizeClass: String,
        role: ModelRole,
        contextLength: Int,
        enabled: Bool = true,
        validationState: ModelValidationState = .unknown,
        lastErrorMessage: String? = nil,
        providerConfiguration: ProviderConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.resolvedPath = resolvedPath
        self.format = format
        self.sizeClass = sizeClass
        self.role = role
        self.contextLength = contextLength
        self.enabled = enabled
        self.validationState = validationState
        self.lastErrorMessage = lastErrorMessage
        self.providerConfiguration = providerConfiguration
    }

    public var displayPath: String {
        if let providerConfiguration, providerConfiguration.isRemote {
            return providerConfiguration.baseURL?.absoluteString ?? ModelProviderCatalog.displayName(for: providerConfiguration.providerID)
        }
        return resolvedPath?.path ?? sourcePath.path
    }

    public var providerID: ModelProviderID {
        providerConfiguration?.providerID ?? .local
    }

    public var providerDisplayName: String {
        ModelProviderCatalog.displayName(for: providerID)
    }

    public var apiModelID: String? {
        providerConfiguration?.modelID
    }

    public var isRemoteProvider: Bool {
        providerConfiguration?.isRemote ?? false
    }
}

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

public struct KeyboardShortcutPreference: Codable, Sendable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let optionSpace = KeyboardShortcutPreference(
        keyCode: 49,
        modifiers: KeyboardShortcutPreference.optionModifier
    )

    public static let optionShiftSpace = KeyboardShortcutPreference(
        keyCode: 49,
        modifiers: KeyboardShortcutPreference.optionModifier | KeyboardShortcutPreference.shiftModifier
    )

    public static let commandModifier: UInt32 = 1 << 8
    public static let shiftModifier: UInt32 = 1 << 9
    public static let optionModifier: UInt32 = 1 << 11
    public static let controlModifier: UInt32 = 1 << 12
}

public struct SelectionLineLimitRule: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var bundleIdentifier: String
    public var maximumLineCount: Int

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        maximumLineCount: Int
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.maximumLineCount = maximumLineCount
    }
}

public struct AppPreferences: Codable, Sendable, Hashable {
    public var defaultModelID: UUID?
    public var autoCollapseWidget: Bool
    public var widgetVisibleOnAllSpaces: Bool
    public var launchAtLogin: Bool
    public var replaceOriginalText: Bool
    public var selectionActionEnabled: Bool
    public var selectionActionTriggerMouseDrag: Bool
    public var selectionActionTriggerDoubleClick: Bool
    public var selectionActionTriggerSelectAll: Bool
    public var selectionLineLimitRules: [SelectionLineLimitRule]
    public var appLanguage: AppLanguage
    public var defaultTranslationTarget: String
    public var defaultPolishStyle: String
    public var recentHistoryLimit: Int
    public var webPageTranslation: WebPageTranslationPreferences
    public var quickActionShortcut: KeyboardShortcutPreference
    public var quickActionWithoutSelectionShortcut: KeyboardShortcutPreference

    public init(
        defaultModelID: UUID? = nil,
        autoCollapseWidget: Bool = true,
        widgetVisibleOnAllSpaces: Bool = true,
        launchAtLogin: Bool = false,
        replaceOriginalText: Bool = false,
        selectionActionEnabled: Bool = true,
        selectionActionTriggerMouseDrag: Bool = true,
        selectionActionTriggerDoubleClick: Bool = true,
        selectionActionTriggerSelectAll: Bool = false,
        selectionLineLimitRules: [SelectionLineLimitRule] = [
            SelectionLineLimitRule(bundleIdentifier: "com.tencent.xinWeChat", maximumLineCount: 2)
        ],
        appLanguage: AppLanguage = .chinese,
        defaultTranslationTarget: String = "auto",
        defaultPolishStyle: String = "natural",
        recentHistoryLimit: Int = 20,
        webPageTranslation: WebPageTranslationPreferences = WebPageTranslationPreferences(),
        quickActionShortcut: KeyboardShortcutPreference = .optionSpace,
        quickActionWithoutSelectionShortcut: KeyboardShortcutPreference = .optionShiftSpace
    ) {
        self.defaultModelID = defaultModelID
        self.autoCollapseWidget = autoCollapseWidget
        self.widgetVisibleOnAllSpaces = widgetVisibleOnAllSpaces
        self.launchAtLogin = launchAtLogin
        self.replaceOriginalText = replaceOriginalText
        self.selectionActionEnabled = selectionActionEnabled
        self.selectionActionTriggerMouseDrag = selectionActionTriggerMouseDrag
        self.selectionActionTriggerDoubleClick = selectionActionTriggerDoubleClick
        self.selectionActionTriggerSelectAll = selectionActionTriggerSelectAll
        self.selectionLineLimitRules = selectionLineLimitRules
        self.appLanguage = appLanguage
        self.defaultTranslationTarget = defaultTranslationTarget
        self.defaultPolishStyle = defaultPolishStyle
        self.recentHistoryLimit = recentHistoryLimit
        self.webPageTranslation = webPageTranslation
        self.quickActionShortcut = quickActionShortcut
        self.quickActionWithoutSelectionShortcut = quickActionWithoutSelectionShortcut
    }

    private enum CodingKeys: String, CodingKey {
        case defaultModelID
        case autoCollapseWidget
        case widgetVisibleOnAllSpaces
        case launchAtLogin
        case replaceOriginalText
        case selectionActionEnabled
        case selectionActionTriggerMouseDrag
        case selectionActionTriggerDoubleClick
        case selectionActionTriggerSelectAll
        case selectionLineLimitRules
        case wechatSelectionMaximumLineCount
        case appLanguage
        case defaultTranslationTarget
        case defaultPolishStyle
        case recentHistoryLimit
        case webPageTranslation
        case quickActionShortcut
        case quickActionWithoutSelectionShortcut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultModelID = try container.decodeIfPresent(UUID.self, forKey: .defaultModelID)
        autoCollapseWidget = try container.decodeIfPresent(Bool.self, forKey: .autoCollapseWidget) ?? true
        widgetVisibleOnAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .widgetVisibleOnAllSpaces) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        replaceOriginalText = try container.decodeIfPresent(Bool.self, forKey: .replaceOriginalText) ?? false
        selectionActionEnabled = try container.decodeIfPresent(Bool.self, forKey: .selectionActionEnabled) ?? true
        selectionActionTriggerMouseDrag = try container.decodeIfPresent(Bool.self, forKey: .selectionActionTriggerMouseDrag) ?? true
        selectionActionTriggerDoubleClick = try container.decodeIfPresent(Bool.self, forKey: .selectionActionTriggerDoubleClick) ?? true
        selectionActionTriggerSelectAll = try container.decodeIfPresent(Bool.self, forKey: .selectionActionTriggerSelectAll) ?? false
        if let rules = try container.decodeIfPresent([SelectionLineLimitRule].self, forKey: .selectionLineLimitRules) {
            selectionLineLimitRules = rules
        } else if let wechatSelectionMaximumLineCount = try container.decodeIfPresent(Int.self, forKey: .wechatSelectionMaximumLineCount) {
            selectionLineLimitRules = [
                SelectionLineLimitRule(
                    bundleIdentifier: "com.tencent.xinWeChat",
                    maximumLineCount: wechatSelectionMaximumLineCount
                )
            ]
        } else {
            selectionLineLimitRules = [
                SelectionLineLimitRule(bundleIdentifier: "com.tencent.xinWeChat", maximumLineCount: 2)
            ]
        }
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .chinese
        defaultTranslationTarget = try container.decodeIfPresent(String.self, forKey: .defaultTranslationTarget) ?? "auto"
        defaultPolishStyle = try container.decodeIfPresent(String.self, forKey: .defaultPolishStyle) ?? "natural"
        recentHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .recentHistoryLimit) ?? 20
        webPageTranslation = try container.decodeIfPresent(WebPageTranslationPreferences.self, forKey: .webPageTranslation) ?? WebPageTranslationPreferences()
        quickActionShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .quickActionShortcut) ?? .optionSpace
        quickActionWithoutSelectionShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .quickActionWithoutSelectionShortcut) ?? .optionShiftSpace
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(defaultModelID, forKey: .defaultModelID)
        try container.encode(autoCollapseWidget, forKey: .autoCollapseWidget)
        try container.encode(widgetVisibleOnAllSpaces, forKey: .widgetVisibleOnAllSpaces)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(replaceOriginalText, forKey: .replaceOriginalText)
        try container.encode(selectionActionEnabled, forKey: .selectionActionEnabled)
        try container.encode(selectionActionTriggerMouseDrag, forKey: .selectionActionTriggerMouseDrag)
        try container.encode(selectionActionTriggerDoubleClick, forKey: .selectionActionTriggerDoubleClick)
        try container.encode(selectionActionTriggerSelectAll, forKey: .selectionActionTriggerSelectAll)
        try container.encode(selectionLineLimitRules, forKey: .selectionLineLimitRules)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(defaultTranslationTarget, forKey: .defaultTranslationTarget)
        try container.encode(defaultPolishStyle, forKey: .defaultPolishStyle)
        try container.encode(recentHistoryLimit, forKey: .recentHistoryLimit)
        try container.encode(webPageTranslation, forKey: .webPageTranslation)
        try container.encode(quickActionShortcut, forKey: .quickActionShortcut)
        try container.encode(quickActionWithoutSelectionShortcut, forKey: .quickActionWithoutSelectionShortcut)
    }
}

public struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var task: TaskKind
    public var modelName: String
    public var inputPreview: String
    public var outputPreview: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        task: TaskKind,
        modelName: String,
        inputPreview: String,
        outputPreview: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.task = task
        self.modelName = modelName
        self.inputPreview = inputPreview
        self.outputPreview = outputPreview
    }
}

public enum TaskKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case translate
    case webPageTranslate
    case polish
    case summarize
    case explain
    case extractTodos

    public var id: String { rawValue }

    public static var interactiveCases: [TaskKind] {
        [.translate, .polish, .summarize, .explain, .extractTodos]
    }

    public var title: String {
        switch self {
        case .translate: return "Translate"
        case .webPageTranslate: return "Web Page Translate"
        case .polish: return "Polish"
        case .summarize: return "Summarize"
        case .explain: return "Explain"
        case .extractTodos: return "Extract TODOs"
        }
    }

    public func title(language: AppLanguage) -> String {
        switch language {
        case .chinese:
            switch self {
            case .translate: return "翻译"
            case .webPageTranslate: return "网页翻译"
            case .polish: return "润色"
            case .summarize: return "总结"
            case .explain: return "解释"
            case .extractTodos: return "提取待办"
            }
        case .english:
            return title
        }
    }
}

public struct TaskRequest: Sendable, Hashable {
    public var task: TaskKind
    public var inputText: String
    public var sourceLanguage: String?
    public var targetLanguage: String?
    public var polishStyle: String?

    public init(
        task: TaskKind,
        inputText: String,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        polishStyle: String? = nil
    ) {
        self.task = task
        self.inputText = inputText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.polishStyle = polishStyle
    }
}

public struct TaskResult: Sendable, Hashable {
    public var text: String
    public var rawText: String
    public var modelName: String
    public var task: TaskKind

    public init(text: String, rawText: String? = nil, modelName: String, task: TaskKind) {
        self.text = text
        self.rawText = rawText ?? text
        self.modelName = modelName
        self.task = task
    }
}
