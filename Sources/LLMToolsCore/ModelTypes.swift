import Foundation

public enum ModelFormat: String, Codable, Sendable, CaseIterable {
    case gguf
    case mlx
    case openAICompatible = "openai-compatible"
    case anthropicMessages = "anthropic-messages"
    case speech
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

public enum TranslationEngineID: String, Codable, Sendable, CaseIterable, Hashable {
    case llm
    case ctranslate2
    case argos
    case customCommand
}

public struct LanguagePair: Codable, Hashable, Sendable {
    public var source: String
    public var target: String

    public init(source: String, target: String) {
        self.source = LanguageCodeNormalizer.normalizedBCP47(source) ?? source
        self.target = LanguageCodeNormalizer.normalizedBCP47(target) ?? target
    }
}

public enum LanguageIDModelVariant: String, Codable, Sendable, CaseIterable, Hashable {
    case ftz
    case bin
    case customCommand
}

public enum ModelInputCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case text
    case image
    case speech
    case languageID
    case speakerDiarization
    case fastTranslation
}

public enum ModelCapabilitySource: String, Codable, Sendable, CaseIterable, Hashable {
    case detected
    case inferred
    case probePassed
    case failedProbe
    case manual
    case unknown
}

public struct LanguageIDModelCapabilities: Codable, Hashable, Sendable {
    public var modelVariant: LanguageIDModelVariant
    public var supportedLanguages: [String]
    public var latencyMillisecondsPerKB: Int?
    public var requiresLocalSidecar: Bool
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?

    public init(
        modelVariant: LanguageIDModelVariant = .ftz,
        supportedLanguages: [String] = [],
        latencyMillisecondsPerKB: Int? = nil,
        requiresLocalSidecar: Bool = true,
        source: ModelCapabilitySource = .unknown,
        confidence: Double = 0.5,
        note: String? = nil,
        lastCheckedAt: Date? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.modelVariant = modelVariant
        self.supportedLanguages = Self.normalizedLanguages(supportedLanguages)
        self.latencyMillisecondsPerKB = latencyMillisecondsPerKB.map { max(0, $0) }
        self.requiresLocalSidecar = requiresLocalSidecar
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.note = note
        self.lastCheckedAt = lastCheckedAt
        self.lastFailureMessage = lastFailureMessage
    }

    private static func normalizedLanguages(_ languages: [String]) -> [String] {
        Array(Set(languages.compactMap { LanguageCodeNormalizer.normalizedBCP47($0) })).sorted()
    }
}

public struct SpeakerDiarizationModelCapabilities: Codable, Hashable, Sendable {
    public var supportsFile: Bool
    public var supportsRealtime: Bool
    public var requiresUserToken: Bool
    public var requiresLocalSidecar: Bool
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?

    public init(
        supportsFile: Bool = true,
        supportsRealtime: Bool = false,
        requiresUserToken: Bool = false,
        requiresLocalSidecar: Bool = true,
        source: ModelCapabilitySource = .unknown,
        confidence: Double = 0.5,
        note: String? = nil,
        lastCheckedAt: Date? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.supportsFile = supportsFile
        self.supportsRealtime = supportsRealtime
        self.requiresUserToken = requiresUserToken
        self.requiresLocalSidecar = requiresLocalSidecar
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.note = note
        self.lastCheckedAt = lastCheckedAt
        self.lastFailureMessage = lastFailureMessage
    }
}

public struct FastTranslationModelCapabilities: Codable, Hashable, Sendable {
    public var engineID: TranslationEngineID
    public var modelID: String?
    public var supportedPairs: [LanguagePair]
    public var supportsBatching: Bool
    public var requiresLocalSidecar: Bool
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?

