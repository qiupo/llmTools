import Foundation

public actor OpenAICompatibleRunner: VisionModelRunner {
    public let format: ModelFormat = .openAICompatible
    public private(set) var isLoaded: Bool = false
    public private(set) var modelID: UUID?
    public private(set) var modelName: String?

    private var configuration: ProviderConfiguration?
    private var thinkingModeEnabled = false

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
              providerConfiguration.apiStyle == .openAICompatible else {
            throw RunnerError.unsupportedConfiguration("OpenAI-compatible provider configuration is missing.")
        }
        guard let baseURL = providerConfiguration.baseURL else {
            throw RunnerError.unsupportedConfiguration("Provider base URL is missing.")
        }
        guard ProviderEndpointPolicy.allows(baseURL) else {
            throw RunnerError.unsupportedConfiguration(ProviderEndpointPolicy.secureTransportMessage)
        }
        guard !providerConfiguration.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.unsupportedConfiguration("Provider model ID is missing.")
        }

        var loadedConfiguration = providerConfiguration
        loadedConfiguration.apiKey = try ProviderCredentialStore.resolvedAPIKey(for: providerConfiguration)
        let preset = ModelProviderCatalog.preset(for: providerConfiguration.providerID)
        if preset?.requiresAPIKey == true && loadedConfiguration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RunnerError.unsupportedConfiguration("\(preset?.name ?? "Provider") API key is missing.")
        }

        configuration = loadedConfiguration
        modelID = descriptor.id
        modelName = descriptor.name
        thinkingModeEnabled = descriptor.thinkingModeEnabled
        isLoaded = true
    }

    public func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        guard isLoaded, let configuration else {
            throw RunnerError.notLoaded
        }
        guard let baseURL = configuration.baseURL else {
            throw RunnerError.unsupportedConfiguration("Provider base URL is missing.")
        }

        let endpoint = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        let systemPrompt = PromptTemplates.systemPrompt(for: request.task, preferences: preferences)
        let userPrompt = PromptTemplates.userPrompt(for: request, preferences: preferences)
        let payload = ChatCompletionsRequest(
            model: configuration.modelID,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            temperature: 0,
            stream: false,
            enableThinking: ProviderRequestOptions.enableThinking(
                for: configuration,
                requested: thinkingModeEnabled
            )
        )

        let data = try await performJSONRequest(
            endpoint: endpoint,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders,
            body: payload
        )
        let response = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        if let message = response.error?.message {
            throw RunnerError.unsupportedConfiguration(message)
        }
        let rawOutput = (response.choices ?? [])
            .compactMap { $0.message.content }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let output = VisibleOutput.from(rawText: rawOutput)
        guard !output.isEmpty else {
            throw RunnerError.emptyResult
        }

        return TaskResult(
            text: output,
            rawText: rawOutput,
            modelName: modelName ?? configuration.modelID,
            task: request.task
        )
    }

    public func generateOCR(request: OCRTaskRequest, preferences: AppPreferences) async throws -> OCRTaskResult {
        guard isLoaded, let configuration else {
            throw RunnerError.notLoaded
        }
        guard let baseURL = configuration.baseURL else {
            throw RunnerError.unsupportedConfiguration("Provider base URL is missing.")
        }

        let endpoint = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        let payload = OCRChatCompletionsRequest(
            model: configuration.modelID,
            messages: [
                OCRChatMessage(
                    role: "system",
                    content: [
                        OCRMessageContent(type: "text", text: PromptTemplates.systemPrompt(for: .ocr, preferences: preferences))
                    ]
                ),
                OCRChatMessage(
                    role: "user",
                    content: [
                        OCRMessageContent(type: "text", text: request.prompt),
                        OCRMessageContent(
                            type: "image_url",
                            imageURL: OCRImageURL(url: request.image.dataURL, detail: "auto")
                        )
                    ]
                )
            ],
            temperature: 0,
            stream: false,
            enableThinking: ProviderRequestOptions.enableThinking(
                for: configuration,
                requested: thinkingModeEnabled
            )
        )

        let data = try await performJSONRequest(
            endpoint: endpoint,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders,
            body: payload,
            timeout: 180
        )
        let response = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        if let message = response.error?.message {
            throw RunnerError.unsupportedConfiguration(message)
        }
        let rawOutput = (response.choices ?? [])
            .compactMap { $0.message.content }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let output = VisibleOutput.from(rawText: rawOutput)
        guard !output.isEmpty else {
            throw RunnerError.emptyResult
        }

        return OCRTaskResult(
            text: output,
            rawModelText: rawOutput,
            structuredMarkdown: request.mode == .structured ? output : nil,
            modelName: modelName ?? configuration.modelID,
            warnings: []
        )
    }

    public func unload() async {
        configuration = nil
        isLoaded = false
        modelID = nil
        modelName = nil
        thinkingModeEnabled = false
    }

    private func performJSONRequest<Body: Encodable>(
        endpoint: URL,
        apiKey: String,
        customHeaders: [String: String],
        body: Body,
        timeout: TimeInterval = 120
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in customHeaders where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()
        let (data, response) = try await ProviderHTTPSession.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunnerError.unsupportedConfiguration("Provider did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeAPIError(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw RunnerError.unsupportedConfiguration("Provider request failed (\(httpResponse.statusCode)): \(message)")
        }
        return data
    }

    private func decodeAPIError(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    private struct ChatCompletionsRequest: Encodable {
        var model: String
        var messages: [ChatMessage]
        var temperature: Double
        var stream: Bool
        var enableThinking: Bool?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case stream
            case enableThinking = "enable_thinking"
        }
    }

    private struct ChatMessage: Codable {
        var role: String
        var content: String?
    }

    private struct OCRChatCompletionsRequest: Encodable {
        var model: String
        var messages: [OCRChatMessage]
        var temperature: Double
        var stream: Bool
        var enableThinking: Bool?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case stream
            case enableThinking = "enable_thinking"
        }
    }

    private struct OCRChatMessage: Encodable {
        var role: String
        var content: [OCRMessageContent]
    }

    private struct OCRMessageContent: Encodable {
        var type: String
        var text: String?
        var imageURL: OCRImageURL?

        init(type: String, text: String? = nil, imageURL: OCRImageURL? = nil) {
            self.type = type
            self.text = text
            self.imageURL = imageURL
        }

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
    }

    private struct OCRImageURL: Encodable {
        var url: String
        var detail: String?
    }

    private struct ChatCompletionsResponse: Decodable {
        var choices: [Choice]?
        var error: APIError?

        struct Choice: Decodable {
            var message: ChatMessage
        }
    }

    private struct APIErrorEnvelope: Decodable {
        var error: APIError
    }

    private struct APIError: Decodable {
        var message: String
    }
}
