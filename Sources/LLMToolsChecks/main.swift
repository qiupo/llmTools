import Foundation
import Darwin
import ImageIO
import LLMToolsCore

@main
struct LLMToolsChecks {
    static func main() async throws {
        try checkGGUFDetectionChoosesPrimaryModel()
        try checkMLXDetection()
        try await checkModelDisplayName()
        try await checkProviderModelRegistration()
        try await checkProviderModelUpdate()
        try checkProviderRequestOptions()
        try await checkHistoryLimit()
        try await checkPhase1InteractiveNativeTasks()
        try checkPreferenceDefaultsDecodeFromOlderRegistry()
        try checkOCRCapabilityDefaultsDecodeFromOlderRegistry()
        try checkOCRPrompts()
        try checkOCRImagePreprocessor()
        try await checkOCRModelPreferenceClearsTextOnlyModel()
        try await checkTextOnlyModelRejectsOCRBeforeRunnerCall()
        try await checkStubVisionOCRAndHistoryRedaction()
        try checkBrowserIntegrationStateDecodesWithoutExtensionChannel()
        try checkBrowserNativeMessagingManifestDiagnostics()
        try await checkTaskEngineReturnsRawModelOutput()
        try await checkOpenAICompatibleRunnerUsesChatCompletions()
        try await checkOpenAICompatibleRunnerUsesImagePayloadForOCR()
        try await checkProviderConnectivityTest()
        try await checkWebPageTranslationBatchSkipsHistoryByDefault()
        try await checkWebPageTranslationBatchPersistsHistoryWhenEnabled()
        try await checkWebPageTranslationQualityModePrompt()
        try await checkWebPageTranslationBatchFallback()
        try await checkWebPageTranslationBatchRetriesOnlyMissingSegments()
        try checkVisibleOutputHidesThinkBlock()
        try checkPromptsStayCompact()
        print("LLMToolsChecks passed")
    }

    private static func checkGGUFDetectionChoosesPrimaryModel() throws {
        let root = try makeTemporaryDirectory(name: "Qwen3.5-0.8B-GGUF")
        defer { try? FileManager.default.removeItem(at: root) }

        let model = root.appendingPathComponent("Qwen3.5-0.8B-Q8_0.gguf")
        let mmproj = root.appendingPathComponent("mmproj-Qwen3.5-0.8B-BF16.gguf")
        FileManager.default.createFile(atPath: model.path, contents: Data())
        FileManager.default.createFile(atPath: mmproj.path, contents: Data())

        let detection = try ModelDetection.detect(from: root)
        try require(detection.format == .gguf, "Expected GGUF detection.")
        try require(
            detection.resolvedPath.lastPathComponent == model.lastPathComponent,
            "Expected primary GGUF, got \(detection.resolvedPath.path)."
        )
        try require(detection.sizeClass == "0.8b", "Expected 0.8b size class.")
    }

    private static func checkMLXDetection() throws {
        let root = try makeTemporaryDirectory(name: "Qwen3.5-4B-MLX-4bit")
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: root.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: root.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: root.appendingPathComponent("model.safetensors").path, contents: Data())

        let detection = try ModelDetection.detect(from: root)
        try require(detection.format == .mlx, "Expected MLX detection.")
        try require(detection.resolvedPath.lastPathComponent == root.lastPathComponent, "Expected MLX root directory.")
        try require(detection.sizeClass == "4b", "Expected 4b size class.")

        let nineBRoot = try makeTemporaryDirectory(name: "Qwen3.5-9B-MLX-4bit")
        defer { try? FileManager.default.removeItem(at: nineBRoot) }

        FileManager.default.createFile(atPath: nineBRoot.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: nineBRoot.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: nineBRoot.appendingPathComponent("model-00001-of-00002.safetensors").path, contents: Data())

