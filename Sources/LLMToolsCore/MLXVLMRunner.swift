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
    private var thinkingModeEnabled = false
    private var dedicatedOCR = false

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
        thinkingModeEnabled = descriptor.thinkingModeEnabled
        dedicatedOCR = ModelDetection.isGLMOCRModel(at: descriptor.resolvedPath ?? descriptor.sourcePath)
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
            // 思考未收束时改用非思考模板重试，避免将中间过程误当成正文。
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
        if dedicatedOCR, request.mode == .explainImage {
            throw OCRTaskError.unsupportedMode(modelName: modelName ?? "GLM-OCR", mode: request.mode)
        }

        try Task.checkCancellation()
        guard let image = CIImage(data: request.image.data) else {
            throw OCRTaskError.unsupportedImageFormat
        }

        let systemPrompt = dedicatedOCR ? nil : PromptTemplates.systemPrompt(for: .ocr, preferences: preferences)
        let parameters = dedicatedOCR
            ? GenerateParameters(maxTokens: request.mode == .structured ? 8_192 : 4_096, temperature: 0)
            : LocalGenerationPolicy.parameters(
                for: request.mode,
                thinkingModeEnabled: thinkingModeEnabled
            )
        var session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": thinkingModeEnabled]
        )
        var response = try await GeneratedOutputGuard.collectGuardedResponse(
            from: session.streamResponse(to: request.prompt, image: .ciImage(image))
        )
        try Task.checkCancellation()

        var rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = VisibleOutput.from(rawText: rawOutput)
        if thinkingModeEnabled, output.isEmpty {
            session = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: dedicatedOCR
                    ? GenerateParameters(maxTokens: request.mode == .structured ? 8_192 : 4_096, temperature: 0)
                    : LocalGenerationPolicy.parameters(for: request.mode),
                additionalContext: ["enable_thinking": false]
            )
            response = try await GeneratedOutputGuard.collectGuardedResponse(
                from: session.streamResponse(to: request.prompt, image: .ciImage(image))
            )
            try Task.checkCancellation()
            rawOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
            output = VisibleOutput.from(rawText: rawOutput)
        }
        guard !output.isEmpty else {
            throw RunnerError.emptyResult
        }
        let visibleOutput = GeneratedOutputGuard.trimDegenerateTail(output)

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
        thinkingModeEnabled = false
        dedicatedOCR = false
        Memory.clearCache()
    }
}
