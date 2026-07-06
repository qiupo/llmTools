import Foundation

public enum ProviderAPIStyle: String, Codable, Sendable, CaseIterable {
    case local
    case openAICompatible
    case anthropicMessages
}

public enum ModelProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case local
    case siliconFlow
    case openAI
    case deepSeek
    case googleGemini
    case openRouter
    case anthropic
    case ollama
    case lmStudio
    case togetherAI
    case mistralAI
    case deepInfra
    case customOpenAICompatible

    public var id: String { rawValue }
}

public struct ModelProviderPreset: Identifiable, Hashable, Sendable {
    public var id: ModelProviderID
    public var name: String
    public var apiStyle: ProviderAPIStyle
    public var defaultBaseURL: String
    public var defaultModelID: String
    public var defaultContextLength: Int
    public var defaultMaxOutputTokens: Int?
    public var requiresAPIKey: Bool
    public var docsURL: String?
    public var note: String

    public init(
        id: ModelProviderID,
        name: String,
        apiStyle: ProviderAPIStyle,
        defaultBaseURL: String = "",
        defaultModelID: String = "",
        defaultContextLength: Int = 32768,
        defaultMaxOutputTokens: Int? = nil,
        requiresAPIKey: Bool = true,
        docsURL: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.apiStyle = apiStyle
        self.defaultBaseURL = defaultBaseURL
        self.defaultModelID = defaultModelID
        self.defaultContextLength = defaultContextLength
        self.defaultMaxOutputTokens = defaultMaxOutputTokens
        self.requiresAPIKey = requiresAPIKey
        self.docsURL = docsURL
        self.note = note
    }
}

public struct ProviderConfiguration: Codable, Hashable, Sendable {
    public var providerID: ModelProviderID
    public var apiStyle: ProviderAPIStyle
    public var baseURL: URL?
    public var apiKey: String
    public var apiKeyKeychainAccount: String?
    public var modelID: String
    public var customHeaders: [String: String]
    public var maxOutputTokens: Int?

    public init(
        providerID: ModelProviderID,
        apiStyle: ProviderAPIStyle,
        baseURL: URL? = nil,
        apiKey: String = "",
        apiKeyKeychainAccount: String? = nil,
        modelID: String = "",
        customHeaders: [String: String] = [:],
        maxOutputTokens: Int? = nil
    ) {
        self.providerID = providerID
        self.apiStyle = apiStyle
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.apiKeyKeychainAccount = apiKeyKeychainAccount
        self.modelID = modelID
        self.customHeaders = customHeaders
        self.maxOutputTokens = maxOutputTokens
    }

    public var isRemote: Bool {
        apiStyle != .local
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case apiStyle
        case baseURL
        case apiKey
        case apiKeyKeychainAccount
        case modelID
        case customHeaders
        case maxOutputTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(ModelProviderID.self, forKey: .providerID)
        apiStyle = try container.decode(ProviderAPIStyle.self, forKey: .apiStyle)
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        apiKeyKeychainAccount = try container.decodeIfPresent(String.self, forKey: .apiKeyKeychainAccount)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? ""
        customHeaders = try container.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(apiStyle, forKey: .apiStyle)
        try container.encodeIfPresent(baseURL, forKey: .baseURL)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            try container.encode(trimmedAPIKey, forKey: .apiKey)
        }
        try container.encode(modelID, forKey: .modelID)
        try container.encode(customHeaders, forKey: .customHeaders)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
    }
}

public enum ProviderRequestOptions {
    public static func enableThinking(for configuration: ProviderConfiguration) -> Bool? {
        guard configuration.providerID == .siliconFlow,
              siliconFlowSupportsThinkingToggle(modelID: configuration.modelID) else {
            return nil
        }
        return false
    }

    private static func siliconFlowSupportsThinkingToggle(modelID: String) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized.contains("qwen3-vl") || normalized.contains("-vl-") {
            return false
        }
        let supportedPrefixes = [
            "Qwen/Qwen3-",
            "Qwen/Qwen3.5-",
            "Pro/zai-org/GLM-",
            "zai-org/GLM-",
            "deepseek-ai/DeepSeek-V3.",
            "Pro/deepseek-ai/DeepSeek-V3."
        ]
        return supportedPrefixes.contains { trimmed.hasPrefix($0) }
            || trimmed == "tencent/Hunyuan-A13B-Instruct"
    }
}

