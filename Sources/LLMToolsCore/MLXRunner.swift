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
        // unload 期间取消的加载不能在异步返回后重新提交为已加载状态。
        try Task.checkCancellation()
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
        let systemPrompt = PromptTemplates.systemPrompt(for: request, preferences: preferences)
        let userPrompt = PromptTemplates.userPrompt(for: request, preferences: preferences)
        let effectiveThinkingModeEnabled = request.thinkingModeOverride ?? thinkingModeEnabled
        var session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: LocalGenerationPolicy.parameters(
                for: request.task,
                thinkingModeEnabled: effectiveThinkingModeEnabled,
                maxTokensOverride: request.maxOutputTokensOverride
            ),
            additionalContext: ["enable_thinking": effectiveThinkingModeEnabled]
        )
        let firstGeneration = try await GeneratedOutputGuard.collectGuardedResponse(
            from: session.streamDetails(to: userPrompt)
        )
        try Task.checkCancellation()

        var rawOutput = firstGeneration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = VisibleOutput.from(rawText: rawOutput)
        if effectiveThinkingModeEnabled,
           LocalGenerationPolicy.shouldRetryThinkingGeneration(
               visibleOutput: output,
               reachedTokenLimit: firstGeneration.reachedTokenLimit
           ) {
            // 达到首轮上限时少量正文也可能已被截断，统一关闭思考后完整重试。
            session = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: LocalGenerationPolicy.parameters(
                    for: request.task,
                    maxTokensOverride: request.maxOutputTokensOverride
                ),
                additionalContext: ["enable_thinking": false]
            )
            let response = try await GeneratedOutputGuard.collectGuardedResponse(
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
