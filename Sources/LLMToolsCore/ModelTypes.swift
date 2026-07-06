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

public enum ModelInputCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case text
    case image
}

public enum ModelCapabilitySource: String, Codable, Sendable, CaseIterable, Hashable {
    case detected
    case inferred
    case probePassed
    case failedProbe
    case manual
    case unknown
}

public struct ModelCapabilities: Codable, Hashable, Sendable {
    public var inputs: [ModelInputCapability]
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?

    public init(
        inputs: [ModelInputCapability] = [.text],
        source: ModelCapabilitySource = .unknown,
        confidence: Double = 0.5,
        note: String? = nil,
        lastCheckedAt: Date? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.inputs = ModelCapabilities.normalizedInputs(inputs)
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.note = note
        self.lastCheckedAt = lastCheckedAt
        self.lastFailureMessage = lastFailureMessage
    }

    public func supports(_ capability: ModelInputCapability) -> Bool {
        inputs.contains(capability)
    }

    public var supportsText: Bool {
        supports(.text)
    }

    public var supportsImage: Bool {
        supports(.image)
    }

    public static func textOnly(source: ModelCapabilitySource = .inferred, note: String? = nil) -> ModelCapabilities {
        ModelCapabilities(
            inputs: [.text],
            source: source,
            confidence: source == .unknown ? 0.35 : 1,
            note: note
        )
    }

    public static func vision(source: ModelCapabilitySource, confidence: Double, note: String? = nil) -> ModelCapabilities {
        ModelCapabilities(
            inputs: [.text, .image],
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func inferred(
        format: ModelFormat,
        providerConfiguration: ProviderConfiguration?
    ) -> ModelCapabilities {
        switch format {
        case .gguf, .mlx:
            return textOnly(source: .inferred, note: "Local text runner.")
        case .openAICompatible:
            guard let providerConfiguration else {
                return textOnly(source: .unknown, note: "Missing provider configuration.")
            }
            return inferOpenAICompatibleCapabilities(providerConfiguration)
        case .anthropicMessages:
            return textOnly(source: .unknown, note: "Anthropic vision payload is not implemented in Phase 3.")
        case .unknown:
            return textOnly(source: .unknown, note: "Unknown model format.")
        }
    }

    private static func inferOpenAICompatibleCapabilities(_ configuration: ProviderConfiguration) -> ModelCapabilities {
        let modelID = configuration.modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let providerID = configuration.providerID

        let visionFragments = [
            "vision",
            "vl",
            "llava",
            "minicpm-v",
            "internvl",
            "qwen-vl",
            "qwen2-vl",
            "qwen2.5-vl",
            "qwen3-vl",
            "pixtral",
            "moondream",
            "gemma-3",
            "gpt-4o",
            "gpt-4.1",
            "gpt-4.5",
            "o4-mini",
            "gemini-1.5",
            "gemini-2",
            "gemini-2.5"
        ]
        if visionFragments.contains(where: { modelID.contains($0) }) {
            return vision(
                source: .inferred,
                confidence: providerID == .customOpenAICompatible ? 0.55 : 0.7,
                note: "Inferred from provider family or model ID."
            )
        }

        return textOnly(
            source: .unknown,
            note: "No image capability metadata or known vision model pattern."
        )
    }

    private static func normalizedInputs(_ inputs: [ModelInputCapability]) -> [ModelInputCapability] {
        let unique = Set(inputs)
        return ModelInputCapability.allCases.filter { unique.contains($0) }
    }
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
    public var capabilities: ModelCapabilities

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
        providerConfiguration: ProviderConfiguration? = nil,
        capabilities: ModelCapabilities? = nil
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
        self.capabilities = capabilities ?? ModelCapabilities.inferred(
            format: format,
            providerConfiguration: providerConfiguration
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourcePath
        case resolvedPath
        case format
        case sizeClass
        case role
        case contextLength
        case enabled
        case validationState
        case lastErrorMessage
        case providerConfiguration
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourcePath = try container.decode(URL.self, forKey: .sourcePath)
        resolvedPath = try container.decodeIfPresent(URL.self, forKey: .resolvedPath)
        format = try container.decode(ModelFormat.self, forKey: .format)
        sizeClass = try container.decode(String.self, forKey: .sizeClass)
        role = try container.decode(ModelRole.self, forKey: .role)
        contextLength = try container.decode(Int.self, forKey: .contextLength)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        validationState = try container.decodeIfPresent(ModelValidationState.self, forKey: .validationState) ?? .unknown
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        providerConfiguration = try container.decodeIfPresent(ProviderConfiguration.self, forKey: .providerConfiguration)
        capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities)
            ?? ModelCapabilities.inferred(format: format, providerConfiguration: providerConfiguration)
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

    public var supportsImageInput: Bool {
        enabled && capabilities.supportsImage
    }
}

public enum OCRMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case plainText
    case structured
    case extractThenTranslate
    case explainImage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plainText: return "Plain text"
        case .structured: return "Structured"
        case .extractThenTranslate: return "Extract then translate"
        case .explainImage: return "Explain image"
        }
    }
}

