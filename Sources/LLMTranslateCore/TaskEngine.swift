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
        if snapshot.preferences.webPageTranslation.modelID == id {
            snapshot.preferences.webPageTranslation.modelID = nil
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
        let persistHistory = snapshot.preferences.webPageTranslation.persistWebHistory
        var translationsByID: [String: WebPageSegmentTranslation] = [:]
        var latestModelName = model.name

        let batchResult = try await runWebPageBatch(
            segments: payload.segments,
            payload: payload,
            model: model,
            isRetry: false,
            persistHistory: persistHistory
        )
        latestModelName = batchResult.modelName
        mergeSuccessfulTranslations(
            batchResult.translations,
            into: &translationsByID
        )
        if hasTranslations(for: payload.segments, in: translationsByID) {
            return webPageResult(
                jobID: payload.jobID,
                modelName: latestModelName,
                segments: payload.segments,
                translations: orderedTranslations(for: payload.segments, from: translationsByID)
            )
        }

        let retrySegments = missingSegments(from: payload.segments, translationsByID: translationsByID)
        let retryResult = try await runWebPageBatch(
            segments: retrySegments,
            payload: payload,
            model: model,
            isRetry: true,
            persistHistory: persistHistory
        )
        latestModelName = retryResult.modelName
        mergeSuccessfulTranslations(
            retryResult.translations,
            into: &translationsByID
        )
        if hasTranslations(for: payload.segments, in: translationsByID) {
            return webPageResult(
                jobID: payload.jobID,
                modelName: latestModelName,
                segments: payload.segments,
                translations: orderedTranslations(for: payload.segments, from: translationsByID)
            )
        }

        let fallbackSegments = missingSegments(from: payload.segments, translationsByID: translationsByID)
        let fallbackResult = try await translateWebPageSegmentsBySplitting(
            fallbackSegments,
            payload: payload,
            model: model,
            persistHistory: persistHistory,
            depth: 0
        )
        latestModelName = fallbackResult.modelName ?? latestModelName
        mergeSuccessfulTranslations(
            fallbackResult.translations,
            into: &translationsByID
        )

        return webPageResult(
            jobID: payload.jobID,
            modelName: latestModelName,
            segments: payload.segments,
            translations: orderedTranslations(for: payload.segments, from: translationsByID)
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

    private func runWebPageBatch(
        segments: [WebPageTranslationSegment],
        payload: WebPageTranslateSegmentsPayload,
        model: ModelDescriptor,
        isRetry: Bool,
        persistHistory: Bool
    ) async throws -> WebPageBatchRunResult {
        guard !segments.isEmpty else {
            return WebPageBatchRunResult(modelName: model.name, translations: [])
        }
        let request = TaskRequest(
            task: .webPageTranslate,
            inputText: try PromptTemplates.webPageBatchPrompt(
                segments: segments,
                targetLanguage: payload.targetLanguage,
                isRetry: isRetry
            ),
            sourceLanguage: payload.sourceLanguage,
            targetLanguage: payload.targetLanguage
        )
        try validateInputSize(request, for: model)
        let result = try await run(
            request: request,
            modelID: model.id,
            persistHistory: persistHistory
        )
        return WebPageBatchRunResult(
            modelName: result.modelName,
            translations: parseWebPageTranslations(from: result.text, segments: segments)
        )
    }

    private func translateWebPageSegmentsBySplitting(
        _ segments: [WebPageTranslationSegment],
        payload: WebPageTranslateSegmentsPayload,
        model: ModelDescriptor,
        persistHistory: Bool,
        depth: Int
    ) async throws -> WebPageFallbackResult {
        guard !segments.isEmpty else {
            return WebPageFallbackResult(modelName: nil, translations: [])
        }
        try Task.checkCancellation()

        if segments.count == 1 {
            let segment = segments[0]
            do {
                let result = try await run(
                    request: TaskRequest(
                        task: .translate,
                        inputText: segment.text,
                        targetLanguage: payload.targetLanguage
                    ),
                    modelID: model.id,
                    persistHistory: persistHistory
                )
                return WebPageFallbackResult(
                    modelName: result.modelName,
                    translations: [
                        WebPageSegmentTranslation(
                            segmentID: segment.segmentID,
                            translation: result.text,
                            status: .translated
                        )
                    ]
                )
            } catch {
                return WebPageFallbackResult(
                    modelName: nil,
                    translations: [
                        WebPageSegmentTranslation(
                            segmentID: segment.segmentID,
                            translation: "",
                            status: .failed,
                            errorMessage: error.localizedDescription
                        )
                    ]
                )
            }
        }

        do {
            let batchResult = try await runWebPageBatch(
                segments: segments,
                payload: payload,
                model: model,
                isRetry: true,
                persistHistory: persistHistory
            )
            var translationsByID: [String: WebPageSegmentTranslation] = [:]
            mergeSuccessfulTranslations(batchResult.translations, into: &translationsByID)
            if hasTranslations(for: segments, in: translationsByID) {
                return WebPageFallbackResult(
                    modelName: batchResult.modelName,
                    translations: orderedTranslations(for: segments, from: translationsByID)
                )
            }

            let missing = missingSegments(from: segments, translationsByID: translationsByID)
            let splitResult = try await splitWebPageSegments(
                missing,
                payload: payload,
                model: model,
                persistHistory: persistHistory,
                depth: depth
            )
            mergeSuccessfulTranslations(splitResult.translations, into: &translationsByID)
            return WebPageFallbackResult(
                modelName: splitResult.modelName ?? batchResult.modelName,
                translations: orderedTranslations(for: segments, from: translationsByID)
            )
        } catch {
            return try await splitWebPageSegments(
                segments,
                payload: payload,
                model: model,
                persistHistory: persistHistory,
                depth: depth
            )
        }
    }

    private func splitWebPageSegments(
        _ segments: [WebPageTranslationSegment],
        payload: WebPageTranslateSegmentsPayload,
        model: ModelDescriptor,
        persistHistory: Bool,
        depth: Int
    ) async throws -> WebPageFallbackResult {
        guard segments.count > 1 else {
            return try await translateWebPageSegmentsBySplitting(
                segments,
                payload: payload,
                model: model,
                persistHistory: persistHistory,
                depth: depth + 1
            )
        }
        let midpoint = max(1, segments.count / 2)
        let left = try await translateWebPageSegmentsBySplitting(
            Array(segments[..<midpoint]),
            payload: payload,
            model: model,
            persistHistory: persistHistory,
            depth: depth + 1
        )
        let right = try await translateWebPageSegmentsBySplitting(
            Array(segments[midpoint...]),
            payload: payload,
            model: model,
            persistHistory: persistHistory,
            depth: depth + 1
        )
        return WebPageFallbackResult(
            modelName: right.modelName ?? left.modelName,
            translations: left.translations + right.translations
        )
    }

    private func parseWebPageTranslations(
        from output: String,
        segments: [WebPageTranslationSegment]
    ) -> [WebPageSegmentTranslation] {
        let jsonText = extractJSONArray(from: output)
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WebPageTranslationJSONItem].self, from: data) else {
            return []
        }

        let expectedIDs = Set(segments.map(\.segmentID))
        var seenIDs = Set<String>()
        return decoded.compactMap { item -> WebPageSegmentTranslation? in
            guard expectedIDs.contains(item.id) else {
                return nil
            }
            guard seenIDs.insert(item.id).inserted else {
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
    }

    private func mergeSuccessfulTranslations(
        _ translations: [WebPageSegmentTranslation],
        into translationsByID: inout [String: WebPageSegmentTranslation]
    ) {
        for translation in translations where translation.status == .translated && !translation.translation.isEmpty {
            translationsByID[translation.segmentID] = translation
        }
    }

    private func hasTranslations(
        for segments: [WebPageTranslationSegment],
        in translationsByID: [String: WebPageSegmentTranslation]
    ) -> Bool {
        segments.allSatisfy { translationsByID[$0.segmentID] != nil }
    }

    private func missingSegments(
        from segments: [WebPageTranslationSegment],
        translationsByID: [String: WebPageSegmentTranslation]
    ) -> [WebPageTranslationSegment] {
        segments.filter { translationsByID[$0.segmentID] == nil }
    }

    private func orderedTranslations(
        for segments: [WebPageTranslationSegment],
        from translationsByID: [String: WebPageSegmentTranslation]
    ) -> [WebPageSegmentTranslation] {
        segments.map { segment in
            translationsByID[segment.segmentID] ?? WebPageSegmentTranslation(
                segmentID: segment.segmentID,
                translation: "",
                status: .failed,
                errorMessage: "Translation failed"
            )
        }
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

    private struct WebPageBatchRunResult {
        var modelName: String
        var translations: [WebPageSegmentTranslation]
    }

    private struct WebPageFallbackResult {
        var modelName: String?
        var translations: [WebPageSegmentTranslation]
    }

    private struct WebPageTranslationJSONItem: Decodable {
        var id: String
        var translation: String
    }
}
