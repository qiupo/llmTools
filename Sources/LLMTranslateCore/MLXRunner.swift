import Foundation
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
        isLoaded = true
    }

    public func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        guard isLoaded, let container else {
            throw RunnerError.notLoaded
        }

        let systemPrompt = PromptTemplates.systemPrompt(for: request.task, preferences: preferences)
        let userPrompt = PromptTemplates.userPrompt(for: request, preferences: preferences)
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await session.respond(to: userPrompt)

        let rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = VisibleOutput.from(rawText: rawOutput)
        guard !output.isEmpty || !rawOutput.isEmpty else {
            throw RunnerError.emptyResult
        }

        return TaskResult(text: output.isEmpty ? rawOutput : output, rawText: rawOutput, modelName: modelName ?? "MLX", task: request.task)
    }

    public func unload() async {
        unloadSync()
    }

    private func unloadSync() {
        container = nil
        isLoaded = false
        modelID = nil
        modelName = nil
    }
}