public struct OCRPreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var modelID: UUID?
    public var defaultMode: OCRMode
    public var persistHistory: Bool
    public var useModelRecognitionByDefault: Bool
    public var maximumImageBytes: Int
    public var maximumPixelCount: Int

    public init(
        enabled: Bool = true,
        modelID: UUID? = nil,
        defaultMode: OCRMode = .plainText,
        persistHistory: Bool = false,
        useModelRecognitionByDefault: Bool = false,
        maximumImageBytes: Int = 8_000_000,
        maximumPixelCount: Int = 16_000_000
    ) {
        self.enabled = enabled
        self.modelID = modelID
        self.defaultMode = defaultMode
        self.persistHistory = persistHistory
        self.useModelRecognitionByDefault = useModelRecognitionByDefault
        self.maximumImageBytes = maximumImageBytes
        self.maximumPixelCount = maximumPixelCount
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case modelID
        case defaultMode
        case persistHistory
        case useModelRecognitionByDefault
        case maximumImageBytes
        case maximumPixelCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        modelID = try container.decodeIfPresent(UUID.self, forKey: .modelID)
        defaultMode = try container.decodeIfPresent(OCRMode.self, forKey: .defaultMode) ?? .plainText
        persistHistory = try container.decodeIfPresent(Bool.self, forKey: .persistHistory) ?? false
        useModelRecognitionByDefault = try container.decodeIfPresent(Bool.self, forKey: .useModelRecognitionByDefault) ?? false
        maximumImageBytes = max(try container.decodeIfPresent(Int.self, forKey: .maximumImageBytes) ?? 8_000_000, 128_000)
        maximumPixelCount = max(try container.decodeIfPresent(Int.self, forKey: .maximumPixelCount) ?? 16_000_000, 1_000_000)
    }
}

public struct PromptTemplatePair: Codable, Hashable, Sendable {
    public var systemPrompt: String
    public var userPrompt: String

    public init(systemPrompt: String = "", userPrompt: String = "") {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
    }

    private enum CodingKeys: String, CodingKey {
        case systemPrompt
        case userPrompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        userPrompt = try container.decodeIfPresent(String.self, forKey: .userPrompt) ?? ""
    }

