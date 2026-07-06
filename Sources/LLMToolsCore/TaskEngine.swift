import Foundation

public actor TaskEngine {
    private enum RunnerSlot: Hashable, Sendable {
        case format(ModelFormat)
        case mlxVision
    }

    private let registryStore: RegistryStore
    private let historyStore: HistoryStore
    private var snapshot: RegistrySnapshot
    private var history: [HistoryItem]
    private var runners: [RunnerSlot: any ModelRunner]

    public init(
        registryStore: RegistryStore = RegistryStore(),
        historyStore: HistoryStore = HistoryStore(),
        runners: [ModelFormat: any ModelRunner] = [:]
    ) {
        self.registryStore = registryStore
        self.historyStore = historyStore
        self.snapshot = .init()
        self.history = []
        self.runners = Dictionary(uniqueKeysWithValues: runners.map { (.format($0.key), $0.value) })
    }

    public func bootstrap() async {
        do {
            snapshot = try await registryStore.load()
        } catch {
            snapshot = .init()
        }
        if refreshDetectedLocalVisionCapabilities() {
            sanitizePreferences(&snapshot.preferences, models: snapshot.models)
            try? await registryStore.save(snapshot)
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
            lastErrorMessage: nil,
            capabilities: inferredCapabilities(
                format: detection.format,
                resolvedPath: detection.resolvedPath,
                providerConfiguration: nil
            )
        )
        snapshot.models.append(descriptor)
        if snapshot.preferences.defaultModelID == nil {
            snapshot.preferences.defaultModelID = descriptor.id
        }
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
        return descriptor
    }

    public func addProviderModel(
        providerID: ModelProviderID,
        name: String? = nil,
        modelID: String,
        apiKey: String,
        baseURL: String? = nil,
        contextLength: Int? = nil
    ) async throws -> ModelDescriptor {
        guard let preset = ModelProviderCatalog.preset(for: providerID), preset.apiStyle != .local else {
            throw RunnerError.unsupportedConfiguration("Choose a remote provider.")
        }
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            throw RunnerError.unsupportedConfiguration("Provider model ID is required.")
        }
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if preset.requiresAPIKey && trimmedAPIKey.isEmpty {
            throw RunnerError.unsupportedConfiguration("\(preset.name) API key is required.")
        }

        let baseURLString = (baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? preset.defaultBaseURL
        guard let resolvedBaseURL = URL(string: baseURLString), resolvedBaseURL.scheme != nil, resolvedBaseURL.host != nil else {
            throw RunnerError.unsupportedConfiguration("Provider base URL is invalid.")
        }

        let configuration = ProviderConfiguration(
            providerID: providerID,
            apiStyle: preset.apiStyle,
            baseURL: resolvedBaseURL,
            apiKey: trimmedAPIKey,
            apiKeyKeychainAccount: nil,
            modelID: trimmedModelID,
            maxOutputTokens: preset.defaultMaxOutputTokens
        )
        let descriptorID = UUID()
        let displayName = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(preset.name) · \(trimmedModelID)"
        let descriptor = ModelDescriptor(
            id: descriptorID,
            name: displayName,
            sourcePath: resolvedBaseURL,
            resolvedPath: nil,
            format: ModelProviderCatalog.format(for: preset.apiStyle),
            sizeClass: "remote",
            role: .default,
            contextLength: contextLength ?? preset.defaultContextLength,
            enabled: true,
            validationState: .valid,
            lastErrorMessage: nil,
            providerConfiguration: configuration
        )
        snapshot.models.append(descriptor)
        if snapshot.preferences.defaultModelID == nil {
            snapshot.preferences.defaultModelID = descriptor.id
        }
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
        return descriptor
    }

    public func updateProviderModel(
        id: UUID,
        providerID: ModelProviderID,
        name: String,
        modelID: String,
        apiKey: String,
        baseURL: String,
        contextLength: Int
    ) async throws -> ModelDescriptor {
        guard let index = snapshot.models.firstIndex(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        guard snapshot.models[index].providerConfiguration?.isRemote == true else {
            throw RunnerError.unsupportedConfiguration("Only provider models can be edited here.")
        }
        guard let preset = ModelProviderCatalog.preset(for: providerID), preset.apiStyle != .local else {
            throw RunnerError.unsupportedConfiguration("Choose a remote provider.")
        }

        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else {
            throw RunnerError.unsupportedConfiguration("Provider model ID is required.")
        }
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingConfiguration = snapshot.models[index].providerConfiguration
        let existingInlineAPIKey = existingConfiguration?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let previousProviderID = snapshot.models[index].providerID
        let effectiveAPIKey: String
        if preset.requiresAPIKey {
            if !trimmedAPIKey.isEmpty {
                effectiveAPIKey = trimmedAPIKey
            } else if providerID == previousProviderID {
                effectiveAPIKey = existingInlineAPIKey
            } else {
                effectiveAPIKey = ""
            }
        } else {
            effectiveAPIKey = ""
        }
        if preset.requiresAPIKey && effectiveAPIKey.isEmpty {
            throw RunnerError.unsupportedConfiguration("\(preset.name) API key is required.")
        }

        let baseURLString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedBaseURL = URL(string: baseURLString), resolvedBaseURL.scheme != nil, resolvedBaseURL.host != nil else {
            throw RunnerError.unsupportedConfiguration("Provider base URL is invalid.")
        }

        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(preset.name) · \(trimmedModelID)"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousCapabilities = snapshot.models[index].capabilities
        let configuration = ProviderConfiguration(
            providerID: providerID,
            apiStyle: preset.apiStyle,
            baseURL: resolvedBaseURL,
            apiKey: effectiveAPIKey,
            apiKeyKeychainAccount: nil,
            modelID: trimmedModelID,
            customHeaders: existingConfiguration?.customHeaders ?? [:],
            maxOutputTokens: preset.defaultMaxOutputTokens
        )

        await unloadModel(id: id)
        snapshot.models[index].name = displayName
        snapshot.models[index].sourcePath = resolvedBaseURL
        snapshot.models[index].resolvedPath = nil
        snapshot.models[index].format = ModelProviderCatalog.format(for: preset.apiStyle)
        snapshot.models[index].sizeClass = "remote"
        snapshot.models[index].role = .default
        snapshot.models[index].contextLength = max(contextLength, 1024)
        snapshot.models[index].validationState = .valid
        snapshot.models[index].lastErrorMessage = nil
        snapshot.models[index].providerConfiguration = configuration
        if previousCapabilities.source != .manual {
            snapshot.models[index].capabilities = ModelCapabilities.inferred(
                format: snapshot.models[index].format,
                providerConfiguration: configuration
            )
        }
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
        return snapshot.models[index]
    }

    public func testProviderModel(id: UUID) async throws -> ProviderTestResult {
        guard let model = snapshot.models.first(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        do {
            let result = try await ProviderConnectivity.test(model: model)
            if let index = snapshot.models.firstIndex(where: { $0.id == id }) {
                snapshot.models[index].validationState = .ready
                snapshot.models[index].lastErrorMessage = nil
                try await registryStore.save(snapshot)
            }
            return result
        } catch {
            if let index = snapshot.models.firstIndex(where: { $0.id == id }) {
                snapshot.models[index].validationState = .failed
                snapshot.models[index].lastErrorMessage = error.localizedDescription
                try? await registryStore.save(snapshot)
            }
            throw error
        }
    }

    public func removeModel(id: UUID) async throws {
        snapshot.models.removeAll { $0.id == id }
        if snapshot.preferences.defaultModelID == id {
            snapshot.preferences.defaultModelID = snapshot.models.first?.id
        }
        if snapshot.preferences.webPageTranslation.modelID == id {
            snapshot.preferences.webPageTranslation.modelID = nil
        }
        if snapshot.preferences.ocr.modelID == id {
            snapshot.preferences.ocr.modelID = nil
        }
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
    }

    public func updatePreferences(_ transform: (inout AppPreferences) -> Void) async throws {
        transform(&snapshot.preferences)
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
    }

    public func setPreferences(_ preferences: AppPreferences) async throws {
        snapshot.preferences = preferences
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
    }

    public func visionCapableModels() -> [ModelDescriptor] {
        snapshot.models.filter { $0.enabled && $0.capabilities.supportsImage }
    }

    public func markModelVisionCapable(id: UUID) async throws -> ModelDescriptor {
        try await updateModelCapabilities(
            id: id,
            capabilities: ModelCapabilities.vision(
                source: .manual,
                confidence: 1,
                note: "Manually marked vision-capable."
            )
        )
    }

    public func markModelTextOnly(id: UUID) async throws -> ModelDescriptor {
        try await updateModelCapabilities(
            id: id,
            capabilities: ModelCapabilities.textOnly(
                source: .manual,
                note: "Manually marked text-only."
            )
        )
    }

    public func resetModelCapabilities(id: UUID) async throws -> ModelDescriptor {
        guard let index = snapshot.models.firstIndex(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        let model = snapshot.models[index]
        return try await updateModelCapabilities(
            id: id,
            capabilities: inferredCapabilities(
                format: model.format,
                resolvedPath: model.resolvedPath ?? model.sourcePath,
                providerConfiguration: model.providerConfiguration
            )
        )
    }

    public func testVisionCapability(id: UUID) async throws -> VisionCapabilityProbeResult {
        guard let index = snapshot.models.firstIndex(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        var model = snapshot.models[index]
        guard model.enabled else {
            throw RunnerError.unsupportedConfiguration("Model is disabled.")
        }
        let runner = try runner(for: model, requiringVision: true)
        guard let visionRunner = runner as? any VisionModelRunner else {
            let message = "\(model.name) does not support the Phase 3 OpenAI-compatible vision payload."
            snapshot.models[index].capabilities = ModelCapabilities(
                inputs: [.text],
                source: .failedProbe,
                confidence: 0.9,
                note: "Vision probe failed before provider call.",
                lastCheckedAt: .now,
                lastFailureMessage: message
            )
            sanitizePreferences(&snapshot.preferences, models: snapshot.models)
            try await registryStore.save(snapshot)
            throw OCRTaskError.unsupportedVisionRunner(model.name)
        }

        do {
            if await runner.loadedModelID() != model.id {
                await runner.unload()
                try await runner.load(model: model)
            }
            let request = OCRTaskRequest(
                image: OCRImagePreprocessor.probeImage,
                mode: .explainImage,
                prompt: PromptTemplates.visionProbePrompt()
            )
            let result = try await visionRunner.generateOCR(
                request: request,
                preferences: snapshot.preferences
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw RunnerError.emptyResult
            }
            model.capabilities = ModelCapabilities.vision(
                source: .probePassed,
                confidence: 1,
                note: "Vision probe passed."
            )
            model.capabilities.lastCheckedAt = .now
            snapshot.models[index] = model
            sanitizePreferences(&snapshot.preferences, models: snapshot.models)
            try await registryStore.save(snapshot)
            return VisionCapabilityProbeResult(
                modelID: model.id,
                modelName: model.name,
                ok: true,
                message: text
            )
        } catch {
            snapshot.models[index].capabilities = ModelCapabilities(
                inputs: [.text],
                source: .failedProbe,
                confidence: 0.9,
                note: "Vision probe failed.",
                lastCheckedAt: .now,
                lastFailureMessage: error.localizedDescription
            )
            sanitizePreferences(&snapshot.preferences, models: snapshot.models)
            try? await registryStore.save(snapshot)
            throw error
        }
    }

    public func setRunner(_ runner: any ModelRunner, for format: ModelFormat) {
        runners[.format(format)] = runner
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

    public func runOCR(
        image: OCRImageInput,
        mode: OCRMode,
        modelID: UUID? = nil,
        persistHistory: Bool? = nil
    ) async throws -> TaskResult {
        guard snapshot.preferences.ocr.enabled else {
            throw OCRTaskError.disabled
        }
        let model = try resolveOCRModel(for: modelID)
        guard model.capabilities.supportsImage else {
            throw OCRTaskError.modelNotVisionCapable(model.name)
        }
        let runner = try runner(for: model, requiringVision: true)
        guard let visionRunner = runner as? any VisionModelRunner else {
            throw OCRTaskError.unsupportedVisionRunner(model.name)
        }
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }

        let prompt = PromptTemplates.ocrPrompt(
            mode: mode,
            targetLanguage: snapshot.preferences.defaultTranslationTarget,
            preferences: snapshot.preferences
        )
        let ocrResult = try await visionRunner.generateOCR(
            request: OCRTaskRequest(image: image, mode: mode, prompt: prompt),
            preferences: snapshot.preferences
        )
        let rawModelText = ocrResult.rawModelText ?? ocrResult.text
        let visibleOCRText = ocrResult.structuredMarkdown ?? ocrResult.text
        let finalText: String
        let finalRawText: String
        let finalModelName: String

        if mode == .extractThenTranslate && !isNoReadableText(visibleOCRText) {
            let translation = try await run(
                request: TaskRequest(
                    task: .translate,
                    inputText: visibleOCRText,
                    targetLanguage: snapshot.preferences.defaultTranslationTarget
                ),
                modelID: nil,
                persistHistory: false
            )
            finalText = translation.text
            finalRawText = """
            OCR raw output:
            \(rawModelText)

            Translation raw output:
            \(translation.rawText)
            """
            finalModelName = "\(ocrResult.modelName ?? model.name) -> \(translation.modelName)"
        } else {
            finalText = visibleOCRText
            finalRawText = rawModelText
            finalModelName = ocrResult.modelName ?? model.name
        }

        let result = TaskResult(
            text: finalText,
            rawText: finalRawText,
            modelName: finalModelName,
            task: .ocr
        )
        if persistHistory ?? snapshot.preferences.ocr.persistHistory {
            appendOCRHistory(model: model, result: result, image: image)
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

    private func unloadModel(id: UUID) async {
        for runner in runners.values {
            if await runner.loadedModelID() == id {
                await runner.unload()
            }
        }
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

    private func resolveOCRModel(for modelID: UUID?) throws -> ModelDescriptor {
        if let modelID, let model = snapshot.models.first(where: { $0.id == modelID && $0.enabled }) {
            return model
        }
        if let preferred = snapshot.preferences.ocr.modelID,
           let model = snapshot.models.first(where: { $0.id == preferred && $0.enabled }) {
            return model
        }
        throw OCRTaskError.missingVisionModel
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
                repairAction: "在 llmTools 设置中启用网页翻译。"
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
                qualityMode: payload.translationQuality,
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

    private func runner(for model: ModelDescriptor, requiringVision: Bool = false) throws -> any ModelRunner {
        let slot = runnerSlot(for: model, requiringVision: requiringVision)
        if let runner = runners[slot] {
            return runner
        }
        switch slot {
        case .mlxVision:
            let runner = MLXVLMRunner()
            runners[slot] = runner
            return runner
        case .format(let format):
            switch format {
            case .gguf:
                let runner = GGUFRunner()
                runners[slot] = runner
                return runner
            case .mlx:
                let runner = MLXRunner()
                runners[slot] = runner
                return runner
            case .openAICompatible:
                let runner = OpenAICompatibleRunner()
                runners[slot] = runner
                return runner
            case .anthropicMessages:
                let runner = AnthropicMessagesRunner()
                runners[slot] = runner
                return runner
            case .unknown:
                throw RunnerError.unsupportedFormat(format)
            }
        }
    }

    private func runnerSlot(for model: ModelDescriptor, requiringVision: Bool) -> RunnerSlot {
        if model.format == .mlx,
           (ModelDetection.isLocalVisionModel(at: model.resolvedPath ?? model.sourcePath)
               || (requiringVision && model.capabilities.supportsImage)) {
            return .mlxVision
        }
        return .format(model.format)
    }

    private func inferredCapabilities(
        format: ModelFormat,
        resolvedPath: URL?,
        providerConfiguration: ProviderConfiguration?
    ) -> ModelCapabilities {
        if format == .mlx,
           let resolvedPath,
           ModelDetection.isLocalVisionModel(at: resolvedPath) {
            return ModelCapabilities.vision(
                source: .detected,
                confidence: 0.9,
                note: "Detected local MLX vision-language model metadata."
            )
        }
        return ModelCapabilities.inferred(
            format: format,
            providerConfiguration: providerConfiguration
        )
    }

    private func refreshDetectedLocalVisionCapabilities() -> Bool {
        var changed = false
        for index in snapshot.models.indices {
            let model = snapshot.models[index]
            guard model.format == .mlx,
                  model.capabilities.source != .manual,
                  ModelDetection.isLocalVisionModel(at: model.resolvedPath ?? model.sourcePath) else {
                continue
            }
            let capabilities = ModelCapabilities.vision(
                source: .detected,
                confidence: 0.9,
                note: "Detected local MLX vision-language model metadata."
            )
            if model.capabilities != capabilities {
                snapshot.models[index].capabilities = capabilities
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func updateModelCapabilities(
        id: UUID,
        capabilities: ModelCapabilities
    ) async throws -> ModelDescriptor {
        guard let index = snapshot.models.firstIndex(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        snapshot.models[index].capabilities = capabilities
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
        return snapshot.models[index]
    }

    private func sanitizePreferences(_ preferences: inout AppPreferences, models: [ModelDescriptor]) {
        if let modelID = preferences.defaultModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled }) {
            preferences.defaultModelID = models.first(where: { $0.enabled })?.id
        }
        if let modelID = preferences.webPageTranslation.modelID,
           !models.contains(where: { $0.id == modelID && $0.enabled }) {
            preferences.webPageTranslation.modelID = nil
        }
        if let modelID = preferences.ocr.modelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsImage }) {
            preferences.ocr.modelID = nil
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

    private func appendOCRHistory(model: ModelDescriptor, result: TaskResult, image: OCRImageInput) {
        let entry = HistoryItem(
            task: .ocr,
            modelName: model.name,
            inputPreview: image.redactedHistoryPreview,
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

    private func isNoReadableText(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "no readable text detected."
            || normalized == "未检测到可读文本。"
            || normalized == "未检测到可读文本"
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
        if format == .openAICompatible || format == .anthropicMessages {
            return 32768
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
