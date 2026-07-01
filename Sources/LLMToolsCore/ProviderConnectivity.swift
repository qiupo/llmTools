import Foundation

public enum ProviderTestStage: String, Codable, Sendable {
    case configuration
    case models
    case chat
}

public struct ProviderTestResult: Sendable, Hashable {
    public var modelID: UUID
    public var providerName: String
    public var modelName: String
    public var ok: Bool
    public var stage: ProviderTestStage
    public var message: String

    public init(
        modelID: UUID,
        providerName: String,
        modelName: String,
        ok: Bool,
        stage: ProviderTestStage,
        message: String
    ) {
        self.modelID = modelID
        self.providerName = providerName
        self.modelName = modelName
        self.ok = ok
        self.stage = stage
        self.message = message
    }
}

public enum ProviderConnectivityError: Error, LocalizedError, Sendable {
    case notRemoteProvider
    case missingBaseURL
    case missingModelID
    case missingAPIKey(String)
    case requestFailed(Int, String)
    case modelNotFound(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notRemoteProvider:
            return "This model is local and does not use a network provider."
        case .missingBaseURL:
            return "Provider base URL is missing."
        case .missingModelID:
            return "Provider model ID is missing."
        case .missingAPIKey(let providerName):
            return "\(providerName) API key is missing."
        case .requestFailed(let statusCode, let message):
            return "Provider request failed (\(statusCode)): \(message)"
        case .modelNotFound(let modelID):
            return "Connected to provider, but model was not found: \(modelID)"
        case .emptyResponse:
            return "Provider returned an empty response."
        }
    }
}

public enum ProviderConnectivity {
    public static func test(model descriptor: ModelDescriptor, timeout: TimeInterval = 30) async throws -> ProviderTestResult {
        guard let configuration = descriptor.providerConfiguration, configuration.isRemote else {
            throw ProviderConnectivityError.notRemoteProvider
        }
        let providerName = ModelProviderCatalog.displayName(for: configuration.providerID)
        guard let baseURL = configuration.baseURL else {
            throw ProviderConnectivityError.missingBaseURL
        }
        let modelID = configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            throw ProviderConnectivityError.missingModelID
        }