    public init(
        engineID: TranslationEngineID = .ctranslate2,
        modelID: String? = nil,
        supportedPairs: [LanguagePair] = [],
        supportsBatching: Bool = true,
        requiresLocalSidecar: Bool = true,
        source: ModelCapabilitySource = .unknown,
        confidence: Double = 0.5,
        note: String? = nil,
        lastCheckedAt: Date? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.engineID = engineID
        self.modelID = Self.normalizedOptionalString(modelID)
        self.supportedPairs = Self.normalizedPairs(supportedPairs)
        self.supportsBatching = supportsBatching
        self.requiresLocalSidecar = requiresLocalSidecar
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.note = note
        self.lastCheckedAt = lastCheckedAt
        self.lastFailureMessage = lastFailureMessage
    }

    public func supports(_ pair: LanguagePair) -> Bool {
        supportedPairs.contains(pair)
    }

    private static func normalizedPairs(_ pairs: [LanguagePair]) -> [LanguagePair] {
        Array(Set(pairs)).sorted {
            if $0.source == $1.source {
                return $0.target < $1.target
            }
            return $0.source < $1.source
        }
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

public struct ModelCapabilities: Codable, Hashable, Sendable {
    public var inputs: [ModelInputCapability]
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?
    public var speech: SpeechModelCapabilities?
    public var languageID: LanguageIDModelCapabilities?
    public var speakerDiarization: SpeakerDiarizationModelCapabilities?
    public var fastTranslation: FastTranslationModelCapabilities?

    public init(
        inputs: [ModelInputCapability] = [.text],
        source: ModelCapabilitySource = .unknown,
        confidence: Double = 0.5,
        note: String? = nil,
        lastCheckedAt: Date? = nil,
        lastFailureMessage: String? = nil,
        speech: SpeechModelCapabilities? = nil,
        languageID: LanguageIDModelCapabilities? = nil,
        speakerDiarization: SpeakerDiarizationModelCapabilities? = nil,
        fastTranslation: FastTranslationModelCapabilities? = nil
    ) {
        var normalizedInputs = inputs
        if speech != nil, !normalizedInputs.contains(.speech) {
            normalizedInputs.append(.speech)
        }
        if languageID != nil, !normalizedInputs.contains(.languageID) {
            normalizedInputs.append(.languageID)
        }
        if speakerDiarization != nil, !normalizedInputs.contains(.speakerDiarization) {
            normalizedInputs.append(.speakerDiarization)
        }
        if fastTranslation != nil, !normalizedInputs.contains(.fastTranslation) {
            normalizedInputs.append(.fastTranslation)
        }
        self.inputs = ModelCapabilities.normalizedInputs(normalizedInputs)
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.note = note
        self.lastCheckedAt = lastCheckedAt
        self.lastFailureMessage = lastFailureMessage
        self.speech = speech
        self.languageID = languageID
        self.speakerDiarization = speakerDiarization
        self.fastTranslation = fastTranslation
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

    public var supportsSpeech: Bool {
        supports(.speech) && speech?.isSelectableASRBackend == true
    }

    public var supportsLanguageID: Bool {
        supports(.languageID)
    }

    public var supportsSpeakerDiarization: Bool {
        supports(.speakerDiarization)
    }

    public var supportsFastTranslation: Bool {
        supports(.fastTranslation)
    }

    public var supportsRealtimeSpeech: Bool {
        speech?.isSelectableASRBackend == true && speech?.supports(.realtime) == true
    }

    public var supportsFileSpeech: Bool {
        speech?.isSelectableASRBackend == true
            && (speech?.supports(.fileOnly) == true || speech?.supports(.realtime) == true)
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

    public static func speech(
        _ speech: SpeechModelCapabilities,
        note: String? = nil
    ) -> ModelCapabilities {
        ModelCapabilities(
            inputs: [.speech],
            source: speech.source,
            confidence: speech.confidence,
            note: note ?? speech.note,
            lastCheckedAt: speech.lastCheckedAt,
            lastFailureMessage: speech.lastFailureMessage,
            speech: speech
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
        case .speech:
            return textOnly(source: .unknown, note: "Speech model metadata is required.")
        case .unknown:
            return textOnly(source: .unknown, note: "Unknown model format.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case inputs
        case source
        case confidence
        case note
        case lastCheckedAt
        case lastFailureMessage
        case speech
        case languageID
        case speakerDiarization
        case fastTranslation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSpeech = try container.decodeIfPresent(SpeechModelCapabilities.self, forKey: .speech)
        let decodedLanguageID = try container.decodeIfPresent(LanguageIDModelCapabilities.self, forKey: .languageID)
        let decodedSpeakerDiarization = try container.decodeIfPresent(SpeakerDiarizationModelCapabilities.self, forKey: .speakerDiarization)
        let decodedFastTranslation = try container.decodeIfPresent(FastTranslationModelCapabilities.self, forKey: .fastTranslation)
        var decodedInputs = try container.decodeIfPresent([ModelInputCapability].self, forKey: .inputs) ?? [.text]
        if decodedSpeech != nil, !decodedInputs.contains(.speech) {
            decodedInputs.append(.speech)
        }
        if decodedLanguageID != nil, !decodedInputs.contains(.languageID) {
            decodedInputs.append(.languageID)
        }
        if decodedSpeakerDiarization != nil, !decodedInputs.contains(.speakerDiarization) {
            decodedInputs.append(.speakerDiarization)
        }
        if decodedFastTranslation != nil, !decodedInputs.contains(.fastTranslation) {
            decodedInputs.append(.fastTranslation)
        }
        inputs = ModelCapabilities.normalizedInputs(decodedInputs)
        source = try container.decodeIfPresent(ModelCapabilitySource.self, forKey: .source) ?? .unknown
        confidence = min(max(try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5, 0), 1)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastFailureMessage = try container.decodeIfPresent(String.self, forKey: .lastFailureMessage)
        speech = decodedSpeech
        languageID = decodedLanguageID
        speakerDiarization = decodedSpeakerDiarization
        fastTranslation = decodedFastTranslation
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

    public static let commandOptionControlL = KeyboardShortcutPreference(
        keyCode: 37,
        modifiers: KeyboardShortcutPreference.commandModifier | KeyboardShortcutPreference.optionModifier | KeyboardShortcutPreference.controlModifier
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
    public var mediaMode: KeyboardShortcutPreference
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
        mediaMode: KeyboardShortcutPreference = .commandControlNumber(3),
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
        self.mediaMode = mediaMode
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
        case mediaMode
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
        mediaMode = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .mediaMode) ?? defaults.mediaMode
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

public struct LanguageRoutingPreferences: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var modelVariant: LanguageIDModelVariant
    public var ftzModelPath: String
    public var binModelPath: String
    public var shortTextMinimumCharactersLatin: Int
    public var shortTextMinimumCharactersCJK: Int
    public var lowConfidenceThreshold: Double
    public var ocrConfidenceBoost: Double
    public var useForTextTasks: Bool
    public var useForWebpage: Bool
    public var useForOCR: Bool
    public var useForSubtitles: Bool
    public var commandTemplate: String

    public init(
        enabled: Bool = false,
        modelVariant: LanguageIDModelVariant = .ftz,
        ftzModelPath: String = "",
        binModelPath: String = "",
        shortTextMinimumCharactersLatin: Int = 20,
        shortTextMinimumCharactersCJK: Int = 3,
        lowConfidenceThreshold: Double = 0.65,
        ocrConfidenceBoost: Double = 0.1,
        useForTextTasks: Bool = false,
        useForWebpage: Bool = false,
        useForOCR: Bool = false,
        useForSubtitles: Bool = false,
        commandTemplate: String = ""
    ) {
        self.enabled = enabled
        self.modelVariant = modelVariant
        self.ftzModelPath = Self.normalizedCommandTemplate(ftzModelPath)
        self.binModelPath = Self.normalizedCommandTemplate(binModelPath)
        self.shortTextMinimumCharactersLatin = max(1, shortTextMinimumCharactersLatin)
        self.shortTextMinimumCharactersCJK = max(1, shortTextMinimumCharactersCJK)
        self.lowConfidenceThreshold = Self.normalizedConfidence(lowConfidenceThreshold)
        self.ocrConfidenceBoost = Self.normalizedConfidence(ocrConfidenceBoost)
        self.useForTextTasks = useForTextTasks
        self.useForWebpage = useForWebpage
        self.useForOCR = useForOCR
        self.useForSubtitles = useForSubtitles
        self.commandTemplate = Self.normalizedCommandTemplate(commandTemplate)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case modelVariant
        case ftzModelPath
        case binModelPath
        case shortTextMinimumCharactersLatin
        case shortTextMinimumCharactersCJK
        case lowConfidenceThreshold
        case ocrConfidenceBoost
        case useForTextTasks
        case useForWebpage
        case useForOCR
        case useForSubtitles
        case commandTemplate
    }

    public init(from decoder: Decoder) throws {
        let defaults = LanguageRoutingPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        modelVariant = try container.decodeIfPresent(LanguageIDModelVariant.self, forKey: .modelVariant) ?? defaults.modelVariant
        ftzModelPath = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .ftzModelPath) ?? defaults.ftzModelPath
        )
        binModelPath = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .binModelPath) ?? defaults.binModelPath
        )
        shortTextMinimumCharactersLatin = max(
            1,
            try container.decodeIfPresent(Int.self, forKey: .shortTextMinimumCharactersLatin)
                ?? defaults.shortTextMinimumCharactersLatin
        )
        shortTextMinimumCharactersCJK = max(
            1,
            try container.decodeIfPresent(Int.self, forKey: .shortTextMinimumCharactersCJK)
                ?? defaults.shortTextMinimumCharactersCJK
        )
        lowConfidenceThreshold = Self.normalizedConfidence(
            try container.decodeIfPresent(Double.self, forKey: .lowConfidenceThreshold) ?? defaults.lowConfidenceThreshold
        )
        ocrConfidenceBoost = Self.normalizedConfidence(
            try container.decodeIfPresent(Double.self, forKey: .ocrConfidenceBoost) ?? defaults.ocrConfidenceBoost
        )
        useForTextTasks = try container.decodeIfPresent(Bool.self, forKey: .useForTextTasks) ?? defaults.useForTextTasks
        useForWebpage = try container.decodeIfPresent(Bool.self, forKey: .useForWebpage) ?? defaults.useForWebpage
        useForOCR = try container.decodeIfPresent(Bool.self, forKey: .useForOCR) ?? defaults.useForOCR
        useForSubtitles = try container.decodeIfPresent(Bool.self, forKey: .useForSubtitles) ?? defaults.useForSubtitles
        commandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .commandTemplate) ?? defaults.commandTemplate
        )
    }

    public func shouldSkipDetection(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        let containsCJK = trimmed.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
                || (0x3040...0x30FF).contains(Int(scalar.value))
                || (0xAC00...0xD7AF).contains(Int(scalar.value))
        }
        let minimum = containsCJK ? shortTextMinimumCharactersCJK : shortTextMinimumCharactersLatin
        return trimmed.count < minimum
    }