        let nineBDetection = try ModelDetection.detect(from: nineBRoot)
        try require(nineBDetection.format == .mlx, "Expected 9B MLX detection.")
        try require(nineBDetection.sizeClass == "9b", "Expected 9b size class.")
    }

    private static func checkModelDisplayName() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)

        let modelDirectory = root.appendingPathComponent("Qwen3.5-9B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        let descriptor = try await engine.addModel(from: modelDirectory)
        try require(descriptor.name == "Qwen3.5-9B-MLX-4bit", "Expected full directory name, got \(descriptor.name).")
        try require(descriptor.providerID == .local, "Expected older local models to default to local provider.")
    }

    private static func checkProviderModelRegistration() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(format: .openAICompatible)
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.openAICompatible: runner]
        )

        let descriptor = try await engine.addProviderModel(
            providerID: .siliconFlow,
            name: "",
            modelID: "Qwen/Qwen2.5-7B-Instruct",
            apiKey: "test-key",
            baseURL: "https://api.siliconflow.cn/v1",
            contextLength: 32768
        )
        try require(descriptor.providerID == .siliconFlow, "Expected SiliconFlow provider ID.")
        try require(descriptor.format == .openAICompatible, "Expected OpenAI-compatible format.")
        try require(descriptor.apiModelID == "Qwen/Qwen2.5-7B-Instruct", "Expected provider model ID.")
        try require(descriptor.displayPath == "https://api.siliconflow.cn/v1", "Expected provider display URL.")
        try require(descriptor.providerConfiguration?.apiKey == "test-key", "Expected provider API key to stay in the registry descriptor.")
        try require(descriptor.providerConfiguration?.apiKeyKeychainAccount == nil, "Expected provider descriptor not to reference a Keychain account.")
        let registryData = try Data(contentsOf: root.appendingPathComponent("registry.json"))
        let registryText = String(data: registryData, encoding: .utf8) ?? ""
        try require(registryText.contains("test-key"), "Expected registry file to contain provider API key.")

        let result = try await engine.run(request: TaskRequest(task: .translate, inputText: "hello"), modelID: descriptor.id)
        try require(result.modelName == "Stub", "Expected provider runner result.")
        let loadedID = await runner.loadedModelID()
        try require(loadedID == descriptor.id, "Expected provider runner to load the provider descriptor.")
    }

    private static func checkProviderModelUpdate() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)

        let descriptor = try await engine.addProviderModel(
            providerID: .siliconFlow,
            name: "old",
            modelID: "old-model",
            apiKey: "old-key",
            baseURL: "https://api.siliconflow.cn/v1",
            contextLength: 32768
        )

        let updated = try await engine.updateProviderModel(
            id: descriptor.id,
            providerID: .siliconFlow,
            name: "siliconflow translator",
            modelID: "Qwen/Qwen3.5-4B",
            apiKey: "",
            baseURL: "https://api.siliconflow.cn/v1",
            contextLength: 64000
        )
        try require(updated.id == descriptor.id, "Expected provider update to preserve model ID.")
        try require(updated.providerID == .siliconFlow, "Expected provider ID to stay SiliconFlow.")
        try require(updated.name == "siliconflow translator", "Expected provider name to update.")
        try require(updated.apiModelID == "Qwen/Qwen3.5-4B", "Expected provider model ID to update.")
        try require(updated.contextLength == 64000, "Expected provider context length to update.")
        try require(updated.providerConfiguration?.apiKey == "old-key", "Expected blank provider update to preserve the existing API key.")
        try require(updated.providerConfiguration?.apiKeyKeychainAccount == nil, "Expected provider update not to reference Keychain.")
        let registryText = String(data: try Data(contentsOf: root.appendingPathComponent("registry.json")), encoding: .utf8) ?? ""
        try require(registryText.contains("old-key"), "Expected updated registry to preserve old API key.")

        do {
            _ = try await engine.updateProviderModel(
                id: descriptor.id,
                providerID: .deepSeek,
                name: "deepseek translator",
                modelID: "deepseek-chat",
                apiKey: "",
                baseURL: "https://api.deepseek.com",
                contextLength: 64000
            )
            throw CheckError("Expected changing to another API-key provider without a new API key to fail.")
        } catch let error as RunnerError {
            try require(error.localizedDescription.contains("API key"), "Expected missing API key error.")
        }
    }

    private static func checkProviderRequestOptions() throws {
        let qwen3Text = ProviderConfiguration(
            providerID: .siliconFlow,
            apiStyle: .openAICompatible,
            modelID: "Qwen/Qwen3-8B"
        )
        try require(
            ProviderRequestOptions.enableThinking(for: qwen3Text) == false,
            "Expected SiliconFlow Qwen3 text models to disable thinking explicitly."
        )

        let qwen3Vision = ProviderConfiguration(
            providerID: .siliconFlow,
            apiStyle: .openAICompatible,
            modelID: "Qwen/Qwen3-VL-8B-Instruct"
        )
        try require(
            ProviderRequestOptions.enableThinking(for: qwen3Vision) == nil,
            "Expected SiliconFlow Qwen3-VL models not to receive unsupported enable_thinking."
        )
    }

    private static func checkHistoryLimit() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner()
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        var preferences = await engine.registry().preferences
        preferences.recentHistoryLimit = 2
        try await engine.setPreferences(preferences)

        for index in 0..<3 {
            _ = try await engine.run(request: TaskRequest(task: .summarize, inputText: "item \(index)"))
        }

        let history = await engine.recentHistory()
        try require(history.count == 2, "Expected 2 history entries, got \(history.count).")
        try require(history.first?.inputPreview == "item 2", "Expected latest history entry first.")
    }

    private static func checkPhase1InteractiveNativeTasks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(outputs: [
            "translated native output",
            "polished native output",
            "summarized native output",
            "explained native output",
            "- extracted native todo"
        ])
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        let descriptor = try await engine.addModel(from: modelDirectory)
        try await engine.updatePreferences { preferences in
            preferences.recentHistoryLimit = 10
            preferences.defaultTranslationTarget = "Japanese"
            preferences.defaultPolishStyle = "formal"
        }

        let requests = [
            TaskRequest(task: .translate, inputText: "Phase one translate input", targetLanguage: "Japanese"),
            TaskRequest(task: .polish, inputText: "Phase one polish input", polishStyle: "formal"),
            TaskRequest(task: .summarize, inputText: "Phase one summarize input"),
            TaskRequest(task: .explain, inputText: "Phase one explain input"),
            TaskRequest(task: .extractTodos, inputText: "Alice must send the report by Friday.")
        ]
        try require(requests.map(\.task) == TaskKind.interactiveCases, "Expected Phase 1 regression to cover every interactive task.")
        try require(!TaskKind.interactiveCases.contains(.ocr), "OCR must stay outside text-only interactive tasks.")

        var outputs: [String] = []
        for request in requests {
            let result = try await engine.run(request: request)
            try require(result.task == request.task, "Expected result task to match \(request.task.rawValue).")
            try require(result.modelName == "Stub", "Expected Phase 1 task to run through the stub model.")
            outputs.append(result.text)
        }
        try require(outputs == [
            "translated native output",
            "polished native output",
            "summarized native output",
            "explained native output",
            "- extracted native todo"
        ], "Expected each Phase 1 native task to return its corresponding runner output.")
        let loadedModelID = await runner.loadedModelID()
        let generatedRequestCount = await runner.generatedRequestCount()
        let recordedRequests = await runner.recordedRequests()
        try require(loadedModelID == descriptor.id, "Expected Phase 1 native tasks to load the default model.")
        try require(generatedRequestCount == requests.count, "Expected one generation per Phase 1 native task.")
        try require(recordedRequests.map(\.task) == requests.map(\.task), "Expected runner to receive Phase 1 native tasks in order.")

        let history = await engine.recentHistory()
        try require(history.count == requests.count, "Expected Phase 1 native tasks to persist to recent history.")
        try require(history.map(\.task) == requests.map(\.task).reversed(), "Expected recent history to store newest Phase 1 task first.")
        try require(history.first?.task == .extractTodos, "Expected latest Phase 1 history item to be the TODO extraction task.")
        try require(history.first?.inputPreview == "Alice must send the report by Friday.", "Expected latest Phase 1 history input preview to match the TODO source.")
        try require(history.first?.outputPreview == "- extracted native todo", "Expected latest Phase 1 history output preview to match the TODO output.")

        try await engine.clearHistory()
        let clearedHistory = await engine.recentHistory()
        try require(clearedHistory.isEmpty, "Expected Phase 1 clear-history flow to empty recent history.")
    }

    private static func checkPreferenceDefaultsDecodeFromOlderRegistry() throws {
        let json = """
        {
          "defaultTranslationTarget": "English",
          "defaultPolishStyle": "formal",
          "recentHistoryLimit": 8
        }
        """
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        try require(preferences.appLanguage == .chinese, "Expected Chinese to be the default app language.")
        try require(preferences.selectionActionEnabled, "Expected selected-text action panel to default on.")
        try require(preferences.selectionActionTriggerMouseDrag, "Expected mouse-drag selection trigger to default on.")
        try require(preferences.selectionActionTriggerDoubleClick, "Expected double-click selection trigger to default on.")
        try require(!preferences.selectionActionTriggerSelectAll, "Expected Command-A selection trigger to default off.")
        try require(preferences.selectionLineLimitRules.count == 1, "Expected one default selection line-limit rule.")
        try require(preferences.selectionLineLimitRules.first?.bundleIdentifier == "com.tencent.xinWeChat", "Expected WeChat line-limit rule by default.")
        try require(preferences.selectionLineLimitRules.first?.maximumLineCount == 2, "Expected WeChat selection line limit to default to 2.")
        try require(preferences.webPageTranslation.enabled, "Expected webpage translation to default on.")
        try require(preferences.webPageTranslation.defaultTargetLanguage == "zh-Hans", "Expected webpage translation target to default to Simplified Chinese.")
        try require(preferences.webPageTranslation.modelID == nil, "Expected webpage translation model to follow the default model.")
        try require(preferences.webPageTranslation.pendingIndicatorStyle == .loading, "Expected webpage pending indicator to default to loading.")
        try require(preferences.webPageTranslation.autoTranslateDomains.isEmpty, "Expected webpage auto-translate domains to default empty.")
        try require(preferences.webPageTranslation.disabledDomains.isEmpty, "Expected webpage disabled domains to default empty.")
        try require(preferences.webPageTranslation.domainReadingModes.isEmpty, "Expected webpage domain reading defaults to default empty.")
        try require(preferences.webPageTranslation.domainTranslationQualities.isEmpty, "Expected webpage domain quality defaults to default empty.")
        try require(!preferences.webPageTranslation.persistWebHistory, "Expected webpage translation history to default off.")
        try require(preferences.webPageTranslation.localConcurrentTranslationRequests == 1, "Expected local webpage concurrency to default to 1.")
        try require(preferences.quickActionShortcut == .optionSpace, "Expected quick action shortcut to default to Option-Space.")
        try require(preferences.quickActionWithoutSelectionShortcut == .optionShiftSpace, "Expected no-selection quick action shortcut to default to Option-Shift-Space.")
        try require(preferences.defaultTranslationTarget == "English", "Expected existing target language value to be preserved.")
        try require(preferences.defaultPolishStyle == "formal", "Expected existing polish style value to be preserved.")
        try require(preferences.recentHistoryLimit == 8, "Expected existing history limit to be preserved.")

        let legacySelectionLimitJSON = """
        {
          "wechatSelectionMaximumLineCount": 3
        }
        """
        let migratedPreferences = try JSONDecoder().decode(AppPreferences.self, from: Data(legacySelectionLimitJSON.utf8))
        try require(migratedPreferences.selectionLineLimitRules.count == 1, "Expected legacy WeChat line limit to migrate to one rule.")
        try require(migratedPreferences.selectionLineLimitRules.first?.bundleIdentifier == "com.tencent.xinWeChat", "Expected migrated rule to target WeChat.")
        try require(migratedPreferences.selectionLineLimitRules.first?.maximumLineCount == 3, "Expected migrated WeChat line limit to preserve value.")

        let webPagePreferences = try JSONDecoder().decode(WebPageTranslationPreferences.self, from: Data("""
        {
          "enabled": true,
          "defaultTargetLanguage": "zh-Hans"
        }
        """.utf8))
        try require(webPagePreferences.pendingIndicatorStyle == .loading, "Expected older webpage preferences to default pending indicator to loading.")
        try require(webPagePreferences.modelID == nil, "Expected older webpage preferences to default modelID to nil.")
        try require(webPagePreferences.autoTranslateDomains.isEmpty, "Expected older webpage preferences to default auto-translate domains to empty.")
        try require(webPagePreferences.disabledDomains.isEmpty, "Expected older webpage preferences to default disabled domains to empty.")
        try require(webPagePreferences.domainReadingModes.isEmpty, "Expected older webpage preferences to default domain reading modes to empty.")
        try require(webPagePreferences.domainTranslationQualities.isEmpty, "Expected older webpage preferences to default domain translation qualities to empty.")
        try require(webPagePreferences.localConcurrentTranslationRequests == 1, "Expected older webpage preferences to default local concurrency to 1.")

        let webPagePreferencesWithDomainDefaults = try JSONDecoder().decode(WebPageTranslationPreferences.self, from: Data("""
        {
          "domainReadingModes": {
            "docs.example.com": "bilingual"
          },
          "domainTranslationQualities": {
            "docs.example.com": "technical"
          }
        }
        """.utf8))
        try require(webPagePreferencesWithDomainDefaults.domainReadingModes["docs.example.com"] == .bilingual, "Expected domain reading mode defaults to decode.")
        try require(webPagePreferencesWithDomainDefaults.domainTranslationQualities["docs.example.com"] == .technical, "Expected domain quality defaults to decode.")

        let clampedWebPagePreferences = try JSONDecoder().decode(WebPageTranslationPreferences.self, from: Data("""
        {
          "localConcurrentTranslationRequests": 99
        }
        """.utf8))
        try require(clampedWebPagePreferences.localConcurrentTranslationRequests == WebPageTranslationPreferences.maximumLocalConcurrentTranslationRequests, "Expected local concurrency to clamp to the maximum.")
    }

    private static func checkOCRCapabilityDefaultsDecodeFromOlderRegistry() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("""
        {
          "defaultTranslationTarget": "English"
        }
        """.utf8))
        try require(preferences.ocr.enabled, "Expected OCR preferences to default enabled.")
        try require(preferences.ocr.modelID == nil, "Expected OCR model to default empty.")
        try require(preferences.ocr.defaultMode == .plainText, "Expected OCR mode to default to plain text.")
        try require(!preferences.ocr.persistHistory, "Expected OCR history to default off.")
        try require(!preferences.ocr.useModelRecognitionByDefault, "Expected model recognition default to stay explicit.")

        let localDescriptor = try JSONDecoder().decode(ModelDescriptor.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Qwen local",
          "sourcePath": "file:///tmp/qwen",
          "format": "mlx",
          "sizeClass": "4b",
          "role": "default",
          "contextLength": 8192,
          "enabled": true,
          "validationState": "valid"
        }
        """.utf8))
        try require(localDescriptor.capabilities.supportsText, "Expected older local model to support text.")
        try require(!localDescriptor.capabilities.supportsImage, "Expected older local model to decode as text-only.")

        let providerDescriptor = ModelDescriptor(
            name: "OpenAI vision",
            sourcePath: URL(string: "https://api.openai.com/v1")!,
            format: .openAICompatible,
            sizeClass: "remote",
            role: .default,
            contextLength: 128000,
            providerConfiguration: ProviderConfiguration(
                providerID: .openAI,
                apiStyle: .openAICompatible,
                baseURL: URL(string: "https://api.openai.com/v1")!,
                modelID: "gpt-4o-mini"
            )
        )
        try require(providerDescriptor.capabilities.supportsImage, "Expected known OpenAI vision model to infer image support.")
        try require(providerDescriptor.capabilities.source == .inferred, "Expected inferred capability source.")
    }

    private static func checkOCRPrompts() throws {
        let plain = PromptTemplates.ocrPrompt(mode: .plainText)
        try require(plain.contains("Output only text that is visible in the image."), "Expected OCR prompt to restrict output to visible text.")
        try require(plain.contains("No readable text detected."), "Expected OCR prompt to define no-text output.")
        try require(!plain.localizedCaseInsensitiveContains("Apple Vision"), "OCR prompt must not reference Apple Vision.")

        let explain = PromptTemplates.ocrPrompt(mode: .explainImage)
        try require(explain.contains("Explain the screenshot or image"), "Expected image explanation prompt.")
        let probe = PromptTemplates.visionProbePrompt()
        try require(probe.contains("VISION_OK"), "Expected deterministic vision probe output.")
    }

    private static func checkOCRImagePreprocessor() throws {
        guard CGImageSourceCreateWithData(OCRImagePreprocessor.probeImage.data as CFData, nil) != nil else {
            throw CheckError("Expected probe image to be a decodable PNG.")
        }
        let image = try OCRImagePreprocessor.normalizeImageData(
            OCRImagePreprocessor.probeImage.data,
            preferences: OCRPreferences(),
            fileName: "fixture.png",
            sourceDescription: "Fixture image"
        )
        try require(image.mimeType == "image/png" || image.mimeType == "image/jpeg", "Expected provider-safe image MIME type.")
        try require(image.pixelWidth == 64 && image.pixelHeight == 64, "Expected fixture image dimensions to survive normalization.")
        try require(image.dataURL.hasPrefix("data:\(image.mimeType);base64,"), "Expected image data URL to use normalized local bytes.")
        try require(!image.dataURL.contains("http://") && !image.dataURL.contains("https://"), "Image data URL must not pass through a remote URL.")
    }

    private static func checkOCRModelPreferenceClearsTextOnlyModel() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)

        let descriptor = try await engine.addProviderModel(
            providerID: .openAI,
            name: "Vision model",
            modelID: "gpt-4o-mini",
            apiKey: "test-key",
            baseURL: "https://api.openai.com/v1",
            contextLength: 128000
        )
        try await engine.updatePreferences { preferences in
            preferences.ocr.modelID = descriptor.id
        }
        let selectablePreference = await engine.registry().preferences.ocr.modelID
        try require(selectablePreference == descriptor.id, "Expected vision-capable model to remain selectable for OCR.")

        _ = try await engine.markModelTextOnly(id: descriptor.id)
        let clearedPreference = await engine.registry().preferences.ocr.modelID
        try require(clearedPreference == nil, "Expected OCR preference to clear when selected model becomes text-only.")
    }

    private static func checkTextOnlyModelRejectsOCRBeforeRunnerCall() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubVisionRunner()
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.openAICompatible: runner]
        )
        let descriptor = try await engine.addProviderModel(
            providerID: .customOpenAICompatible,
            name: "Text provider",
            modelID: "text-only-model",
            apiKey: "test-key",
            baseURL: "https://example.com/v1",
            contextLength: 8192
        )
        do {
            _ = try await engine.runOCR(
                image: OCRImagePreprocessor.probeImage,
                mode: .plainText,
                modelID: descriptor.id
            )
            throw CheckError("Expected text-only model to reject OCR.")
        } catch let error as OCRTaskError {
            try require(error == .modelNotVisionCapable("Text provider"), "Expected model-not-vision-capable error.")
        }
        let ocrRequestCount = await runner.ocrRequestCount()
        try require(ocrRequestCount == 0, "Expected OCR to fail before provider call.")
    }

    private static func checkStubVisionOCRAndHistoryRedaction() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubVisionRunner(output: "VISIBLE OCR TEXT")
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.openAICompatible: runner]
        )
        let descriptor = try await engine.addProviderModel(
            providerID: .openAI,
            name: "Vision provider",
            modelID: "gpt-4o-mini",
            apiKey: "test-key",
            baseURL: "https://api.openai.com/v1",
            contextLength: 128000
        )
        try await engine.updatePreferences { preferences in
            preferences.ocr.modelID = descriptor.id
            preferences.ocr.persistHistory = true
        }
        let result = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .plainText
        )
        try require(result.text == "VISIBLE OCR TEXT", "Expected stub OCR output.")
        try require(result.task == .ocr, "Expected OCR task result.")
        let history = await engine.recentHistory()
        try require(history.count == 1, "Expected opted-in OCR history entry.")
        try require(history.first?.task == .ocr, "Expected OCR history task.")
        try require(history.first?.inputPreview.contains("data:") == false, "OCR history must not contain base64 data URLs.")
        try require(history.first?.inputPreview.contains("Probe image") == true, "OCR history should use a redacted image descriptor.")
    }

    private static func checkBrowserIntegrationStateDecodesWithoutExtensionChannel() throws {
        let json = """
        {
          "id": "chrome",
          "name": "Google Chrome",
          "bundleID": "com.google.Chrome",
          "extensionID": "jednddlgkkohaebgoejcidfppddjegij",
          "status": "ready"
        }
        """
        let state = try JSONDecoder().decode(BrowserIntegrationState.self, from: Data(json.utf8))
        try require(state.extensionChannel == nil, "Expected older browser state JSON to decode without extensionChannel.")

        let encoded = try JSONEncoder().encode(BrowserIntegrationState(
            id: "chrome",
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            extensionChannel: "development",
            extensionID: "jednddlgkkohaebgoejcidfppddjegij",
            status: .ready
        ))
        let roundTripped = try JSONDecoder().decode(BrowserIntegrationState.self, from: encoded)
        try require(roundTripped.extensionChannel == "development", "Expected browser extension channel to round-trip.")
        try require(roundTripped.lastErrorCode == nil, "Expected ready browser state to round-trip without an error code.")
    }

    private static func checkBrowserNativeMessagingManifestDiagnostics() throws {
        let expectedName = "com.llmtools.native_host"
        let expectedPath = "/Applications/llmTools.app/Contents/MacOS/LLMToolsNativeHost"
        let expectedExtensionID = "jednddlgkkohaebgoejcidfppddjegij"
        let manifest = BrowserNativeMessagingManifest(
            name: expectedName,
            description: "llmTools native messaging host",
            path: expectedPath,
            allowedOrigins: ["chrome-extension://\(expectedExtensionID)/"]
        )
        let encoder = JSONEncoder()
        let validData = try encoder.encode(manifest)
        try require(
            BrowserNativeMessagingManifestValidator.diagnosticCode(
                data: validData,
                expectedName: expectedName,
                expectedPath: expectedPath,
                expectedExtensionID: expectedExtensionID
            ) == nil,
            "Expected valid browser native messaging manifest to pass diagnostics."
        )

        let stalePathData = try encoder.encode(BrowserNativeMessagingManifest(
            name: expectedName,
            description: "llmTools native messaging host",
            path: "/tmp/old/LLMToolsNativeHost",
            allowedOrigins: ["chrome-extension://\(expectedExtensionID)/"]
        ))
        try require(
            BrowserNativeMessagingManifestValidator.diagnosticCode(
                data: stalePathData,
                expectedName: expectedName,
                expectedPath: expectedPath,
                expectedExtensionID: expectedExtensionID
            ) == .nativeHostManifestPathMismatch,
            "Expected stale native host path to produce a stable diagnostic code."
        )

        let wrongExtensionData = try encoder.encode(BrowserNativeMessagingManifest(
            name: expectedName,
            description: "llmTools native messaging host",
            path: expectedPath,
            allowedOrigins: ["chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"]
        ))
        try require(
            BrowserNativeMessagingManifestValidator.diagnosticCode(
                data: wrongExtensionData,
                expectedName: expectedName,
                expectedPath: expectedPath,
                expectedExtensionID: expectedExtensionID
            ) == .nativeHostManifestExtensionIDMismatch,
            "Expected wrong extension ID to produce a stable diagnostic code."
        )

        let wrongTypeData = try encoder.encode(BrowserNativeMessagingManifest(
            name: expectedName,
            description: "llmTools native messaging host",
            path: expectedPath,
            type: "socket",
            allowedOrigins: ["chrome-extension://\(expectedExtensionID)/"]
        ))
        try require(
            BrowserNativeMessagingManifestValidator.diagnosticCode(
                data: wrongTypeData,
                expectedName: expectedName,
                expectedPath: expectedPath,
                expectedExtensionID: expectedExtensionID
            ) == .nativeHostManifestTypeMismatch,
            "Expected wrong native messaging manifest type to produce a stable diagnostic code."
        )

        try require(
            BrowserNativeMessagingManifestValidator.diagnosticCode(
                data: Data("{".utf8),
                expectedName: expectedName,
                expectedPath: expectedPath,
                expectedExtensionID: expectedExtensionID
            ) == .nativeHostManifestUnreadable,
            "Expected unreadable native messaging manifest to produce a stable diagnostic code."
        )

        let encodedState = try JSONEncoder().encode(BrowserIntegrationState(
            id: "chrome",
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            extensionChannel: "development",
            extensionID: expectedExtensionID,
            status: .nativeHostInvalid,
            lastErrorCode: BrowserIntegrationDiagnosticCode.nativeHostManifestPathMismatch.rawValue,
            lastErrorMessage: "stale native host path"
        ))
        let decodedState = try JSONDecoder().decode(BrowserIntegrationState.self, from: encodedState)
        try require(
            decodedState.lastErrorCode == BrowserIntegrationDiagnosticCode.nativeHostManifestPathMismatch.rawValue,
            "Expected browser integration diagnostic code to round-trip in state JSON."
        )
    }

    private static func checkWebPageTranslationBatchSkipsHistoryByDefault() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(output: """
        [
          {"id":"s1","translation":"你好。"},
          {"id":"s2","translation":"世界。"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        let result = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "job-1",
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "Hello."),
                    WebPageTranslationSegment(segmentID: "s2", text: "World.")
                ]
            )
        )
        try require(result.translations.count == 2, "Expected two webpage translations.")
        try require(result.translations.first?.translation == "你好。", "Expected parsed JSON translation.")
        let history = await engine.recentHistory()
        try require(history.isEmpty, "Expected webpage translation to skip recent history by default.")
    }

    private static func checkWebPageTranslationBatchPersistsHistoryWhenEnabled() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(output: """
        [
          {"id":"s1","translation":"你好。"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        try await engine.updatePreferences { preferences in
            preferences.webPageTranslation.persistWebHistory = true
        }
        _ = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "history-job",
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "Hello.")
                ]
            )
        )
        let history = await engine.recentHistory()
        try require(history.count == 1, "Expected opted-in webpage translation to persist one history entry.")
        try require(history.first?.task == .webPageTranslate, "Expected opted-in history entry to be marked as webpage translation.")
        try require(history.first?.outputPreview.contains("你好") == true, "Expected opted-in history entry to include the translation preview.")
    }

    private static func checkWebPageTranslationQualityModePrompt() async throws {
        let legacyPayload = try JSONDecoder().decode(WebPageTranslateSegmentsPayload.self, from: Data("""
        {
          "jobID": "legacy-job",
          "segments": [
            { "segmentID": "s1", "text": "Open the API reference." }
          ]
        }
        """.utf8))
        try require(legacyPayload.translationQuality == .natural, "Expected missing translationQuality to default to natural.")

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(output: """
        [
          {"id":"s1","translation":"打开 API 参考。"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        _ = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "quality-job",
                translationQuality: .technical,
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "Open the API reference.")
                ]
            )
        )
        let prompt = await runner.lastInputText()
        try require(prompt.contains("Preserve technical terminology"), "Expected technical quality mode to be included in webpage prompt.")
        try require(prompt.contains("API names"), "Expected technical prompt to preserve API names.")
    }

    private static func checkWebPageTranslationBatchFallback() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(outputs: [
            "not json",
            "still not json",
            "你好。"
        ])
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        let result = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "job-2",
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "Hello.")
                ]
            )
        )
        try require(result.translations.first?.translation == "你好。", "Expected single-segment fallback translation.")
        try require(result.translations.first?.status == .translated, "Expected fallback segment to be marked translated.")
    }

    private static func checkWebPageTranslationBatchRetriesOnlyMissingSegments() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(outputs: [
            """
            [
              {"id":"s1","translation":"你好。"}
            ]
            """,
            """
            [
              {"id":"s2","translation":"世界。"}
            ]
            """
        ])
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        let result = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "job-3",
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "Hello."),
                    WebPageTranslationSegment(segmentID: "s2", text: "World.")
                ]
            )
        )
        try require(result.translations.map(\.translation) == ["你好。", "世界。"], "Expected partial batch result to be preserved while retrying only the missing segment.")
        let requestCount = await runner.generatedRequestCount()
        try require(requestCount == 2, "Expected one initial batch and one retry for the missing segment.")
    }

    private static func checkPromptsStayCompact() throws {
        let request = TaskRequest(task: .translate, inputText: "hello", targetLanguage: "Chinese")
        let prompt = PromptTemplates.userPrompt(for: request, preferences: AppPreferences())
        try require(prompt.contains("Output only the translation."), "Expected translation prompt to require translation-only output.")

        let prompts = [prompt, PromptTemplates.systemPrompt(for: .translate, preferences: AppPreferences())]
        for prompt in prompts {
            let lowercased = prompt.lowercased()
            let forbiddenFragments = [
                "/no_think",
                "thinking process",
                "chain-of-thought",
                "<think>",
                "hidden reasoning",
                "analysis notes",
                "do not explain",
                "do not mention"
            ]
            for fragment in forbiddenFragments {
                try require(!lowercased.contains(fragment), "Prompt should not contain trigger fragment \(fragment): \(prompt)")
            }
        }
    }

    private static func checkTaskEngineReturnsRawModelOutput() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let runner = StubRunner(output: """
        Thinking Process:
        The translation of "hello" in Chinese is "你好".
        """)
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: runner]
        )

        let modelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        _ = try await engine.addModel(from: modelDirectory)
        let result = try await engine.run(request: TaskRequest(task: .translate, inputText: "hello"))
        try require(
            result.text == "Thinking Process:\nThe translation of \"hello\" in Chinese is \"你好\".",
            "Expected raw model output to be preserved, got \(result.text)."
        )
        try require(result.rawText == result.text, "Stub runner output should be raw and visible.")
    }

    private static func checkOpenAICompatibleRunnerUsesChatCompletions() async throws {
        let server = try await HTTPStubServer.start { request in
            try require(request.path == "/v1/chat/completions", "Expected /v1/chat/completions, got \(request.path).")
            try require(request.authorization == "Bearer test-key", "Expected bearer auth header.")
            try require(request.body.contains("\"model\":\"stub-model\""), "Expected model in request body.")
            try require(request.body.contains("\"role\":\"system\""), "Expected system message in request body.")
            return """
            {
              "choices": [
                { "message": { "role": "assistant", "content": "你好" } }
              ]
            }
            """
        }
        defer { server.stop() }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let descriptor = try await engine.addProviderModel(
            providerID: .customOpenAICompatible,
            name: "Stub Provider",
            modelID: "stub-model",
            apiKey: "test-key",
            baseURL: server.baseURL.absoluteString,
            contextLength: 8192
        )

        let result = try await engine.run(request: TaskRequest(task: .translate, inputText: "hello"), modelID: descriptor.id)
        try require(result.text == "你好", "Expected chat completions response text.")
    }

    private static func checkOpenAICompatibleRunnerUsesImagePayloadForOCR() async throws {
        let server = try await HTTPStubServer.start { request in
            try require(request.path == "/v1/chat/completions", "Expected /v1/chat/completions, got \(request.path).")
            try require(request.authorization == "Bearer test-key", "Expected bearer auth header.")
            try require(request.body.contains("\"model\":\"gpt-4o-mini\""), "Expected OCR model in request body.")
            try require(request.body.contains("\"type\":\"image_url\""), "Expected image_url content block.")
            try require(
                request.body.contains("data:image/png;base64,") || request.body.contains("data:image\\/png;base64,"),
                "Expected normalized local image data URL."
            )
            try require(!request.body.contains("https://example.com/image.png"), "Provider payload must not contain the original remote image URL.")
            return """
            {
              "choices": [
                { "message": { "role": "assistant", "content": "OCR result" } }
              ]
            }
            """
        }
        defer { server.stop() }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let descriptor = try await engine.addProviderModel(
            providerID: .openAI,
            name: "OpenAI Vision",
            modelID: "gpt-4o-mini",
            apiKey: "test-key",
            baseURL: server.baseURL.absoluteString,
            contextLength: 128000
        )
        try await engine.updatePreferences { preferences in
            preferences.ocr.modelID = descriptor.id
        }
        let result = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .structured
        )
        try require(result.text == "OCR result", "Expected OCR response text.")
    }

    private static func checkProviderConnectivityTest() async throws {
        final class RequestCounter: @unchecked Sendable {
            var chatRequestCount = 0
        }
        let counter = RequestCounter()
        let server = try await HTTPStubServer.start { request in
            if request.path == "/v1/models" {
                return """
                {
                  "data": [
                    { "id": "stub-model" }
                  ]
                }
                """
            }
            counter.chatRequestCount += 1
            try require(request.path == "/v1/chat/completions", "Expected /v1/chat/completions, got \(request.path).")
            return """
            {
              "choices": [
                { "message": { "role": "assistant", "content": "OK" } }
              ]
            }
            """
        }
        defer { server.stop() }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let descriptor = try await engine.addProviderModel(
            providerID: .customOpenAICompatible,
            name: "Stub Provider",
            modelID: "stub-model",
            apiKey: "test-key",
            baseURL: server.baseURL.absoluteString,
            contextLength: 8192
        )

        let result = try await engine.testProviderModel(id: descriptor.id)
        try require(result.ok, "Expected provider connectivity test to pass.")
        try require(result.stage == .models, "Expected connectivity test to use the fast model-list check.")
        try require(result.message.contains("stub-model"), "Expected connectivity message to include the provider model ID.")
        try require(counter.chatRequestCount == 0, "Expected model-list success to skip slow chat generation.")
        let updated = await engine.registry().models.first { $0.id == descriptor.id }
        try require(updated?.validationState == .ready, "Expected successful provider test to mark model ready.")
    }

    private static func checkVisibleOutputHidesThinkBlock() throws {
        let raw = """
        <think>
        Thinking Process:
        The translation of "hello" in Chinese is "你好".
        </think>

        你好
        """
        try require(VisibleOutput.from(rawText: raw) == "你好", "Expected visible output after think block.")
        try require(VisibleOutput.from(rawText: "你好") == "你好", "Expected text without think block to stay unchanged.")
    }

    private static func makeTemporaryDirectory(name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmTools-checks", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw CheckError(message)
        }
    }
}