        var resolvedConfiguration = configuration
        resolvedConfiguration.apiKey = try ProviderCredentialStore.resolvedAPIKey(for: configuration)
        let preset = ModelProviderCatalog.preset(for: configuration.providerID)
        if preset?.requiresAPIKey == true && resolvedConfiguration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProviderConnectivityError.missingAPIKey(providerName)
        }

        switch configuration.apiStyle {
        case .local:
            throw ProviderConnectivityError.notRemoteProvider
        case .openAICompatible:
            return try await testOpenAICompatible(
                descriptor: descriptor,
                configuration: resolvedConfiguration,
                baseURL: baseURL,
                providerName: providerName,
                timeout: timeout
            )
        case .anthropicMessages:
            return try await testAnthropic(
                descriptor: descriptor,
                configuration: resolvedConfiguration,
                baseURL: baseURL,
                providerName: providerName,
                timeout: timeout
            )
        }
    }

    private static func testOpenAICompatible(
        descriptor: ModelDescriptor,
        configuration: ProviderConfiguration,
        baseURL: URL,
        providerName: String,
        timeout: TimeInterval
    ) async throws -> ProviderTestResult {
        let modelsURL = baseURL.appendingPathComponent("models")
        let modelsData = try? await performRequest(
            url: modelsURL,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders,
            timeout: min(timeout, 10)
        )
        let availableModels = modelsData.map(decodeModelIDs(from:)) ?? []
        if !availableModels.isEmpty {
            guard availableModels.contains(configuration.modelID) else {
                throw ProviderConnectivityError.modelNotFound(configuration.modelID)
            }
            return ProviderTestResult(
                modelID: descriptor.id,
                providerName: providerName,
                modelName: descriptor.name,
                ok: true,
                stage: .models,
                message: "Provider connected. Model is available: \(configuration.modelID)"
            )
        }

        let chatURL = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        let payload = OpenAITestRequest(
            model: configuration.modelID,
            messages: [OpenAITestMessage(role: "user", content: "Reply with OK only.")],
            temperature: 0,
            stream: false,
            maxTokens: 64,
            enableThinking: ProviderRequestOptions.enableThinking(for: configuration)
        )
        let chatData = try await performRequest(
            url: chatURL,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders,
            timeout: timeout,
            body: payload
        )
        let response = try JSONDecoder().decode(OpenAITestResponse.self, from: chatData)
        let text = (response.choices ?? [])
            .compactMap { $0.message.content }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ProviderConnectivityError.emptyResponse
        }

        return ProviderTestResult(
            modelID: descriptor.id,
            providerName: providerName,
            modelName: descriptor.name,
            ok: true,
            stage: .chat,
            message: "Provider connected. Chat response: \(text.prefix(80))"
        )
    }

    private static func testAnthropic(
        descriptor: ModelDescriptor,
        configuration: ProviderConfiguration,
        baseURL: URL,
        providerName: String,
        timeout: TimeInterval
    ) async throws -> ProviderTestResult {
        let chatURL = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("messages")
        let payload = AnthropicTestRequest(
            model: configuration.modelID,
            maxTokens: min(max(configuration.maxOutputTokens ?? 8, 1), 64),
            system: "Reply with OK only.",
            messages: [AnthropicTestMessage(role: "user", content: "Reply with OK only.")],
            temperature: 0
        )
        let data = try await performRequest(
            url: chatURL,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders.merging([
                "x-api-key": configuration.apiKey,
                "anthropic-version": "2023-06-01"
            ]) { current, _ in current },
            timeout: timeout,
            authorizationStyle: .none,
            body: payload
        )
        let response = try JSONDecoder().decode(AnthropicTestResponse.self, from: data)
        let text = (response.content ?? [])
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ProviderConnectivityError.emptyResponse
        }
        return ProviderTestResult(
            modelID: descriptor.id,
            providerName: providerName,
            modelName: descriptor.name,
            ok: true,
            stage: .chat,
            message: "Provider connected. Chat response: \(text.prefix(80))"
        )
    }

    private enum AuthorizationStyle {
        case bearer
        case none
    }

    private static func performRequest<Body: Encodable>(
        url: URL,
        apiKey: String,
        customHeaders: [String: String],
        timeout: TimeInterval,
        authorizationStyle: AuthorizationStyle = .bearer,
        body: Body
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorizationStyle == .bearer {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            }
        }
        for (key, value) in customHeaders where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return try await data(for: request)
    }

    private static func performRequest(
        url: URL,
        apiKey: String,
        customHeaders: [String: String],
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in customHeaders where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await data(for: request)
    }

    private static func data(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderConnectivityError.requestFailed(0, "No HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderConnectivityError.requestFailed(
                httpResponse.statusCode,
                decodeAPIError(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        return data
    }

    private static func decodeModelIDs(from data: Data) -> Set<String> {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        return Set((response.data ?? []).compactMap(\.id))
    }

    private static func decodeAPIError(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    private struct ModelsResponse: Decodable {
        var data: [ModelItem]?
    }

    private struct ModelItem: Decodable {
        var id: String?
    }

    private struct OpenAITestRequest: Encodable {
        var model: String
        var messages: [OpenAITestMessage]
        var temperature: Double
        var stream: Bool
        var maxTokens: Int
        var enableThinking: Bool?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case stream
            case maxTokens = "max_tokens"
            case enableThinking = "enable_thinking"
        }
    }

    private struct OpenAITestMessage: Codable {
        var role: String
        var content: String?
    }

    private struct OpenAITestResponse: Decodable {
        var choices: [Choice]?

        struct Choice: Decodable {
            var message: OpenAITestMessage
        }
    }

    private struct AnthropicTestRequest: Encodable {
        var model: String
        var maxTokens: Int
        var system: String
        var messages: [AnthropicTestMessage]
        var temperature: Double

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case temperature
        }
    }

    private struct AnthropicTestMessage: Codable {
        var role: String
        var content: String
    }

    private struct AnthropicTestResponse: Decodable {
        var content: [ContentBlock]?
    }

    private struct ContentBlock: Decodable {
        var type: String
        var text: String?
    }

    private struct APIErrorEnvelope: Decodable {
        var error: APIError
    }

    private struct APIError: Decodable {
        var message: String
    }
}
