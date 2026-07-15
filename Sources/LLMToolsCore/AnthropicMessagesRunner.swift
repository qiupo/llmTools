import Foundation

public actor AnthropicMessagesRunner: ModelRunner {
    public let format: ModelFormat = .anthropicMessages
    public private(set) var isLoaded: Bool = false
    public private(set) var modelID: UUID?
    public private(set) var modelName: String?

    private var configuration: ProviderConfiguration?

    public init() {}

    public func modelFormat() async -> ModelFormat {
        format
    }

    public func loadedState() async -> Bool {
        isLoaded
    }

    public func loadedModelID() async -> UUID? {
        modelID
    }

    public func loadedModelName() async -> String? {
        modelName
    }

    public func load(model descriptor: ModelDescriptor) async throws {
        guard let providerConfiguration = descriptor.providerConfiguration,
              providerConfiguration.apiStyle == .anthropicMessages else {
            throw RunnerError.unsupportedConfiguration("Anthropic provider configuration is missing.")
        }
        guard let baseURL = providerConfiguration.baseURL else {
            throw RunnerError.unsupportedConfiguration("Anthropic base URL is missing.")
        }
        guard ProviderEndpointPolicy.allows(baseURL) else {
            throw RunnerError.unsupportedConfiguration(ProviderEndpointPolicy.secureTransportMessage)
        }
        var loadedConfiguration = providerConfiguration
        loadedConfiguration.apiKey = try ProviderCredentialStore.resolvedAPIKey(for: providerConfiguration)
        guard !loadedConfiguration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.unsupportedConfiguration("Anthropic API key is missing.")
        }
        guard !providerConfiguration.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.unsupportedConfiguration("Anthropic model ID is missing.")
        }

        configuration = loadedConfiguration
        modelID = descriptor.id
        modelName = descriptor.name
        isLoaded = true
    }

    public func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        guard isLoaded, let configuration else {
            throw RunnerError.notLoaded
        }
        guard let baseURL = configuration.baseURL else {
            throw RunnerError.unsupportedConfiguration("Anthropic base URL is missing.")
        }

        let endpoint = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("messages")
        let payload = MessagesRequest(
            model: configuration.modelID,
            maxTokens: max(configuration.maxOutputTokens ?? 4096, 1),
            system: PromptTemplates.systemPrompt(for: request.task, preferences: preferences),
            messages: [
                Message(role: "user", content: PromptTemplates.userPrompt(for: request, preferences: preferences))
            ],
            temperature: 0
        )
        let data = try await performJSONRequest(
            endpoint: endpoint,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders,
            body: payload
        )
        let response = try JSONDecoder().decode(MessagesResponse.self, from: data)
        if let message = response.error?.message {
            throw RunnerError.unsupportedConfiguration(message)
        }
        let rawOutput = (response.content ?? [])
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let output = VisibleOutput.from(rawText: rawOutput)
        guard !output.isEmpty || !rawOutput.isEmpty else {
            throw RunnerError.emptyResult
        }

        return TaskResult(
            text: output.isEmpty ? rawOutput : output,
            rawText: rawOutput,
            modelName: modelName ?? configuration.modelID,
            task: request.task
        )
    }

    public func unload() async {
        configuration = nil
        isLoaded = false
        modelID = nil
        modelName = nil
    }

    private func performJSONRequest<Body: Encodable>(
        endpoint: URL,
        apiKey: String,
        customHeaders: [String: String],
        body: Body
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        for (key, value) in customHeaders where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()
        let (data, response) = try await ProviderHTTPSession.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunnerError.unsupportedConfiguration("Anthropic did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeAPIError(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw RunnerError.unsupportedConfiguration("Anthropic request failed (\(httpResponse.statusCode)): \(message)")
        }
        return data
    }

    private func decodeAPIError(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    private struct MessagesRequest: Encodable {
        var model: String
        var maxTokens: Int
        var system: String
        var messages: [Message]
        var temperature: Double

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case temperature
        }
    }

    private struct Message: Codable {
        var role: String
        var content: String
    }

    private struct MessagesResponse: Decodable {
        var content: [ContentBlock]?
        var error: APIError?
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