private struct CheckError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private actor StubRunner: ModelRunner {
    private let format: ModelFormat
    private var loadedID: UUID?
    private var outputs: [String]
    private var requestCount = 0
    private var lastInput = ""
    private var requests: [TaskRequest] = []

    init(output: String? = nil, format: ModelFormat = .mlx) {
        self.format = format
        if let output {
            self.outputs = [output]
        } else {
            self.outputs = []
        }
    }

    init(outputs: [String], format: ModelFormat = .mlx) {
        self.format = format
        self.outputs = outputs
    }

    func modelFormat() async -> ModelFormat {
        format
    }

    func loadedState() async -> Bool {
        loadedID != nil
    }

    func loadedModelID() async -> UUID? {
        loadedID
    }

    func loadedModelName() async -> String? {
        "Stub"
    }

    func load(model: ModelDescriptor) async throws {
        loadedID = model.id
    }

    func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        requestCount += 1
        lastInput = request.inputText
        requests.append(request)
        let output = outputs.isEmpty ? "result \(request.inputText)" : outputs.removeFirst()
        return TaskResult(text: output, modelName: "Stub", task: request.task)
    }

    func unload() async {
        loadedID = nil
    }

    func generatedRequestCount() -> Int {
        requestCount
    }

    func lastInputText() -> String {
        lastInput
    }

    func recordedRequests() -> [TaskRequest] {
        requests
    }
}

