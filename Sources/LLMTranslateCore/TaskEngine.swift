import Foundation

public actor TaskEngine {
    private let registryStore: RegistryStore
    private let historyStore: HistoryStore
    private var snapshot: RegistrySnapshot
    private var history: [HistoryItem]
    private var runners: [ModelFormat: any ModelRunner]

    public init(
        registryStore: RegistryStore = RegistryStore(),
        historyStore: HistoryStore = HistoryStore(),
        runners: [ModelFormat: any ModelRunner] = [:]
    ) {
        self.registryStore = registryStore
        self.historyStore = historyStore
        self.snapshot = .init()
        self.history = []
        self.runners = runners
    }

    public func bootstrap() async {
        do {
            snapshot = try await registryStore.load()
        } catch {
            snapshot = .init()
        }

        do {
            history = try await historyStore.load()
        } catch {
            history = []
        }
    }

    public func registry() -> RegistrySnapshot {
        snapshot
    }

    public func recentHistory() -> [HistoryItem] {
        history
    }

    public func addModel(from url: URL, name: String? = nil, role: ModelRole? = nil) async throws -> ModelDescriptor {
        let detection = try ModelDetection.detect(from: url)
        let displayName = name ?? inferDisplayName(from: url)
        let inferredRole: ModelRole = role ?? inferRole(format: detection.format, sizeClass: detection.sizeClass)
        let inferredContext = inferContextLength(format: detection.format, sizeClass: detection.sizeClass)
        let descriptor = ModelDescriptor(
            name: displayName,
            sourcePath: url,
            resolvedPath: detection.resolvedPath,
            format: detection.format,
            sizeClass: detection.sizeClass,
            role: inferredRole,
            contextLength: inferredContext,
            enabled: true,
            validationState: .valid,
            lastErrorMessage: nil
        )
        snapshot.models.append(descriptor)
        if snapshot.preferences.defaultModelID == nil {
            snapshot.preferences.defaultModelID = descriptor.id
        }
        try await registryStore.save(snapshot)
        return descriptor
    }

    public func removeModel(id: UUID) async throws {
        snapshot.models.removeAll { $0.id == id }
        if snapshot.preferences.defaultModelID == id {
            snapshot.preferences.defaultModelID = snapshot.models.first?.id
        }
        try await registryStore.save(snapshot)
    }

    public func updatePreferences(_ transform: (inout AppPreferences) -> Void) async throws {
        transform(&snapshot.preferences)
        try await registryStore.save(snapshot)
    }

    public func setPreferences(_ preferences: AppPreferences) async throws {
        snapshot.preferences = preferences
        try await registryStore.save(snapshot)
    }

    public func setRunner(_ runner: any ModelRunner, for format: ModelFormat) {
        runners[format] = runner
    }

    public func warmUpModel(id: UUID) async throws {
        guard let model = snapshot.models.first(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        let runner = try runner(for: model)
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }
    }

    public func run(request: TaskRequest, modelID: UUID? = nil, persistHistory: Bool = true) async throws -> TaskResult {
        let model = try resolveModel(for: modelID)
        try validateInputSize(request, for: model)
        let runner = try runner(for: model)
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }
        let result = try await runner.generate(request: request, preferences: snapshot.preferences)
        if persistHistory {
            appendHistory(model: model, result: result, request: request)
        }
        return result
    }

    public func translateWebPageSegments(
        payload: WebPageTranslateSegmentsPayload,
        modelID: UUID? = nil
    ) async throws -> WebPageTranslateSegmentsResult {
        try validateWebPagePayload(payload)
        let model = try resolveModel(for: modelID)
        let request = TaskRequest(
            task: .webPageTranslate,
            inputText: try PromptTemplates.webPageBatchPrompt(
                segments: payload.segments,
                targetLanguage: payload.targetLanguage,
                isRetry: false
            ),
            sourceLanguage: payload.sourceLanguage,
            targetLanguage: payload.targetLanguage
        )
        try validateInputSize(request, for: model)
        let batchResult = try await run(
            request: request,
            modelID: model.id,
            persistHistory: snapshot.preferences.webPageTranslation.persistWebHistory
        )
        if let translations = parseWebPageTranslations(from: batchResult.text, segments: payload.segments) {
            return webPageResult(
                jobID: payload.jobID,
                modelName: batchResult.modelName,
                segments: payload.segments,
                translations: translations
            )
        }

        let retryRequest = TaskRequest(
            task: .webPageTranslate,
            inputText: try PromptTemplates.webPageBatchPrompt(
                segments: payload.segments,
                targetLanguage: payload.targetLanguage,
                isRetry: true
            ),
            sourceLanguage: payload.sourceLanguage,
            targetLanguage: payload.targetLanguage
        )
        let retryResult = try await run(
            request: retryRequest,
            modelID: model.id,
            persistHistory: snapshot.preferences.webPageTranslation.persistWebHistory
        )
        if let translations = parseWebPageTranslations(from: retryResult.text, segments: payload.segments) {
            return webPageResult(
                jobID: payload.jobID,
                modelName: retryResult.modelName,
                segments: payload.segments,
                translations: translations
            )
        }

        var fallbackTranslations: [WebPageSegmentTranslation] = []
        var fallbackModelName = retryResult.modelName
        for segment in payload.segments {
            try Task.checkCancellation()
            do {
                let result = try await run(
                    request: TaskRequest(
                        task: .translate,
                        inputText: segment.text,
                        targetLanguage: payload.targetLanguage
                    ),
                    modelID: model.id,
                    persistHistory: snapshot.preferences.webPageTranslation.persistWebHistory
                )
                fallbackModelName = result.modelName
                fallbackTranslations.append(
                    WebPageSegmentTranslation(
                        segmentID: segment.segmentID,
                        translation: result.text,
                        status: .translated
                    )
                )
            } catch {
                fallbackTranslations.append(
                    WebPageSegmentTranslation(
                        segmentID: segment.segmentID,
                        translation: "",
                        status: .failed,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }

        return webPageResult(
            jobID: payload.jobID,
            modelName: fallbackModelName,
            segments: payload.segments,
            translations: fallbackTranslations
        )
    }

    public func clearHistory() async throws {
        history = []
        try await historyStore.save(history)
    }

    public func unloadAll() async {
        for runner in runners.values {
            await runner.unload()
        }
        runners.removeAll()
    }

    private func resolveModel(for modelID: UUID?) throws -> ModelDescriptor {
        if let modelID, let model = snapshot.models.first(where: { $0.id == modelID && $0.enabled }) {
            return model
        }
        if let preferred = snapshot.preferences.defaultModelID,
           let model = snapshot.models.first(where: { $0.id == preferred && $0.enabled }) {
            return model
        }
        if let firstEnabled = snapshot.models.first(where: { $0.enabled }) {
            return firstEnabled
        }
        throw RunnerError.unsupportedConfiguration("No enabled model is registered.")
    }

    private func validateInputSize(_ request: TaskRequest, for model: ModelDescriptor) throws {
        let limit = InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength)
        let current = request.inputText.count
        guard current <= limit else {
            throw RunnerError.inputTooLong(current: current, limit: limit)
        }
    }

    private func validateWebPagePayload(_ payload: WebPageTranslateSegmentsPayload) throws {
        guard snapshot.preferences.webPageTranslation.enabled else {
            throw WebPageTranslationError(
                code: .permissionMissing,
                message: "网页翻译已关闭。",
                repairAction: "在 llmTranslate 设置中启用网页翻译。"
            )
        }
        guard !payload.segments.isEmpty else {
            throw WebPageTranslationError(
                code: .payloadTooLarge,
                message: "没有可翻译的网页文本。"
            )
        }
        let maxSegments = max(snapshot.preferences.webPageTranslation.maxSegmentsPerBatch, 1)
        guard payload.segments.count <= maxSegments else {
            throw WebPageTranslationError(
                code: .payloadTooLarge,
                message: "单次网页翻译段落过多。",
                diagnostic: "\(payload.segments.count)/\(maxSegments)"
            )
        }
        let maxCharacters = max(snapshot.preferences.webPageTranslation.maxCharactersPerBatch, 1)
        let sourceCharacters = payload.segments.reduce(0) { $0 + $1.text.count }
        guard sourceCharacters <= maxCharacters else {
            throw WebPageTranslationError(
                code: .payloadTooLarge,
                message: "单次网页翻译内容过长。",
                diagnostic: "\(sourceCharacters)/\(maxCharacters)"
            )
        }
    }

    private func parseWebPageTranslations(
        from output: String,
        segments: [WebPageTranslationSegment]
    ) -> [WebPageSegmentTranslation]? {
        let jsonText = extractJSONArray(from: output)
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WebPageTranslationJSONItem].self, from: data) else {
            return nil
        }

        let expectedIDs = Set(segments.map(\.segmentID))
        let mapped = decoded.compactMap { item -> WebPageSegmentTranslation? in
            guard expectedIDs.contains(item.id) else {
                return nil
            }
            let translation = item.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else {
                return WebPageSegmentTranslation(
                    segmentID: item.id,
                    translation: "",
                    status: .failed,
                    errorMessage: "Empty translation"
                )
            }
            return WebPageSegmentTranslation(
                segmentID: item.id,
                translation: translation,
                status: .translated
            )
        }

        guard mapped.count == segments.count else {
            return nil
        }
        return mapped
    }

    private func extractJSONArray(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "["),
              let end = trimmed.lastIndex(of: "]"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }

    private func webPageResult(
        jobID: String,
        modelName: String,
        segments: [WebPageTranslationSegment],
        translations: [WebPageSegmentTranslation]
    ) -> WebPageTranslateSegmentsResult {
        let sourceCharacters = segments.reduce(0) { $0 + $1.text.count }
        let targetCharacters = translations.reduce(0) { $0 + $1.translation.count }
        return WebPageTranslateSegmentsResult(
            jobID: jobID,
            modelName: modelName,
            translations: translations,
            usage: WebPageTranslationUsage(
                sourceCharacters: sourceCharacters,
                targetCharacters: targetCharacters
            )
        )
    }

    private func runner(for model: ModelDescriptor) throws -> any ModelRunner {
        if let runner = runners[model.format] {
            return runner
        }
        switch model.format {
        case .gguf:
            let runner = GGUFRunner()
            runners[.gguf] = runner
            return runner
        case .mlx:
            let runner = MLXRunner()
            runners[.mlx] = runner
            return runner
        case .unknown:
            throw RunnerError.unsupportedFormat(model.format)
        }
    }

    private func appendHistory(model: ModelDescriptor, result: TaskResult, request: TaskRequest) {
        let entry = HistoryItem(
            task: request.task,
            modelName: model.name,
            inputPreview: request.inputText.prefix(160).description,
            outputPreview: result.text.prefix(240).description
        )
        history.insert(entry, at: 0)
        let limit = max(snapshot.preferences.recentHistoryLimit, 0)
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
        let itemsToSave = history
        Task {
            try? await historyStore.save(itemsToSave)
        }
    }

    private func inferRole(format: ModelFormat, sizeClass: String) -> ModelRole {
        if sizeClass == "0.8b" || sizeClass == "1.5b" {
            return .fast
        }
        if sizeClass == "9b" || sizeClass == "14b" || sizeClass == "27b" {
            return .quality
        }
        if format == .gguf {
            return .fast
        }
        return .default
    }

    private func inferContextLength(format: ModelFormat, sizeClass: String) -> Int {
        if format == .gguf && (sizeClass == "0.8b" || sizeClass == "1.5b") {
            return 4096
        }
        return 8192
    }

    private func inferDisplayName(from url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url.lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private struct WebPageTranslationJSONItem: Decodable {
        var id: String
        var translation: String
    }
}