public enum ModelProviderCatalog {
    public static let presets: [ModelProviderPreset] = [
        ModelProviderPreset(
            id: .local,
            name: "Local Model",
            apiStyle: .local,
            requiresAPIKey: false,
            note: "Use a local GGUF file or MLX model folder."
        ),
        ModelProviderPreset(
            id: .siliconFlow,
            name: "SiliconFlow",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://api.siliconflow.cn/v1",
            defaultContextLength: 32768,
            docsURL: "https://docs.siliconflow.cn/",
            note: "OpenAI-compatible Chat Completions provider."
        ),
        ModelProviderPreset(
            id: .openAI,
            name: "OpenAI",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://api.openai.com/v1",
            defaultContextLength: 128000,
            docsURL: "https://platform.openai.com/docs/api-reference/chat/create",
            note: "OpenAI Chat Completions compatible endpoint."
        ),
        ModelProviderPreset(
            id: .deepSeek,
            name: "DeepSeek",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://api.deepseek.com",
            defaultModelID: "deepseek-chat",
            defaultContextLength: 64000,
            docsURL: "https://api-docs.deepseek.com/",
            note: "OpenAI-compatible endpoint."
        ),
        ModelProviderPreset(
            id: .googleGemini,
            name: "Google Gemini",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            defaultContextLength: 1000000,
            docsURL: "https://ai.google.dev/gemini-api/docs/openai",
            note: "Gemini OpenAI-compatible endpoint."
        ),
        ModelProviderPreset(
            id: .openRouter,
            name: "OpenRouter",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://openrouter.ai/api/v1",
            defaultContextLength: 128000,
            docsURL: "https://openrouter.ai/docs/quickstart",
            note: "OpenAI-compatible routing provider."
        ),
        ModelProviderPreset(
            id: .anthropic,
            name: "Anthropic",
            apiStyle: .anthropicMessages,
            defaultBaseURL: "https://api.anthropic.com",
            defaultContextLength: 200000,
            defaultMaxOutputTokens: 4096,
            docsURL: "https://docs.anthropic.com/en/api/messages",
            note: "Native Anthropic Messages API."
        ),
        ModelProviderPreset(
            id: .ollama,
            name: "Ollama",
            apiStyle: .openAICompatible,
            defaultBaseURL: "http://localhost:11434/v1",
            defaultContextLength: 8192,
            requiresAPIKey: false,
            docsURL: "https://github.com/ollama/ollama/blob/main/docs/openai.md",
            note: "Local OpenAI-compatible server."
        ),
        ModelProviderPreset(
            id: .lmStudio,
            name: "LM Studio",
            apiStyle: .openAICompatible,
            defaultBaseURL: "http://localhost:1234/v1",
            defaultContextLength: 8192,
            requiresAPIKey: false,
            docsURL: "https://lmstudio.ai/docs/app/api",
            note: "Local OpenAI-compatible server."
        ),
        ModelProviderPreset(
            id: .togetherAI,
            name: "Together AI",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://api.together.xyz/v1",
            defaultContextLength: 128000,
            docsURL: "https://docs.together.ai/docs/openai-api-compatibility",
            note: "OpenAI-compatible hosted model provider."
        ),
        ModelProviderPreset(
            id: .mistralAI,
            name: "Mistral AI",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://api.mistral.ai/v1",
            defaultContextLength: 128000,
            docsURL: "https://docs.mistral.ai/api/",
            note: "OpenAI-compatible hosted model provider."
        ),
        ModelProviderPreset(
            id: .deepInfra,
            name: "DeepInfra",
            apiStyle: .openAICompatible,
            defaultBaseURL: "https://api.deepinfra.com/v1/openai",
            defaultContextLength: 128000,
            docsURL: "https://deepinfra.com/docs/openai_api",
            note: "OpenAI-compatible hosted model provider."
        ),
        ModelProviderPreset(
            id: .customOpenAICompatible,
            name: "Custom OpenAI-Compatible",
            apiStyle: .openAICompatible,
            defaultContextLength: 32768,
            docsURL: nil,
            note: "Use any provider that exposes /chat/completions."
        )
    ]

    public static var remotePresets: [ModelProviderPreset] {
        presets.filter { $0.apiStyle != .local }
    }

    public static func preset(for providerID: ModelProviderID) -> ModelProviderPreset? {
        presets.first { $0.id == providerID }
    }

    public static func displayName(for providerID: ModelProviderID) -> String {
        preset(for: providerID)?.name ?? providerID.rawValue
    }

    public static func format(for apiStyle: ProviderAPIStyle) -> ModelFormat {
        switch apiStyle {
        case .local:
            return .unknown
        case .openAICompatible:
            return .openAICompatible
        case .anthropicMessages:
            return .anthropicMessages
        }
    }
}