private actor StubVisionRunner: VisionModelRunner {
    private var loadedID: UUID?
    private var output: String
    private var ocrCount = 0

    init(output: String = "OCR stub result") {
        self.output = output
    }

    func modelFormat() async -> ModelFormat {
        .openAICompatible
    }

    func loadedState() async -> Bool {
        loadedID != nil
    }

    func loadedModelID() async -> UUID? {
        loadedID
    }

    func loadedModelName() async -> String? {
        "Vision Stub"
    }

    func load(model: ModelDescriptor) async throws {
        loadedID = model.id
    }

    func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        TaskResult(text: "text stub result", modelName: "Vision Stub", task: request.task)
    }

    func generateOCR(request: OCRTaskRequest, preferences: AppPreferences) async throws -> OCRTaskResult {
        ocrCount += 1
        return OCRTaskResult(
            text: output,
            rawModelText: output,
            structuredMarkdown: request.mode == .structured ? output : nil,
            modelName: "Vision Stub"
        )
    }

    func unload() async {
        loadedID = nil
    }

    func ocrRequestCount() -> Int {
        ocrCount
    }
}

private final class HTTPStubServer {
    struct Request {
        var path: String
        var authorization: String?
        var body: String
    }

    typealias Handler = @Sendable (Request) throws -> String