    private static func normalizedConfidence(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    private static func normalizedCommandTemplate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SpeakerDiarizationPreferences: Codable, Sendable, Hashable {
    public static let defaultModelIdentifier = "pyannote/speaker-diarization-3.1"

    public var enabledForFileSubtitles: Bool
    public var enabledForLiveSubtitles: Bool
    public var modelIdentifier: String
    public var cacheDirectory: String
    public var commandTemplate: String
    public var persistSpeakerEmbeddings: Bool

    public init(
        enabledForFileSubtitles: Bool = false,
        enabledForLiveSubtitles: Bool = false,
        modelIdentifier: String = Self.defaultModelIdentifier,
        cacheDirectory: String = "",
        commandTemplate: String = "",
        persistSpeakerEmbeddings: Bool = false
    ) {
        self.enabledForFileSubtitles = enabledForFileSubtitles
        self.enabledForLiveSubtitles = false
        self.modelIdentifier = Self.normalizedModelIdentifier(modelIdentifier)
        self.cacheDirectory = Self.normalizedCommandTemplate(cacheDirectory)
        self.commandTemplate = Self.normalizedCommandTemplate(commandTemplate)
        self.persistSpeakerEmbeddings = persistSpeakerEmbeddings
    }

    private enum CodingKeys: String, CodingKey {
        case enabledForFileSubtitles
        case enabledForLiveSubtitles
        case modelIdentifier
        case cacheDirectory
        case commandTemplate
        case persistSpeakerEmbeddings
    }

    public init(from decoder: Decoder) throws {
        let defaults = SpeakerDiarizationPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledForFileSubtitles = try container.decodeIfPresent(Bool.self, forKey: .enabledForFileSubtitles)
            ?? defaults.enabledForFileSubtitles
        _ = try container.decodeIfPresent(Bool.self, forKey: .enabledForLiveSubtitles)
        enabledForLiveSubtitles = false
        modelIdentifier = Self.normalizedModelIdentifier(
            try container.decodeIfPresent(String.self, forKey: .modelIdentifier) ?? defaults.modelIdentifier
        )
        cacheDirectory = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .cacheDirectory) ?? defaults.cacheDirectory
        )
        commandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .commandTemplate) ?? defaults.commandTemplate
        )
        persistSpeakerEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .persistSpeakerEmbeddings)
            ?? defaults.persistSpeakerEmbeddings
    }

    private static func normalizedCommandTemplate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedModelIdentifier(_ value: String) -> String {
        normalizedCommandTemplate(value).isEmpty ? Self.defaultModelIdentifier : normalizedCommandTemplate(value)
    }
}