    public var hasCustomSystemPrompt: Bool {
        !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasCustomUserPrompt: Bool {
        !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasCustomPrompt: Bool {
        hasCustomSystemPrompt || hasCustomUserPrompt
    }
}

public struct PromptTemplatePreferences: Codable, Hashable, Sendable {
    public var translate: PromptTemplatePair
    public var polish: PromptTemplatePair
    public var summarize: PromptTemplatePair
    public var explain: PromptTemplatePair
    public var extractTodos: PromptTemplatePair
    public var ocrSystemPrompt: String
    public var ocrPlainTextPrompt: String
    public var ocrStructuredPrompt: String
    public var ocrExtractThenTranslatePrompt: String
    public var ocrExplainImagePrompt: String

    public init(
        translate: PromptTemplatePair = PromptTemplatePair(),
        polish: PromptTemplatePair = PromptTemplatePair(),
        summarize: PromptTemplatePair = PromptTemplatePair(),
        explain: PromptTemplatePair = PromptTemplatePair(),
        extractTodos: PromptTemplatePair = PromptTemplatePair(),
        ocrSystemPrompt: String = "",
        ocrPlainTextPrompt: String = "",
        ocrStructuredPrompt: String = "",
        ocrExtractThenTranslatePrompt: String = "",
        ocrExplainImagePrompt: String = ""
    ) {
        self.translate = translate
        self.polish = polish
        self.summarize = summarize
        self.explain = explain
        self.extractTodos = extractTodos
        self.ocrSystemPrompt = ocrSystemPrompt
        self.ocrPlainTextPrompt = ocrPlainTextPrompt
        self.ocrStructuredPrompt = ocrStructuredPrompt
        self.ocrExtractThenTranslatePrompt = ocrExtractThenTranslatePrompt
        self.ocrExplainImagePrompt = ocrExplainImagePrompt
    }

    private enum CodingKeys: String, CodingKey {
        case translate
        case polish
        case summarize
        case explain
        case extractTodos
        case ocrSystemPrompt
        case ocrPlainTextPrompt
        case ocrStructuredPrompt
        case ocrExtractThenTranslatePrompt
        case ocrExplainImagePrompt
    }

    public init(from decoder: Decoder) throws {
        let defaults = PromptTemplatePreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translate = try container.decodeIfPresent(PromptTemplatePair.self, forKey: .translate) ?? defaults.translate
        polish = try container.decodeIfPresent(PromptTemplatePair.self, forKey: .polish) ?? defaults.polish
        summarize = try container.decodeIfPresent(PromptTemplatePair.self, forKey: .summarize) ?? defaults.summarize
        explain = try container.decodeIfPresent(PromptTemplatePair.self, forKey: .explain) ?? defaults.explain
        extractTodos = try container.decodeIfPresent(PromptTemplatePair.self, forKey: .extractTodos) ?? defaults.extractTodos
        ocrSystemPrompt = try container.decodeIfPresent(String.self, forKey: .ocrSystemPrompt) ?? defaults.ocrSystemPrompt
        ocrPlainTextPrompt = try container.decodeIfPresent(String.self, forKey: .ocrPlainTextPrompt) ?? defaults.ocrPlainTextPrompt
        ocrStructuredPrompt = try container.decodeIfPresent(String.self, forKey: .ocrStructuredPrompt) ?? defaults.ocrStructuredPrompt
        ocrExtractThenTranslatePrompt = try container.decodeIfPresent(String.self, forKey: .ocrExtractThenTranslatePrompt) ?? defaults.ocrExtractThenTranslatePrompt
        ocrExplainImagePrompt = try container.decodeIfPresent(String.self, forKey: .ocrExplainImagePrompt) ?? defaults.ocrExplainImagePrompt
    }

    public func textPrompt(for task: TaskKind) -> PromptTemplatePair {
        switch task {
        case .translate:
            return translate
        case .polish:
            return polish
        case .summarize:
            return summarize
        case .explain:
            return explain
        case .extractTodos:
            return extractTodos
        case .webPageTranslate, .ocr:
            return PromptTemplatePair()
        }
    }

    public mutating func setTextPrompt(_ prompt: PromptTemplatePair, for task: TaskKind) {
        switch task {
        case .translate:
            translate = prompt
        case .polish:
            polish = prompt
        case .summarize:
            summarize = prompt
        case .explain:
            explain = prompt
        case .extractTodos:
            extractTodos = prompt
        case .webPageTranslate, .ocr:
            break
        }
    }

    public mutating func setSystemPrompt(_ value: String, for task: TaskKind) {
        var prompt = textPrompt(for: task)
        prompt.systemPrompt = value
        setTextPrompt(prompt, for: task)
    }

    public mutating func setUserPrompt(_ value: String, for task: TaskKind) {
        var prompt = textPrompt(for: task)
        prompt.userPrompt = value
        setTextPrompt(prompt, for: task)
    }

    public func ocrPrompt(for mode: OCRMode) -> String {
        switch mode {
        case .plainText:
            return ocrPlainTextPrompt
        case .structured:
            return ocrStructuredPrompt
        case .extractThenTranslate:
            return ocrExtractThenTranslatePrompt
        case .explainImage:
            return ocrExplainImagePrompt
        }
    }

    public mutating func setOCRPrompt(_ value: String, for mode: OCRMode) {
        switch mode {
        case .plainText:
            ocrPlainTextPrompt = value
        case .structured:
            ocrStructuredPrompt = value
        case .extractThenTranslate:
            ocrExtractThenTranslatePrompt = value
        case .explainImage:
            ocrExplainImagePrompt = value
        }
    }

    public var hasCustomOCRSystemPrompt: Bool {
        !ocrSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func hasCustomOCRPrompt(for mode: OCRMode) -> Bool {
        !ocrPrompt(for: mode).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum SummaryMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case keyPoints
    case oneSentence
    case detailed
    case meetingNotes
    case structured

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keyPoints: return "Key points"
        case .oneSentence: return "One sentence"
        case .detailed: return "Detailed summary"
        case .meetingNotes: return "Meeting notes"
        case .structured: return "Structured summary"
        }
    }
}

public enum ExplanationMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case plain
    case technical
    case errorDiagnosis
    case code
    case background

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: return "Plain explanation"
        case .technical: return "Technical explanation"
        case .errorDiagnosis: return "Error diagnosis"
        case .code: return "Code explanation"
        case .background: return "Background"
        }
    }
}

