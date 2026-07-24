import Foundation

public actor TaskEngine {
    private enum RunnerSlot: Hashable, Sendable {
        case format(ModelFormat)
        case mlxVision
    }

    private enum LanguageRoutingSurface {
        case text
        case webpage
        case ocr
        case subtitles
    }

    private let registryStore: RegistryStore
    private let historyStore: HistoryStore
    private let languageDetectionService: LanguageDetectionService
    private let speakerDiarizationService: SpeakerDiarizationService
    private let fastTranslationService: FastTranslationCommandRunner
    private var snapshot: RegistrySnapshot
    private var history: [HistoryItem]
    private var runners: [RunnerSlot: any ModelRunner]

    public init(
        registryStore: RegistryStore = RegistryStore(),
        historyStore: HistoryStore = HistoryStore(),
        languageDetectionService: LanguageDetectionService = LanguageDetectionService(),
        speakerDiarizationService: SpeakerDiarizationService = SpeakerDiarizationService(),
        fastTranslationService: FastTranslationCommandRunner = FastTranslationCommandRunner(),
        runners: [ModelFormat: any ModelRunner] = [:]
    ) {
        self.registryStore = registryStore
        self.historyStore = historyStore
        self.languageDetectionService = languageDetectionService
        self.speakerDiarizationService = speakerDiarizationService
        self.fastTranslationService = fastTranslationService
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
        let refreshedVision = refreshDetectedLocalVisionCapabilities()
        let refreshedSpeech = refreshDetectedSpeechCapabilities()
        if refreshedVision || refreshedSpeech {
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
        if let speech = ModelDetection.detectSpeechModel(at: url) {
            return try await addSpeechModel(from: url, name: name, speech: speech)
        }
        let detection = try ModelDetection.detect(from: url)
        let displayName = name ?? inferDisplayName(from: url)
        let inferredRole: ModelRole = role ?? inferRole(format: detection.format, sizeClass: detection.sizeClass)
        let inferredContext = ModelDetection.contextLength(at: detection.resolvedPath)
            ?? inferContextLength(format: detection.format, sizeClass: detection.sizeClass)
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

    public func addModelDescriptorForTesting(_ descriptor: ModelDescriptor) async throws {
        snapshot.models.removeAll { $0.id == descriptor.id }
        snapshot.models.append(descriptor)
        if snapshot.preferences.defaultModelID == nil && descriptor.enabled && descriptor.capabilities.supportsText {
            snapshot.preferences.defaultModelID = descriptor.id
        }
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        try await registryStore.save(snapshot)
    }

    public func addSpeechModel(
        from url: URL,
        name: String? = nil,
        speech: SpeechModelCapabilities? = nil
    ) async throws -> ModelDescriptor {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelDetectionError.pathDoesNotExist(url)
        }
        guard let speech = speech ?? ModelDetection.detectSpeechModel(at: url) else {
            throw ModelDetectionError.unsupported(url)
        }
        let resolvedPath: URL
        if speech.family == .nemotron35ASRStreaming06B,
           let variant = ModelDetection.nemotronStreamingCoreMLVariantDirectory(at: url) {
            resolvedPath = variant
        } else {
            resolvedPath = url
        }
        let displayName = name ?? inferDisplayName(from: url)
        let descriptor = ModelDescriptor(
            name: displayName,
            sourcePath: url,
            resolvedPath: resolvedPath,
            format: .speech,
            sizeClass: speech.family.rawValue,
            role: .default,
            contextLength: 0,
            enabled: true,
            validationState: .valid,
            lastErrorMessage: nil,
            capabilities: ModelCapabilities.speech(speech)
        )
        snapshot.models.append(descriptor)
        sanitizePreferences(&snapshot.preferences, models: snapshot.models)
        if descriptor.capabilities.supportsRealtimeSpeech,
           shouldPromoteRealtimeSpeechModel(descriptor, over: snapshot.preferences.mediaSubtitles.realtimeASRModelID, models: snapshot.models) {
            snapshot.preferences.mediaSubtitles.realtimeASRModelID = descriptor.id
        }
        if snapshot.preferences.mediaSubtitles.fileASRModelID == nil,
           descriptor.capabilities.supportsFileSpeech {
            snapshot.preferences.mediaSubtitles.fileASRModelID = descriptor.id
        }
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
        guard ProviderEndpointPolicy.allows(resolvedBaseURL) else {
            throw RunnerError.unsupportedConfiguration(ProviderEndpointPolicy.secureTransportMessage)
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
        guard ProviderEndpointPolicy.allows(resolvedBaseURL) else {
            throw RunnerError.unsupportedConfiguration(ProviderEndpointPolicy.secureTransportMessage)
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
        if snapshot.preferences.mediaSubtitles.realtimeASRModelID == id {
            snapshot.preferences.mediaSubtitles.realtimeASRModelID = nil
        }
        if snapshot.preferences.mediaSubtitles.fileASRModelID == id {
            snapshot.preferences.mediaSubtitles.fileASRModelID = nil
        }
        if snapshot.preferences.liveMeeting.realtimeASRModelID == id {
            snapshot.preferences.liveMeeting.realtimeASRModelID = nil
        }
        if snapshot.preferences.liveMeeting.fileASRModelID == id {
            snapshot.preferences.liveMeeting.fileASRModelID = nil
        }
        if snapshot.preferences.liveMeeting.notesModelID == id {
            snapshot.preferences.liveMeeting.notesModelID = nil
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

    public func speechCapableModels() -> [ModelDescriptor] {
        snapshot.models.filter { $0.enabled && $0.capabilities.supportsSpeech }
    }

    public func realtimeSpeechModels() -> [ModelDescriptor] {
        snapshot.models.filter { $0.enabled && $0.capabilities.supportsRealtimeSpeech }
    }

    public func fileSpeechModels() -> [ModelDescriptor] {
        snapshot.models.filter { $0.enabled && $0.capabilities.supportsFileSpeech }
    }

    public func checkASRHealth(
        modelID: UUID? = nil,
        mode: SpeechRuntimeMode = .fileOnly,
        sourceLanguageHint: ASRSourceLanguageHint? = nil
    ) async throws -> ASRHealthReport {
        let model = try resolveSpeechModel(for: modelID, mode: mode)
        let runner = LocalASRProcessRunner()
        var asrPreferences = snapshot.preferences.mediaSubtitles
        if let sourceLanguageHint {
            asrPreferences.sourceLanguageHint = sourceLanguageHint
        }
        let report = runner.health(for: model, preferences: asrPreferences, mode: mode)
        if let index = snapshot.models.firstIndex(where: { $0.id == model.id }),
           var speech = snapshot.models[index].capabilities.speech {
            speech.lastCheckedAt = report.checkedAt
            speech.lastFailureMessage = report.status == .ready ? nil : report.message
            snapshot.models[index].capabilities.speech = speech
            snapshot.models[index].capabilities.lastCheckedAt = report.checkedAt
            snapshot.models[index].capabilities.lastFailureMessage = report.status == .ready ? nil : report.message
            snapshot.models[index].validationState = report.status == .ready ? .ready : .failed
            snapshot.models[index].lastErrorMessage = report.status == .ready ? nil : report.message
            try? await registryStore.save(snapshot)
        }
        return report
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

    public func setModelThinkingModeEnabled(id: UUID, enabled: Bool) async throws -> ModelDescriptor {
        guard let index = snapshot.models.firstIndex(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        guard snapshot.models[index].supportsThinkingModeControl else {
            throw RunnerError.unsupportedConfiguration("This model does not support thinking mode control.")
        }
        guard snapshot.models[index].thinkingModeEnabled != enabled else {
            return snapshot.models[index]
        }

        // runner 在 load 时读取该开关，先卸载才能保证下一次请求立即使用新模式。
        await unloadModel(id: id)
        snapshot.models[index].thinkingModeEnabled = enabled
        try await registryStore.save(snapshot)
        return snapshot.models[index]
    }

    public func setModelContextLength(id: UUID, contextLength: Int) async throws -> ModelDescriptor {
        guard let index = snapshot.models.firstIndex(where: { $0.id == id }) else {
            throw RunnerError.unsupportedConfiguration("Model not found.")
        }
        guard !snapshot.models[index].capabilities.supportsSpeech else {
            throw RunnerError.unsupportedConfiguration("Speech models do not use the LLM context setting.")
        }
        guard (1_024...1_048_576).contains(contextLength) else {
            throw RunnerError.unsupportedConfiguration("Context length must be between 1024 and 1048576 tokens.")
        }
        guard snapshot.models[index].contextLength != contextLength else {
            return snapshot.models[index]
        }

        // GGUF 会在 load 时按上下文创建资源，统一卸载可确保所有后端从下一次请求生效。
        await unloadModel(id: id)
        snapshot.models[index].contextLength = contextLength
        try await registryStore.save(snapshot)
        return snapshot.models[index]
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
        let preferredModelID = modelID ?? snapshot.preferences.preferredTextModelID(for: request.task)
        let model = try resolveModel(for: preferredModelID)
        let routedRequest = await requestWithDetectedSourceLanguageIfNeeded(request, surface: .text)
        if let fastResult = try await translateTextWithFastMTIfSelected(routedRequest) {
            if persistHistory {
                appendHistory(model: model, result: fastResult, request: routedRequest)
            }
            return fastResult
        }
        try validateInputSize(routedRequest, for: model)
        let runner = try runner(for: model)
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }
        var result = try await runner.generate(request: routedRequest, preferences: snapshot.preferences)
        result.sourceLanguage = routedRequest.sourceLanguage
        if routedRequest.task == .translate,
           routedRequest.translationOutputMode == .detailed,
           let study = TranslationStudyResult.parse(modelText: result.text) {
            // 复制、历史和原文回填继续使用纯译文；结构化内容只交给支持它的结果视图。
            result.text = study.translation
            result.translationStudy = study
        }
        if persistHistory {
            appendHistory(model: model, result: result, request: routedRequest)
        }
        return result
    }

    private func translateTextWithFastMTIfSelected(_ request: TaskRequest) async throws -> TaskResult? {
        guard request.task == .translate, request.translationOutputMode == .plain else {
            return nil
        }
        let preferences = snapshot.preferences.fastTranslation
        guard preferences.engine(for: .translate) != .llm else {
            return nil
        }
        guard let pair = await fastTranslationPair(forTextRequest: request) else {
            return nil
        }
        let supportedPairs = await fastTranslationService.supportedPairs(preferences: preferences)
        let decision = TranslationRoutingService.decide(
            surface: .text,
            preferences: preferences,
            pair: pair.pair,
            supportedPairs: supportedPairs,
            detectedConfidence: pair.confidence,
            lowConfidenceThreshold: snapshot.preferences.languageRouting.lowConfidenceThreshold
        )
        guard decision.usesFastMT else {
            return nil
        }
        do {
            let translated = try await fastTranslationService.translate(
                batch: [FastTranslationSegment(id: "text", text: request.inputText)],
                pair: pair.pair,
                preferences: preferences
            )
            guard let first = translated.first else {
                throw FastTranslationError.incompleteResponse("Fast translation did not return the text translation.")
            }
            return TaskResult(
                text: first.translation,
                rawText: first.translation,
                modelName: fastTranslationDisplayName(for: first.engineID),
                task: .translate,
                sourceLanguage: pair.pair.source
            )
        } catch {
            if preferences.fallbackPolicy == .fallbackToLLM {
                return nil
            }
            throw error
        }
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

        let dedicatedOCR = ModelDetection.isGLMOCRModel(at: model.resolvedPath ?? model.sourcePath)
        if dedicatedOCR, mode == .explainImage {
            throw OCRTaskError.unsupportedMode(modelName: model.name, mode: mode)
        }
        let prompt = PromptTemplates.ocrPrompt(
            mode: mode,
            targetLanguage: snapshot.preferences.defaultTranslationTarget,
            preferences: snapshot.preferences,
            dedicatedOCR: dedicatedOCR
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
        var detectedOCRSourceLanguage: String?

        if mode == .extractThenTranslate && !isNoReadableText(visibleOCRText) {
            let sourceLanguage = await detectedSourceLanguageIfNeeded(
                for: visibleOCRText,
                currentSourceLanguage: nil,
                targetLanguage: snapshot.preferences.defaultTranslationTarget,
                surface: .ocr,
                confidenceBoost: snapshot.preferences.languageRouting.ocrConfidenceBoost
            )?.language
            detectedOCRSourceLanguage = sourceLanguage
            let translation = try await run(
                request: TaskRequest(
                    task: .translate,
                    inputText: visibleOCRText,
                    sourceLanguage: sourceLanguage,
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
            task: .ocr,
            sourceLanguage: detectedOCRSourceLanguage
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
        let startedAt = Date()
        try validateWebPagePayload(payload)
        let detectedSourceLanguage = await webPageSourceLanguageIfNeeded(
            segments: payload.segments,
            payload: payload
        )
        if let fastResult = try await translateWebPageSegmentsWithFastMTIfSelected(
            payload: payload,
            detectedSourceLanguage: detectedSourceLanguage,
            startedAt: startedAt
        ) {
            return fastResult
        }
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
                translations: orderedTranslations(for: payload.segments, from: translationsByID),
                translationEngineID: TranslationEngineID.llm.rawValue,
                translationModelID: model.id.uuidString,
                detectedSourceLanguage: detectedSourceLanguage,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
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
                translations: orderedTranslations(for: payload.segments, from: translationsByID),
                translationEngineID: TranslationEngineID.llm.rawValue,
                translationModelID: model.id.uuidString,
                detectedSourceLanguage: detectedSourceLanguage,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
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
            translations: orderedTranslations(for: payload.segments, from: translationsByID),
            translationEngineID: TranslationEngineID.llm.rawValue,
            translationModelID: model.id.uuidString,
            detectedSourceLanguage: detectedSourceLanguage,
            elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
        )
    }

    public func transcribeMediaFile(
        at url: URL,
        modelID: UUID? = nil
    ) async throws -> MediaSubtitleFileResult {
        guard snapshot.preferences.mediaSubtitles.isEnabled else {
            throw MediaSubtitleError.disabled
        }
        let startedAt = Date()
        var descriptor = try MediaIntakeService.descriptor(for: url)
        let model = try resolveSpeechModel(for: modelID, mode: .fileOnly)
        let health = LocalASRProcessRunner().health(for: model, preferences: snapshot.preferences.mediaSubtitles, mode: .fileOnly)
        guard health.status == .ready else {
            switch health.status {
            case .modelMissing:
                throw MediaSubtitleError.asrModelMissing(health.message)
            case .runtimeMissing:
                throw MediaSubtitleError.asrRuntimeMissing(health.message)
            case .incompatibleModel:
                throw MediaSubtitleError.asrModelMissing(health.message)
            case .loadFailed, .inferenceFailed:
                throw MediaSubtitleError.asrRuntimeFailed(health.message)
            case .ready:
                throw MediaSubtitleError.asrRuntimeFailed(health.message)
            }
        }
        let normalizedAudio = try await AudioExtractionService.normalizeMediaFile(at: url)
        defer {
            try? FileManager.default.removeItem(at: normalizedAudio.url.deletingLastPathComponent())
        }
        descriptor.duration = normalizedAudio.duration
        let sessionID = UUID()
        var segments = try await LocalASRProcessRunner().transcribe(
            audioURL: normalizedAudio.url,
            model: model,
            sessionID: sessionID,
            duration: normalizedAudio.duration,
            preferences: snapshot.preferences.mediaSubtitles,
            context: ASRTranscriptionContext(
                mode: .fileOnly,
                sourceLanguageHint: snapshot.preferences.mediaSubtitles.sourceLanguageHint,
                isFinal: true
            )
        )
        var diarizationModelID: String?
        var diarizationErrorCode: String?
        var diarizationErrorMessage: String?
        if snapshot.preferences.speakerDiarization.enabledForFileSubtitles {
            if SpeakerTurnMapper.speakerCount(in: segments) > 0 {
                diarizationModelID = health.runtimeSource == .funASRCompositePipeline
                    ? "funasr-nano+cam++"
                    : "\(model.capabilities.speech?.family.rawValue ?? "asr")-native"
            } else if model.capabilities.speech?.canEmitSpeakerLabels == true {
                diarizationModelID = "\(model.capabilities.speech?.family.rawValue ?? "asr")-native"
                diarizationErrorCode = "native_speaker_labels_missing"
                diarizationErrorMessage = "\(model.name) supports native speaker-attributed transcription, but the configured ASR runtime returned no speaker labels. Use the model's rich transcription output instead of plain transcript text."
            } else {
                do {
                    let diarization = try await speakerDiarizationService.diarize(
                        audioURL: normalizedAudio.url,
                        preferences: snapshot.preferences.speakerDiarization
                    )
                    diarizationModelID = diarization.modelID
                    segments = SpeakerTurnMapper.apply(turns: diarization.turns, to: segments)
                } catch {
                    diarizationErrorCode = String(describing: type(of: error))
                    diarizationErrorMessage = Self.userVisibleErrorMessage(error)
                }
            }
        }
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        let diagnostics = MediaSubtitleDiagnostics(
            mediaKind: descriptor.mediaKind,
            fileType: descriptor.fileExtension,
            durationBucket: durationBucket(normalizedAudio.duration),
            sampleRate: normalizedAudio.sampleRate,
            asrModelID: model.id.uuidString,
            targetLanguage: snapshot.preferences.mediaSubtitles.defaultTargetLanguage,
            elapsedMilliseconds: elapsed,
            segmentCount: segments.count,
            speakerCount: SpeakerTurnMapper.speakerCount(in: segments),
            diarizationModelID: diarizationModelID,
            diarizationErrorCode: diarizationErrorCode,
            diarizationErrorMessage: diarizationErrorMessage,
            errorCode: nil,
            urlHash: nil,
            domainHash: nil
        )
        return MediaSubtitleFileResult(
            descriptor: descriptor,
            normalizedAudioURL: normalizedAudio.url,
            segments: segments,
            diagnostics: diagnostics
        )
    }

    public func transcribeMeetingFile(
        at url: URL,
        modelID: UUID? = nil,
        sourceLanguageHint: ASRSourceLanguageHint? = nil,
        expectedSpeakerCount: Int? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> LiveMeetingFileTranscriptionResult {
        guard snapshot.preferences.mediaSubtitles.isEnabled else {
            throw MediaSubtitleError.disabled
        }
        var descriptor = try MediaIntakeService.descriptor(for: url)
        let selectedModelID = modelID ?? snapshot.preferences.liveMeeting.fileASRModelID
        let model = try resolveSpeechModel(for: selectedModelID, mode: .fileOnly)
        var meetingASRPreferences = snapshot.preferences.mediaSubtitles
        meetingASRPreferences.sourceLanguageHint = sourceLanguageHint ?? snapshot.preferences.liveMeeting.sourceLanguageHint
        let health = LocalASRProcessRunner().health(
            for: model,
            preferences: meetingASRPreferences,
            mode: .fileOnly
        )
        guard health.status == .ready else {
            switch health.status {
            case .modelMissing, .incompatibleModel:
                throw MediaSubtitleError.asrModelMissing(health.message)
            case .runtimeMissing:
                throw MediaSubtitleError.asrRuntimeMissing(health.message)
            case .loadFailed, .inferenceFailed, .ready:
                throw MediaSubtitleError.asrRuntimeFailed(health.message)
            }
        }
        let normalizedAudio = try await AudioExtractionService.normalizeMediaFile(
            at: url,
            temporaryDirectory: temporaryDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: normalizedAudio.url.deletingLastPathComponent())
        }
        descriptor.duration = normalizedAudio.duration
        let usesFunASRCompositePipeline = health.runtimeSource == .funASRCompositePipeline
        let canEmitCombinedSpeakers = model.capabilities.speech?.canEmitSpeakerLabels == true
            || usesFunASRCompositePipeline
        var recognitionStrategy: LiveMeetingRecognitionStrategy = .transcriptOnly
        var diarizationModelID: String?
        var segments: [LiveMeetingSegment]

        if canEmitCombinedSpeakers {
            let nativeSubtitles = try await transcribeMeetingAudio(
                audioURL: normalizedAudio.url,
                model: model,
                duration: normalizedAudio.duration,
                preferences: meetingASRPreferences,
                maximumTokens: meetingMaximumTokens(for: model, duration: normalizedAudio.duration)
            )
            let nativeSegments = liveMeetingSegments(from: nativeSubtitles)
            if nativeSegments.contains(where: { $0.speakerID != nil }) {
                recognitionStrategy = usesFunASRCompositePipeline ? .compositeSpeakerASR : .nativeSpeakerASR
                diarizationModelID = usesFunASRCompositePipeline
                    ? "funasr-nano+cam++"
                    : "\(model.capabilities.speech?.family.rawValue ?? "asr")-native"
                segments = nativeSegments
            } else if let speakerAware = try? await transcribeMeetingBySpeakerTurns(
                normalizedAudioURL: normalizedAudio.url,
                duration: normalizedAudio.duration,
                model: model,
                preferences: meetingASRPreferences,
                expectedSpeakerCount: expectedSpeakerCount
            ), !speakerAware.segments.isEmpty {
                recognitionStrategy = .diarizationFirst
                diarizationModelID = speakerAware.diarizationModelID
                segments = speakerAware.segments
            } else {
                segments = nativeSegments
            }
        } else if let speakerAware = try? await transcribeMeetingBySpeakerTurns(
            normalizedAudioURL: normalizedAudio.url,
            duration: normalizedAudio.duration,
            model: model,
            preferences: meetingASRPreferences,
            expectedSpeakerCount: expectedSpeakerCount
        ), !speakerAware.segments.isEmpty {
            recognitionStrategy = .diarizationFirst
            diarizationModelID = speakerAware.diarizationModelID
            segments = speakerAware.segments
        } else {
            let subtitles = try await transcribeMeetingAudio(
                audioURL: normalizedAudio.url,
                model: model,
                duration: normalizedAudio.duration,
                preferences: meetingASRPreferences
            )
            segments = liveMeetingSegments(from: subtitles)
        }
        return LiveMeetingFileTranscriptionResult(
            descriptor: descriptor,
            segments: segments,
            duration: normalizedAudio.duration,
            asrRuntimeSource: health.runtimeSource,
            recognitionStrategy: recognitionStrategy,
            diarizationModelID: diarizationModelID
        )
    }

    private func transcribeMeetingAudio(
        audioURL: URL,
        model: ModelDescriptor,
        duration: TimeInterval?,
        preferences: MediaSubtitlePreferences,
        maximumTokens: Int? = nil
    ) async throws -> [SubtitleSegment] {
        try await LocalASRProcessRunner().transcribe(
            audioURL: audioURL,
            model: model,
            sessionID: UUID(),
            duration: duration,
            preferences: preferences,
            context: ASRTranscriptionContext(
                mode: .fileOnly,
                sourceLanguageHint: preferences.sourceLanguageHint,
                isFinal: true,
                maximumTokens: maximumTokens
            )
        )
    }

    private func transcribeMeetingBySpeakerTurns(
        normalizedAudioURL: URL,
        duration: TimeInterval?,
        model: ModelDescriptor,
        preferences: MediaSubtitlePreferences,
        expectedSpeakerCount: Int?
    ) async throws -> (segments: [LiveMeetingSegment], diarizationModelID: String?) {
        let diarization = try await diarizeMeetingFile(
            at: normalizedAudioURL,
            expectedSpeakerCount: expectedSpeakerCount
        )
        let pcm = try LiveMeetingAudioStorage.readPCM16WAV(at: normalizedAudioURL)
        let audioDuration = duration
            ?? (Double(pcm.data.count / 2) / Double(pcm.sampleRate))
        let slices = LiveMeetingSpeakerTurnPlanner.plan(
            turns: diarization.turns,
            processedThrough: 0,
            stableThrough: audioDuration
        )
        guard !slices.isEmpty else { return ([], diarization.modelID) }

        var result: [LiveMeetingSegment] = []
        for (sliceIndex, slice) in slices.enumerated() {
            try Task.checkCancellation()
            let audio = LiveMeetingAudioStorage.slicePCM16(
                pcm.data,
                sampleRate: pcm.sampleRate,
                startTime: slice.startTime,
                endTime: slice.endTime
            )
            guard !audio.isEmpty else { continue }
            let turnURL = normalizedAudioURL.deletingLastPathComponent()
                .appendingPathComponent(String(format: "meeting-speaker-turn-%06d.wav", sliceIndex))
            try LiveMeetingAudioStorage.writePCM16WAV(data: audio, sampleRate: pcm.sampleRate, to: turnURL)
            defer { try? FileManager.default.removeItem(at: turnURL) }
            let subtitles = try await transcribeMeetingAudio(
                audioURL: turnURL,
                model: model,
                duration: slice.endTime - slice.startTime,
                preferences: preferences,
                maximumTokens: meetingMaximumTokens(for: model, duration: slice.endTime - slice.startTime)
            )
            let technicalSegments = liveMeetingSegments(
                from: subtitles,
                timeOffset: slice.startTime,
                assignedSpeaker: slice,
                startingIndex: result.count
            )
            if let grouped = LiveMeetingTranscriptReducer.groupSpeakerSlice(
                technicalSegments,
                slice: slice,
                index: result.count
            ) {
                result.append(grouped)
            }
        }
        return (result, diarization.modelID)
    }

    private func liveMeetingSegments(
        from subtitles: [SubtitleSegment],
        timeOffset: TimeInterval = 0,
        assignedSpeaker: LiveMeetingSpeakerAudioSlice? = nil,
        startingIndex: Int = 0
    ) -> [LiveMeetingSegment] {
        subtitles.enumerated().map { offset, segment in
            let confidence = assignedSpeaker?.confidence ?? segment.speakerConfidence
            return LiveMeetingSegment(
                id: segment.id,
                index: startingIndex + offset,
                startTime: timeOffset + segment.startTime,
                endTime: segment.endTime.map { timeOffset + $0 },
                text: segment.originalText,
                originalText: segment.originalText,
                speakerID: assignedSpeaker?.speakerID ?? segment.speakerID,
                speakerLabel: assignedSpeaker?.speakerLabel ?? segment.speakerLabel,
                confidence: confidence,
                state: assignedSpeaker?.isLowConfidence == true || confidence.map { $0 < 0.55 } == true
                    ? .lowConfidence
                    : .final
            )
        }
    }

    private func meetingMaximumTokens(
        for model: ModelDescriptor,
        duration: TimeInterval?
    ) -> Int? {
        guard model.capabilities.speech?.canEmitSpeakerLabels == true else { return nil }
        let estimated = Int(max(0, duration ?? 0) * 10)
        return min(32_768, max(8_192, estimated))
    }

    public func generateLocalMeetingNotes(
        segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker],
        modelID: UUID? = nil
    ) async throws -> MeetingNoteState {
        let model = try resolveLocalMeetingNotesModel(for: modelID)
        let usable = segments.filter { $0.state != .partial && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else {
            return MeetingNoteState(
                summary: "暂无可用于生成纪要的已完成转写。",
                language: "zh-Hans",
                sourceSegmentCount: 0,
                generationState: .completed,
                chunkCount: 0
            )
        }
        let contextLimit = InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength)
        let chunkLimit = max(800, min(5_000, contextLimit / 2))
        let chunks = meetingTranscriptChunks(usable, maximumCharacters: chunkLimit)
        var partialNotes: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let result = try await runLocalMeetingNotesPrompt(
                meetingNotesChunkPrompt(chunk),
                model: model
            )
            partialNotes.append(result)
        }
        let finalSource: String
        if partialNotes.count == 1 {
            finalSource = partialNotes[0]
        } else {
            finalSource = try await runLocalMeetingNotesPrompt(
                meetingNotesMergePrompt(partialNotes),
                model: model
            )
        }
        return parseMeetingNotes(
            finalSource,
            sourceSegmentCount: usable.count,
            chunkCount: chunks.count
        )
    }

    public func analyzeTTSScript(
        source: String,
        modelID: UUID? = nil,
        availableVoices: [TTSVoiceProfile] = []
    ) async throws -> TTSScriptAnalysis {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.invalidScript("请输入需要配音的文案。") }
        if availableVoices.isEmpty, let explicit = TTSScriptParser.explicitAnalysis(source) {
            return explicit
        }

        let model = try resolveLocalMeetingNotesModel(for: modelID)
        let contextLimit = InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength)
        let units = TTSScriptParser.sourceUnits(source)
        guard !units.isEmpty else { throw TTSError.invalidScript("无法安全切分原文，请改用显式角色格式。") }
        let chunks = TTSScriptParser.sourceUnitChunks(
            units,
            maximumCharacters: max(400, min(900, contextLimit / 3)),
            maximumUnits: 10
        )
        var mergedVoices = availableVoices.isEmpty ? [TTSVoiceProfile(name: "旁白")] : availableVoices
        var voiceIDsByName = Dictionary(
            mergedVoices.map { ($0.name, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        var knownVoiceIDs = Set(mergedVoices.map(\.id))
        var mergedSegments: [TTSSegment] = []
        var knownRoleNames: [String] = []
        var knownRoleVoiceIndices: [String: Int] = [:]

        for chunk in chunks {
            try Task.checkCancellation()
            let raw = try await runLocalPrompt(
                ttsRoleAnalysisPrompt(
                    chunk,
                    knownRoleNames: knownRoleNames,
                    availableVoices: availableVoices,
                    knownRoleVoiceIndices: knownRoleVoiceIndices
                ),
                task: .ocr,
                model: model,
                returnRawOutput: true
            )
            if ProcessInfo.processInfo.environment["LLMTOOLS_TTS_DEBUG_ANALYSIS"] == "1" {
                // 默认不记录文案；仅显式调试时输出本地模型原始结果。
                FileHandle.standardError.write(Data("[TTS role analysis]\n\(raw)\n".utf8))
            }
            let analysis = try TTSScriptParser.parseModelAssignments(
                raw,
                units: chunk,
                availableVoices: availableVoices
            )
            var roleMapping: [UUID: UUID] = [:]
            for voice in analysis.voices {
                if knownVoiceIDs.contains(voice.id) {
                    roleMapping[voice.id] = voice.id
                    continue
                }
                if let existing = voiceIDsByName[voice.name] {
                    roleMapping[voice.id] = existing
                    continue
                }
                var merged = voice
                merged.id = UUID()
                mergedVoices.append(merged)
                knownVoiceIDs.insert(merged.id)
                voiceIDsByName[merged.name] = merged.id
                if availableVoices.isEmpty {
                    knownRoleNames.append(merged.name)
                }
                roleMapping[voice.id] = merged.id
            }
            for segment in analysis.segments {
                var merged = segment
                merged.index = mergedSegments.count
                if let speakerName = merged.speakerName,
                   let knownVoiceIndex = knownRoleVoiceIndices[speakerName],
                   availableVoices.indices.contains(knownVoiceIndex) {
                    // 首次识别结果成为角色锚点，后续分块即使模型漂移也保持同一音色。
                    merged.roleID = availableVoices[knownVoiceIndex].id
                } else {
                    merged.roleID = roleMapping[segment.roleID] ?? mergedVoices[0].id
                }
                mergedSegments.append(merged)
                if let speakerName = merged.speakerName,
                   !speakerName.isEmpty,
                   knownRoleVoiceIndices[speakerName] == nil,
                   let voiceIndex = availableVoices.firstIndex(where: { $0.id == merged.roleID }) {
                    knownRoleVoiceIndices[speakerName] = voiceIndex
                }
            }
        }
        guard !mergedSegments.isEmpty else { throw TTSError.invalidScript("没有识别出可朗读片段。") }
        return TTSScriptAnalysis(voices: mergedVoices, segments: mergedSegments)
    }

    public func diarizeMeetingFile(
        at audioURL: URL,
        expectedSpeakerCount: Int? = nil
    ) async throws -> SpeakerDiarizationResult {
        guard !SpeakerDiarizationCommandRunner.hasCustomCommand(preferences: snapshot.preferences.speakerDiarization) else {
            throw SpeakerDiarizationError.runtimeMissing(
                "Meeting transcription does not use arbitrary diarization commands. Use the configured local pyannote runtime."
            )
        }
        var meetingPreferences = snapshot.preferences.speakerDiarization
        meetingPreferences.enabledForFileSubtitles = true
        return try await speakerDiarizationService.diarize(
            audioURL: audioURL,
            preferences: meetingPreferences,
            expectedSpeakerCount: expectedSpeakerCount
        )
    }

    private func resolveLocalMeetingNotesModel(for modelID: UUID?) throws -> ModelDescriptor {
        let preferredID = modelID ?? snapshot.preferences.liveMeeting.notesModelID ?? snapshot.preferences.defaultModelID
        let candidates = snapshot.models.filter {
            $0.enabled && $0.capabilities.supportsText && !$0.isRemoteProvider && ($0.format == .gguf || $0.format == .mlx)
        }
        guard !candidates.isEmpty else { throw LiveMeetingError.missingLocalTextModel }
        if let preferredID,
           let model = candidates.first(where: { $0.id == preferredID }) {
            return model
        }
        if let requested = modelID,
           let model = snapshot.models.first(where: { $0.id == requested }) {
            if model.isRemoteProvider { throw LiveMeetingError.remoteTextModelForbidden }
            throw LiveMeetingError.missingLocalTextModel
        }
        return candidates.first(where: { $0.role == .default }) ?? candidates[0]
    }

    private func runLocalMeetingNotesPrompt(_ prompt: String, model: ModelDescriptor) async throws -> String {
        try await runLocalPrompt(prompt, task: .summarize, model: model)
    }

    private func runLocalPrompt(
        _ prompt: String,
        task: TaskKind,
        model: ModelDescriptor,
        returnRawOutput: Bool = false
    ) async throws -> String {
        let request = TaskRequest(task: task, inputText: prompt)
        try validateInputSize(request, for: model)
        let runner = try runner(for: model)
        if await runner.loadedModelID() != model.id {
            await runner.unload()
            try await runner.load(model: model)
        }
        let result = try await runner.generate(request: request, preferences: snapshot.preferences)
        return returnRawOutput ? result.rawText : result.text
    }

    private func meetingTranscriptChunks(_ segments: [LiveMeetingSegment], maximumCharacters: Int) -> [[LiveMeetingSegment]] {
        var result: [[LiveMeetingSegment]] = []
        var current: [LiveMeetingSegment] = []
        var size = 0
        for segment in segments {
            let lineLength = segment.text.count + (segment.speakerLabel?.count ?? 0) + 32
            if !current.isEmpty && size + lineLength > maximumCharacters {
                result.append(current)
                current = []
                size = 0
            }
            current.append(segment)
            size += lineLength
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func meetingNotesChunkPrompt(_ segments: [LiveMeetingSegment]) -> String {
        let transcript = segments.map { segment in
            let speaker = segment.speakerLabel ?? "Unknown"
            return "[\(meetingTimestamp(segment.startTime))] \(speaker): \(segment.text)"
        }.joined(separator: "\n")
        return """
        你是本地会议纪要整理器。基于以下转写，使用简体中文输出严格的 Markdown：
        ## 摘要
        一段简明摘要
        ## 关键决策
        - 决策
        ## 待办事项
        - 事项
        ## 开放问题
        - 问题
        ## 讨论主题
        - 主题

        只输出该 Markdown，不要解释。转写：
        \(transcript)
        """
    }

    private func meetingNotesMergePrompt(_ partialNotes: [String]) -> String {
        """
        你是本地会议纪要整理器。请合并以下分块会议纪要，去重并使用简体中文输出严格的 Markdown：
        ## 摘要
        一段简明摘要
        ## 关键决策
        - 决策
        ## 待办事项
        - 事项
        ## 开放问题
        - 问题
        ## 讨论主题
        - 主题

        只输出该 Markdown，不要解释。
        \(partialNotes.enumerated().map { "### 分块\($0.offset + 1)\n\($0.element)" }.joined(separator: "\n\n"))
        """
    }

    private func ttsRoleAnalysisPrompt(
        _ units: [TTSSourceUnit],
        knownRoleNames: [String],
        availableVoices: [TTSVoiceProfile],
        knownRoleVoiceIndices: [String: Int]
    ) throws -> String {
        let knownRoles = knownRoleNames.isEmpty ? "无" : knownRoleNames.joined(separator: "、")
        let payload = units.map { ["index": $0.index, "text": $0.text] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let sourceJSON = String(data: data, encoding: .utf8) else {
            throw TTSError.invalidScript("无法编码本地角色分析句段。")
        }
        let voiceCatalog = availableVoices.enumerated().map { index, voice in
            [
                "voiceIndex": index,
                "name": voice.name.isEmpty ? "未命名音色" : voice.name,
                "description": voice.instruction
            ] as [String: Any]
        }
        let voiceCatalogData = try JSONSerialization.data(withJSONObject: voiceCatalog, options: [.sortedKeys])
        guard let voiceCatalogJSON = String(data: voiceCatalogData, encoding: .utf8) else {
            throw TTSError.invalidScript("无法编码本地音色目录。")
        }
        let knownVoiceMappings = knownRoleVoiceIndices
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=voiceIndex \($0.value)" }
            .joined(separator: "；")
        let assignmentShape = availableVoices.isEmpty
            ? #"{"index":0,"speaker":"旁白或角色名","type":"narration或dialogue","deliveryStyle":"语气、情绪和语速","pauseAfterMilliseconds":400,"confidence":0.0}"#
            : #"{"index":0,"speaker":"旁白或角色名","voiceIndex":0,"type":"narration或dialogue","deliveryStyle":"语气、情绪和语速","pauseAfterMilliseconds":400,"confidence":0.0}"#
        let voiceRules = availableVoices.isEmpty ? "" : """
        7. 每条 assignment 必须提供 voiceIndex，并且只能从下方音色目录选择；根据角色年龄、性别、性格、语境和叙事类型匹配音色。
        8. 同一 speaker 必须始终复用同一个 voiceIndex。已有映射优先复用：\(knownVoiceMappings.isEmpty ? "无" : knownVoiceMappings)。

        可用音色目录：
        \(voiceCatalogJSON)
        """
        return """
        你是本地有声文案角色与表达标注器。软件已把原文切成带 index 的句段；你只做结构化标注，不要改写或返回原文。
        JSON 格式：
        {"roles":[{"name":"角色名","aliases":[],"voiceHint":"简短音色建议"}],"assignments":[\(assignmentShape)]}

        必须遵守：
        1. 每个输入 index 必须在 assignments 中出现且只出现一次，顺序与输入一致。
        2. 不要输出 text；只有叙述、环境和动作描写使用 narration/旁白。引号内台词必须使用 dialogue，并结合相邻句段推断最可能的说话角色。
        3. speaker 只写稳定的人名或角色名，禁止写动作、神态或整句描述；已知角色优先复用：\(knownRoles)。
        4. roles 不包含旁白，但必须列出本分块出现的其他角色。
        5. deliveryStyle 用简短中文描述本段表达方式，例如“低声克制，带迟疑，语速稍慢”；只写语气、情绪、音量和语速，不要重复角色音色描述。
        6. pauseAfterMilliseconds 是本段结束后的停顿整数：连续语句 250-400，完整句 400-600，换人或强烈情绪 500-800，场景或章节转换 800-1500。
        \(voiceRules)

        句段：
        \(sourceJSON)
        """
    }

    private func parseMeetingNotes(_ text: String, sourceSegmentCount: Int, chunkCount: Int) -> MeetingNoteState {
        var sections: [String: [String]] = [:]
        var current = "摘要"
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                current = String(trimmed.dropFirst(3))
                continue
            }
            guard !trimmed.isEmpty else { continue }
            sections[current, default: []].append(trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed)
        }
        func values(_ keys: [String]) -> [String] {
            keys.flatMap { sections[$0] ?? [] }
        }
        return MeetingNoteState(
            summary: values(["摘要", "Summary"]).joined(separator: " "),
            decisions: values(["关键决策", "决策", "Decisions"]),
            actionItems: values(["待办事项", "行动项", "Action Items"]),
            openQuestions: values(["开放问题", "问题", "Open Questions"]),
            topics: values(["讨论主题", "主题", "Topics"]),
            language: "zh-Hans",
            sourceSegmentCount: sourceSegmentCount,
            generationState: .completed,
            isStale: false,
            chunkCount: chunkCount
        )
    }

    private func meetingTimestamp(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func userVisibleErrorMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? String(describing: type(of: error)) : normalized
    }

    public func translateSubtitleSegments(
        _ segments: [SubtitleSegment],
        targetLanguage: String? = nil,
        modelID: UUID? = nil
    ) async throws -> [SubtitleSegment] {
        guard !segments.isEmpty else {
            return []
        }
        let target = targetLanguage ?? snapshot.preferences.mediaSubtitles.defaultTargetLanguage
        let routedSegments = await subtitleSegmentsWithDetectedSourceLanguageIfNeeded(
            segments,
            targetLanguage: target
        )
        if let fastResult = try await translateSubtitleSegmentsWithFastMTIfSelected(
            routedSegments,
            targetLanguage: target
        ) {
            return fastResult
        }
        let model = try resolveTextModel(for: modelID)
        return try await translateSubtitleSegmentsWithLLM(
            routedSegments,
            targetLanguage: target,
            model: model
        )
    }

    private func translateSubtitleSegmentsWithLLM(
        _ routedSegments: [SubtitleSegment],
        targetLanguage target: String,
        model: ModelDescriptor
    ) async throws -> [SubtitleSegment] {
        var translatedByID = try await runSubtitleTranslationBatches(
            segments: routedSegments,
            targetLanguage: target,
            model: model,
            isRetry: false
        )
        if translatedByID.count < routedSegments.count {
            let missing = routedSegments.filter { translatedByID[$0.id.uuidString] == nil }
            let retry = try await runSubtitleTranslationBatches(
                segments: missing,
                targetLanguage: target,
                model: model,
                isRetry: true
            )
            translatedByID.merge(retry) { current, _ in current }
        }
        return routedSegments.map { segment in
            var updated = segment
            updated.translatedText = translatedByID[segment.id.uuidString]
            updated.translationModelID = model.id.uuidString
            updated.translationEngineID = TranslationEngineID.llm.rawValue
            return updated
        }
    }

    private func runSubtitleTranslationBatches(
        segments: [SubtitleSegment],
        targetLanguage: String,
        model: ModelDescriptor,
        isRetry: Bool
    ) async throws -> [String: String] {
        guard !segments.isEmpty else {
            return [:]
        }
        let batches = try subtitleTranslationBatches(
            segments: segments,
            targetLanguage: targetLanguage,
            model: model,
            isRetry: isRetry
        )
        var translatedByID: [String: String] = [:]
        for batch in batches {
            try Task.checkCancellation()
            if batch.count == 1,
               let segment = batch.first,
               try subtitleTranslationPromptLength(
                   segments: batch,
                   targetLanguage: targetLanguage,
                   isRetry: isRetry
               ) > InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength) {
                translatedByID[segment.id.uuidString] = try await translateOversizedSubtitleSegment(
                    segment,
                    targetLanguage: targetLanguage,
                    model: model
                )
                continue
            }
            let batchTranslations = try await runSubtitleTranslationBatch(
                segments: batch,
                targetLanguage: targetLanguage,
                model: model,
                isRetry: isRetry
            )
            translatedByID.merge(batchTranslations) { current, _ in current }
        }
        return translatedByID
    }

    private func subtitleTranslationBatches(
        segments: [SubtitleSegment],
        targetLanguage: String,
        model: ModelDescriptor,
        isRetry: Bool
    ) throws -> [[SubtitleSegment]] {
        let hardLimit = InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength)
        let softLimit = subtitleTranslationSoftLimit(forHardLimit: hardLimit)
        var batches: [[SubtitleSegment]] = []
        var current: [SubtitleSegment] = []

        for segment in segments {
            let candidate = current + [segment]
            let candidatePromptLength = try subtitleTranslationPromptLength(
                segments: candidate,
                targetLanguage: targetLanguage,
                isRetry: isRetry
            )
            if !current.isEmpty && candidatePromptLength > softLimit {
                batches.append(current)
                current = [segment]
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private func subtitleTranslationSoftLimit(forHardLimit hardLimit: Int) -> Int {
        let reserve = min(1_024, max(256, hardLimit / 5))
        return max(1, hardLimit - reserve)
    }

    private func subtitleTranslationPromptLength(
        segments: [SubtitleSegment],
        targetLanguage: String,
        isRetry: Bool
    ) throws -> Int {
        try PromptTemplates.subtitleBatchPrompt(
            segments: segments,
            targetLanguage: targetLanguage,
            isRetry: isRetry
        ).count
    }

    private func translateOversizedSubtitleSegment(
        _ segment: SubtitleSegment,
        targetLanguage: String,
        model: ModelDescriptor
    ) async throws -> String {
        let limit = InputSizePolicy.maximumInputCharacters(forContextLength: model.contextLength)
        let chunks = subtitleTextChunks(segment.originalText, hardLimit: limit)
        var translatedChunks: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let request = TaskRequest(
                task: .translate,
                inputText: chunk,
                sourceLanguage: segment.sourceLanguage ?? "auto",
                targetLanguage: targetLanguage
            )
            try validateInputSize(request, for: model)
            let result = try await run(
                request: request,
                modelID: model.id,
                persistHistory: snapshot.preferences.mediaSubtitles.saveTranslatedSubtitleHistory
            )
            let translated = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !translated.isEmpty {
                translatedChunks.append(translated)
            }
        }
        return translatedChunks.joined(separator: "\n")
    }

    private func subtitleTextChunks(_ text: String, hardLimit: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        let limit = max(1, subtitleTranslationSoftLimit(forHardLimit: hardLimit))
        guard trimmed.count > limit else {
            return [trimmed]
        }
        var chunks: [String] = []
        var start = trimmed.startIndex
        while start < trimmed.endIndex {
            let hardEnd = trimmed.index(start, offsetBy: limit, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let end = preferredSubtitleChunkBoundary(in: trimmed, start: start, proposedEnd: hardEnd)
            let chunk = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            start = end
            while start < trimmed.endIndex, trimmed[start].isWhitespace {
                start = trimmed.index(after: start)
            }
        }
        return chunks
    }

    private func preferredSubtitleChunkBoundary(
        in text: String,
        start: String.Index,
        proposedEnd: String.Index
    ) -> String.Index {
        guard proposedEnd < text.endIndex else {
            return text.endIndex
        }
        let minimumDistance = max(1, text.distance(from: start, to: proposedEnd) / 2)
        let minimumIndex = text.index(start, offsetBy: minimumDistance, limitedBy: proposedEnd) ?? start
        var index = proposedEnd
        while index > minimumIndex {
            let previous = text.index(before: index)
            if text[previous].isWhitespace || ".!?。！？；;，,".contains(text[previous]) {
                return index
            }
            index = previous
        }
        return proposedEnd
    }

    private func translateSubtitleSegmentsWithFastMTIfSelected(
        _ segments: [SubtitleSegment],
        targetLanguage: String
    ) async throws -> [SubtitleSegment]? {
        guard let pair = fastTranslationPair(from: segments, targetLanguage: targetLanguage) else {
            return nil
        }
        let preferences = snapshot.preferences.fastTranslation
        let supportedPairs = await fastTranslationService.supportedPairs(preferences: preferences)
        let confidence = segments.compactMap(\.languageConfidence).max()
        let decision = TranslationRoutingService.decide(
            surface: .subtitle,
            preferences: preferences,
            pair: pair,
            supportedPairs: supportedPairs,
            detectedConfidence: confidence,
            lowConfidenceThreshold: snapshot.preferences.languageRouting.lowConfidenceThreshold
        )
        guard decision.usesFastMT else {
            return nil
        }
        do {
            let translated = try await fastTranslationService.translate(
                batch: segments.map { FastTranslationSegment(id: $0.id.uuidString, text: $0.originalText) },
                pair: pair,
                preferences: preferences
            )
            let translatedByID = Dictionary(uniqueKeysWithValues: translated.map { ($0.id, $0) })
            guard translatedByID.count == segments.count else {
                throw FastTranslationError.incompleteResponse("Fast translation did not return all subtitle segments.")
            }
            return segments.map { segment in
                var updated = segment
                if let translated = translatedByID[segment.id.uuidString] {
                    updated.translatedText = translated.translation
                    updated.translationEngineID = translated.engineID.rawValue
                    updated.translationModelID = translated.modelID
                }
                return updated
            }
        } catch {
            if preferences.fallbackPolicy == .fallbackToLLM {
                return nil
            }
            throw error
        }
    }

    private func fastTranslationPair(
        from segments: [SubtitleSegment],
        targetLanguage: String
    ) -> LanguagePair? {
        guard let target = LanguageCodeNormalizer.normalizedBCP47(targetLanguage) else {
            return nil
        }
        let source = segments.lazy.compactMap { segment -> String? in
            LanguageCodeNormalizer.normalizedBCP47(segment.sourceLanguage)
        }.first
        guard let source, source != target else {
            return nil
        }
        return LanguagePair(source: source, target: target)
    }

    private func fastTranslationPair(
        sourceLanguage: String,
        targetLanguage: String
    ) -> LanguagePair? {
        guard let source = LanguageCodeNormalizer.normalizedBCP47(sourceLanguage),
              let target = LanguageCodeNormalizer.normalizedBCP47(targetLanguage),
              source != target else {
            return nil
        }
        return LanguagePair(source: source, target: target)
    }

    private func fastTranslationPair(forTextRequest request: TaskRequest) async -> (pair: LanguagePair, confidence: Double)? {
        let targetLanguage = request.targetLanguage ?? snapshot.preferences.defaultTranslationTarget
        guard let target = LanguageCodeNormalizer.normalizedBCP47(targetLanguage) else {
            return nil
        }
        if let source = LanguageCodeNormalizer.normalizedBCP47(request.sourceLanguage), source != target {
            return (LanguagePair(source: source, target: target), 1)
        }
        var routingPreferences = snapshot.preferences.languageRouting
        routingPreferences.enabled = true
        routingPreferences.useForTextTasks = true
        do {
            let detected = try await languageDetectionService.detect(
                text: languageDetectionSample([request.inputText]),
                preferences: routingPreferences
            )
            guard let source = detected.language, source != target, detected.isReliable else {
                return nil
            }
            return (LanguagePair(source: source, target: target), detected.confidence)
        } catch {
            return nil
        }
    }

    public func exportSubtitleSegments(
        _ segments: [SubtitleSegment],
        format: SubtitleExportFormat,
        mode: SubtitleDisplayMode,
        options: SubtitleExportOptions = SubtitleExportOptions()
    ) throws -> String {
        try SubtitleExporter.render(segments: segments, format: format, mode: mode, options: options)
    }

    public func checkSpeakerDiarizationHealth() async -> SpeakerDiarizationHealth {
        await speakerDiarizationService.health(preferences: snapshot.preferences.speakerDiarization)
    }

    public func checkFastTranslationHealth() async -> FastTranslationHealth {
        await fastTranslationService.probe(preferences: snapshot.preferences.fastTranslation)
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
        // 全局空闲卸载也要覆盖进程型模型，不能只清理进程内的 GGUF/MLX runner。
        await languageDetectionService.stop()
        await fastTranslationService.stop()
    }

    private func unloadModel(id: UUID) async {
        for runner in runners.values {
            if await runner.loadedModelID() == id {
                await runner.unload()
            }
        }
    }

    private func resolveModel(for modelID: UUID?) throws -> ModelDescriptor {
        try resolveTextModel(for: modelID)
    }

    private func resolveTextModel(for modelID: UUID?) throws -> ModelDescriptor {
        if let modelID, let model = snapshot.models.first(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsText }) {
            return model
        }
        if let preferred = snapshot.preferences.defaultModelID,
           let model = snapshot.models.first(where: { $0.id == preferred && $0.enabled && $0.capabilities.supportsText }) {
            return model
        }
        if let firstEnabled = snapshot.models.first(where: { $0.enabled && $0.capabilities.supportsText }) {
            return firstEnabled
        }
        throw RunnerError.unsupportedConfiguration("No enabled model is registered.")
    }

    private func resolveSpeechModel(for modelID: UUID?, mode: SpeechRuntimeMode) throws -> ModelDescriptor {
        let supportsRequestedMode: (ModelDescriptor) -> Bool = { model in
            guard model.enabled, model.capabilities.supportsSpeech else {
                return false
            }
            switch mode {
            case .realtime:
                return model.capabilities.supportsRealtimeSpeech
            case .fileOnly:
                return model.capabilities.supportsFileSpeech
            }
        }
        if let modelID, let model = snapshot.models.first(where: { $0.id == modelID && supportsRequestedMode($0) }) {
            return model
        }
        let preferred = mode == .realtime
            ? snapshot.preferences.mediaSubtitles.realtimeASRModelID
            : snapshot.preferences.mediaSubtitles.fileASRModelID
        if let preferred,
           let model = snapshot.models.first(where: { $0.id == preferred && supportsRequestedMode($0) }) {
            return model
        }
        if mode == .fileOnly,
           let realtime = snapshot.preferences.mediaSubtitles.realtimeASRModelID,
           let model = snapshot.models.first(where: { $0.id == realtime && supportsRequestedMode($0) }) {
            return model
        }
        if let first = snapshot.models.first(where: supportsRequestedMode) {
            return first
        }
        throw MediaSubtitleError.missingASRModel
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
            sourceLanguage: await webPageSourceLanguageIfNeeded(
                segments: segments,
                payload: payload
            ),
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

    private func translateWebPageSegmentsWithFastMTIfSelected(
        payload: WebPageTranslateSegmentsPayload,
        detectedSourceLanguage: String,
        startedAt: Date
    ) async throws -> WebPageTranslateSegmentsResult? {
        guard let pair = fastTranslationPair(
            sourceLanguage: detectedSourceLanguage,
            targetLanguage: payload.targetLanguage
        ) else {
            return nil
        }
        let preferences = snapshot.preferences.fastTranslation
        let supportedPairs = await fastTranslationService.supportedPairs(preferences: preferences)
        let decision = TranslationRoutingService.decide(
            surface: .webpage,
            preferences: preferences,
            pair: pair,
            supportedPairs: supportedPairs,
            detectedConfidence: sourceLanguageIsExplicit(detectedSourceLanguage) ? 1 : nil,
            lowConfidenceThreshold: snapshot.preferences.languageRouting.lowConfidenceThreshold,
            domainOverride: payload.translationEngine
        )
        guard decision.usesFastMT else {
            return nil
        }
        do {
            let translated = try await fastTranslationService.translate(
                batch: payload.segments.map { FastTranslationSegment(id: $0.segmentID, text: $0.text) },
                pair: pair,
                preferences: preferences
            )
            let translatedByID = Dictionary(uniqueKeysWithValues: translated.map { ($0.id, $0) })
            let ordered = payload.segments.map { segment -> WebPageSegmentTranslation in
                guard let translated = translatedByID[segment.segmentID] else {
                    return WebPageSegmentTranslation(
                        segmentID: segment.segmentID,
                        translation: "",
                        status: .failed,
                        errorMessage: "Fast translation did not return this segment."
                    )
                }
                return WebPageSegmentTranslation(
                    segmentID: segment.segmentID,
                    translation: translated.translation,
                    status: .translated
                )
            }
            let firstTranslation = translated.first
            return webPageResult(
                jobID: payload.jobID,
                modelName: fastTranslationDisplayName(for: firstTranslation?.engineID ?? decision.engineID),
                segments: payload.segments,
                translations: ordered,
                translationEngineID: firstTranslation?.engineID.rawValue ?? decision.engineID.rawValue,
                translationModelID: firstTranslation?.modelID ?? decision.modelID,
                detectedSourceLanguage: pair.source,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        } catch {
            if preferences.fallbackPolicy == .fallbackToLLM {
                return nil
            }
            throw WebPageTranslationError(
                code: .translationFailed,
                message: error.localizedDescription,
                diagnostic: "fastMT"
            )
        }
    }

    private func fastTranslationDisplayName(for engineID: TranslationEngineID) -> String {
        switch engineID {
        case .ctranslate2:
            return "Fast MT (CTranslate2)"
        case .argos:
            return "Fast MT (Argos)"
        case .customCommand:
            return "Fast MT (Custom)"
        case .llm:
            return "LLM"
        }
    }

    private func requestWithDetectedSourceLanguageIfNeeded(
        _ request: TaskRequest,
        surface: LanguageRoutingSurface
    ) async -> TaskRequest {
        guard request.task != .webPageTranslate else {
            return request
        }
        guard let detected = await detectedSourceLanguageIfNeeded(
            for: request.inputText,
            currentSourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage ?? snapshot.preferences.defaultTranslationTarget,
            surface: surface
        ) else {
            return request
        }
        var updated = request
        updated.sourceLanguage = detected.language
        return updated
    }

    private func webPageSourceLanguageIfNeeded(
        segments: [WebPageTranslationSegment],
        payload: WebPageTranslateSegmentsPayload
    ) async -> String {
        guard !sourceLanguageIsExplicit(payload.sourceLanguage) else {
            return payload.sourceLanguage
        }
        let sample = languageDetectionSample(segments.map(\.text))
        if let scriptLanguage = scriptDetectedSourceLanguage(for: sample) {
            return scriptLanguage
        }
        var routingPreferences = snapshot.preferences.languageRouting
        routingPreferences.enabled = true
        routingPreferences.useForWebpage = true
        return await detectedSourceLanguageIfNeeded(
            for: sample,
            currentSourceLanguage: payload.sourceLanguage,
            targetLanguage: payload.targetLanguage,
            surface: .webpage,
            preferencesOverride: routingPreferences
        )?.language ?? payload.sourceLanguage
    }

    private func subtitleSegmentsWithDetectedSourceLanguageIfNeeded(
        _ segments: [SubtitleSegment],
        targetLanguage: String
    ) async -> [SubtitleSegment] {
        let currentSource = segments.compactMap(\.sourceLanguage).first
        let sample = languageDetectionSample(segments.map(\.originalText))
        guard let detected = await detectedSourceLanguageIfNeeded(
            for: sample,
            currentSourceLanguage: currentSource,
            targetLanguage: targetLanguage,
            surface: .subtitles
        ) else {
            return segments
        }
        return segments.map { segment in
            guard !sourceLanguageIsExplicit(segment.sourceLanguage) else {
                return segment
            }
            var updated = segment
            updated.sourceLanguage = detected.language
            updated.languageConfidence = detected.confidence
            updated.sourceLanguageDetectorModel = detected.detectorModel
            return updated
        }
    }

    private func detectedSourceLanguageIfNeeded(
        for text: String,
        currentSourceLanguage: String?,
        targetLanguage: String?,
        surface: LanguageRoutingSurface,
        confidenceBoost: Double = 0,
        preferencesOverride: LanguageRoutingPreferences? = nil
    ) async -> LanguageDetectionResult? {
        let preferences = preferencesOverride ?? snapshot.preferences.languageRouting
        guard languageRoutingEnabled(for: surface, preferences: preferences),
              !sourceLanguageIsExplicit(currentSourceLanguage) else {
            return nil
        }
        let sample = languageDetectionSample([text])
        guard !sample.isEmpty else {
            return nil
        }
        do {
            var result = try await languageDetectionService.detect(
                text: sample,
                preferences: preferences
            )
            guard let language = result.language else {
                return nil
            }
            let effectiveConfidence = min(max(result.confidence + confidenceBoost, 0), 1)
            guard effectiveConfidence >= preferences.lowConfidenceThreshold else {
                return nil
            }
            result.language = language
            result.confidence = effectiveConfidence
            result.isReliable = true
            return result
        } catch {
            return nil
        }
    }

    private func languageRoutingEnabled(
        for surface: LanguageRoutingSurface,
        preferences: LanguageRoutingPreferences
    ) -> Bool {
        guard preferences.enabled else {
            return false
        }
        switch surface {
        case .text:
            return preferences.useForTextTasks
        case .webpage:
            return preferences.useForWebpage
        case .ocr:
            return preferences.useForOCR
        case .subtitles:
            return preferences.useForSubtitles
        }
    }

    private func sourceLanguageIsExplicit(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return false
        }
        return value.lowercased() != "auto"
    }

    private func languageDetectionSample(_ texts: [String], maxCharacters: Int = 4_000) -> String {
        var sample = ""
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if !sample.isEmpty {
                sample += "\n"
            }
            let remaining = maxCharacters - sample.count
            guard remaining > 0 else {
                break
            }
            sample += String(trimmed.prefix(remaining))
            if sample.count >= maxCharacters {
                break
            }
        }
        return sample
    }

    private func scriptDetectedSourceLanguage(for text: String) -> String? {
        var kanaCount = 0
        var hangulCount = 0
        var thaiCount = 0
        var arabicCount = 0
        var devanagariCount = 0
        var cyrillicCount = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0xFF66...0xFF9F:
                kanaCount += 1
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
                hangulCount += 1
            case 0x0E00...0x0E7F:
                thaiCount += 1
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
                arabicCount += 1
            case 0x0900...0x097F:
                devanagariCount += 1
            case 0x0400...0x04FF, 0x0500...0x052F:
                cyrillicCount += 1
            default:
                continue
            }
        }
        if kanaCount >= 2 {
            return "ja"
        }
        if hangulCount >= 2 {
            return "ko"
        }
        if thaiCount >= 2 {
            return "th"
        }
        if arabicCount >= 2 {
            return "ar"
        }
        if devanagariCount >= 2 {
            return "hi"
        }
        if cyrillicCount >= 2 {
            return "ru"
        }
        return nil
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
                let sourceLanguage = await webPageSourceLanguageIfNeeded(
                    segments: [segment],
                    payload: payload
                )
                let result = try await run(
                    request: TaskRequest(
                        task: .translate,
                        inputText: segment.text,
                        sourceLanguage: sourceLanguage,
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

    private func runSubtitleTranslationBatch(
        segments: [SubtitleSegment],
        targetLanguage: String,
        model: ModelDescriptor,
        isRetry: Bool
    ) async throws -> [String: String] {
        let request = TaskRequest(
            task: .webPageTranslate,
            inputText: try PromptTemplates.subtitleBatchPrompt(
                segments: segments,
                targetLanguage: targetLanguage,
                isRetry: isRetry
            ),
            sourceLanguage: "auto",
            targetLanguage: targetLanguage
        )
        try validateInputSize(request, for: model)
        let result = try await run(
            request: request,
            modelID: model.id,
            persistHistory: snapshot.preferences.mediaSubtitles.saveTranslatedSubtitleHistory
        )
        let expectedIDs = Set(segments.map { $0.id.uuidString })
        let jsonText = extractJSONArray(from: result.text)
        guard let data = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SubtitleTranslationJSONItem].self, from: data) else {
            throw MediaSubtitleError.translationFailed("The translation model did not return subtitle JSON.")
        }
        var translatedByID: [String: String] = [:]
        for item in decoded where expectedIDs.contains(item.id) {
            let translation = item.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !translation.isEmpty {
                translatedByID[item.id] = translation
            }
        }
        return translatedByID
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
        translations: [WebPageSegmentTranslation],
        translationEngineID: String = TranslationEngineID.llm.rawValue,
        translationModelID: String? = nil,
        detectedSourceLanguage: String? = nil,
        elapsedMilliseconds: Int? = nil,
        fallbackReason: String? = nil
    ) -> WebPageTranslateSegmentsResult {
        let sourceCharacters = segments.reduce(0) { $0 + $1.text.count }
        let targetCharacters = translations.reduce(0) { $0 + $1.translation.count }
        return WebPageTranslateSegmentsResult(
            jobID: jobID,
            modelName: modelName,
            translationEngineID: translationEngineID,
            translationModelID: translationModelID,
            detectedSourceLanguage: detectedSourceLanguage,
            elapsedMilliseconds: elapsedMilliseconds,
            fallbackReason: fallbackReason,
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
            case .speech:
                throw RunnerError.unsupportedFormat(format)
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
            if ModelDetection.isGLMOCRModel(at: resolvedPath) {
                return ModelCapabilities.ocrOnly(
                    source: .detected,
                    confidence: 0.95,
                    note: "Detected GLM-OCR local single-image OCR metadata."
                )
            }
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
            let modelPath = model.resolvedPath ?? model.sourcePath
            let capabilities: ModelCapabilities
            if ModelDetection.isGLMOCRModel(at: modelPath) {
                capabilities = ModelCapabilities.ocrOnly(
                    source: .detected,
                    confidence: 0.95,
                    note: "Detected GLM-OCR local single-image OCR metadata."
                )
            } else {
                capabilities = ModelCapabilities.vision(
                    source: .detected,
                    confidence: 0.9,
                    note: "Detected local MLX vision-language model metadata."
                )
            }
            if model.capabilities != capabilities {
                snapshot.models[index].capabilities = capabilities
                changed = true
            }
        }
        return changed
    }

    private func refreshDetectedSpeechCapabilities() -> Bool {
        var changed = false
        for index in snapshot.models.indices {
            let model = snapshot.models[index]
            guard model.format == .speech,
                  model.capabilities.source != .manual,
                  let detected = ModelDetection.detectSpeechModel(at: model.resolvedPath ?? model.sourcePath) else {
                continue
            }
            var speech = detected
            speech.lastCheckedAt = model.capabilities.speech?.lastCheckedAt
            speech.lastFailureMessage = model.capabilities.speech?.lastFailureMessage
            var capabilities = ModelCapabilities.speech(speech)
            capabilities.lastCheckedAt = model.capabilities.lastCheckedAt
            capabilities.lastFailureMessage = model.capabilities.lastFailureMessage
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
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsText }) {
            preferences.defaultModelID = models.first(where: { $0.enabled && $0.capabilities.supportsText })?.id
        }
        preferences.textTaskModelIDs = preferences.textTaskModelIDs.filter { entry in
            TaskKind.perTaskModelCases.contains(entry.key)
                && models.contains(where: { $0.id == entry.value && $0.enabled && $0.capabilities.supportsText })
        }
        if let modelID = preferences.detailedTranslationModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsText }) {
            preferences.detailedTranslationModelID = nil
        }
        if let modelID = preferences.webPageTranslation.modelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsText }) {
            preferences.webPageTranslation.modelID = nil
        }
        if let modelID = preferences.ocr.modelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsImage }) {
            preferences.ocr.modelID = nil
        }
        if let modelID = preferences.mediaSubtitles.realtimeASRModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsRealtimeSpeech }) {
            preferences.mediaSubtitles.realtimeASRModelID = preferredRealtimeSpeechModel(in: models)?.id
        }
        if let modelID = preferences.mediaSubtitles.fileASRModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsFileSpeech }) {
            preferences.mediaSubtitles.fileASRModelID = models.first(where: { $0.enabled && $0.capabilities.supportsFileSpeech })?.id
        }
        if preferences.mediaSubtitles.fileASRModelID == nil {
            preferences.mediaSubtitles.fileASRModelID = models.first(where: { $0.enabled && $0.capabilities.supportsFileSpeech })?.id
        }
        if preferences.mediaSubtitles.realtimeASRModelID == nil {
            preferences.mediaSubtitles.realtimeASRModelID = preferredRealtimeSpeechModel(in: models)?.id
        }
        if let modelID = preferences.liveMeeting.realtimeASRModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.supportsMeetingCaptureSpeech }) {
            preferences.liveMeeting.realtimeASRModelID = nil
        }
        if let modelID = preferences.liveMeeting.fileASRModelID,
           !models.contains(where: { $0.id == modelID && $0.enabled && $0.capabilities.supportsFileSpeech }) {
            preferences.liveMeeting.fileASRModelID = nil
        }
        if let modelID = preferences.liveMeeting.notesModelID,
           !models.contains(where: {
               $0.id == modelID && $0.enabled && $0.capabilities.supportsText && !$0.isRemoteProvider && ($0.format == .gguf || $0.format == .mlx)
           }) {
            preferences.liveMeeting.notesModelID = nil
        }
        if !preferences.liveMeeting.defaultAudioSource.isLiveCapture {
            preferences.liveMeeting.defaultAudioSource = .microphone
        }
    }

    private func shouldPromoteRealtimeSpeechModel(
        _ candidate: ModelDescriptor,
        over currentID: UUID?,
        models: [ModelDescriptor]
    ) -> Bool {
        guard candidate.enabled, candidate.capabilities.supportsRealtimeSpeech else {
            return false
        }
        guard let currentID,
              let current = models.first(where: { $0.id == currentID && $0.enabled && $0.capabilities.supportsRealtimeSpeech }) else {
            return true
        }
        return realtimeSpeechPriority(candidate) < realtimeSpeechPriority(current)
    }

    private func preferredRealtimeSpeechModel(in models: [ModelDescriptor]) -> ModelDescriptor? {
        models
            .filter { $0.enabled && $0.capabilities.supportsRealtimeSpeech }
            .min { lhs, rhs in
                let lhsPriority = realtimeSpeechPriority(lhs)
                let rhsPriority = realtimeSpeechPriority(rhs)
                if lhsPriority == rhsPriority {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhsPriority < rhsPriority
            }
    }

    private func realtimeSpeechPriority(_ model: ModelDescriptor) -> Int {
        switch model.capabilities.speech?.family {
        case .funASRMLTNano:
            return 0
        case .funASRNano:
            return 1
        case .senseVoiceSmall:
            return 2
        case .qwen3ASR06B:
            return 3
        case .nemotron35ASRStreaming06B:
            // 新增的低延迟模型不应擅自覆盖用户已经验证过的实时字幕选择。
            return 4
        case .qwen3ASRSherpaOnnx, .vibeVoiceASR, .whisperCppCoreML, .customLocal, .none:
            return 4
        }
    }

    private func appendHistory(model: ModelDescriptor, result: TaskResult, request: TaskRequest) {
        let entry = HistoryItem(
            task: request.task,
            modelName: result.modelName,
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
        if sizeClass == "0.6b" || sizeClass == "0.8b" || sizeClass == "0.9b" || sizeClass == "1b" || sizeClass == "1.5b" || sizeClass == "2b" {
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
        if format == .speech {
            return 0
        }
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

    private struct SubtitleTranslationJSONItem: Decodable {
        var id: String
        var translation: String
    }

    private func durationBucket(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "unknown"
        }
        switch duration {
        case ..<60:
            return "<1m"
        case ..<300:
            return "1-5m"
        case ..<1800:
            return "5-30m"
        case ..<3600:
            return "30-60m"
        default:
            return "60m+"
        }
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}
