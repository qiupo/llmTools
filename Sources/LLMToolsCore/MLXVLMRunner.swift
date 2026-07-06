import CoreImage
import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

public actor MLXVLMRunner: VisionModelRunner {
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
            throw RunnerError.unsupportedConfiguration("MLX VLM model directory does not exist: \(directory.path)")
        }

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let loaded = try await VLMModelFactory.shared.loadContainer(
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

        try Task.checkCancellation()
        let session = ChatSession(
            container,
            instructions: PromptTemplates.systemPrompt(for: request.task, preferences: preferences),
            generateParameters: LocalGenerationPolicy.parameters(for: request.task),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await GeneratedOutputGuard.collectGuardedResponse(
            from: session.streamResponse(
                to: PromptTemplates.userPrompt(for: request, preferences: preferences)
            )
        )
        try Task.checkCancellation()

        let rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = VisibleOutput.from(rawText: rawOutput)
        guard !output.isEmpty || !rawOutput.isEmpty else {
            throw RunnerError.emptyResult
        }

        let visibleOutput = GeneratedOutputGuard.trimDegenerateTail(output.isEmpty ? rawOutput : output)
        return TaskResult(
            text: visibleOutput,
            rawText: rawOutput,
            modelName: modelName ?? "MLX VLM",
            task: request.task
        )
    }

    public func generateOCR(request: OCRTaskRequest, preferences: AppPreferences) async throws -> OCRTaskResult {
        guard isLoaded, let container else {
            throw RunnerError.notLoaded
        }

        try Task.checkCancellation()
        guard let image = CIImage(data: request.image.data) else {
            throw OCRTaskError.unsupportedImageFormat
        }

        let session = ChatSession(
            container,
            instructions: PromptTemplates.systemPrompt(for: .ocr, preferences: preferences),
            generateParameters: LocalGenerationPolicy.parameters(for: request.mode),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await GeneratedOutputGuard.collectGuardedResponse(
            from: session.streamResponse(to: request.prompt, image: .ciImage(image))
        )
        try Task.checkCancellation()

        let rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = VisibleOutput.from(rawText: rawOutput)
        guard !output.isEmpty || !rawOutput.isEmpty else {
            throw RunnerError.emptyResult
        }
        let visibleOutput = GeneratedOutputGuard.trimDegenerateTail(output.isEmpty ? rawOutput : output)

        return OCRTaskResult(
            text: visibleOutput,
            rawModelText: rawOutput,
            structuredMarkdown: request.mode == .structured ? visibleOutput : nil,
            modelName: modelName ?? "MLX VLM"
        )
    }

    public func unload() async {
        unloadSync()
    }

    private func unloadSync() {
        container = nil
        isLoaded = false
        modelID = nil
        modelName = nil
        Memory.clearCache()
    }
}
