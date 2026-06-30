import Foundation
import llama

public actor GGUFRunner: ModelRunner {
    public let format: ModelFormat = .gguf
    public private(set) var isLoaded: Bool = false
    public private(set) var modelID: UUID?
    public private(set) var modelName: String?

    private let defaultMaxNewTokens = 512
    private var model: OpaquePointer?
    private var context: OpaquePointer?

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
        let path = descriptor.resolvedPath?.path ?? descriptor.sourcePath.path
        guard !path.isEmpty else {
            throw RunnerError.unsupportedConfiguration("GGUF model path is missing.")
        }

        llama_backend_init()

        let modelParams = llama_model_default_params()
        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw RunnerError.unsupportedConfiguration("Failed to load GGUF model at \(path).")
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(max(descriptor.contextLength, 1))
        contextParams.n_batch = 512

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw RunnerError.unsupportedConfiguration("Failed to initialize GGUF context.")
        }

        model = loadedModel
        context = loadedContext
        modelID = descriptor.id
        modelName = descriptor.name
        isLoaded = true
    }

    public func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        guard isLoaded, let model, let context else {
            throw RunnerError.notLoaded
        }

        let systemPrompt = PromptTemplates.systemPrompt(for: request.task, preferences: preferences)
        let userPrompt = PromptTemplates.userPrompt(for: request, preferences: preferences)
        let fullPrompt = chatPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)

        try Task.checkCancellation()
        let output = try generateText(
            prompt: fullPrompt,
            model: model,
            context: context,
            maxNewTokens: defaultMaxNewTokens
        )
        try Task.checkCancellation()
        let rawOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleOutput = VisibleOutput.from(rawText: rawOutput)
        guard !visibleOutput.isEmpty || !rawOutput.isEmpty else {
            throw RunnerError.emptyResult
        }

        return TaskResult(text: visibleOutput.isEmpty ? rawOutput : visibleOutput, rawText: rawOutput, modelName: modelName ?? "GGUF", task: request.task)
    }

    public func unload() async {
        unloadSync()
    }

    private func unloadSync() {
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        if isLoaded {
            llama_backend_free()
        }
        isLoaded = false
        modelID = nil
        modelName = nil
    }

    private func generateText(
        prompt: String,
        model: OpaquePointer,
        context: OpaquePointer,
        maxNewTokens: Int
    ) throws -> String {
        try Task.checkCancellation()
        llama_memory_clear(llama_get_memory(context), true)

        guard let vocab = llama_model_get_vocab(model) else {
            throw RunnerError.unsupportedConfiguration("Failed to read GGUF vocabulary.")
        }
        let promptBytes = Array(prompt.utf8)
        var promptTokens = [llama_token](repeating: 0, count: promptBytes.count + 8)

        let tokenCount = promptBytes.withUnsafeBufferPointer { bytes -> Int32 in
            bytes.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { pointer in
                llama_tokenize(vocab, pointer, Int32(bytes.count), &promptTokens, Int32(promptTokens.count), true, true)
            }
        }

        guard tokenCount > 0 else {
            throw RunnerError.unsupportedConfiguration("Failed to tokenize GGUF prompt.")
        }

        let promptSlice = Array(promptTokens.prefix(Int(tokenCount)))
        let contextLength = Int(llama_n_ctx(context))
        guard promptSlice.count < contextLength else {
            throw RunnerError.unsupportedConfiguration("GGUF prompt is longer than the context window.")
        }

        let batchSize = max(1, Int(llama_n_batch(context)))
        var batch = llama_batch_init(Int32(batchSize), 0, 1)
        defer { llama_batch_free(batch) }

        var promptOffset = 0
        while promptOffset < promptSlice.count {
            try Task.checkCancellation()
            let chunk = promptSlice[promptOffset..<min(promptOffset + batchSize, promptSlice.count)]
            batch.n_tokens = Int32(chunk.count)
            for (localIndex, token) in chunk.enumerated() {
                let globalIndex = promptOffset + localIndex
                batch.token[localIndex] = token
                batch.pos[localIndex] = Int32(globalIndex)
                batch.n_seq_id[localIndex] = 1
                if let seqIDs = batch.seq_id, let seqID = seqIDs[localIndex] {
                    seqID[0] = 0
                }
                batch.logits[localIndex] = globalIndex == promptSlice.count - 1 ? 1 : 0
            }

            guard llama_decode(context, batch) == 0 else {
                throw RunnerError.unsupportedConfiguration("GGUF prompt evaluation failed.")
            }

            promptOffset += chunk.count
        }

        var output = ""
        var currentTokenCount = promptSlice.count
        let remainingContext = max(contextLength - promptSlice.count, 0)
        let generationLimit = min(maxNewTokens, remainingContext)
        for _ in 0..<generationLimit {
            try Task.checkCancellation()
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                throw RunnerError.unsupportedConfiguration("Failed to read GGUF logits.")
            }

            let vocabSize = Int(llama_vocab_n_tokens(vocab))
            var bestLogit = logits[0]
            var nextToken: llama_token = 0
            if vocabSize > 1 {
                for i in 1..<vocabSize {
                    if logits[i] > bestLogit {
                        bestLogit = logits[i]
                        nextToken = llama_token(i)
                    }
                }
            }

            if llama_vocab_is_eog(vocab, nextToken) {
                break
            }

            let pieceLength = tokenPieceLength(vocab: vocab, token: nextToken)
            if pieceLength > 0 {
                var tokenBuffer = [CChar](repeating: 0, count: pieceLength)
                _ = llama_token_to_piece(vocab, nextToken, &tokenBuffer, Int32(tokenBuffer.count), 0, false)
                output += String(decoding: tokenBuffer.prefix(Int(pieceLength)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = Int32(currentTokenCount)
            batch.n_seq_id[0] = 1
            if let seqIDs = batch.seq_id, let seqID = seqIDs[0] {
                seqID[0] = 0
            }
            batch.logits[0] = 1
            currentTokenCount += 1

            guard llama_decode(context, batch) == 0 else {
                if output.isEmpty {
                    throw RunnerError.unsupportedConfiguration("GGUF generation failed.")
                }
                break
            }
        }

        return output
    }

    private func chatPrompt(systemPrompt: String, userPrompt: String) -> String {
        """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(userPrompt)<|im_end|>
        <|im_start|>assistant

        """
    }

    private func tokenPieceLength(vocab: OpaquePointer, token: llama_token) -> Int {
        let initialBufferSize = 64
        var tokenBuffer = [CChar](repeating: 0, count: initialBufferSize)
        let pieceLength = llama_token_to_piece(vocab, token, &tokenBuffer, Int32(tokenBuffer.count), 0, false)
        if pieceLength >= 0 {
            return Int(pieceLength)
        }
        return Int(-pieceLength)
    }
}