public enum TodoExtractionMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case actionItems
    case byOwner
    case byPriority
    case byDeadline
    case table

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .actionItems: return "Action items"
        case .byOwner: return "By owner"
        case .byPriority: return "By priority"
        case .byDeadline: return "By deadline"
        case .table: return "Task table"
        }
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

    public static func commandNumber(_ number: Int) -> KeyboardShortcutPreference {
        KeyboardShortcutPreference(
            keyCode: ansiNumberKeyCode(number),
            modifiers: commandModifier
        )
    }

    public static func commandControlNumber(_ number: Int) -> KeyboardShortcutPreference {
        KeyboardShortcutPreference(
            keyCode: ansiNumberKeyCode(number),
            modifiers: commandModifier | controlModifier
        )
    }

    private static func ansiNumberKeyCode(_ number: Int) -> UInt32 {
        switch number {
        case 0: return 29
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        default:
            preconditionFailure("Unsupported ANSI number shortcut: \(number)")
        }
    }

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

public struct QuickActionPopupShortcuts: Codable, Sendable, Hashable {
    public var textMode: KeyboardShortcutPreference
    public var imageMode: KeyboardShortcutPreference
    public var translate: KeyboardShortcutPreference
    public var polish: KeyboardShortcutPreference
    public var summarize: KeyboardShortcutPreference
    public var explain: KeyboardShortcutPreference
    public var extractTodos: KeyboardShortcutPreference
    public var ocrPlainText: KeyboardShortcutPreference
    public var ocrStructured: KeyboardShortcutPreference
    public var ocrExtractThenTranslate: KeyboardShortcutPreference
    public var ocrExplainImage: KeyboardShortcutPreference

    public init(
        textMode: KeyboardShortcutPreference = .commandControlNumber(1),
        imageMode: KeyboardShortcutPreference = .commandControlNumber(2),
        translate: KeyboardShortcutPreference = .commandNumber(1),
        polish: KeyboardShortcutPreference = .commandNumber(2),
        summarize: KeyboardShortcutPreference = .commandNumber(3),
        explain: KeyboardShortcutPreference = .commandNumber(4),
        extractTodos: KeyboardShortcutPreference = .commandNumber(5),
        ocrPlainText: KeyboardShortcutPreference = .commandNumber(1),
        ocrStructured: KeyboardShortcutPreference = .commandNumber(2),
        ocrExtractThenTranslate: KeyboardShortcutPreference = .commandNumber(3),
        ocrExplainImage: KeyboardShortcutPreference = .commandNumber(4)
    ) {
        self.textMode = textMode
        self.imageMode = imageMode
        self.translate = translate
        self.polish = polish
        self.summarize = summarize
        self.explain = explain
        self.extractTodos = extractTodos
        self.ocrPlainText = ocrPlainText
        self.ocrStructured = ocrStructured
        self.ocrExtractThenTranslate = ocrExtractThenTranslate
        self.ocrExplainImage = ocrExplainImage
    }