public enum FastTranslationSurfaceEngine: String, Codable, Sendable, CaseIterable, Hashable {
    case auto
    case llm
    case fastMT
}

public enum FastTranslationFallbackPolicy: String, Codable, Sendable, CaseIterable, Hashable {
    case showError
    case fallbackToLLM
}

public enum FastTranslationModelVariant: String, Codable, Sendable, CaseIterable, Hashable {
    case opusMTEnZh
    case nllb200Distilled600M
}

public struct FastTranslationCommandTemplates: Codable, Sendable, Hashable {
    public var ctranslate2: String
    public var argos: String
    public var generic: String

    public init(
        ctranslate2: String = "{python} {sidecar} --engine ctranslate2 --model {model_ct2}",
        argos: String = "{python} {sidecar} --engine argos",
        generic: String = ""
    ) {
        self.ctranslate2 = Self.normalizedCommandTemplate(ctranslate2)
        self.argos = Self.normalizedCommandTemplate(argos)
        self.generic = Self.normalizedCommandTemplate(generic)
    }

    private enum CodingKeys: String, CodingKey {
        case ctranslate2
        case argos
        case generic
    }

    public init(from decoder: Decoder) throws {
        let defaults = FastTranslationCommandTemplates()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ctranslate2 = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .ctranslate2) ?? defaults.ctranslate2
        )
        argos = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .argos) ?? defaults.argos
        )
        generic = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .generic) ?? defaults.generic
        )
    }

    public func template(for engineID: TranslationEngineID) -> String? {
        let template: String
        switch engineID {
        case .ctranslate2:
            template = ctranslate2
        case .argos:
            template = argos
        case .customCommand:
            template = generic
        case .llm:
            template = ""
        }
        return template.isEmpty ? nil : template
    }

    private static func normalizedCommandTemplate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct FastTranslationPreferences: Codable, Sendable, Hashable {
    public var subtitleEngine: FastTranslationSurfaceEngine
    public var webpageEngine: FastTranslationSurfaceEngine
    public var textEngine: FastTranslationSurfaceEngine
    public var modelVariant: FastTranslationModelVariant
    public var opusMTEnZhCT2ModelPath: String
    public var nllb200Distilled600MCT2ModelPath: String
    public var fallbackPolicy: FastTranslationFallbackPolicy
    public var commandTemplates: FastTranslationCommandTemplates
    public var maxConcurrentBatches: Int
    public var forceLLM: Bool

    public init(
        subtitleEngine: FastTranslationSurfaceEngine = .llm,
        webpageEngine: FastTranslationSurfaceEngine = .llm,
        textEngine: FastTranslationSurfaceEngine = .llm,
        modelVariant: FastTranslationModelVariant = .nllb200Distilled600M,
        opusMTEnZhCT2ModelPath: String = "",
        nllb200Distilled600MCT2ModelPath: String = "",
        fallbackPolicy: FastTranslationFallbackPolicy = .fallbackToLLM,
        commandTemplates: FastTranslationCommandTemplates = FastTranslationCommandTemplates(),
        maxConcurrentBatches: Int = 1,
        forceLLM: Bool = false
    ) {
        self.subtitleEngine = subtitleEngine
        self.webpageEngine = webpageEngine
        self.textEngine = textEngine
        self.modelVariant = modelVariant
        self.opusMTEnZhCT2ModelPath = Self.normalizedPath(opusMTEnZhCT2ModelPath)
        self.nllb200Distilled600MCT2ModelPath = Self.normalizedPath(nllb200Distilled600MCT2ModelPath)
        self.fallbackPolicy = fallbackPolicy
        self.commandTemplates = commandTemplates
        self.maxConcurrentBatches = Self.normalizedMaxConcurrentBatches(maxConcurrentBatches)
        self.forceLLM = forceLLM
    }

    private enum CodingKeys: String, CodingKey {
        case subtitleEngine
        case webpageEngine
        case textEngine
        case modelVariant
        case opusMTEnZhCT2ModelPath
        case nllb200Distilled600MCT2ModelPath
        case fallbackPolicy
        case commandTemplates
        case maxConcurrentBatches
        case forceLLM
    }

    public init(from decoder: Decoder) throws {
        let defaults = FastTranslationPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitleEngine = try container.decodeIfPresent(FastTranslationSurfaceEngine.self, forKey: .subtitleEngine)
            ?? defaults.subtitleEngine
        webpageEngine = try container.decodeIfPresent(FastTranslationSurfaceEngine.self, forKey: .webpageEngine)
            ?? defaults.webpageEngine
        textEngine = try container.decodeIfPresent(FastTranslationSurfaceEngine.self, forKey: .textEngine)
            ?? defaults.textEngine
        modelVariant = try container.decodeIfPresent(FastTranslationModelVariant.self, forKey: .modelVariant)
            ?? defaults.modelVariant
        opusMTEnZhCT2ModelPath = Self.normalizedPath(
            try container.decodeIfPresent(String.self, forKey: .opusMTEnZhCT2ModelPath) ?? defaults.opusMTEnZhCT2ModelPath
        )
        nllb200Distilled600MCT2ModelPath = Self.normalizedPath(
            try container.decodeIfPresent(String.self, forKey: .nllb200Distilled600MCT2ModelPath) ?? defaults.nllb200Distilled600MCT2ModelPath
        )
        fallbackPolicy = try container.decodeIfPresent(FastTranslationFallbackPolicy.self, forKey: .fallbackPolicy)
            ?? defaults.fallbackPolicy
        commandTemplates = try container.decodeIfPresent(FastTranslationCommandTemplates.self, forKey: .commandTemplates)
            ?? defaults.commandTemplates
        maxConcurrentBatches = Self.normalizedMaxConcurrentBatches(
            try container.decodeIfPresent(Int.self, forKey: .maxConcurrentBatches) ?? defaults.maxConcurrentBatches
        )
        forceLLM = try container.decodeIfPresent(Bool.self, forKey: .forceLLM) ?? defaults.forceLLM
    }

    public func engine(for task: TaskKind) -> FastTranslationSurfaceEngine {
        guard !forceLLM else {
            return .llm
        }
        switch task {
        case .webPageTranslate:
            return webpageEngine
        case .translate:
            return textEngine
        case .polish, .summarize, .explain, .extractTodos, .ocr:
            return .llm
        }
    }

    public func engineForSubtitles() -> FastTranslationSurfaceEngine {
        forceLLM ? .llm : subtitleEngine
    }

    private static func normalizedMaxConcurrentBatches(_ value: Int) -> Int {
        min(max(value, 1), 8)
    }

    private static func normalizedPath(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
    public var defaultTranslationQuality: WebPageTranslationQualityMode
    public var defaultPolishStyle: String
    public var defaultSummaryMode: SummaryMode
    public var defaultExplanationMode: ExplanationMode
    public var defaultTodoExtractionMode: TodoExtractionMode
    public var recentHistoryLimit: Int
    public var webPageTranslation: WebPageTranslationPreferences
    public var ocr: OCRPreferences
    public var mediaSubtitles: MediaSubtitlePreferences
    public var languageRouting: LanguageRoutingPreferences
    public var speakerDiarization: SpeakerDiarizationPreferences
    public var fastTranslation: FastTranslationPreferences
    public var promptTemplates: PromptTemplatePreferences
    public var quickActionShortcut: KeyboardShortcutPreference
    public var quickActionWithoutSelectionShortcut: KeyboardShortcutPreference
    public var liveSubtitleShortcut: KeyboardShortcutPreference
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
        defaultTranslationQuality: WebPageTranslationQualityMode = .natural,
        defaultPolishStyle: String = "natural",
        defaultSummaryMode: SummaryMode = .keyPoints,
        defaultExplanationMode: ExplanationMode = .plain,
        defaultTodoExtractionMode: TodoExtractionMode = .actionItems,
        recentHistoryLimit: Int = 20,
        webPageTranslation: WebPageTranslationPreferences = WebPageTranslationPreferences(),
        ocr: OCRPreferences = OCRPreferences(),
        mediaSubtitles: MediaSubtitlePreferences = MediaSubtitlePreferences(),
        languageRouting: LanguageRoutingPreferences = LanguageRoutingPreferences(),
        speakerDiarization: SpeakerDiarizationPreferences = SpeakerDiarizationPreferences(),
        fastTranslation: FastTranslationPreferences = FastTranslationPreferences(),
        promptTemplates: PromptTemplatePreferences = PromptTemplatePreferences(),
        quickActionShortcut: KeyboardShortcutPreference = .optionSpace,
        quickActionWithoutSelectionShortcut: KeyboardShortcutPreference = .optionShiftSpace,
        liveSubtitleShortcut: KeyboardShortcutPreference = .commandOptionControlL,
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
        self.defaultTranslationQuality = defaultTranslationQuality
        self.defaultPolishStyle = defaultPolishStyle
        self.defaultSummaryMode = defaultSummaryMode
        self.defaultExplanationMode = defaultExplanationMode
        self.defaultTodoExtractionMode = defaultTodoExtractionMode
        self.recentHistoryLimit = recentHistoryLimit
        self.webPageTranslation = webPageTranslation
        self.ocr = ocr
        self.mediaSubtitles = mediaSubtitles
        self.languageRouting = languageRouting
        self.speakerDiarization = speakerDiarization
        self.fastTranslation = fastTranslation
        self.promptTemplates = promptTemplates
        self.quickActionShortcut = quickActionShortcut
        self.quickActionWithoutSelectionShortcut = quickActionWithoutSelectionShortcut
        self.liveSubtitleShortcut = liveSubtitleShortcut
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
        case defaultTranslationQuality
        case defaultPolishStyle
        case defaultSummaryMode
        case defaultExplanationMode
        case defaultTodoExtractionMode
        case recentHistoryLimit
        case webPageTranslation
        case ocr
        case mediaSubtitles
        case languageRouting
        case speakerDiarization
        case fastTranslation
        case promptTemplates
        case quickActionShortcut
        case quickActionWithoutSelectionShortcut
        case liveSubtitleShortcut
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
        defaultTranslationQuality = try container.decodeIfPresent(WebPageTranslationQualityMode.self, forKey: .defaultTranslationQuality) ?? .natural
        defaultPolishStyle = try container.decodeIfPresent(String.self, forKey: .defaultPolishStyle) ?? "natural"
        defaultSummaryMode = (try? container.decodeIfPresent(SummaryMode.self, forKey: .defaultSummaryMode)) ?? .keyPoints
        defaultExplanationMode = (try? container.decodeIfPresent(ExplanationMode.self, forKey: .defaultExplanationMode)) ?? .plain
        defaultTodoExtractionMode = (try? container.decodeIfPresent(TodoExtractionMode.self, forKey: .defaultTodoExtractionMode)) ?? .actionItems
        recentHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .recentHistoryLimit) ?? 20
        webPageTranslation = try container.decodeIfPresent(WebPageTranslationPreferences.self, forKey: .webPageTranslation) ?? WebPageTranslationPreferences()
        ocr = try container.decodeIfPresent(OCRPreferences.self, forKey: .ocr) ?? OCRPreferences()
        mediaSubtitles = try container.decodeIfPresent(MediaSubtitlePreferences.self, forKey: .mediaSubtitles) ?? MediaSubtitlePreferences()
        languageRouting = try container.decodeIfPresent(LanguageRoutingPreferences.self, forKey: .languageRouting) ?? LanguageRoutingPreferences()
        speakerDiarization = try container.decodeIfPresent(SpeakerDiarizationPreferences.self, forKey: .speakerDiarization) ?? SpeakerDiarizationPreferences()
        fastTranslation = try container.decodeIfPresent(FastTranslationPreferences.self, forKey: .fastTranslation) ?? FastTranslationPreferences()
        promptTemplates = try container.decodeIfPresent(PromptTemplatePreferences.self, forKey: .promptTemplates) ?? PromptTemplatePreferences()
        quickActionShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .quickActionShortcut) ?? .optionSpace
        quickActionWithoutSelectionShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .quickActionWithoutSelectionShortcut) ?? .optionShiftSpace
        liveSubtitleShortcut = try container.decodeIfPresent(KeyboardShortcutPreference.self, forKey: .liveSubtitleShortcut) ?? .commandOptionControlL
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
        try container.encode(defaultTranslationQuality, forKey: .defaultTranslationQuality)
        try container.encode(defaultPolishStyle, forKey: .defaultPolishStyle)
        try container.encode(defaultSummaryMode, forKey: .defaultSummaryMode)
        try container.encode(defaultExplanationMode, forKey: .defaultExplanationMode)
        try container.encode(defaultTodoExtractionMode, forKey: .defaultTodoExtractionMode)
        try container.encode(recentHistoryLimit, forKey: .recentHistoryLimit)
        try container.encode(webPageTranslation, forKey: .webPageTranslation)
        try container.encode(ocr, forKey: .ocr)
        try container.encode(mediaSubtitles, forKey: .mediaSubtitles)
        try container.encode(languageRouting, forKey: .languageRouting)
        try container.encode(speakerDiarization, forKey: .speakerDiarization)
        try container.encode(fastTranslation, forKey: .fastTranslation)
        try container.encode(promptTemplates, forKey: .promptTemplates)
        try container.encode(quickActionShortcut, forKey: .quickActionShortcut)
        try container.encode(quickActionWithoutSelectionShortcut, forKey: .quickActionWithoutSelectionShortcut)
        try container.encode(liveSubtitleShortcut, forKey: .liveSubtitleShortcut)
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
    public var translationQuality: WebPageTranslationQualityMode?
    public var polishStyle: String?
    public var summaryMode: SummaryMode?
    public var explanationMode: ExplanationMode?
    public var todoExtractionMode: TodoExtractionMode?

    public init(
        task: TaskKind,
        inputText: String,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        translationQuality: WebPageTranslationQualityMode? = nil,
        polishStyle: String? = nil,
        summaryMode: SummaryMode? = nil,
        explanationMode: ExplanationMode? = nil,
        todoExtractionMode: TodoExtractionMode? = nil
    ) {
        self.task = task
        self.inputText = inputText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translationQuality = translationQuality
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
    public var sourceLanguage: String?

    public init(text: String, rawText: String? = nil, modelName: String, task: TaskKind, sourceLanguage: String? = nil) {
        self.text = text
        self.rawText = rawText ?? text
        self.modelName = modelName
        self.task = task
        self.sourceLanguage = sourceLanguage
    }
}
