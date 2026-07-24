import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

public actor MLXRunner: ModelRunner {
    public let format: ModelFormat = .mlx
    public private(set) var isLoaded: Bool = false
    public private(set) var modelID: UUID?
    public private(set) var modelName: String?

    private var container: ModelContainer?
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
        unloadSync()
        let directory = descriptor.resolvedPath ?? descriptor.sourcePath
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw RunnerError.unsupportedConfiguration("MLX model directory does not exist: \(directory.path)")
        }

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let loaded = try await loadModelContainer(
            from: directory,
            using: tokenizerLoader
        )
        container = loaded
        modelID = descriptor.id
        modelName = descriptor.name
        thinkingModeEnabled = descriptor.thinkingModeEnabled
        isLoaded = true
    }

    public func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        guard isLoaded, let container else {
            throw RunnerError.notLoaded
        }

        try Task.checkCancellation()
        let systemPrompt = PromptTemplates.systemPrompt(for: request.task, preferences: preferences)
        let userPrompt = PromptTemplates.userPrompt(for: request, preferences: preferences)
        var session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: LocalGenerationPolicy.parameters(
                for: request.task,
                thinkingModeEnabled: thinkingModeEnabled
            ),
            additionalContext: ["enable_thinking": thinkingModeEnabled]
        )
        var response = try await GeneratedOutputGuard.collectGuardedResponse(
            from: session.streamResponse(to: userPrompt)
        )
        try Task.checkCancellation()

        var rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = VisibleOutput.from(rawText: rawOutput)
        if thinkingModeEnabled, output.isEmpty {
            // 模型耗尽预算仍未结束思考时，自动关闭思考重试，保证只把可用正文交给界面。
            session = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: LocalGenerationPolicy.parameters(for: request.task),
                additionalContext: ["enable_thinking": false]
            )
            response = try await GeneratedOutputGuard.collectGuardedResponse(
                from: session.streamResponse(to: userPrompt)
            )
            try Task.checkCancellation()
            rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
            output = VisibleOutput.from(rawText: rawOutput)
        }
        guard !output.isEmpty else {
            throw RunnerError.emptyResult
        }

        let visibleOutput = GeneratedOutputGuard.trimDegenerateTail(output)
        return TaskResult(text: visibleOutput, rawText: rawOutput, modelName: modelName ?? "MLX", task: request.task)
    }

    public func unload() async {
        unloadSync()
    }

    private func unloadSync() {
        container = nil
        isLoaded = false
        modelID = nil
        modelName = nil
        thinkingModeEnabled = false
        Memory.clearCache()
    }
}