    private enum CodingKeys: String, CodingKey {
        case textMode
        case imageMode
        case translate
        case polish
        case summarize
        case explain
        case extractTodos
        case ocrPlainText
        case ocrStructured
        case ocrExtractThenTranslate
        case ocrExplainImage
    }

    public init(from decoder: Decoder) throws {
        let defaults = QuickActionPopupShortcuts()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textMode = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .textMode) ?? defaults.textMode
        imageMode = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .imageMode) ?? defaults.imageMode
        translate = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .translate) ?? defaults.translate
        polish = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .polish) ?? defaults.polish
        summarize = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .summarize) ?? defaults.summarize
        explain = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .explain) ?? defaults.explain
        extractTodos = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .extractTodos) ?? defaults.extractTodos
        ocrPlainText = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .ocrPlainText) ?? defaults.ocrPlainText
        ocrStructured = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .ocrStructured) ?? defaults.ocrStructured
        ocrExtractThenTranslate = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .ocrExtractThenTranslate) ?? defaults.ocrExtractThenTranslate
        ocrExplainImage = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .ocrExplainImage) ?? defaults.ocrExplainImage
    }

    public func textTaskShortcut(for task: TaskKind) -> KeyboardShortcutPreference? {
        switch task {
        case .translate:
            return translate
        case .polish:
            return polish
        case .summarize:
            return summarize
        case .explain:
            return explain
        case .extractTodos:
            return extractTodos
        case .webPageTranslate, .ocr:
            return nil
        }
    }

    public mutating func setTextTaskShortcut(_ shortcut: KeyboardShortcutPreference, for task: TaskKind) {
        switch task {
        case .translate:
            translate = shortcut
        case .polish:
            polish = shortcut
        case .summarize:
            summarize = shortcut
        case .explain:
            explain = shortcut
        case .extractTodos:
            extractTodos = shortcut
        case .webPageTranslate, .ocr:
            break
        }
    }

    public func textTask(matching shortcut: KeyboardShortcutPreference) -> TaskKind? {
        TaskKind.interactiveCases.first { textTaskShortcut(for: $0) == shortcut }
    }

    public func ocrModeShortcut(for mode: OCRMode) -> KeyboardShortcutPreference {
        switch mode {
        case .plainText:
            return ocrPlainText
        case .structured:
            return ocrStructured
        case .extractThenTranslate:
            return ocrExtractThenTranslate
        case .explainImage:
            return ocrExplainImage
        }
    }

    public mutating func setOCRModeShortcut(_ shortcut: KeyboardShortcutPreference, for mode: OCRMode) {
        switch mode {
        case .plainText:
            ocrPlainText = shortcut
        case .structured:
            ocrStructured = shortcut
        case .extractThenTranslate:
            ocrExtractThenTranslate = shortcut
        case .explainImage:
            ocrExplainImage = shortcut
        }
    }

    public func ocrMode(matching shortcut: KeyboardShortcutPreference) -> OCRMode? {
        OCRMode.allCases.first { ocrModeShortcut(for: $0) == shortcut }
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
    public var defaultSummaryMode: SummaryMode
    public var defaultExplanationMode: ExplanationMode
    public var defaultTodoExtractionMode: TodoExtractionMode
    public var recentHistoryLimit: Int
    public var webPageTranslation: WebPageTranslationPreferences
    public var ocr: OCRPreferences
    public var promptTemplates: PromptTemplatePreferences
    public var quickActionShortcut: KeyboardShortcutPreference
    public var quickActionWithoutSelectionShortcut: KeyboardShortcutPreference
    public var quickActionPopupShortcuts: QuickActionPopupShortcuts

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
        defaultSummaryMode: SummaryMode = .keyPoints,
        defaultExplanationMode: ExplanationMode = .plain,
        defaultTodoExtractionMode: TodoExtractionMode = .actionItems,
        recentHistoryLimit: Int = 20,
        webPageTranslation: WebPageTranslationPreferences = WebPageTranslationPreferences(),
        ocr: OCRPreferences = OCRPreferences(),
        promptTemplates: PromptTemplatePreferences = PromptTemplatePreferences(),
        quickActionShortcut: KeyboardShortcutPreference = .optionSpace,
        quickActionWithoutSelectionShortcut: KeyboardShortcutPreference = .optionShiftSpace,
        quickActionPopupShortcuts: QuickActionPopupShortcuts = QuickActionPopupShortcuts()
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
        self.defaultSummaryMode = defaultSummaryMode
        self.defaultExplanationMode = defaultExplanationMode
        self.defaultTodoExtractionMode = defaultTodoExtractionMode
        self.recentHistoryLimit = recentHistoryLimit
        self.webPageTranslation = webPageTranslation
        self.ocr = ocr
        self.promptTemplates = promptTemplates
        self.quickActionShortcut = quickActionShortcut
        self.quickActionWithoutSelectionShortcut = quickActionWithoutSelectionShortcut
        self.quickActionPopupShortcuts = quickActionPopupShortcuts
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
        case defaultSummaryMode
        case defaultExplanationMode
        case defaultTodoExtractionMode
        case recentHistoryLimit
        case webPageTranslation
        case ocr
        case promptTemplates
        case quickActionShortcut
        case quickActionWithoutSelectionShortcut
        case quickActionPopupShortcuts
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
        defaultSummaryMode = (try? container.decodeIfPresent(SummaryMode.self, forKey: .defaultSummaryMode)) ?? .keyPoints
        defaultExplanationMode = (try? container.decodeIfPresent(ExplanationMode.self, forKey: .defaultExplanationMode)) ?? .plain
        defaultTodoExtractionMode = (try? container.decodeIfPresent(TodoExtractionMode.self, forKey: .defaultTodoExtractionMode)) ?? .actionItems
        recentHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .recentHistoryLimit) ?? 20
        webPageTranslation = try container.decodeIfPresent(WebPageTranslationPreferences.self, forKey: .webPageTranslation) ?? WebPageTranslationPreferences()
        ocr = try container.decodeIfPresent(OCRPreferences.self, forKey: .ocr) ?? OCRPreferences()
        promptTemplates = try container.decodeIfPresent(PromptTemplatePreferences.self, forKey: .promptTemplates) ?? PromptTemplatePreferences()
        quickActionShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .quickActionShortcut) ?? .optionSpace
        quickActionWithoutSelectionShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .quickActionWithoutSelectionShortcut) ?? .optionShiftSpace
        quickActionPopupShortcuts = try container.decodeIfPresent(QuickActionPopupShortcuts.self, forKey: .quickActionPopupShortcuts) ?? QuickActionPopupShortcuts()
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
        try container.encode(defaultSummaryMode, forKey: .defaultSummaryMode)
        try container.encode(defaultExplanationMode, forKey: .defaultExplanationMode)
        try container.encode(defaultTodoExtractionMode, forKey: .defaultTodoExtractionMode)
        try container.encode(recentHistoryLimit, forKey: .recentHistoryLimit)
        try container.encode(webPageTranslation, forKey: .webPageTranslation)
        try container.encode(ocr, forKey: .ocr)
        try container.encode(promptTemplates, forKey: .promptTemplates)
        try container.encode(quickActionShortcut, forKey: .quickActionShortcut)
        try container.encode(quickActionWithoutSelectionShortcut, forKey: .quickActionWithoutSelectionShortcut)
        try container.encode(quickActionPopupShortcuts, forKey: .quickActionPopupShortcuts)
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
    case ocr

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
        case .ocr: return "OCR Image"
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
            case .ocr: return "图片识别"
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
    public var summaryMode: SummaryMode?
    public var explanationMode: ExplanationMode?
    public var todoExtractionMode: TodoExtractionMode?

    public init(
        task: TaskKind,
        inputText: String,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        polishStyle: String? = nil,
        summaryMode: SummaryMode? = nil,
        explanationMode: ExplanationMode? = nil,
        todoExtractionMode: TodoExtractionMode? = nil
    ) {
        self.task = task
        self.inputText = inputText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.polishStyle = polishStyle
        self.summaryMode = summaryMode
        self.explanationMode = explanationMode
        self.todoExtractionMode = todoExtractionMode
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