    let baseURL: URL
    private let listener: TCPListener

    private init(baseURL: URL, listener: TCPListener) {
        self.baseURL = baseURL
        self.listener = listener
    }

    static func start(handler: @escaping Handler) async throws -> HTTPStubServer {
        let listener = try TCPListener(port: 0, handler: handler)
        try listener.start()
        return HTTPStubServer(
            baseURL: URL(string: "http://127.0.0.1:\(listener.port)/v1")!,
            listener: listener
        )
    }

    func stop() {
        listener.stop()
    }
}

private final class TCPListener: @unchecked Sendable {
    private let socketFD: Int32
    private let handler: HTTPStubServer.Handler
    private let queue = DispatchQueue(label: "llmTools.checks.http-stub")
    private var stopped = false

    let port: UInt16

    init(port: UInt16, handler: @escaping HTTPStubServer.Handler) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CheckError("Could not create stub server socket.")
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        var bindAddress = address
        let bindResult = withUnsafePointer(to: &bindAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw CheckError("Could not bind stub server socket.")
        }

        var actualAddress = sockaddr_in()
        var actualLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &actualAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &actualLength)
            }
        }
        guard nameResult == 0 else {
            close(fd)
            throw CheckError("Could not read stub server port.")
        }
        self.socketFD = fd
        self.handler = handler
        self.port = UInt16(bigEndian: actualAddress.sin_port)
    }

    func start() throws {
        guard listen(socketFD, 8) == 0 else {
            throw CheckError("Could not listen on stub server socket.")
        }
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        stopped = true
        shutdown(socketFD, SHUT_RDWR)
        close(socketFD)
    }

    private func acceptLoop() {
        while !stopped {
            let clientFD = accept(socketFD, nil, nil)
            guard clientFD >= 0 else {
                continue
            }
            handle(clientFD: clientFD)
        }
    }

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(clientFD, &buffer, buffer.count, 0)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
            if let requestText = String(data: data, encoding: .utf8),
               requestText.contains("\r\n\r\n"),
               requestText.count >= expectedRequestLength(requestText) {
                break
            }
        }

        let requestText = String(data: data, encoding: .utf8) ?? ""
        let responseBody: String
        do {
            responseBody = try handler(parseRequest(requestText))
            writeResponse(clientFD: clientFD, status: "200 OK", body: responseBody)
        } catch {
            writeResponse(clientFD: clientFD, status: "500 Internal Server Error", body: #"{"error":{"message":"\#(error)"}}"#)
        }
    }

    private func parseRequest(_ requestText: String) -> HTTPStubServer.Request {
        let parts = requestText.components(separatedBy: "\r\n\r\n")
        let headerText = parts.first ?? ""
        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        let lines = headerText.components(separatedBy: "\r\n")
        let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let authorization = lines.first { $0.lowercased().hasPrefix("authorization:") }
            .flatMap { line in line.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) } }
        return HTTPStubServer.Request(path: path, authorization: authorization, body: body)
    }

    private func expectedRequestLength(_ requestText: String) -> Int {
        let parts = requestText.components(separatedBy: "\r\n\r\n")
        let headerText = parts.first ?? ""
        let bodyLength = parts.dropFirst().joined(separator: "\r\n\r\n").utf8.count
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { $0.split(separator: ":", maxSplits: 1).last }
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            ?? 0
        return requestText.count - bodyLength + contentLength
    }

    private func writeResponse(clientFD: Int32, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        response.withCString { pointer in
            _ = send(clientFD, pointer, strlen(pointer), 0)
        }
    }
}
