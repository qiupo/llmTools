import Foundation
import Darwin
import ImageIO
import LLMToolsCore

@main
struct LLMToolsChecks {
    static func main() async throws {
        try checkGGUFDetectionChoosesPrimaryModel()
        try await checkModelSetupStates()
        try checkMLXDetection()
        try await checkMiniCPM5Registration()
        try await checkLocalMLXVisionMetadataDetection()
        try await checkModelDisplayName()
        try await checkProviderModelRegistration()
        try await checkProviderModelUpdate()
        try await checkPrivateStorePermissions()
        try checkProviderCredentialStoragePolicy()
        try await checkProviderEndpointPolicy()
        try checkProviderRedirectPolicy()
        try checkLocalBridgeHTTPFraming()
        try checkProviderRequestOptions()
        try await checkHistoryLimit()
        try await checkPhase1InteractiveNativeTasks()
        try await checkPerTaskDefaultModelRouting()
        try checkPreferenceDefaultsDecodeFromOlderRegistry()
        try await checkDesktopAssistantStageAContracts()
        try await checkDesktopAssistantLocalPromptBoundary()
        try await checkDesktopAssistantPrivacyAndContextBuffer()
        try await checkDesktopAssistantBehaviorStore()
        try checkDesktopAssistantDropClassifier()
        try await checkDesktopAssistantIntelligenceContracts()
        try checkMediaSubtitlePreferenceDefaultsDecodeFromOlderRegistry()
        try checkPhase4XFoundationTypesAndPreferences()
        try await checkLiveMeetingTranscriptionFixtures()
        try checkTextToSpeechProjectFixtures()
        try await checkLanguageDetectionFixture()
        try await checkLanguageRoutingCallerWiring()
        try await checkSpeakerDiarizationFixtureAndMapping()
        try await checkSpeakerDiarizationFailureMessageSanitization()
        try await checkSpeakerDiarizationCommandDrainsLargeStderr()
        try await checkSpeakerDiarizationCommandCancellation()
        try checkSpeakerDiarizationRejectsTokenInCommand()
        try await checkProcessOutputCollectorDrainsLargePipes()
        try checkSubtitleExportWithSpeakers()
        try await checkSpeakerDiarizationFilePipeline()
        try await checkFastMTFixtureRoundTrip()
        try await checkFastMTDegenerateOutputGuard()
        try checkFastMTPreferencesMigration()
        try checkTranslationRoutingDecisionTable()
        try await checkTextTranslateFastMTPipeline()
        try await checkPersistentSidecarCancellationInterruptsBlockedRequest()
        try await checkSubtitleFastMTPipeline()
        try await checkWebPageFastMTRouting()
        try checkTextTaskModePreferencesAndPrompts()
        try checkCustomPromptTemplates()
        try checkOCRCapabilityDefaultsDecodeFromOlderRegistry()
        try checkOCRPrompts()
        try checkLocalGenerationTokenLimits()
        try checkOCRImagePreprocessor()
        try checkRemoteImageURLPolicy()
        try await checkOCRModelPreferenceClearsTextOnlyModel()
        try await checkManualVisionOverrideForLocalModel()
        try await checkTextOnlyModelRejectsOCRBeforeRunnerCall()
        try await checkStubVisionOCRAndHistoryRedaction()
        try await checkDedicatedOCRTextProcessingPipeline()
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
        try await checkSpeechModelDetectionPreferencesAndHealth()
        try await checkLocalASRCommandCancellation()
        try await checkAudioExtractionWorkspaceCleanup()
        try await checkAudioExtractionCancellationCleanup()
        try await checkSubtitleTranslationCoordinatorUsesTextRunner()
        try await checkSubtitleTranslationSplitsLongLLMBatches()
        try await checkSubtitleTranslationSplitsOversizedSingleSegment()
        try await checkMediaFileSubtitlePipelineWithConfiguredLocalCommand()
        try checkSubtitlePromptExporterAndPrivacyDefaults()
        try checkVisibleOutputHidesThinkBlock()
        try checkGeneratedOutputGuardTrimsDegenerateTail()
        try checkPromptsStayCompact()
        try checkDetailedTranslationResultContract()
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

    private static func checkModelSetupStates() async throws {
        let root = try makeTemporaryDirectory(name: "model-setup-states")
        defer { try? FileManager.default.removeItem(at: root) }

        let emptyStore = RegistryStore(fileURL: root.appendingPathComponent("missing-registry.json"))
        let emptySnapshot = try await emptyStore.load()
        let empty = ModelFeatureAvailability(models: emptySnapshot.models)
        try require(empty.registeredModelCount == 0 && empty.availableModelCount == 0, "Expected a missing registry to produce an empty setup state.")
        try require(!empty.hasAnyProcessingFeature, "Expected every processing feature to be unavailable without models.")

        func directory(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url.appendingPathComponent("config.json"))
            try Data("{}".utf8).write(to: url.appendingPathComponent("tokenizer.json"))
            FileManager.default.createFile(
                atPath: url.appendingPathComponent("model.safetensors").path,
                contents: Data()
            )
            return url
        }

        let textModel = ModelDescriptor(
            name: "Qwen3.5-0.8B-MLX-8bit",
            sourcePath: try directory("Qwen3.5-0.8B-MLX-8bit"),
            format: .mlx,
            sizeClass: "0.8b",
            role: .default,
            contextLength: 32_768,
            capabilities: .textOnly(source: .manual)
        )
        let textOnly = ModelFeatureAvailability(models: [textModel])
        try require(textOnly.textTasks && textOnly.webPageTranslation, "Expected one text model to unlock text and webpage tasks.")
        try require(!textOnly.imageRecognition && !textOnly.mediaTranscription, "Text-only setup must not unlock OCR or ASR.")

        let visionModel = ModelDescriptor(
            name: "GLM-OCR-4bit",
            sourcePath: try directory("GLM-OCR-4bit"),
            format: .mlx,
            sizeClass: "0.9b",
            role: .fast,
            contextLength: 32_768,
            capabilities: .ocrOnly(source: .manual, confidence: 1)
        )
        let visionOnly = ModelFeatureAvailability(models: [visionModel], selectedOCRModelID: visionModel.id)
        try require(visionOnly.imageRecognition && !visionOnly.imagePostProcessing, "OCR-only setup should allow recognition but not text post-processing.")

        let generalVisionModel = ModelDescriptor(
            name: "General VLM",
            sourcePath: textModel.sourcePath,
            format: .mlx,
            sizeClass: "fixture",
            role: .default,
            contextLength: 32_768,
            capabilities: .vision(source: .manual, confidence: 1)
        )
        let generalVisionOnly = ModelFeatureAvailability(
            models: [generalVisionModel],
            selectedOCRModelID: generalVisionModel.id
        )
        try require(
            generalVisionOnly.imageRecognition && generalVisionOnly.imagePostProcessing,
            "A general VLM should handle image explanation without requiring a second text model."
        )
        let fastAssistantVisionModel = ModelDescriptor(
            name: "Fast general VLM",
            sourcePath: textModel.sourcePath,
            format: .mlx,
            sizeClass: "0.8b",
            role: .fast,
            contextLength: 32_768,
            capabilities: .vision(source: .manual, confidence: 1)
        )
        let qualityAssistantVisionModel = ModelDescriptor(
            name: "Quality general VLM",
            sourcePath: textModel.sourcePath,
            format: .mlx,
            sizeClass: "9b",
            role: .quality,
            contextLength: 32_768,
            capabilities: .vision(source: .manual, confidence: 1)
        )
        try require(
            ModelRecommendationPolicy.preferredVisionModel(
                in: [qualityAssistantVisionModel, fastAssistantVisionModel]
            )?.id == fastAssistantVisionModel.id,
            "Automatic desktop vision routing must prefer the fast local VLM over the qualified judgment model."
        )

        let speechModel = ModelDescriptor(
            name: "Qwen3-ASR-0.6B-8bit",
            sourcePath: try directory("Qwen3-ASR-0.6B-8bit"),
            format: .speech,
            sizeClass: "0.6b",
            role: .default,
            contextLength: 0,
            capabilities: .speech(.qwen3ASR06B(source: .manual, confidence: 1))
        )
        let speechOnly = ModelFeatureAvailability(models: [speechModel])
        try require(speechOnly.realtimeSubtitles && speechOnly.mediaTranscription && speechOnly.meetingTranscription, "Recommended ASR should unlock live, file, and meeting transcription.")
        try require(!speechOnly.subtitleTranslation && !speechOnly.meetingNotes, "ASR-only setup must keep translation and notes unavailable.")

        let fastMTOnly = ModelFeatureAvailability(models: [], fastTranslationReady: true)
        try require(fastMTOnly.webPageTranslation && fastMTOnly.subtitleTranslation && !fastMTOnly.textTasks, "Fast MT alone should unlock translation routes, not general text tasks.")
        let incompleteFastMTDirectory = root.appendingPathComponent("incomplete-fastmt", isDirectory: true)
        try FileManager.default.createDirectory(at: incompleteFastMTDirectory, withIntermediateDirectories: true)
        var incompleteFastMTPreferences = FastTranslationPreferences()
        incompleteFastMTPreferences.nllb200Distilled600MCT2ModelPath = incompleteFastMTDirectory.path
        try require(
            FastTranslationCommandRunner.passiveHealth(preferences: incompleteFastMTPreferences).status != .ready,
            "An empty Fast MT model directory must not pass the startup readiness check."
        )

        let complete = ModelFeatureAvailability(
            models: [textModel, visionModel, speechModel],
            selectedOCRModelID: visionModel.id,
            fastTranslationReady: false,
            textToSpeechReady: true
        )
        try require(
            complete.textTasks && complete.imagePostProcessing && complete.realtimeSubtitles
                && complete.mediaTranscription && complete.meetingNotes && complete.multiRoleTextToSpeech,
            "Expected one recommended model per core feature to form a complete setup."
        )

        let staleModel = ModelDescriptor(
            name: "Moved model",
            sourcePath: root.appendingPathComponent("does-not-exist"),
            format: .mlx,
            sizeClass: "fixture",
            role: .default,
            contextLength: 4_096,
            capabilities: .textOnly(source: .manual)
        )
        let stale = ModelFeatureAvailability(models: [staleModel])
        try require(stale.registeredModelCount == 1 && stale.availableModelCount == 0 && stale.missingLocalFileCount == 1, "Expected a stale local path to stay registered but be unavailable.")
        try require(!stale.textTasks, "A missing local path must not unlock text tasks.")

        let emptyDirectoryURL = root.appendingPathComponent("empty-model", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDirectoryURL, withIntermediateDirectories: true)
        let emptyDirectoryModel = ModelDescriptor(
            name: "Empty model directory",
            sourcePath: emptyDirectoryURL,
            format: .mlx,
            sizeClass: "fixture",
            role: .default,
            contextLength: 4_096,
            capabilities: .textOnly(source: .manual)
        )
        let emptyDirectoryState = ModelFeatureAvailability(models: [emptyDirectoryModel])
        try require(
            emptyDirectoryState.availableModelCount == 0 && emptyDirectoryState.missingLocalFileCount == 1,
            "A directory without model files must not be treated as an installed model."
        )

        let failedModel = ModelDescriptor(
            name: "Failed text model",
            sourcePath: textModel.sourcePath,
            format: .mlx,
            sizeClass: "fixture",
            role: .default,
            contextLength: 4_096,
            validationState: .failed,
            capabilities: .textOnly(source: .manual)
        )
        try require(
            !ModelFeatureAvailability(models: [failedModel]).textTasks,
            "A model with an explicit failed validation state must not unlock features."
        )

        let funASRModel = ModelDescriptor(
            name: "Fun-ASR-MLT-Nano",
            sourcePath: try directory("Fun-ASR-MLT-Nano"),
            format: .speech,
            sizeClass: "fixture",
            role: .default,
            contextLength: 0,
            capabilities: .speech(.funASRMLTNano(source: .manual, confidence: 1))
        )
        try require(
            ModelRecommendationPolicy.preferredRealtimeSpeechModel(in: [funASRModel, speechModel])?.id == speechModel.id,
            "Expected Qwen3-ASR 0.6B 8bit to be the accuracy-first automatic recommendation."
        )

        let preferenceStore = RegistryStore(fileURL: root.appendingPathComponent("preference-registry.json"))
        let engine = TaskEngine(
            registryStore: preferenceStore,
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("preference-history.json"))
        )
        try await engine.addModelDescriptorForTesting(funASRModel)
        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.realtimeASRModelID = funASRModel.id
        }
        try await engine.addModelDescriptorForTesting(speechModel)
        let retainedSelection = await engine.registry().preferences.mediaSubtitles.realtimeASRModelID
        try require(retainedSelection == funASRModel.id, "Adding a recommended ASR model must not replace an existing valid user selection.")

        let externalModelURL = try directory("external-text-model")
        let externalModel = ModelDescriptor(
            name: "External text model",
            sourcePath: externalModelURL,
            format: .mlx,
            sizeClass: "fixture",
            role: .default,
            contextLength: 4_096,
            validationState: .valid,
            capabilities: .textOnly(source: .manual)
        )
        let externalStore = RegistryStore(fileURL: root.appendingPathComponent("external-registry.json"))
        let externalHistory = HistoryStore(fileURL: root.appendingPathComponent("external-history.json"))
        let externalEngine = TaskEngine(registryStore: externalStore, historyStore: externalHistory)
        try await externalEngine.addModelDescriptorForTesting(externalModel)
        try await externalEngine.updatePreferences { $0.defaultModelID = externalModel.id }
        try FileManager.default.removeItem(at: externalModelURL)

        let offlineEngine = TaskEngine(registryStore: externalStore, historyStore: externalHistory)
        await offlineEngine.bootstrap()
        let offlineSnapshot = await offlineEngine.registry()
        try require(
            offlineSnapshot.preferences.defaultModelID == externalModel.id,
            "A temporarily unavailable external model must keep the user's preference."
        )
        _ = try directory("external-text-model")
        let remountedEngine = TaskEngine(registryStore: externalStore, historyStore: externalHistory)
        await remountedEngine.bootstrap()
        let remountedSnapshot = await remountedEngine.registry()
        try require(
            remountedSnapshot.preferences.defaultModelID == externalModel.id
                && remountedSnapshot.models.first(where: { $0.id == externalModel.id })?.isAvailableForUse == true,
            "The preserved preference must become usable again after the model path is restored."
        )

        let ocrStore = RegistryStore(fileURL: root.appendingPathComponent("ocr-registry.json"))
        let ocrEngine = TaskEngine(
            registryStore: ocrStore,
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("ocr-history.json"))
        )
        try await ocrEngine.addModelDescriptorForTesting(visionModel)
        let selectedOCRModelID = await ocrEngine.registry().preferences.ocr.modelID
        try require(
            selectedOCRModelID == visionModel.id,
            "The first usable OCR model should be selected automatically."
        )
    }

    private static func checkTextToSpeechProjectFixtures() throws {
        let explicitSource = "旁白：夜色降临。\n张三：我们出发吧。\n[李四] 等一下！"
        let explicit = try requireNonNil(
            TTSScriptParser.explicitAnalysis(explicitSource),
            "Expected explicit multi-role TTS parsing."
        )
        try require(explicit.voices.map(\.name) == ["旁白", "张三", "李四"], "Expected stable explicit role ordering.")
        try require(explicit.segments.map(\.sourceText) == ["夜色降临。", "我们出发吧。", "等一下！"], "Explicit parsing must preserve spoken text.")
        try require(explicit.segments[1].kind == .dialogue, "Expected role-prefixed line to become dialogue.")

        let prose = "雨停了。张三说：“走吧。”李四回答：“好。”"
        try require(TTSScriptParser.explicitAnalysis(prose) == nil, "Natural prose punctuation must not be treated as an explicit role prefix.")
        let novelStyle = """
        顾凡看着眼前挚爱的女人，声音低沉。
        顾凡压低着声音：“你要离婚，我同意了。”
        苏若冰俏脸一怒：“我心意已决。”
        圆桌上，美味佳肴。
        """
        try require(
            TTSScriptParser.explicitAnalysis(novelStyle) == nil,
            "Novel action descriptions before a colon must not bypass local role analysis."
        )
        let sourceUnits = TTSScriptParser.sourceUnits(prose)
        try require(
            sourceUnits.map(\.text) == ["雨停了。", "张三说：", "“走吧。”", "李四回答：", "“好。”"],
            "TTS source units should separate narration from inline dialogue."
        )
        let inlineDialogue = "顾凡看了一眼自己母亲与女儿：“你要离婚，我同意了，但能不能先把这顿饭吃完。”"
        try require(
            TTSScriptParser.sourceUnits(inlineDialogue).map(\.text) == [
                "顾凡看了一眼自己母亲与女儿：",
                "“你要离婚，我同意了，但能不能先把这顿饭吃完。”"
            ],
            "Inline novel dialogue must keep narration and character speech in separate units."
        )
        let assigned = try TTSScriptParser.parseModelAssignments(
            """
            {"roles":[{"name":"张三","voiceHint":"沉稳男声"},{"name":"李四","voiceHint":"清晰女声"}],"assignments":[{"index":0,"speaker":"旁白","type":"narration","confidence":1},{"index":1,"speaker":"旁白","type":"narration","confidence":1},{"index":2,"speaker":"张三","type":"dialogue","confidence":0.9},{"index":3,"speaker":"旁白","type":"narration","confidence":1},{"index":4,"speaker":"李四","type":"dialogue","confidence":0.9}]}
            """,
            units: sourceUnits
        )
        try require(assigned.segments.map(\.sourceText).joined() == prose, "Indexed role assignments must preserve source text.")
        try require(
            assigned.segments.map(\.speakerName) == ["旁白", "旁白", "张三", "旁白", "李四"],
            "Indexed role assignments should preserve detected speaker names."
        )
        let voiceCatalog = [
            TTSVoiceProfile(name: "沉稳旁白", instruction: "成熟男声，适合叙事"),
            TTSVoiceProfile(name: "热血少年", instruction: "年轻男声，明亮坚定")
        ]
        let catalogAssigned = try TTSScriptParser.parseModelAssignments(
            """
            {"roles":[{"name":"张三"},{"name":"李四"}],"assignments":[{"index":0,"speaker":"旁白","voiceIndex":0,"type":"narration","deliveryStyle":"沉稳舒缓，语速稍慢","pauseAfterMilliseconds":650},{"index":1,"speaker":"旁白","voiceIndex":0,"type":"narration","deliveryStyle":"平静铺陈","pauseAfterMilliseconds":350},{"index":2,"speaker":"张三","voiceIndex":1,"type":"dialogue","deliveryStyle":"坚定直接","pauseAfterMilliseconds":450},{"index":3,"speaker":"旁白","voiceIndex":0,"type":"narration","deliveryStyle":"平静铺陈","pauseAfterMilliseconds":350},{"index":4,"speaker":"李四","voiceIndex":1,"type":"dialogue","deliveryStyle":"急切回应","pauseAfterMilliseconds":550}]}
            """,
            units: sourceUnits,
            availableVoices: voiceCatalog
        )
        try require(
            catalogAssigned.segments.map(\.roleID) == [voiceCatalog[0].id, voiceCatalog[0].id, voiceCatalog[1].id, voiceCatalog[0].id, voiceCatalog[1].id],
            "Role analysis should map voice indexes back to existing solidified voices."
        )
        try require(
            catalogAssigned.voices == voiceCatalog,
            "Catalog-backed role analysis must never create new voice profiles."
        )
        try require(
            catalogAssigned.segments.map(\.deliveryStyle) == ["沉稳舒缓，语速稍慢", "平静铺陈", "坚定直接", "平静铺陈", "急切回应"]
                && catalogAssigned.segments.map(\.pauseAfterMilliseconds) == [650, 350, 450, 350, 550],
            "Role analysis should retain per-segment delivery styles and pauses."
        )
        let repairedCatalogAssignment = try TTSScriptParser.parseModelAssignments(
            """
            {"roles":[],"assignments":[{"index":0,"speaker":"旁白","voiceIndex":0,"type":"narration","deliveryStyle":"平静铺陈","pauseAfterMilliseconds":600},{"index":1,"speaker":"旁白","voiceIndex":0,"type":"narration","deliveryStyle":"平静铺陈","pauseAfterMilliseconds":350},{"index":2,"speaker":"张三","voiceIndex":1,"type":"dialogue","deliveryStyle":"压低声音","pauseAfterMilliseconds":500},{"index":3,"speaker":"旁白","voiceIndex":0,"type":"narration","deliveryStyle":"平静铺陈","pauseAfterMilliseconds":350},{"index":4,"speaker":"李四","voiceIndex":1,"type":"dialogue","deliveryStyle":"迅速回应","pauseAfterMilliseconds":550}]
            """,
            units: sourceUnits,
            availableVoices: voiceCatalog
        )
        try require(
            repairedCatalogAssignment.segments.map(\.deliveryStyle) == ["平静铺陈", "平静铺陈", "压低声音", "平静铺陈", "迅速回应"],
            "Role analysis should repair a model response missing only its outer closing brace."
        )
        let groupedVoices = [
            TTSVoiceProfile(name: "男声 A", groupName: "男声"),
            TTSVoiceProfile(name: "未分组"),
            TTSVoiceProfile(name: "女声 A", groupName: "女声"),
            TTSVoiceProfile(name: "男声 B", groupName: " 男声 ")
        ]
        let voiceSections = TTSVoiceCatalog.sections(for: groupedVoices)
        try require(
            voiceSections.map(\.groupName) == ["男声", "女声", nil],
            "TTS voice groups should preserve first-seen group order and place ungrouped voices last."
        )
        let reorderedVoices = try requireNonNil(
            TTSVoiceCatalog.movingVoice(groupedVoices[3].id, by: -1, in: groupedVoices),
            "Expected voice to move within its group."
        )
        try require(
            TTSVoiceCatalog.sections(for: reorderedVoices)[0].voices.map(\.name) == ["男声 B", "男声 A"],
            "TTS voice sorting should only change order inside the selected group."
        )
        do {
            _ = try TTSScriptParser.parseModelAssignments(
                #"{"roles":[],"assignments":[{"index":0,"speaker":"旁白","voiceIndex":0},{"index":1,"speaker":"旁白","voiceIndex":0},{"index":2,"speaker":"张三","voiceIndex":99},{"index":3,"speaker":"旁白","voiceIndex":0},{"index":4,"speaker":"李四","voiceIndex":1}]}"#,
                units: sourceUnits,
                availableVoices: voiceCatalog
            )
            throw CheckError("Expected out-of-range TTS voice indexes to be rejected.")
        } catch is TTSError {
            // Expected: invalid model output must not silently select the wrong solidified voice.
        }
        do {
            _ = try TTSScriptParser.parseModelAssignments(
                #"{"roles":[],"assignments":[{"index":0,"speaker":"旁白"}]}"#,
                units: sourceUnits
            )
            throw CheckError("Expected incomplete indexed role assignments to be rejected.")
        } catch is TTSError {
            // Expected: every deterministic source index must be assigned exactly once.
        }
        let manyUnits = (0..<40).map {
            TTSSourceUnit(index: $0, text: "句段\($0)。", sourceStart: $0 * 4, sourceEnd: $0 * 4 + 4)
        }
        let unitChunks = TTSScriptParser.sourceUnitChunks(manyUnits, maximumCharacters: 10_000)
        try require(unitChunks.allSatisfy { $0.count <= 16 }, "Role-analysis chunks must respect the output-budget unit limit.")
        try require(unitChunks.flatMap { $0 }.count == manyUnits.count, "Role-analysis chunking must retain every source unit.")
        let longText = String(repeating: "这是一句需要保持原样的长文案。", count: 30)
        let longVoice = TTSVoiceProfile(name: "旁白")
        let synthesisReady = TTSScriptParser.synthesisReadyAnalysis(
            TTSScriptAnalysis(
                voices: [longVoice],
                segments: [TTSSegment(
                    index: 0,
                    kind: .narration,
                    roleID: longVoice.id,
                    sourceText: longText,
                    deliveryStyle: "沉稳叙述",
                    pauseAfterMilliseconds: 700
                )]
            ),
            maximumCharacters: 120
        )
        try require(synthesisReady.segments.count > 1, "Long TTS text should be split before synthesis.")
        try require(synthesisReady.segments.map(\.sourceText).joined() == longText, "Synthesis splitting must preserve exact text.")
        try require(
            synthesisReady.segments.allSatisfy { $0.deliveryStyle == "沉稳叙述" }
                && synthesisReady.segments.dropLast().allSatisfy { $0.pauseAfterMilliseconds == 180 }
                && synthesisReady.segments.last?.pauseAfterMilliseconds == 700,
            "Synthesis splitting should preserve delivery style and use audible internal pauses."
        )
        let emptyQuoteRemoved = TTSScriptParser.synthesisReadyAnalysis(
            TTSScriptAnalysis(
                voices: [longVoice],
                segments: [
                    TTSSegment(index: 0, kind: .narration, roleID: longVoice.id, sourceText: "可正常朗读。"),
                    TTSSegment(index: 1, kind: .dialogue, roleID: longVoice.id, sourceText: "”")
                ]
            )
        )
        try require(
            emptyQuoteRemoved.segments.map(\.sourceText) == ["可正常朗读。"]
                && emptyQuoteRemoved.segments.map(\.index) == [0],
            "Quote-only TTS segments must be removed before synthesis."
        )

        let root = try makeTemporaryDirectory(name: "tts-project")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TTSProjectStore(rootDirectory: root.appendingPathComponent("projects"))
        var project = TTSProject(name: "角色测试", mode: .multiRole, sourceText: explicitSource)
        project.voicePreviewText = "这是需要跨启动保留的试听文案。"
        project.voices = explicit.voices
        project.voices[0].groupName = "旁白"
        project.selectedVoiceID = explicit.voices[1].id
        project.segments = explicit.segments
        let audioDirectory = try store.audioDirectory(for: project.id)
        for index in project.segments.indices {
            let audioURL = audioDirectory.appendingPathComponent("segment-\(index).wav")
            try LiveMeetingAudioStorage.writePCM16WAV(
                data: Data(repeating: UInt8(index), count: 9_600),
                sampleRate: 48_000,
                to: audioURL
            )
            project.segments[index].generationState = .completed
            project.segments[index].audioRelativePath = store.relativePath(for: audioURL, projectID: project.id)
            project.segments[index].duration = 0.1
            project.segments[index].pauseAfterMilliseconds = 100
        }
        project.voices[1].previewAudioRelativePath = project.segments[1].audioRelativePath
        try store.save(project)
        let restored = try requireNonNil(store.loadMostRecent(), "Expected TTS project recovery.")
        try require(restored.sourceText == explicitSource && restored.segments.count == 3, "Expected complete TTS project recovery.")
        try require(restored.selectedVoiceID == project.voices[1].id, "Expected selected TTS voice to persist.")
        try require(
            restored.voicePreviewText == project.voicePreviewText,
            "Expected edited TTS voice preview text to persist."
        )
        try require(
            restored.voices[1].previewAudioRelativePath == project.voices[1].previewAudioRelativePath,
            "Expected solidified voice preview path to persist."
        )
        try require(restored.voices[0].groupName == "旁白", "Expected TTS voice groups to persist.")
        let projectDirectory = store.projectDirectory(for: project.id)
        let projectPermissions = try posixPermissions(at: projectDirectory)
        let projectFileURL = projectDirectory.appendingPathComponent("project.json")
        let projectFilePermissions = try posixPermissions(at: projectFileURL)
        try require(projectPermissions == 0o700, "TTS project directory must be owner-only.")
        try require(projectFilePermissions == 0o600, "TTS project JSON must be owner-only.")

        // 旧项目没有当前音色、试听文案、说话角色和试听路径字段，升级后仍必须能正常恢复。
        var legacyJSON = try requireNonNil(
            JSONSerialization.jsonObject(with: Data(contentsOf: projectFileURL)) as? [String: Any],
            "Expected decodable TTS project JSON."
        )
        legacyJSON.removeValue(forKey: "selectedVoiceID")
        legacyJSON.removeValue(forKey: "voicePreviewText")
        if var voices = legacyJSON["voices"] as? [[String: Any]] {
            for index in voices.indices {
                voices[index].removeValue(forKey: "previewAudioRelativePath")
                voices[index].removeValue(forKey: "groupName")
            }
            legacyJSON["voices"] = voices
        }
        if var segments = legacyJSON["segments"] as? [[String: Any]] {
            for index in segments.indices {
                segments[index].removeValue(forKey: "speakerName")
                segments[index].removeValue(forKey: "deliveryStyle")
            }
            legacyJSON["segments"] = segments
        }
        try JSONSerialization.data(withJSONObject: legacyJSON).write(to: projectFileURL, options: .atomic)
        let legacyRestored = try requireNonNil(store.loadMostRecent(), "Expected legacy TTS project recovery.")
        try require(legacyRestored.selectedVoiceID == nil, "Legacy selected voice should decode as unset.")
        try require(legacyRestored.voicePreviewText == nil, "Legacy voice preview text should decode as unset.")
        try require(
            legacyRestored.segments.allSatisfy { $0.speakerName == nil },
            "Legacy TTS segments should decode without speaker names."
        )
        try require(
            legacyRestored.segments.allSatisfy { $0.deliveryStyle == nil },
            "Legacy TTS segments should decode without delivery styles."
        )
        try require(
            legacyRestored.voices.allSatisfy { $0.previewAudioRelativePath == nil },
            "Legacy voice previews should decode as unset."
        )
        try require(
            legacyRestored.voices.allSatisfy { $0.groupName == nil },
            "Legacy TTS voices should decode without groups."
        )

        let composedURL = root.appendingPathComponent("composed.wav")
        let composedDuration = try TTSAudioExporter.composeWAV(project: restored, store: store, outputURL: composedURL)
        let composed = try LiveMeetingAudioStorage.readPCM16WAV(at: composedURL)
        try require(composed.sampleRate == 48_000, "Expected 48 kHz TTS composition.")
        try require(abs(composedDuration - 0.6) < 0.01, "Expected generated audio plus configured pauses.")
        try require(composed.data.count == 57_600, "Expected deterministic PCM composition length.")
        let subtitles = TTSAudioExporter.srt(project: restored)
        try require(subtitles.contains("张三：我们出发吧。") && subtitles.contains("00:00:00,200"), "Expected role-aware TTS SRT timeline.")
        var partialProject = restored
        partialProject.segments[1].generationState = .failed
        let partialSubtitles = TTSAudioExporter.srt(project: partialProject)
        try require(!partialSubtitles.contains("张三：我们出发吧。"), "TTS SRT must exclude segments without completed audio.")
        let m4aURL = root.appendingPathComponent("composed.m4a")
        try TTSAudioExporter.convert(wavURL: composedURL, to: m4aURL, format: .m4a)
        try require(FileManager.default.fileExists(atPath: m4aURL.path), "Expected native M4A export.")
        let m4aPermissions = try posixPermissions(at: m4aURL)
        try require(m4aPermissions == 0o600, "Exported M4A must be owner-only.")

        let shardedModel = root.appendingPathComponent("VoxCPM2-bf16", isDirectory: true)
        try FileManager.default.createDirectory(at: shardedModel, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: shardedModel.appendingPathComponent("config.json"))
        try Data(#"{"weight_map":{"a":"model-00001.safetensors","b":"model-00002.safetensors"}}"#.utf8)
            .write(to: shardedModel.appendingPathComponent("model.safetensors.index.json"))
        try Data().write(to: shardedModel.appendingPathComponent("model-00001.safetensors"))
        try require(!LocalTTSService.modelFilesAreComplete(at: shardedModel), "Incomplete sharded model must not report ready.")
        try Data().write(to: shardedModel.appendingPathComponent("model-00002.safetensors"))
        try require(LocalTTSService.modelFilesAreComplete(at: shardedModel), "Complete sharded model should report ready.")
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

    private static func checkMiniCPM5Registration() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelDirectory = root.appendingPathComponent("MiniCPM5-1B-MLX", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "architectures": ["LlamaForCausalLM"],
          "max_position_embeddings": 131072,
          "model_type": "llama"
        }
        """.utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data().write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let descriptor = try await engine.addModel(from: modelDirectory)

        try require(descriptor.format == .mlx, "MiniCPM5-1B must register as an MLX text model.")
        try require(descriptor.role == .fast, "MiniCPM5-1B must default to the fast local-model role.")
        try require(descriptor.contextLength == 131_072, "MiniCPM5-1B must retain its 131K context metadata.")
        try require(descriptor.capabilities.supportsText && !descriptor.capabilities.supportsImage, "MiniCPM5-1B must remain text-only.")
    }

    private static func checkLocalMLXVisionMetadataDetection() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelDirectory = root.appendingPathComponent("Qwen3.5-0.8B-MLX-8bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("""
        {
          "model_type": "qwen3_5",
          "image_token_id": 248056,
          "vision_start_token_id": 248053,
          "vision_end_token_id": 248054,
          "vision_config": {
            "model_type": "qwen3_5_vision"
          }
        }
        """.utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("processor_config.json").path, contents: Data("""
        {
          "processor_class": "Qwen3VLProcessor",
          "image_processor": {
            "image_processor_type": "Qwen3VLImageProcessor"
          }
        }
        """.utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        try require(ModelDetection.isLocalVisionModel(at: modelDirectory), "Expected Qwen3VL MLX metadata to detect image capability.")

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let descriptor = try await engine.addModel(from: modelDirectory)
        try require(descriptor.capabilities.supportsImage, "Expected local MLX VLM to be image-capable after addModel.")
        try require(descriptor.capabilities.source == .detected, "Expected detected local MLX VLM capability source.")

        try await engine.updatePreferences { preferences in
            preferences.ocr.modelID = descriptor.id
        }
        let selectablePreference = await engine.registry().preferences.ocr.modelID
        try require(selectablePreference == descriptor.id, "Expected detected local MLX VLM to remain selectable for OCR.")

        let glmDirectory = root.appendingPathComponent("GLM-OCR-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: glmDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "architectures": ["GlmOcrForConditionalGeneration"],
          "model_type": "glm_ocr",
          "image_token_id": 59280,
          "text_config": {"max_position_embeddings": 131072},
          "vision_config": {"model_type": "glm_ocr_vision", "image_size": 336}
        }
        """.utf8).write(to: glmDirectory.appendingPathComponent("config.json"))
        try Data("""
        {"image_processor_type":"Glm46VImageProcessor","processor_class":"Glm46VProcessor"}
        """.utf8).write(to: glmDirectory.appendingPathComponent("preprocessor_config.json"))
        try Data("{}".utf8).write(to: glmDirectory.appendingPathComponent("tokenizer.json"))
        try Data().write(to: glmDirectory.appendingPathComponent("model.safetensors"))

        try require(ModelDetection.isLocalVisionModel(at: glmDirectory), "Expected GLM-OCR metadata to detect image capability.")
        try require(ModelDetection.isGLMOCRModel(at: glmDirectory), "Expected GLM-OCR model type detection.")
        let glm = try await engine.addModel(from: glmDirectory)
        try require(glm.capabilities.supportsImage && !glm.capabilities.supportsText, "GLM-OCR must be image-only rather than a generic text VLM.")
        try await engine.updatePreferences { preferences in
            preferences.ocr.modelID = glm.id
        }
        let glmOCRPreference = await engine.registry().preferences.ocr.modelID
        try require(glmOCRPreference == glm.id, "GLM-OCR must remain selectable for OCR.")
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
        let updated = try await engine.setModelContextLength(id: descriptor.id, contextLength: 131_072)
        try require(updated.contextLength == 131_072, "Expected local model context length to update independently.")
        let persisted = try JSONDecoder().decode(
            RegistrySnapshot.self,
            from: Data(contentsOf: root.appendingPathComponent("registry.json"))
        )
        try require(persisted.models.first?.contextLength == 131_072, "Expected local model context length to persist.")
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

    private static func checkPrivateStorePermissions() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let privateDirectory = root.appendingPathComponent("Application Support/llmTools", isDirectory: true)
        try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
        let registryURL = privateDirectory.appendingPathComponent("model-registry.json")
        let historyURL = privateDirectory.appendingPathComponent("history.json")
        let registryBackupURL = privateDirectory.appendingPathComponent("model-registry.json.bak-test")
        try Data("{\"models\":[],\"preferences\":{}}".utf8).write(to: registryURL)
        try Data("[]".utf8).write(to: historyURL)
        try Data("backup".utf8).write(to: registryBackupURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: privateDirectory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: registryURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: historyURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: registryBackupURL.path)

        let registryStore = RegistryStore(fileURL: registryURL)
        let historyStore = HistoryStore(fileURL: historyURL)
        _ = try await registryStore.load()
        _ = try await historyStore.load()
        let migratedDirectoryPermissions = try posixPermissions(at: privateDirectory)
        let migratedRegistryPermissions = try posixPermissions(at: registryURL)
        let migratedHistoryPermissions = try posixPermissions(at: historyURL)
        let migratedBackupPermissions = try posixPermissions(at: registryBackupURL)
        try require(migratedDirectoryPermissions == 0o700, "Expected local data directory permissions to migrate to 0700.")
        try require(migratedRegistryPermissions == 0o600, "Expected existing registry permissions to migrate to 0600.")
        try require(migratedHistoryPermissions == 0o600, "Expected existing history permissions to migrate to 0600.")
        try require(migratedBackupPermissions == 0o600, "Expected existing registry backup permissions to migrate to 0600.")

        try await registryStore.save(.init())
        try await historyStore.save([])
        let savedRegistryPermissions = try posixPermissions(at: registryURL)
        let savedHistoryPermissions = try posixPermissions(at: historyURL)
        try require(savedRegistryPermissions == 0o600, "Expected saved registry permissions to remain 0600.")
        try require(savedHistoryPermissions == 0o600, "Expected saved history permissions to remain 0600.")
    }

    private static func checkProviderCredentialStoragePolicy() throws {
        let inline = ProviderConfiguration(
            providerID: .siliconFlow,
            apiStyle: .openAICompatible,
            apiKey: " local-key ",
            apiKeyKeychainAccount: "legacy-account"
        )
        let resolvedInline = try ProviderCredentialStore.resolvedAPIKey(for: inline)
        try require(
            resolvedInline == "local-key",
            "Expected provider credentials to resolve only from the local registry value."
        )
        var legacyOnly = inline
        legacyOnly.apiKey = ""
        let resolvedLegacy = try ProviderCredentialStore.resolvedAPIKey(for: legacyOnly)
        try require(
            resolvedLegacy.isEmpty,
            "Expected legacy Keychain references to be ignored without accessing macOS Keychain."
        )
    }

    private static func checkProviderEndpointPolicy() async throws {
        try require(ProviderEndpointPolicy.allows(URL(string: "https://api.example.com/v1")!), "Expected remote HTTPS provider URL to be allowed.")
        try require(ProviderEndpointPolicy.allows(URL(string: "http://localhost:11434/v1")!), "Expected localhost HTTP provider URL to be allowed.")
        try require(ProviderEndpointPolicy.allows(URL(string: "http://127.0.0.1:1234/v1")!), "Expected loopback HTTP provider URL to be allowed.")
        try require(!ProviderEndpointPolicy.allows(URL(string: "http://api.example.com/v1")!), "Expected remote HTTP provider URL to be rejected.")
        try require(!ProviderEndpointPolicy.allows(URL(string: "https://user:secret@api.example.com/v1")!), "Expected provider URL credentials to be rejected.")

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        )
        do {
            _ = try await engine.addProviderModel(
                providerID: .customOpenAICompatible,
                modelID: "remote-model",
                apiKey: "secret",
                baseURL: "http://api.example.com/v1"
            )
            throw CheckError("Expected remote HTTP provider registration to fail.")
        } catch let error as RunnerError {
            try require(error.localizedDescription == ProviderEndpointPolicy.secureTransportMessage, "Expected clear HTTPS validation error.")
        }
    }

    private static func checkLocalBridgeHTTPFraming() throws {
        let complete = Data("POST /translate HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}".utf8)
        try require(
            LocalBridgeHTTPFraming.readState(for: complete) == .complete(expectedByteCount: complete.count),
            "Expected a complete local bridge request."
        )
        let incomplete = Data("POST /translate HTTP/1.1\r\nContent-Length: 4\r\n\r\n{}".utf8)
        try require(LocalBridgeHTTPFraming.readState(for: incomplete) == .incomplete, "Expected an incomplete request body.")
        let duplicate = Data("POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\na".utf8)
        try require(LocalBridgeHTTPFraming.readState(for: duplicate) == .invalid, "Expected duplicate Content-Length to be rejected.")
        let negative = Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        try require(LocalBridgeHTTPFraming.readState(for: negative) == .invalid, "Expected negative Content-Length to be rejected.")
        let oversized = Data("POST / HTTP/1.1\r\nContent-Length: 999999999999999999999999\r\n\r\n".utf8)
        try require(LocalBridgeHTTPFraming.readState(for: oversized) == .invalid, "Expected overflowing Content-Length to be rejected.")
        let tooLarge = Data("POST / HTTP/1.1\r\nContent-Length: \(LocalBridgeHTTPFraming.maximumRequestBytes)\r\n\r\n".utf8)
        try require(LocalBridgeHTTPFraming.readState(for: tooLarge) == .tooLarge, "Expected an oversized request to be rejected.")
    }

    private static func checkProviderRedirectPolicy() throws {
        let source = URL(string: "https://api.example.com/v1/chat")!
        try require(
            ProviderRedirectPolicy.allowsRedirect(from: source, to: URL(string: "https://api.example.com/v2/chat")!),
            "Expected a same-origin provider redirect to be allowed."
        )
        try require(
            !ProviderRedirectPolicy.allowsRedirect(from: source, to: URL(string: "https://other.example.com/v1/chat")!),
            "Expected a cross-host provider redirect to be rejected."
        )
        try require(
            !ProviderRedirectPolicy.allowsRedirect(from: source, to: URL(string: "http://api.example.com/v1/chat")!),
            "Expected a provider HTTPS downgrade redirect to be rejected."
        )
        let local = URL(string: "http://127.0.0.1:11434/v1/chat")!
        try require(
            !ProviderRedirectPolicy.allowsRedirect(from: local, to: URL(string: "http://127.0.0.1:11435/v1/chat")!),
            "Expected a provider redirect to another local port to be rejected."
        )
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
        try require(
            ProviderRequestOptions.enableThinking(for: qwen3Text, requested: true) == true,
            "Expected SiliconFlow Qwen3 text models to enable thinking when requested."
        )
        try require(
            ProviderRequestOptions.supportsThinkingToggle(for: qwen3Text),
            "Expected SiliconFlow Qwen3 text models to expose thinking mode control."
        )
        let remoteDescriptor = ModelDescriptor(
            name: "Qwen3 remote",
            sourcePath: URL(string: "https://api.siliconflow.cn/v1")!,
            format: .openAICompatible,
            sizeClass: "remote",
            role: .default,
            contextLength: 32_768,
            providerConfiguration: qwen3Text
        )
        try require(remoteDescriptor.supportsThinkingModeControl, "Expected the supported remote model card to expose thinking mode control.")

        let qwen3Vision = ProviderConfiguration(
            providerID: .siliconFlow,
            apiStyle: .openAICompatible,
            modelID: "Qwen/Qwen3-VL-8B-Instruct"
        )
        try require(
            ProviderRequestOptions.enableThinking(for: qwen3Vision) == nil,
            "Expected SiliconFlow Qwen3-VL models not to receive unsupported enable_thinking."
        )

        let localRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: localRoot) }
        try Data("{% if enable_thinking %}".utf8).write(
            to: localRoot.appendingPathComponent("chat_template.jinja")
        )
        let localDescriptor = ModelDescriptor(
            name: "Qwen3 local",
            sourcePath: localRoot,
            format: .mlx,
            sizeClass: "4b",
            role: .default,
            contextLength: 8_192
        )
        try require(localDescriptor.supportsThinkingModeControl, "Expected a local MLX thinking template to expose thinking mode control.")
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

    private static func checkPerTaskDefaultModelRouting() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let defaultRunner = StubRunner(output: "default summary", format: .mlx)
        let polishRunner = StubRunner(output: "task polish", format: .gguf)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: defaultRunner, .gguf: polishRunner]
        )
        let defaultModel = ModelDescriptor(
            name: "Default Text Fixture",
            sourcePath: root.appendingPathComponent("default-model"),
            format: .mlx,
            sizeClass: "fixture",
            role: .default,
            contextLength: 4_096,
            capabilities: .textOnly(source: .manual)
        )
        let taskModel = ModelDescriptor(
            name: "Polish Fixture",
            sourcePath: root.appendingPathComponent("polish-model"),
            format: .gguf,
            sizeClass: "fixture",
            role: .quality,
            contextLength: 4_096,
            capabilities: .textOnly(source: .manual)
        )
        try FileManager.default.createDirectory(at: defaultModel.sourcePath, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: defaultModel.sourcePath.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: defaultModel.sourcePath.appendingPathComponent("tokenizer.json"))
        FileManager.default.createFile(
            atPath: defaultModel.sourcePath.appendingPathComponent("model.safetensors").path,
            contents: Data()
        )
        FileManager.default.createFile(atPath: taskModel.sourcePath.path, contents: Data())
        try await engine.addModelDescriptorForTesting(defaultModel)
        try await engine.addModelDescriptorForTesting(taskModel)
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = defaultModel.id
            preferences.setTextModelID(taskModel.id, for: .polish)
            preferences.detailedTranslationEnabled = true
            preferences.detailedTranslationModelID = taskModel.id
        }

        let configured = await engine.registry().preferences
        let roundTripped = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONEncoder().encode(configured)
        )
        try require(roundTripped.preferredTextModelID(for: .polish) == taskModel.id, "Expected the polish model override to persist.")
        try require(roundTripped.detailedTranslationEnabled, "Expected detailed translation to stay enabled after preference round-trip.")
        try require(roundTripped.detailedTranslationModelID == taskModel.id, "Expected the detailed translation model to persist.")
        for task in [TaskKind.summarize, .explain, .extractTodos] {
            try require(roundTripped.preferredTextModelID(for: task) == defaultModel.id, "Expected an unset task model to fall back to the default model.")
        }

        let polished = try await engine.run(request: TaskRequest(task: .polish, inputText: "Polish this."))
        let summarized = try await engine.run(request: TaskRequest(task: .summarize, inputText: "Summarize this."))
        try require(polished.text == "task polish", "Expected polish to use its configured task model.")
        try require(summarized.text == "default summary", "Expected summary to use the shared default model when no override is configured.")
        let loadedPolishModelID = await polishRunner.loadedModelID()
        let loadedDefaultModelID = await defaultRunner.loadedModelID()
        try require(loadedPolishModelID == taskModel.id, "Expected the polish runner to load the task-specific model.")
        try require(loadedDefaultModelID == defaultModel.id, "Expected the default runner to load the fallback model.")
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
        try require(preferences.ocr.postProcessingModelID == nil, "Expected older OCR preferences to follow the default text model.")
        try require(preferences.webPageTranslation.pendingIndicatorStyle == .loading, "Expected webpage pending indicator to default to loading.")
        try require(preferences.webPageTranslation.autoTranslateDomains.isEmpty, "Expected webpage auto-translate domains to default empty.")
        try require(preferences.webPageTranslation.disabledDomains.isEmpty, "Expected webpage disabled domains to default empty.")
        try require(preferences.webPageTranslation.domainReadingModes.isEmpty, "Expected webpage domain reading defaults to default empty.")
        try require(preferences.webPageTranslation.domainTranslationQualities.isEmpty, "Expected webpage domain quality defaults to default empty.")
        try require(!preferences.webPageTranslation.persistWebHistory, "Expected webpage translation history to default off.")
        try require(preferences.webPageTranslation.localConcurrentTranslationRequests == 1, "Expected local webpage concurrency to default to 1.")
        try require(!preferences.promptTemplates.translate.hasCustomPrompt, "Expected custom translate prompts to default empty.")
        try require(!preferences.promptTemplates.hasCustomOCRSystemPrompt, "Expected custom OCR system prompt to default empty.")
        try require(!preferences.promptTemplates.hasCustomOCRPrompt(for: .plainText), "Expected custom OCR mode prompts to default empty.")
        try require(preferences.quickActionShortcut == .optionSpace, "Expected quick action shortcut to default to Option-Space.")
        try require(preferences.quickActionWithoutSelectionShortcut == .optionShiftSpace, "Expected no-selection quick action shortcut to default to Option-Shift-Space.")
        try require(preferences.liveSubtitleShortcut == .commandOptionControlL, "Expected live subtitle shortcut to default to Command-Option-Control-L.")
        try require(preferences.quickActionPopupShortcuts.textMode == .commandControlNumber(1), "Expected popup text-mode shortcut to default to Command-Control-1.")
        try require(preferences.quickActionPopupShortcuts.imageMode == .commandControlNumber(2), "Expected popup image-mode shortcut to default to Command-Control-2.")
        try require(preferences.quickActionPopupShortcuts.mediaMode == .commandControlNumber(3), "Expected popup media-mode shortcut to default to Command-Control-3.")
        try require(preferences.quickActionPopupShortcuts.speechMode == .commandControlNumber(4), "Expected popup speech-mode shortcut to default to Command-Control-4.")
        try require(preferences.quickActionPopupShortcuts.textTaskShortcut(for: .translate) == .commandNumber(1), "Expected popup translate shortcut to default to Command-1.")
        try require(preferences.quickActionPopupShortcuts.textTaskShortcut(for: .extractTodos) == .commandNumber(5), "Expected popup TODO shortcut to default to Command-5.")
        try require(preferences.quickActionPopupShortcuts.ocrModeShortcut(for: .plainText) == .commandNumber(1), "Expected popup plain OCR shortcut to default to Command-1.")
        try require(preferences.quickActionPopupShortcuts.ocrModeShortcut(for: .explainImage) == .commandNumber(4), "Expected popup image explanation shortcut to default to Command-4.")
        for (index, action) in QuickActionSpeechAction.allCases.enumerated() {
            try require(
                preferences.quickActionPopupShortcuts.speechActionShortcut(for: action) == .commandNumber(index + 1),
                "Expected popup speech action shortcut \(action.rawValue) to use Command-\(index + 1)."
            )
        }

        // 旧快捷键 JSON 不含语音字段时，既要保留旧值，也要补上新的默认快捷键。
        var legacyPopupSource = QuickActionPopupShortcuts()
        legacyPopupSource.textMode = .commandControlNumber(9)
        var legacyPopupJSON = try requireNonNil(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyPopupSource)) as? [String: Any],
            "Expected encodable popup shortcut preferences."
        )
        for key in [
            "speechMode",
            "speechGenerate",
            "speechVoicePreview",
            "speechPlayback",
            "speechExportWAV",
            "speechExportM4A"
        ] {
            legacyPopupJSON.removeValue(forKey: key)
        }
        let legacyPopup = try JSONDecoder().decode(
            QuickActionPopupShortcuts.self,
            from: JSONSerialization.data(withJSONObject: legacyPopupJSON)
        )
        try require(legacyPopup.textMode == .commandControlNumber(9), "Legacy popup shortcuts should preserve existing values.")
        try require(legacyPopup.speechMode == .commandControlNumber(4), "Legacy popup shortcuts should add the speech-mode default.")
        var remappedSpeechShortcuts = legacyPopup
        remappedSpeechShortcuts.setSpeechActionShortcut(.commandNumber(9), for: .playback)
        try require(
            remappedSpeechShortcuts.speechAction(matching: .commandNumber(9)) == .playback,
            "Speech shortcut setter and matching should use the same action mapping."
        )
        try require(preferences.defaultTranslationTarget == "English", "Expected existing target language value to be preserved.")
        try require(preferences.defaultTranslationQuality == .natural, "Expected older registries to default translation quality to natural.")
        try require(preferences.defaultPolishStyle == "formal", "Expected existing polish style value to be preserved.")
        try require(preferences.defaultSummaryMode == .keyPoints, "Expected older registries to default summaries to key points.")
        try require(preferences.defaultExplanationMode == .plain, "Expected older registries to default explanations to plain mode.")
        try require(preferences.defaultTodoExtractionMode == .actionItems, "Expected older registries to default TODO extraction to action items.")
        try require(preferences.textTaskModelIDs.isEmpty, "Expected older registries to keep per-task model overrides empty.")
        try require(!preferences.detailedTranslationEnabled, "Expected detailed translation to default off for older registries.")
        try require(preferences.detailedTranslationModelID == nil, "Expected older registries to leave the detailed translation model unset.")
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

    private static func checkDesktopAssistantStageAContracts() async throws {
        let legacyJSON = """
        {
          "autoCollapseWidget": false,
          "widgetVisibleOnAllSpaces": false
        }
        """
        let migrated = try JSONDecoder().decode(AppPreferences.self, from: Data(legacyJSON.utf8))
        try require(!migrated.desktopAssistant.isEnabled, "The new assistant must not inherit the old widget's enabled state.")
        try require(!migrated.desktopAssistant.hasCompletedCurrentOnboarding, "The new assistant must require its own onboarding.")
        try require(migrated.desktopAssistant.showOnAllSpaces, "The assistant should default to ordinary Spaces.")
        try require(!migrated.desktopAssistant.showOverFullScreen, "The assistant should stay hidden over full-screen apps by default.")
        try require(
            migrated.desktopAssistant.toolbarTrigger == .hover
                && migrated.desktopAssistant.proactivity == .moderate
                && migrated.desktopAssistant.personality == .gentle
                && !migrated.desktopAssistant.quietHours.isEnabled
                && !migrated.desktopAssistant.lateNightReminderEnabled,
            "Assistant interaction, Moderate proactivity, personality, quiet-hours, and late-night defaults must match the approved first-run behavior."
        )
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let overnightQuietHours = AssistantQuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 8 * 60)
        let beforeStart = utcCalendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 21, minute: 59))!
        let atStart = utcCalendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 22))!
        let beforeEnd = utcCalendar.date(from: DateComponents(year: 2027, month: 1, day: 2, hour: 7, minute: 59))!
        let atEnd = utcCalendar.date(from: DateComponents(year: 2027, month: 1, day: 2, hour: 8))!
        try require(
            !overnightQuietHours.contains(beforeStart, calendar: utcCalendar)
                && overnightQuietHours.contains(atStart, calendar: utcCalendar)
                && overnightQuietHours.contains(beforeEnd, calendar: utcCalendar)
                && !overnightQuietHours.contains(atEnd, calendar: utcCalendar),
            "Overnight quiet hours must include the start minute, cross midnight, and exclude the end minute."
        )
        var persistedControls = migrated
        persistedControls.desktopAssistant.personality = .lightTeasing
        persistedControls.desktopAssistant.lateNightReminderEnabled = true
        let restoredControls = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONEncoder().encode(persistedControls)
        )
        try require(
            restoredControls.desktopAssistant.personality == .lightTeasing
                && restoredControls.desktopAssistant.lateNightReminderEnabled,
            "The optional late-night reminder must persist independently from assistant personality."
        )
        var explicitlyQuiet = migrated
        explicitlyQuiet.desktopAssistant.proactivity = .quiet
        let restoredQuiet = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONEncoder().encode(explicitlyQuiet)
        )
        try require(
            restoredQuiet.desktopAssistant.proactivity == .quiet,
            "Changing the first-run default must not migrate an existing user's explicit Quiet choice."
        )
        var manualOnly = migrated.desktopAssistant
        manualOnly.foregroundApplicationContextEnabled = false
        manualOnly.enhancedWindowContextEnabled = false
        manualOnly.clipboardAuthorization = .denied
        manualOnly.selectionContextEnabled = false
        try require(
            manualOnly.isManualOnly && !manualOnly.hasAnyBackgroundSource,
            "The manual-only preset must require no workspace, clipboard, selection, or permission observer."
        )
        var dormantEnhancedSource = DesktopAssistantPreferences(
            foregroundApplicationContextEnabled: false,
            enhancedWindowContextEnabled: true,
            clipboardAuthorization: .denied,
            selectionContextEnabled: false
        )
        try require(
            dormantEnhancedSource.enhancedWindowContextEnabled && dormantEnhancedSource.isManualOnly,
            "Enhanced-window preference must be retained but stay dormant without its foreground-app source."
        )
        dormantEnhancedSource.enhancedWindowContextEnabled = true
        try require(
            dormantEnhancedSource.isManualOnly,
            "A dormant enhanced-window preference must not create a background observer by itself."
        )
        try require(
            !AssistantProactivity.manual.requiresQualifiedJudgment
                && !AssistantProactivity.quiet.requiresQualifiedJudgment
                && AssistantProactivity.moderate.requiresQualifiedJudgment
                && AssistantProactivity.active.requiresQualifiedJudgment,
            "Only Moderate and Active proactivity may require a qualified local judgment model."
        )

        let encoded = try JSONEncoder().encode(migrated)
        let encodedText = String(decoding: encoded, as: UTF8.self)
        try require(encodedText.contains("desktopAssistant"), "Expected the new assistant preferences to persist.")
        try require(!encodedText.contains("autoCollapseWidget") && !encodedText.contains("widgetVisibleOnAllSpaces"), "Legacy widget keys must not be written.")

        var cancelledLifecycle = AssistantLifecycleMachine(preferences: migrated.desktopAssistant)
        cancelledLifecycle.apply(.requestEnable)
        cancelledLifecycle.apply(.cancelOnboarding)
        try require(
            cancelledLifecycle.mode == .disabled
                && !cancelledLifecycle.isVisible
                && !cancelledLifecycle.observationIsAllowed,
            "Cancelling first onboarding must leave the assistant disabled, hidden, and unable to observe."
        )

        var lifecycle = AssistantLifecycleMachine(preferences: migrated.desktopAssistant)
        lifecycle.apply(.requestEnable)
        try require(lifecycle.mode == .onboarding && !lifecycle.isVisible, "First enable should open onboarding before showing the orb.")
        lifecycle.apply(.finishOnboarding)
        lifecycle.apply(.hide)
        try require(lifecycle.mode == .idle && lifecycle.observationIsAllowed && !lifecycle.isVisible, "Hiding the orb must not silently disable observation.")
        var selectionDisabledPreferences = migrated.desktopAssistant
        selectionDisabledPreferences.selectionContextEnabled = false
        try require(
            lifecycle.allowsSelectionCapture(preferences: migrated.desktopAssistant)
                && !lifecycle.allowsSelectionCapture(preferences: selectionDisabledPreferences),
            "Automatic selection capture must require both active observation and explicit source authorization."
        )
        try require(
            lifecycle.resolvedPresentation(requested: .peek, hardPolicyAllowsPeek: true) == .badge,
            "Hidden assistant windows must accumulate a badge instead of reopening for a proactive peek."
        )
        lifecycle.apply(.show)
        try require(
            lifecycle.resolvedPresentation(requested: .peek, hardPolicyAllowsPeek: true) == .peek
                && lifecycle.resolvedPresentation(requested: .peek, hardPolicyAllowsPeek: false) == .badge,
            "Visible assistant windows may peek only while the final hard policy still allows it."
        )
        try require(
            lifecycle.allowsWindowPresentation(showOverFullScreen: false, frontmostApplicationIsFullScreen: false)
                && !lifecycle.allowsWindowPresentation(showOverFullScreen: false, frontmostApplicationIsFullScreen: true)
                && lifecycle.allowsWindowPresentation(showOverFullScreen: true, frontmostApplicationIsFullScreen: true),
            "Full-screen Spaces must hide assistant windows by default and show them only after explicit opt-in."
        )
        lifecycle.apply(.hide)
        try require(
            !lifecycle.allowsWindowPresentation(showOverFullScreen: true, frontmostApplicationIsFullScreen: false),
            "A user-hidden assistant must stay hidden regardless of full-screen preferences."
        )
        lifecycle.apply(.show)
        let expiredAttachmentCard = AssistantCard(
            createdAt: Date(timeIntervalSince1970: 10),
            source: .clipboard,
            comment: "expired",
            evidence: AssistantCardEvidence(sources: [.clipboard], capability: "test"),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        try require(
            !expiredAttachmentCard.isAvailableForExplicitContext(now: Date(timeIntervalSince1970: 21)),
            "Expired cards must not be eligible for explicit inquiry attachment."
        )
        let companionBubbleCard = AssistantCard(
            source: .windowContext,
            patternType: .contextualOpportunity,
            presentation: .peek,
            comment: "A grounded companion observation.",
            evidence: AssistantCardEvidence(sources: [.windowContext], capability: "contextualOpportunity")
        )
        var actionableOpportunityCard = companionBubbleCard
        actionableOpportunityCard.actionIDs = [.openQuickAction]
        try require(
            companionBubbleCard.prefersSpeechBubblePresentation
                && !actionableOpportunityCard.prefersSpeechBubblePresentation
                && !companionBubbleCard.requiresUserAction
                && actionableOpportunityCard.requiresUserAction
                && AssistantWindowGeometry.speechBubbleWidth < AssistantWindowGeometry.peekSize.width,
            "Only actionless P-06 comments should use the compact speech bubble and stay out of the action badge."
        )
        let badgeStore = AssistantCardStore()
        _ = await badgeStore.add(companionBubbleCard)
        _ = await badgeStore.add(actionableOpportunityCard)
        let badgeUnreadCount = await badgeStore.unreadCount()
        let latestActionableUnread = await badgeStore.latestUnread()
        try require(
            badgeUnreadCount == 1 && latestActionableUnread?.id == actionableOpportunityCard.id,
            "Only unread cards with actions should contribute to the orb badge and latest-action lookup."
        )
        var diagnosticTimeline = AssistantDiagnosticTimeline()
        let diagnosticBase = Date(timeIntervalSince1970: 100)
        for index in 0...AssistantDiagnosticTimeline.maximumEventCount {
            diagnosticTimeline.append(
                stage: .capture,
                state: .scheduled,
                detail: "event-\(index)",
                occurredAt: diagnosticBase.addingTimeInterval(Double(index))
            )
        }
        try require(
            diagnosticTimeline.events.count == AssistantDiagnosticTimeline.maximumEventCount
                && diagnosticTimeline.events.first?.detail == "event-\(AssistantDiagnosticTimeline.maximumEventCount)"
                && diagnosticTimeline.events.last?.detail == "event-1",
            "The live assistant diagnostic timeline must retain only the newest bounded status events."
        )
        var refreshedScheduleTimeline = AssistantDiagnosticTimeline()
        let firstScheduleAt = diagnosticBase.addingTimeInterval(40)
        refreshedScheduleTimeline.refreshScheduled(
            stage: .capture,
            detail: "trigger=user-interaction delay=3.0s reset=false cooldown=false",
            occurredAt: firstScheduleAt
        )
        let firstScheduleID = refreshedScheduleTimeline.events.first?.id
        refreshedScheduleTimeline.append(
            stage: .context,
            state: .running,
            detail: "other-stage",
            occurredAt: firstScheduleAt.addingTimeInterval(1)
        )
        let refreshedScheduleAt = firstScheduleAt.addingTimeInterval(2)
        refreshedScheduleTimeline.refreshScheduled(
            stage: .capture,
            detail: "trigger=user-interaction delay=3.0s reset=true cooldown=false",
            occurredAt: refreshedScheduleAt
        )
        try require(
            refreshedScheduleTimeline.events.filter { $0.stage == .capture && $0.state == .scheduled }.count == 1
                && refreshedScheduleTimeline.events.first?.id == firstScheduleID
                && refreshedScheduleTimeline.events.first?.occurredAt == refreshedScheduleAt
                && refreshedScheduleTimeline.events.first?.detail.contains("reset=true") == true,
            "A pending capture schedule must refresh in place with the latest debounce time."
        )
        let readableDiagnostic = try requireNonNil(
            refreshedScheduleTimeline.events.first,
            "Expected a refreshed capture diagnostic event."
        ).localizedSummary(language: .chinese)
        try require(
            readableDiagnostic.contains("截图 · 已计划")
                && readableDiagnostic.contains("重置为 3.0s"),
            "Exported and on-screen assistant activity must share the same readable diagnostic explanation."
        )
        let readableVisionTimeout = AssistantDiagnosticEvent(
            stage: .vision,
            state: .failed,
            detail: "vision-watchdog-timeout limit=60s elapsed=60000ms"
        ).localizedSummary(language: .chinese)
        try require(
            readableVisionTimeout.contains("超过 60s")
                && readableVisionTimeout.contains("卡死保护"),
            "Vision watchdog diagnostics must distinguish a hung model from cancellation or model failure."
        )
        let resumeAt = Date(timeIntervalSince1970: 200)
        lifecycle.apply(.pause(until: resumeAt))
        lifecycle.apply(.tick(Date(timeIntervalSince1970: 199)))
        try require(
            lifecycle.mode == .paused
                && !lifecycle.observationIsAllowed
                && !lifecycle.allowsSelectionCapture(preferences: migrated.desktopAssistant),
            "A timed pause should block observation and automatic selection capture."
        )
        lifecycle.apply(.tick(resumeAt))
        try require(
            lifecycle.mode == .idle
                && lifecycle.observationIsAllowed
                && lifecycle.allowsSelectionCapture(preferences: migrated.desktopAssistant),
            "A timed pause should resume observation and authorized selection capture deterministically."
        )
        let laterResume = Date(timeIntervalSince1970: 400)
        lifecycle.apply(.pause(until: laterResume))
        lifecycle.apply(.setPrivacy(true))
        try require(lifecycle.mode == .privacy && !lifecycle.observationIsAllowed, "Privacy mode must block observation.")
        lifecycle.apply(.setPrivacy(false))
        try require(lifecycle.mode == .paused && lifecycle.pauseUntil == laterResume, "Leaving privacy mode must restore an active timed pause.")
        lifecycle.apply(.tick(laterResume))
        try require(lifecycle.mode == .idle, "A pause restored after privacy mode should still expire normally.")
        lifecycle.apply(.disable)
        try require(lifecycle.mode == .disabled && !lifecycle.isVisible, "Disabling should close the assistant.")
        lifecycle.apply(.requestEnable)
        try require(
            lifecycle.mode == .idle && lifecycle.isVisible && lifecycle.observationIsAllowed,
            "Re-enabling after completed onboarding must restore the assistant without repeating first onboarding."
        )

        let store = AssistantCardStore()
        let baseDate = Date(timeIntervalSince1970: 1_000)
        for index in 0..<22 {
            _ = await store.add(AssistantCard(
                createdAt: baseDate.addingTimeInterval(Double(index)),
                source: .inquiry,
                comment: "card-\(index)",
                evidence: AssistantCardEvidence(sources: [.inquiry], capability: "test"),
                actionIDs: [.openSettings]
            ))
        }
        var cards = await store.snapshot()
        try require(cards.count == AssistantCardStore.maximumCardCount, "The recent-card store must keep at most 20 cards.")
        let sensitiveCard = AssistantCard(
            source: .inquiry,
            comment: "secret response",
            evidenceSummary: "password=secret",
            evidence: AssistantCardEvidence(sources: [.inquiry], capability: "sensitive-inquiry"),
            sensitivity: .sensitive
        )
        let cardsAfterSensitive = await store.add(sensitiveCard)
        try require(!cardsAfterSensitive.contains(where: { $0.id == sensitiveCard.id }), "Sensitive cards must never enter recent-card storage.")
        try require(cards.first?.comment == "card-21" && cards.last?.comment == "card-2", "The card store should retain the newest cards in reverse chronology.")
        if let latestID = cards.first?.id {
            cards = await store.markViewed(id: latestID)
            try require(cards.first?.state == .viewed, "Opening a card should clear only that card's unread state.")
            cards = await store.update(id: latestID, feedback: .useful)
            cards = await store.update(id: latestID, state: .unread)
            try require(
                cards.first?.state == .unread && cards.first?.feedback == .useful,
                "A timed-out proactive card must become unread again without erasing existing feedback."
            )
            cards = await store.markViewed(id: latestID)
        }
        let unreadCount = await store.unreadCount()
        try require(unreadCount == 19, "Viewing one card should leave the other cards unread.")
        let rollbackStore = AssistantCardStore()
        let retainedCard = AssistantCard(
            source: .inquiry,
            comment: "retained",
            evidence: AssistantCardEvidence(sources: [.inquiry], capability: "rollback-fixture")
        )
        let staleCard = AssistantCard(
            source: .clipboard,
            comment: "stale",
            evidence: AssistantCardEvidence(sources: [.clipboard], capability: "rollback-fixture")
        )
        _ = await rollbackStore.add(retainedCard)
        _ = await rollbackStore.add(staleCard)
        let cardsAfterRollback = await rollbackStore.remove(id: staleCard.id)
        try require(
            cardsAfterRollback.map(\.id) == [retainedCard.id],
            "A privacy epoch rollback must remove only the stale card inserted during an actor hop."
        )
        try require(
            AssistantRemoteWorkbenchDisclosure.requiresConfirmation(
                isAssistantHandoff: true,
                isRemoteModel: true,
                alreadyAcknowledged: false,
                localOnly: false
            ),
            "The first remote Quick Action run with assistant context must require disclosure."
        )
        try require(
            !AssistantRemoteWorkbenchDisclosure.requiresConfirmation(
                isAssistantHandoff: true,
                isRemoteModel: true,
                alreadyAcknowledged: true,
                localOnly: false
            ) && !AssistantRemoteWorkbenchDisclosure.requiresConfirmation(
                isAssistantHandoff: true,
                isRemoteModel: true,
                alreadyAcknowledged: false,
                localOnly: true
            ) && !AssistantRemoteWorkbenchDisclosure.requiresConfirmation(
                isAssistantHandoff: false,
                isRemoteModel: true,
                alreadyAcknowledged: false,
                localOnly: false
            ) && !AssistantRemoteWorkbenchDisclosure.requiresConfirmation(
                isAssistantHandoff: true,
                isRemoteModel: false,
                alreadyAcknowledged: false,
                localOnly: false
            ),
            "Acknowledged, explicitly local, non-assistant, or local-model runs must not show the remote disclosure."
        )

        let visibleFrame = CGRect(x: -200, y: 40, width: 1_000, height: 800)
        let defaultFrame = AssistantWindowGeometry.defaultOrbFrame(in: visibleFrame)
        try require(defaultFrame.size == CGSize(width: 48, height: 48) && visibleFrame.contains(defaultFrame), "The orb must be 48pt and start inside the visible frame.")
        let clamped = AssistantWindowGeometry.clampedOrbFrame(CGRect(x: -9_999, y: 9_999, width: 48, height: 48), in: visibleFrame)
        try require(visibleFrame.contains(clamped), "Dragging must clamp the orb to the current display.")
        let restored = AssistantWindowGeometry.restoredOrbFrame(
            from: AssistantWindowGeometry.storedPosition(for: defaultFrame, in: visibleFrame),
            in: visibleFrame
        )
        try require(abs(restored.midX - defaultFrame.midX) < 0.01 && abs(restored.midY - defaultFrame.midY) < 0.01, "Normalized display positions should round-trip.")

        let edgeCases: [(CGRect, AssistantAccessoryPlacement)] = [
            (CGRect(x: visibleFrame.minX + 8, y: visibleFrame.midY, width: 48, height: 48), .right),
            (CGRect(x: visibleFrame.maxX - 56, y: visibleFrame.midY, width: 48, height: 48), .left),
            (CGRect(x: visibleFrame.midX, y: visibleFrame.minY + 8, width: 48, height: 48), .above),
            (CGRect(x: visibleFrame.midX, y: visibleFrame.maxY - 56, width: 48, height: 48), .below)
        ]
        for (orbFrame, expectedPlacement) in edgeCases {
            let layout = AssistantWindowGeometry.accessoryLayout(orbFrame: orbFrame, visibleFrame: visibleFrame)
            try require(layout.placement == expectedPlacement, "Accessory placement should prefer the largest available side.")
            try require(visibleFrame.contains(layout.toolbarFrame) && visibleFrame.contains(layout.peekFrame), "Assistant accessory windows must remain fully visible.")
        }
        let compactPeek = AssistantWindowGeometry.accessoryLayout(
            orbFrame: defaultFrame,
            visibleFrame: visibleFrame,
            peekSize: CGSize(width: 320, height: 166)
        )
        try require(
            compactPeek.peekFrame.size == CGSize(width: 320, height: 166) && visibleFrame.contains(compactPeek.peekFrame),
            "Content-sized peek cards must retain their frozen width and remain on-screen."
        )
        let speechBubble = AssistantWindowGeometry.accessoryLayout(
            orbFrame: defaultFrame,
            visibleFrame: visibleFrame,
            peekSize: CGSize(
                width: AssistantWindowGeometry.speechBubbleWidth,
                height: AssistantWindowGeometry.speechBubbleMinimumHeight
            )
        )
        try require(
            visibleFrame.contains(speechBubble.peekFrame)
                && speechBubble.peekFrame.width == AssistantWindowGeometry.speechBubbleWidth,
            "Companion speech bubbles must remain compact and fully visible beside the orb."
        )
        try require(
            AssistantWindowGeometry.allowsPassiveToolbar(peekIsVisible: false, dropTargetIsActive: false)
                && !AssistantWindowGeometry.allowsPassiveToolbar(peekIsVisible: true, dropTargetIsActive: false)
                && !AssistantWindowGeometry.allowsPassiveToolbar(peekIsVisible: false, dropTargetIsActive: true),
            "Passive hover must never replace an open card or active drop target with the toolbar."
        )
    }

    private static func checkDesktopAssistantLocalPromptBoundary() async throws {
        let root = try makeTemporaryDirectory(name: "assistant-local-prompt")
        defer { try? FileManager.default.removeItem(at: root) }
        let localDirectory = root.appendingPathComponent("local-model", isDirectory: true)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        for name in ["config.json", "tokenizer.json", "model.safetensors"] {
            FileManager.default.createFile(atPath: localDirectory.appendingPathComponent(name).path, contents: Data("{}".utf8))
        }
        let localID = UUID()
        let remoteID = UUID()
        let local = ModelDescriptor(
            id: localID,
            name: "Local",
            sourcePath: localDirectory,
            resolvedPath: localDirectory,
            format: .mlx,
            sizeClass: "1b",
            role: .default,
            contextLength: 4_096,
            enabled: true,
            validationState: .valid,
            capabilities: .textOnly(source: .manual)
        )
        let remote = ModelDescriptor(
            id: remoteID,
            name: "Remote",
            sourcePath: URL(string: "https://example.com/v1")!,
            format: .openAICompatible,
            sizeClass: "remote",
            role: .default,
            contextLength: 4_096,
            enabled: true,
            validationState: .valid,
            providerConfiguration: ProviderConfiguration(
                providerID: .openAI,
                apiStyle: .openAICompatible,
                baseURL: URL(string: "https://example.com/v1"),
                apiKey: "test",
                modelID: "remote"
            )
        )
        let runner = StubRunner(output: "local answer")
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        try await engine.addModelDescriptorForTesting(remote)
        try await engine.addModelDescriptorForTesting(local)
        try await engine.updatePreferences { $0.defaultModelID = remoteID }
        let request = TaskRequest(
            task: .explain,
            inputText: "ignored",
            systemPromptOverride: "assistant system",
            userPromptOverride: "assistant question"
        )
        let result = try await engine.runLocalText(request: request, modelID: remoteID)
        try require(result.text == "local answer", "Assistant text should fall back to a local model when a remote model is requested.")
        let loadedModelID = await runner.loadedModelID()
        try require(loadedModelID == localID, "Assistant text must never load the configured remote provider.")
        do {
            _ = try await engine.runExactLocalText(request: request, modelID: remoteID)
            try require(false, "Exact assistant model execution must reject a remote model instead of falling back.")
        } catch let error as RunnerError {
            guard case .unsupportedConfiguration = error else { throw error }
        }
        do {
            _ = try AssistantModelFingerprint.fingerprint(for: remote)
            try require(false, "Remote providers must never acquire a desktop-assistant qualification fingerprint.")
        } catch let error as RunnerError {
            guard case .unsupportedConfiguration = error else { throw error }
        }
        var invalidLocal = local
        invalidLocal.id = UUID()
        invalidLocal.name = "Invalid Local"
        invalidLocal.validationState = .failed
        try await engine.addModelDescriptorForTesting(invalidLocal)
        do {
            _ = try await engine.runExactLocalText(request: request, modelID: invalidLocal.id)
            try require(false, "Exact assistant model execution must reject a failed local model even when its files exist.")
        } catch let error as RunnerError {
            guard case .unsupportedConfiguration = error else { throw error }
        }
        let exactResult = try await engine.runExactLocalText(request: request, modelID: localID)
        try require(exactResult.text == "result ignored", "Exact assistant execution should run the selected local model.")
        let reportedLoadedModelID = await engine.loadedLocalTextModelID()
        try require(reportedLoadedModelID == localID, "TaskEngine should report the currently loaded local text model for comment reuse.")
        try require(PromptTemplates.systemPrompt(for: request, preferences: .init()) == "assistant system", "Assistant system prompt override should reach every runner.")
        try require(PromptTemplates.userPrompt(for: request, preferences: .init()) == "assistant question", "Assistant user prompt override should reach every runner.")
        let history = await engine.recentHistory()
        try require(history.isEmpty, "Assistant inquiries must not enter ordinary task history.")
    }

    private static func checkDesktopAssistantPrivacyAndContextBuffer() async throws {
        let root = try makeTemporaryDirectory(name: "assistant-context")
        defer { try? FileManager.default.removeItem(at: root) }
        let keyURL = root.appendingPathComponent("assistant-fingerprint.key")
        let fingerprintStore = AssistantFingerprintStore(fileURL: keyURL)

        try await fingerprintStore.ensureKey()
        try require(FileManager.default.fileExists(atPath: keyURL.path), "Completing assistant onboarding must be able to create the fingerprint key before the first event.")

        let normalizedA = try await fingerprintStore.fingerprint(text: "line one\r\nline two")
        let normalizedB = try await fingerprintStore.fingerprint(text: "line one\nline two")
        try require(normalizedA == normalizedB, "Assistant fingerprints should normalize Unicode newlines without lowercasing content.")
        let caseChanged = try await fingerprintStore.fingerprint(text: "Line one\nline two")
        try require(caseChanged != normalizedA, "Assistant fingerprints must preserve letter case.")
        let beforeRotation = try await fingerprintStore.fingerprint(text: "assistant-key-verification")
        let rotated = try await fingerprintStore.rotate()
        try require(rotated != beforeRotation, "Fingerprint rotation must break linkage to values created with the old key.")
        let keyPermissions = try FileManager.default.attributesOfItem(atPath: keyURL.path)[.posixPermissions] as? NSNumber
        try require(keyPermissions?.intValue == 0o600, "Assistant fingerprint key must use 0600 permissions.")

        let policy = AssistantPrivacyPolicy(excludedApplicationBundleIDs: ["com.example.secret"])
        try require(policy.sensitivity(text: "ordinary note", bundleID: "COM.EXAMPLE.SECRET") == .excludedApplication, "Excluded apps must be rejected case-insensitively before event creation.")
        try require(
            DesktopAssistantPreferences().excludedApplicationBundleIDs.contains("com.apple.passwords"),
            "The system Passwords app must be excluded by default."
        )
        try require(policy.sensitivity(text: "api_key=sk-abcdefghijklmnop", bundleID: "com.example.editor") == .sensitive, "API keys must be treated as sensitive.")
        try require(policy.sensitivity(text: "ordinary note", bundleID: "com.example.editor") == .normal, "Normal text should remain available to authorized local processing.")
        try require(
            AssistantPrivacyPolicy.containsWebURL("Please review https://example.com/report before launch")
                && AssistantPrivacyPolicy.containsWebURL("See www.example.com/report for details")
                && !AssistantPrivacyPolicy.containsWebURL("ordinary local release notes"),
            "P-06 evidence must detect links embedded in prose without changing whole-value URL classification."
        )
        let cleanedTitle = policy.sanitizeWindowTitle("Draft /Users/alice/project/private.txt alice@example.com 123456789") ?? ""
        try require(!cleanedTitle.contains("alice") && !cleanedTitle.contains("123456789"), "Window-title cleaning must remove paths, email addresses, and long identifiers.")
        let cleanedSummary = policy.sanitizeEvidenceSummary("Build failed at /tmp/private.swift token=secret-value") ?? ""
        try require(!cleanedSummary.contains("private.swift") && !cleanedSummary.contains("secret-value"), "Evidence cleaning must remove paths and credentials.")

        let oversizedText = "front-marker " + String(repeating: "neutral context ", count: 1_000) + " tail-marker"
        let oversizedBuffer = AssistantContextBuffer()
        let oversizedEvent = await oversizedBuffer.append(
            AssistantActivityEvent(
                occurredAt: Date(timeIntervalSince1970: 1_000),
                type: .clipboardChanged,
                source: .clipboard,
                contentType: .text,
                contentFingerprint: "oversized-fingerprint"
            ),
            rawText: oversizedText,
            now: Date(timeIntervalSince1970: 1_000)
        )
        let oversizedSummary = oversizedEvent.sanitizedSummary ?? ""
        try require(
            oversizedEvent.ephemeralContextReference == nil
                && oversizedSummary.count <= 240
                && oversizedSummary.contains("front-marker")
                && oversizedSummary.contains("tail-marker"),
            "Text over 12,000 characters must retain only a bounded, sanitized front-and-back summary."
        )

        let buffer = AssistantContextBuffer()
        let base = Date(timeIntervalSince1970: 10_000)
        let first = AssistantActivityEvent(
            occurredAt: base,
            type: .clipboardChanged,
            source: .clipboard,
            appIdentity: "com.example.editor",
            contentType: .text,
            contentFingerprint: normalizedA
        )
        let storedFirst = await buffer.append(first, rawText: "first raw text", now: base)
        let firstRawText = await buffer.rawText(for: storedFirst.ephemeralContextReference, now: base)
        try require(firstRawText == "first raw text", "Authorized raw context should remain available during its 10-minute TTL.")
        let duplicate = AssistantActivityEvent(
            occurredAt: base.addingTimeInterval(1),
            type: .clipboardChanged,
            source: .clipboard,
            appIdentity: "com.example.editor",
            contentType: .text,
            contentFingerprint: normalizedA
        )
        let merged = await buffer.append(duplicate, rawText: "new raw text", now: base.addingTimeInterval(1))
        let refreshedRawText = await buffer.rawText(for: storedFirst.ephemeralContextReference, now: base.addingTimeInterval(1))
        try require(
            merged.occurrenceCount == 2
                && merged.ephemeralContextReference == storedFirst.ephemeralContextReference
                && refreshedRawText == "new raw text",
            "Duplicate evidence must keep a stable raw-context reference while refreshing its bounded in-memory value."
        )
        let mergedEvents = await buffer.snapshot(now: base.addingTimeInterval(1))
        try require(mergedEvents.count == 1, "Merged activity events should occupy one queue slot.")
        var delayedDuplicate = duplicate
        delayedDuplicate.occurredAt = base.addingTimeInterval(0.5)
        let delayedMerge = await buffer.append(
            delayedDuplicate,
            rawText: "stale delayed text",
            now: base.addingTimeInterval(1.5)
        )
        let rawTextAfterDelayedMerge = await buffer.rawText(
            for: storedFirst.ephemeralContextReference,
            now: base.addingTimeInterval(1.5)
        )
        try require(
            delayedMerge.occurredAt == base.addingTimeInterval(1)
                && rawTextAfterDelayedMerge == "new raw text",
            "A late observer callback must not overwrite newer evidence or move its real occurrence time backward."
        )
        let expiredRawText = await buffer.rawText(for: merged.ephemeralContextReference, now: base.addingTimeInterval(601))
        try require(expiredRawText == nil, "Raw context must expire after 10 minutes even while the activity counter remains.")

        let sensitive = AssistantActivityEvent(
            occurredAt: base.addingTimeInterval(700),
            type: .clipboardChanged,
            source: .clipboard,
            contentFingerprint: nil,
            sensitivity: .sensitive
        )
        let sensitiveStored = await buffer.append(sensitive, rawText: "password=secret", now: base.addingTimeInterval(700))
        try require(sensitiveStored.ephemeralContextReference == nil, "Sensitive content must never receive a raw-context reference.")

        for index in 0..<2_005 {
            let date = base.addingTimeInterval(800 + Double(index))
            _ = await buffer.append(
                AssistantActivityEvent(
                    occurredAt: date,
                    type: .selectionCaptured,
                    source: .selection,
                    contentFingerprint: "selection-\(index)"
                ),
                now: date
            )
        }
        let bounded = await buffer.snapshot(now: base.addingTimeInterval(2_805))
        try require(bounded.count == AssistantContextBuffer.maximumEventCount, "Activity memory must enforce its 2,000-event upper bound.")
        await buffer.clear(source: .selection)
        let afterSourceClear = await buffer.snapshot(now: base.addingTimeInterval(2_805))
        try require(afterSourceClear.allSatisfy { $0.source != .selection }, "Revoking one source must remove its unexpired context without affecting other sources.")
        await buffer.clear()
        let afterFullClear = await buffer.snapshot(now: base.addingTimeInterval(2_805))
        try require(afterFullClear.isEmpty, "Pause, privacy, disable, and exit must be able to clear all in-memory context.")

        let epochBuffer = AssistantContextBuffer()
        let staleEvent = AssistantActivityEvent(
            occurredAt: base,
            type: .clipboardChanged,
            source: .clipboard,
            contentFingerprint: "stale"
        )
        await epochBuffer.advanceEpochAndClear(to: 1)
        let staleAppend = await epochBuffer.appendIfCurrent(staleEvent, rawText: "must not return", expectedEpoch: 0, now: base)
        try require(staleAppend == nil, "A delayed observer task must not repopulate context after an epoch privacy barrier.")
        let staleDrop = await epochBuffer.appendIfCurrent(
            AssistantActivityEvent(occurredAt: base, type: .fileDropped, source: .droppedFile),
            expectedEpoch: 0,
            now: base
        )
        try require(staleDrop == nil, "A delayed drop task must not repopulate context after a lifecycle clear.")
        let currentAppend = await epochBuffer.appendIfCurrent(staleEvent, rawText: "current", expectedEpoch: 1, now: base)
        try require(currentAppend != nil, "Current-epoch observer work should still append normally.")
        let selectionEvent = AssistantActivityEvent(
            occurredAt: base,
            type: .selectionCaptured,
            source: .selection,
            contentFingerprint: "selection"
        )
        _ = await epochBuffer.appendIfCurrent(selectionEvent, rawText: "selection raw", expectedEpoch: 1, now: base)
        await epochBuffer.advanceEpochAndClear(to: 3, source: .clipboard)
        await epochBuffer.advanceEpochAndClear(to: 2, source: .selection)
        let afterOutOfOrderClear = await epochBuffer.snapshot(now: base)
        try require(
            afterOutOfOrderClear.isEmpty,
            "Out-of-order privacy barriers must still execute every requested source clear."
        )
        let appBuffer = AssistantContextBuffer()
        _ = await appBuffer.append(
            AssistantActivityEvent(
                occurredAt: base,
                type: .clipboardChanged,
                source: .clipboard,
                appIdentity: "Com.Example.Secret",
                contentType: .text
            ),
            rawText: "private source text",
            now: base
        )
        await appBuffer.clear(appIdentity: "com.example.secret")
        let appContextAfterClear = await appBuffer.snapshot(now: base)
        try require(
            appContextAfterClear.isEmpty,
            "Excluded-app context clearing must compare normalized bundle IDs case-insensitively."
        )
    }

    private static func checkDesktopAssistantBehaviorStore() async throws {
        let root = try makeTemporaryDirectory(name: "assistant-behavior")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("assistant-behavior.json")
        let keyURL = root.appendingPathComponent("assistant-fingerprint.key")
        let fingerprintStore = AssistantFingerprintStore(fileURL: keyURL)
        let store = AssistantBehaviorStore(fileURL: fileURL, fingerprintStore: fingerprintStore)
        let now = Date(timeIntervalSince1970: 50_000)

        let empty = await store.load(now: now)
        try require(empty.records.isEmpty && !FileManager.default.fileExists(atPath: fileURL.path), "Loading before onboarding must not create a behavior file.")
        let oldFingerprint = try await fingerprintStore.fingerprint(text: "same content")
        let normalID = UUID()
        let saved = await store.append(
            AssistantBehaviorRecord(
                id: normalID,
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.selection, .llmToolsTask],
                appIdentity: "com.example.editor",
                appCategory: "development",
                evidenceFeatures: ["count": 3, "durationSeconds": 120],
                sanitizedEvidenceSummary: "Build failed at /tmp/private.swift token=secret-value",
                contentFingerprint: oldFingerprint,
                assistantDecision: .badge,
                presentationResult: .badged
            ),
            now: now
        )
        try require(saved, "A normal behavior record should save atomically.")
        let related = await store.records(
            pattern: .repeatedFailure,
            source: .llmToolsTask,
            appCategory: "development",
            now: now
        )
        try require(related.map(\.id) == [normalID], "Behavior lookup must filter related history by pattern, source, and app category.")
        let unrelated = await store.records(
            pattern: .repeatedFailure,
            source: .clipboard,
            appCategory: "development",
            now: now
        )
        try require(unrelated.isEmpty, "Behavior lookup must not feed unrelated source history to the judgment model.")
        let aggregateBeforeSourceClear = await store.aggregate(for: .repeatedFailure)
        let sourceHistoryCleared = await store.clearDetailedRecords(source: .selection, now: now)
        let taskRecordsAfterClear = await store.records(source: .llmToolsTask, now: now)
        let aggregateAfterSourceClear = await store.aggregate(for: .repeatedFailure)
        try require(sourceHistoryCleared, "Source history clear should save atomically.")
        try require(
            taskRecordsAfterClear.isEmpty,
            "Clearing one source must remove its detailed behavior records."
        )
        try require(
            aggregateAfterSourceClear == aggregateBeforeSourceClear,
            "Source history clear must retain long-term aggregate learning."
        )
        _ = await store.append(
            AssistantBehaviorRecord(
                occurredAt: now,
                patternType: .foreignClipboard,
                sourceTypes: [.clipboard],
                appIdentity: "com.example.reader",
                appCategory: "browser",
                assistantDecision: .silent,
                presentationResult: .suppressed
            ),
            now: now
        )
        _ = await store.clearDetailedRecords(source: .foregroundApplication, now: now)
        let appIdentityRecordsAfterClear = await store.records(source: .clipboard, now: now)
        try require(
            appIdentityRecordsAfterClear.isEmpty,
            "Clearing foreground-app history must remove records enriched with that app identity."
        )
        _ = await store.clearDetailedRecords(clearAggregatePreferences: true, now: now)
        _ = await store.append(
            AssistantBehaviorRecord(
                id: normalID,
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                assistantDecision: .badge,
                presentationResult: .badged
            ),
            now: now
        )
        let fileText = try String(contentsOf: fileURL, encoding: .utf8)
        try require(!fileText.contains("private.swift") && !fileText.contains("secret-value"), "Behavior JSON must not contain unsanitized evidence.")
        let filePermissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        try require(filePermissions?.intValue == 0o600 && directoryPermissions?.intValue == 0o700, "Assistant behavior storage must use 0700/0600 permissions.")
        _ = await store.append(
            AssistantBehaviorRecord(
                id: normalID,
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                assistantDecision: .badge,
                presentationResult: .badged
            ),
            now: now
        )
        let replacedSnapshot = await store.load(now: now)
        try require(
            replacedSnapshot.aggregatePreferences[.repeatedFailure]?.detectedCount == 1,
            "Replacing one behavior record must not double-count its aggregate."
        )

        let aggregateFileURL = root.appendingPathComponent("assistant-aggregate-retention.json")
        let aggregateStore = AssistantBehaviorStore(fileURL: aggregateFileURL, fingerprintStore: fingerprintStore)
        let retainedID = UUID()
        _ = await aggregateStore.append(
            AssistantBehaviorRecord(
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                assistantDecision: .badge,
                presentationResult: .badged
            ),
            now: now
        )
        _ = await aggregateStore.clearDetailedRecords(clearAggregatePreferences: false, now: now)
        _ = await aggregateStore.append(
            AssistantBehaviorRecord(
                id: retainedID,
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                assistantDecision: .peek,
                presentationResult: .presented
            ),
            now: now
        )
        _ = await aggregateStore.update(id: retainedID, feedback: .irrelevant, now: now)
        _ = await aggregateStore.update(id: retainedID, outcome: .acted, now: now)
        let actedAggregate = await aggregateStore.aggregate(for: .repeatedFailure)
        try require(
            actedAggregate.presentedCount == 1 && actedAggregate.actedCount == 1,
            "A proactively presented record must retain its exposure after an action."
        )
        _ = await aggregateStore.update(id: retainedID, outcome: .dismissed, now: now)
        let badgeViewedID = UUID()
        _ = await aggregateStore.append(
            AssistantBehaviorRecord(
                id: badgeViewedID,
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                assistantDecision: .badge,
                presentationResult: .badged
            ),
            now: now
        )
        _ = await aggregateStore.update(id: badgeViewedID, outcome: .viewed, now: now)
        let aggregateSnapshot = await aggregateStore.load(now: now)
        try require(
            aggregateSnapshot.aggregatePreferences[.repeatedFailure]?.detectedCount == 3
                && aggregateSnapshot.aggregatePreferences[.repeatedFailure]?.presentedCount == 1
                && aggregateSnapshot.aggregatePreferences[.repeatedFailure]?.actedCount == 0
                && aggregateSnapshot.aggregatePreferences[.repeatedFailure]?.irrelevantCount == 1,
            "Exposure must follow the original peek decision; later dismissal and badge viewing must not rewrite it."
        )

        let sensitiveID = UUID()
        _ = await store.append(
            AssistantBehaviorRecord(
                id: sensitiveID,
                occurredAt: now.addingTimeInterval(1),
                patternType: .foreignClipboard,
                sourceTypes: [.clipboard],
                appIdentity: "com.example.editor",
                appCategory: "productivity",
                evidenceFeatures: ["count": 3],
                sanitizedEvidenceSummary: "private text",
                contentFingerprint: oldFingerprint,
                sensitivity: .sensitive,
                assistantDecision: .peek,
                judgmentModelID: UUID(),
                judgmentConfidence: 1,
                presentationResult: .presented
            ),
            now: now.addingTimeInterval(1)
        )
        let sensitiveRecord = await store.records(limit: 5, now: now.addingTimeInterval(1)).first { $0.id == sensitiveID }
        try require(
            sensitiveRecord?.patternType == nil
                && sensitiveRecord?.sourceTypes.isEmpty == true
                && sensitiveRecord?.appIdentity == nil
                && sensitiveRecord?.sanitizedEvidenceSummary == nil
                && sensitiveRecord?.contentFingerprint == nil
                && sensitiveRecord?.suppressionReason == .sensitiveContent,
            "Sensitive behavior persistence must contain only the suppression state and timestamp."
        )
        let excludedSaved = await store.append(
            AssistantBehaviorRecord(
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.selection],
                sensitivity: .excludedApplication,
                assistantDecision: .silent,
                presentationResult: .suppressed
            ),
            now: now
        )
        try require(!excludedSaved, "Completely excluded applications must not create behavior records.")

        _ = await store.append(
            AssistantBehaviorRecord(
                occurredAt: now.addingTimeInterval(-AssistantBehaviorStore.retentionInterval - 1),
                patternType: .repeatedFailure,
                sourceTypes: [.selection],
                assistantDecision: .silent,
                presentationResult: .suppressed
            ),
            now: now
        )
        let retainedSummary = await store.summary(now: now)
        try require(retainedSummary.recordCount == 2, "Behavior records older than 30 days must be removed before saving.")

        let reloadedStore = AssistantBehaviorStore(fileURL: fileURL, fingerprintStore: fingerprintStore)
        let reloaded = await reloadedStore.load(now: now.addingTimeInterval(2))
        try require(reloaded.records.count == 2, "The behavior snapshot should round-trip through its independent JSON file.")

        var staleSnapshot = reloaded
        staleSnapshot.records.append(AssistantBehaviorRecord(
            occurredAt: now.addingTimeInterval(-AssistantBehaviorStore.retentionInterval - 10),
            patternType: .repeatedFailure,
            sourceTypes: [.selection],
            assistantDecision: .silent,
            presentationResult: .suppressed
        ))
        let staleEncoder = JSONEncoder()
        staleEncoder.dateEncodingStrategy = .iso8601
        try staleEncoder.encode(staleSnapshot).write(to: fileURL, options: .atomic)
        let pruningStore = AssistantBehaviorStore(fileURL: fileURL, fingerprintStore: fingerprintStore)
        _ = await pruningStore.load(now: now)
        let staleDecoder = JSONDecoder()
        staleDecoder.dateDecodingStrategy = .iso8601
        let prunedDiskSnapshot = try staleDecoder.decode(AssistantBehaviorSnapshot.self, from: Data(contentsOf: fileURL))
        try require(
            prunedDiskSnapshot.records.allSatisfy { $0.occurredAt >= now.addingTimeInterval(-AssistantBehaviorStore.retentionInterval) },
            "Startup retention pruning must be written back to the private behavior file."
        )

        let liveRetentionURL = root.appendingPathComponent("assistant-live-retention.json")
        let liveRetentionStore = AssistantBehaviorStore(fileURL: liveRetentionURL, fingerprintStore: fingerprintStore)
        _ = await liveRetentionStore.append(
            AssistantBehaviorRecord(
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.selection],
                assistantDecision: .silent,
                presentationResult: .suppressed
            ),
            now: now
        )
        let expiredSummary = await liveRetentionStore.summary(
            now: now.addingTimeInterval(AssistantBehaviorStore.retentionInterval + 1)
        )
        let liveRetentionDisk = try staleDecoder.decode(
            AssistantBehaviorSnapshot.self,
            from: Data(contentsOf: liveRetentionURL)
        )
        try require(
            expiredSummary.recordCount == 0 && liveRetentionDisk.records.isEmpty,
            "A continuously running app must remove 30-day details from both summary and disk."
        )

        let limitEncoder = JSONEncoder()
        limitEncoder.dateEncodingStrategy = .iso8601
        limitEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let countLimitURL = root.appendingPathComponent("assistant-count-limit.json")
        let countRecords = (0...AssistantBehaviorStore.maximumRecordCount).map { index in
            AssistantBehaviorRecord(
                occurredAt: now.addingTimeInterval(Double(index)),
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                evidenceFeatures: ["index": Double(index)],
                assistantDecision: .silent,
                presentationResult: .suppressed
            )
        }
        try limitEncoder.encode(AssistantBehaviorSnapshot(records: countRecords, updatedAt: now))
            .write(to: countLimitURL, options: .atomic)
        let countLimitStore = AssistantBehaviorStore(fileURL: countLimitURL, fingerprintStore: fingerprintStore)
        let countLimitedSnapshot = await countLimitStore.load(
            now: now.addingTimeInterval(Double(AssistantBehaviorStore.maximumRecordCount + 1))
        )
        try require(
            countLimitedSnapshot.records.count == AssistantBehaviorStore.maximumRecordCount
                && countLimitedSnapshot.records.first?.evidenceFeatures["index"] == 1
                && countLimitedSnapshot.records.last?.evidenceFeatures["index"] == Double(AssistantBehaviorStore.maximumRecordCount),
            "Behavior loading must keep exactly the newest 5,000 valid records."
        )

        let byteLimitURL = root.appendingPathComponent("assistant-byte-limit.json")
        let denseFeatures = Dictionary(uniqueKeysWithValues: (0..<16).map { index in
            ("feature-\(index)-" + String(repeating: "x", count: 48), Double(index))
        })
        let denseRecords = (0..<AssistantBehaviorStore.maximumRecordCount).map { index in
            AssistantBehaviorRecord(
                occurredAt: now.addingTimeInterval(Double(index)),
                patternType: .foreignClipboard,
                sourceTypes: [.clipboard],
                appIdentity: "com.example.dense-record",
                appCategory: String(repeating: "c", count: 64),
                evidenceFeatures: denseFeatures,
                sanitizedEvidenceSummary: String(repeating: "s", count: 240),
                contentFingerprint: String(repeating: "f", count: 64),
                assistantDecision: .silent,
                judgmentModelID: UUID(),
                judgmentConfidence: 0.75,
                presentationResult: .suppressed
            )
        }
        let oversizedSnapshotData = try limitEncoder.encode(
            AssistantBehaviorSnapshot(records: denseRecords, updatedAt: now)
        )
        try require(
            oversizedSnapshotData.count > AssistantBehaviorStore.maximumByteCount,
            "The byte-limit fixture must exceed 10MB before loading."
        )
        try oversizedSnapshotData.write(to: byteLimitURL, options: .atomic)
        let byteLimitStore = AssistantBehaviorStore(fileURL: byteLimitURL, fingerprintStore: fingerprintStore)
        _ = await byteLimitStore.load(
            now: now.addingTimeInterval(Double(AssistantBehaviorStore.maximumRecordCount))
        )
        let byteLimitedData = try Data(contentsOf: byteLimitURL)
        try require(
            byteLimitedData.count <= AssistantBehaviorStore.maximumByteCount,
            "Behavior loading must rewrite an oversized valid snapshot to at most 10MB."
        )

        let futureData = Data(#"{"schemaVersion":99,"records":[],"aggregatePreferences":{},"updatedAt":"2026-01-01T00:00:00Z"}"#.utf8)
        try futureData.write(to: fileURL, options: .atomic)
        let futureStore = AssistantBehaviorStore(fileURL: fileURL, fingerprintStore: fingerprintStore)
        _ = await futureStore.load(now: now)
        let futureSummary = await futureStore.summary()
        try require(futureSummary.status == .futureSchemaReadOnly && futureSummary.schemaVersion == 99, "A future behavior schema must enter read-only mode with the real version visible.")
        let futureAppend = await futureStore.append(
            AssistantBehaviorRecord(
                patternType: .repeatedFailure,
                sourceTypes: [.selection],
                assistantDecision: .silent,
                presentationResult: .suppressed
            ),
            now: now
        )
        let futureDataAfterAppend = try Data(contentsOf: fileURL)
        try require(!futureAppend && futureDataAfterAppend == futureData, "An older app must never overwrite a newer behavior schema.")

        try Data("not-json-one".utf8).write(to: fileURL, options: .atomic)
        let corruptStore = AssistantBehaviorStore(fileURL: fileURL, fingerprintStore: fingerprintStore)
        _ = await corruptStore.load(now: now)
        try Data("not-json-two".utf8).write(to: fileURL, options: .atomic)
        _ = await corruptStore.load(now: now)
        let quarantinePrefix = "\(fileURL.lastPathComponent).corrupt-"
        let quarantines = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(quarantinePrefix) }
        try require(quarantines.count == 1, "Repeated corruption recovery must keep only the latest quarantine file.")
        let quarantinePermissions = try FileManager.default.attributesOfItem(atPath: quarantines[0].path)[.posixPermissions] as? NSNumber
        try require(quarantinePermissions?.intValue == 0o600, "Corrupt behavior quarantine must remain private.")

        let deleted = await corruptStore.deleteAllFilesAndRotateKey(now: now)
        try require(deleted, "Clearing all behavior data should report success only after file deletion and key rotation.")
        let newFingerprint = try await fingerprintStore.fingerprint(text: "same content")
        try require(newFingerprint != oldFingerprint, "Clearing all behavior data must rotate the HMAC key.")
        let remainingFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        try require(
            !remainingFiles.contains { $0.lastPathComponent == fileURL.lastPathComponent || $0.lastPathComponent.hasPrefix(quarantinePrefix) },
            "Clearing all behavior data must remove the main and quarantine files."
        )
        let raceID = UUID()
        _ = await corruptStore.append(
            AssistantBehaviorRecord(
                id: raceID,
                occurredAt: now,
                patternType: .repeatedFailure,
                sourceTypes: [.llmToolsTask],
                assistantDecision: .peek,
                presentationResult: .presented
            ),
            now: now
        )
        let racingDelete = Task { await corruptStore.deleteAllFilesAndRotateKey(now: now.addingTimeInterval(1)) }
        let racingUpdates = Task {
            for _ in 0..<100 {
                _ = await corruptStore.update(id: raceID, outcome: .acted, now: now.addingTimeInterval(1))
            }
        }
        let racingDeleteSucceeded = await racingDelete.value
        await racingUpdates.value
        let postDeleteStore = AssistantBehaviorStore(fileURL: fileURL, fingerprintStore: fingerprintStore)
        let postDeleteSnapshot = await postDeleteStore.load(now: now.addingTimeInterval(2))
        try require(
            racingDeleteSucceeded && postDeleteSnapshot.records.isEmpty,
            "Concurrent updates must not resurrect records while all behavior data is being deleted."
        )
        let failingStore = AssistantBehaviorStore(
            fileURL: URL(fileURLWithPath: "/dev/null/assistant-behavior.json"),
            fingerprintStore: AssistantFingerprintStore(fileURL: URL(fileURLWithPath: "/dev/null/assistant-fingerprint.key"))
        )
        let failedDelete = await failingStore.deleteAllFilesAndRotateKey(now: now)
        let failedSummary = await failingStore.summary()
        try require(!failedDelete && failedSummary.status == .saveFailed, "A failed data/key deletion must not be reported as ready.")
        let failedDetailedClear = await failingStore.clearDetailedRecords(clearAggregatePreferences: false, now: now)
        let failedDetailedSummary = await failingStore.summary()
        try require(
            !failedDetailedClear && failedDetailedSummary.status == .saveFailed,
            "A failed detailed-record clear must not be reported as successful."
        )

        let failedRotationStore = AssistantBehaviorStore(
            fileURL: root.appendingPathComponent("rotation-failure.json"),
            fingerprintStore: AssistantFingerprintStore(fileURL: URL(fileURLWithPath: "/dev/null/assistant-fingerprint.key"))
        )
        let failedRotationClear = await failedRotationStore.clearDetailedRecords(clearAggregatePreferences: true, now: now)
        let failedRotationSummary = await failedRotationStore.summary()
        try require(
            !failedRotationClear && failedRotationSummary.status == .saveFailed,
            "A failed fingerprint-key rotation must remain visible after detailed records are saved."
        )

        let unlistableRoot = root.appendingPathComponent("unlistable")
        try FileManager.default.createDirectory(at: unlistableRoot, withIntermediateDirectories: false)
        let unlistableURL = unlistableRoot.appendingPathComponent("assistant-behavior.json")
        let unlistableQuarantine = unlistableRoot.appendingPathComponent("assistant-behavior.json.corrupt-fixture")
        FileManager.default.createFile(atPath: unlistableQuarantine.path, contents: Data("private".utf8))
        let unlistableStore = AssistantBehaviorStore(
            fileURL: unlistableURL,
            fingerprintStore: AssistantFingerprintStore(fileURL: unlistableRoot.appendingPathComponent("assistant-fingerprint.key"))
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: unlistableRoot.path)
        let unlistableDelete = await unlistableStore.deleteAllFilesAndRotateKey(now: now)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unlistableRoot.path)
        try require(
            !unlistableDelete && FileManager.default.fileExists(atPath: unlistableQuarantine.path),
            "A quarantine enumeration failure must not be reported as successful deletion."
        )
    }

    private static func checkDesktopAssistantDropClassifier() throws {
        let root = try makeTemporaryDirectory(name: "assistant-drop")
        defer { try? FileManager.default.removeItem(at: root) }
        let textFile = root.appendingPathComponent("note.md")
        let imageFile = root.appendingPathComponent("image.png")
        let mediaFile = root.appendingPathComponent("clip.mp4")
        let unsupportedFile = root.appendingPathComponent("document.pdf")
        for file in [textFile, imageFile, mediaFile, unsupportedFile] {
            FileManager.default.createFile(atPath: file.path, contents: Data("fixture".utf8))
        }

        try require(AssistantDropClassifier.classify(text: "hello").kind == .text, "Plain text should enter text task selection.")
        let url = AssistantDropClassifier.classify(text: "https://example.com/path?q=1")
        try require(url.kind == .url && url.isSupported, "A standalone HTTP URL should expose only URL actions.")
        try require(AssistantDropClassifier.classify(fileURL: textFile).kind == .textFile, "TXT and Markdown files should use text task routing.")
        try require(AssistantDropClassifier.classify(fileURL: imageFile).kind == .image, "Image files should route to OCR.")
        try require(AssistantDropClassifier.classify(fileURL: mediaFile).kind == .media, "Audio and video files should route to media subtitles.")
        try require(!AssistantDropClassifier.classify(fileURL: unsupportedFile).isSupported, "PDF and other unsupported files must be rejected before release.")
        try require(!AssistantDropClassifier.classify(fileURL: root).isSupported, "Directories must be rejected before release.")
        try require(AssistantDropClassifier.multipleItems.kind == .multipleItems && !AssistantDropClassifier.multipleItems.isSupported, "Multiple or mixed pasteboard items must be rejected as a whole.")
        try require(
            AssistantClipboardClassifier.classify(typeIdentifiers: ["public.file-url", "public.utf8-plain-text"]) == .file,
            "A file URL with a string fallback must not be read as clipboard text."
        )
        try require(
            AssistantClipboardClassifier.classify(typeIdentifiers: ["public.rtf", "public.utf8-plain-text"]) == .richText,
            "Rich text with a string fallback must remain type-only context."
        )
        try require(
            AssistantClipboardClassifier.classify(typeIdentifiers: ["public.html", "public.utf8-plain-text"]) == .plainText,
            "Browser clipboard content with a standard plain-text representation must enter text observation."
        )
        try require(
            AssistantClipboardClassifier.classify(typeIdentifiers: ["public.html"]) == .richText,
            "HTML-only clipboard content must remain type-only context."
        )
        try require(
            AssistantClipboardClassifier.classify(typeIdentifiers: ["public.png", "public.utf8-plain-text"]) == .image,
            "Image payloads with a string fallback must remain type-only context."
        )
        try require(
            AssistantClipboardClassifier.classify(typeIdentifiers: ["public.utf8-plain-text"]) == .plainText,
            "A plain-text-only pasteboard item should be readable after authorization."
        )
    }

    private static func checkDesktopAssistantIntelligenceContracts() async throws {
        let detector = AssistantPatternDetector()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let fingerprint = "fixture-error-fingerprint"
        func failureEvent(offset: TimeInterval, source: AssistantSource) -> AssistantActivityEvent {
            AssistantActivityEvent(
                occurredAt: base.addingTimeInterval(offset),
                type: source == .llmToolsTask ? .taskFailed : .selectionCaptured,
                source: source,
                appIdentity: "com.example.editor",
                contentType: .text,
                contentFingerprint: fingerprint,
                ephemeralContextReference: UUID()
            )
        }
        let firstFailure = await detector.ingestFailure(failureEvent(offset: 0, source: .selection), now: base)
        try require(firstFailure == nil, "P-01 must not trigger on its first occurrence.")
        let secondFailure = await detector.ingestFailure(
            failureEvent(offset: 120, source: .llmToolsTask),
            now: base.addingTimeInterval(120)
        )
        try require(secondFailure == nil, "P-01 must not trigger before the third matching error.")
        let repeated = await detector.ingestFailure(
            failureEvent(offset: 300, source: .llmToolsTask),
            workbenchIsRecoverable: true,
            now: base.addingTimeInterval(300)
        )
        try require(repeated?.patternType == .repeatedFailure && repeated?.evidenceCount == 3, "P-01 must combine matching explicit sources within 10 minutes.")
        try require(
            repeated?.sourceTypes == [.llmToolsTask, .selection],
            "P-01 must retain every evidence source for explanation and source-history deletion."
        )
        try require(repeated?.evidenceContextReferences.count == 3, "P-01 must retain bounded ephemeral evidence references for semantic judgment.")
        try require(repeated?.appIdentity == "com.example.editor" && repeated?.appCategory == "other", "P-01 must carry only the allowed app identity and coarse category into related-history filtering.")
        try require(repeated?.actionIDs == [.explainError, .returnToWorkbench], "Recoverable llmTools failures should expose both frozen P-01 actions.")
        let mixedDetector = AssistantPatternDetector()
        let recoverableTask = failureEvent(offset: 0, source: .llmToolsTask)
        _ = await mixedDetector.ingestFailure(recoverableTask, workbenchIsRecoverable: true, now: base)
        _ = await mixedDetector.ingestFailure(failureEvent(offset: 1, source: .selection), now: base.addingTimeInterval(1))
        let mixedFailure = await mixedDetector.ingestFailure(
            failureEvent(offset: 2, source: .selection),
            now: base.addingTimeInterval(2)
        )
        try require(
            mixedFailure?.source == .selection
                && mixedFailure?.sourceTypes == [.llmToolsTask, .selection]
                && mixedFailure?.workbenchContextReference == recoverableTask.ephemeralContextReference
                && mixedFailure?.actionIDs == [.explainError, .returnToWorkbench]
                && mixedFailure?.isTaskFailure == true,
            "P-01 must retain a recoverable llmTools workbench route even when later matching evidence comes from selections."
        )
        let failureDuringReservation = await detector.ingestFailure(
            failureEvent(offset: 301, source: .llmToolsTask),
            now: base.addingTimeInterval(301)
        )
        try require(failureDuringReservation == nil, "P-01 must not emit the same candidate while its first decision is pending.")
        if let repeated { await detector.settle(repeated, delivered: false, now: base.addingTimeInterval(301)) }
        let failureAfterSuppression = await detector.ingestFailure(
            failureEvent(offset: 302, source: .llmToolsTask),
            now: base.addingTimeInterval(302)
        )
        try require(failureAfterSuppression != nil, "A suppressed P-01 candidate must become eligible again without burning its cooldown.")
        if let failureAfterSuppression {
            await detector.settle(failureAfterSuppression, delivered: true, now: base.addingTimeInterval(302))
        }
        let failureDuringCooldown = await detector.ingestFailure(
            failureEvent(offset: 303, source: .llmToolsTask),
            now: base.addingTimeInterval(303)
        )
        try require(failureDuringCooldown == nil, "A delivered P-01 candidate must enforce its 30-minute fingerprint cooldown.")
        try require(AssistantPatternRules.looksLikeError("Fatal error: port already in use"), "Explicit error text should pass P-01 prefiltering.")
        try require(!AssistantPatternRules.looksLikeError("A normal paragraph about today's project notes."), "Ordinary text must not enter P-01 detection.")

        let p03Detector = AssistantPatternDetector()
        func foreignEvent(_ id: String, offset: TimeInterval, confidence: Double = 0.95) -> AssistantActivityEvent {
            AssistantActivityEvent(
                occurredAt: base.addingTimeInterval(offset),
                type: .foreignTextDetected,
                source: .clipboard,
                appIdentity: "com.apple.Safari",
                contentType: .text,
                contentFingerprint: id,
                confidence: confidence,
                ephemeralContextReference: UUID()
            )
        }
        let firstForeign = await p03Detector.ingestForeignClipboard(
            foreignEvent("a", offset: 0),
            language: "en-US",
            effectiveCharacterCount: 30,
            now: base
        )
        try require(firstForeign == nil, "P-03 must wait for three distinct texts.")
        let duplicateForeign = await p03Detector.ingestForeignClipboard(
            foreignEvent("a", offset: 30),
            language: "en-US",
            effectiveCharacterCount: 30,
            now: base.addingTimeInterval(30)
        )
        try require(duplicateForeign == nil, "P-03 must not count a duplicate clipboard fingerprint twice.")
        _ = await p03Detector.ingestForeignClipboard(foreignEvent("b", offset: 60), language: "en", effectiveCharacterCount: 30, now: base.addingTimeInterval(60))
        let foreign = await p03Detector.ingestForeignClipboard(foreignEvent("c", offset: 90), language: "en", effectiveCharacterCount: 30, now: base.addingTimeInterval(90))
        try require(foreign?.patternType == .foreignClipboard && foreign?.evidenceCount == 3, "P-03 must trigger at three distinct same-language texts.")
        try require(foreign?.evidenceContextReferences.count == 3, "P-03 must give the value judge all three distinct ephemeral texts.")
        try require(foreign?.appCategory == "browser", "P-03 must retain the coarse app category for related-history filtering.")
        let foreignDuringReservation = await p03Detector.ingestForeignClipboard(
            foreignEvent("d", offset: 120),
            language: "en",
            effectiveCharacterCount: 30,
            now: base.addingTimeInterval(120)
        )
        try require(foreignDuringReservation == nil, "P-03 must not emit a duplicate while its first decision is pending.")
        if let foreign { await p03Detector.settle(foreign, delivered: false, now: base.addingTimeInterval(120)) }
        let foreignAfterSuppression = await p03Detector.ingestForeignClipboard(
            foreignEvent("e", offset: 121),
            language: "en",
            effectiveCharacterCount: 30,
            now: base.addingTimeInterval(121)
        )
        try require(foreignAfterSuppression != nil, "A suppressed P-03 candidate must be eligible again.")
        if let foreignAfterSuppression {
            await p03Detector.settle(foreignAfterSuppression, delivered: true, now: base.addingTimeInterval(121))
        }
        let foreignDuringCooldown = await p03Detector.ingestForeignClipboard(
            foreignEvent("f", offset: 122),
            language: "en",
            effectiveCharacterCount: 30,
            now: base.addingTimeInterval(122)
        )
        try require(foreignDuringCooldown == nil, "A delivered P-03 candidate must enforce its 60-minute language cooldown.")
        let lowConfidenceDetector = AssistantPatternDetector()
        let lowConfidence = await lowConfidenceDetector.ingestForeignClipboard(
            foreignEvent("low", offset: 0, confidence: 0.79),
            language: "fr",
            effectiveCharacterCount: 100,
            now: base
        )
        try require(lowConfidence == nil, "P-03 must reject language confidence below 0.80.")

        let isolatedFailureDetector = AssistantPatternDetector()
        _ = await isolatedFailureDetector.ingestFailure(failureEvent(offset: 0, source: .selection), now: base)
        _ = await isolatedFailureDetector.ingestFailure(failureEvent(offset: 1, source: .selection), now: base.addingTimeInterval(1))
        await isolatedFailureDetector.clear(pattern: .foreignClipboard)
        let failureAfterForeignClear = await isolatedFailureDetector.ingestFailure(
            failureEvent(offset: 2, source: .selection),
            now: base.addingTimeInterval(2)
        )
        try require(failureAfterForeignClear != nil, "Clearing P-03 state must preserve pending P-01 evidence.")

        let isolatedForeignDetector = AssistantPatternDetector()
        _ = await isolatedForeignDetector.ingestForeignClipboard(foreignEvent("isolation-a", offset: 0), language: "fr", effectiveCharacterCount: 30, now: base)
        _ = await isolatedForeignDetector.ingestForeignClipboard(foreignEvent("isolation-b", offset: 1), language: "fr", effectiveCharacterCount: 30, now: base.addingTimeInterval(1))
        await isolatedForeignDetector.clear(pattern: .repeatedFailure)
        let foreignAfterFailureClear = await isolatedForeignDetector.ingestForeignClipboard(
            foreignEvent("isolation-c", offset: 2),
            language: "fr",
            effectiveCharacterCount: 30,
            now: base.addingTimeInterval(2)
        )
        try require(foreignAfterFailureClear != nil, "Clearing P-01 state must preserve pending P-03 evidence.")

        let p06Detector = AssistantPatternDetector()
        func contextEvent(
            _ id: String,
            offset: TimeInterval,
            source: AssistantSource,
            appIdentity: String? = "com.example.editor",
            surfaceID: String? = "4242:7",
            surfaceRevision: UInt64 = 1,
            anchorGeneration: UInt64 = 1,
            provenance: AssistantEvidenceProvenance = .explicit,
            contentType: AssistantContentType? = nil,
            sceneSignal: String? = nil
        ) -> AssistantActivityEvent {
            let type: AssistantActivityType = switch source {
            case .clipboard: .clipboardChanged
            case .selection: .selectionCaptured
            case .windowContext: .windowContextChanged
            default: .applicationActivated
            }
            return AssistantActivityEvent(
                occurredAt: base.addingTimeInterval(offset),
                type: type,
                source: source,
                appIdentity: appIdentity,
                contentType: contentType ?? (source == .windowContext ? .metadata : .text),
                contentFingerprint: id,
                surfaceID: surfaceID,
                surfaceRevision: surfaceRevision,
                anchorGeneration: anchorGeneration,
                provenance: provenance,
                sceneSignal: sceneSignal,
                ephemeralContextReference: source == .foregroundApplication ? nil : UUID()
            )
        }
        var opportunityBatch = AssistantContextOpportunityBatch()
        let observedBatchTrigger = contextEvent(
            "batch-visual",
            offset: 0,
            source: .windowContext,
            provenance: .observed,
            contentType: .image,
            sceneSignal: "success"
        )
        let explicitBatchTrigger = contextEvent("batch-selection", offset: 0.2, source: .selection)
        _ = opportunityBatch.insert(observedBatchTrigger)
        let selectedBatchTrigger = opportunityBatch.insert(explicitBatchTrigger)
        let otherSurfaceTrigger = contextEvent(
            "batch-other-window",
            offset: 0.3,
            source: .clipboard,
            surfaceID: "5252:8",
            anchorGeneration: 2
        )
        _ = opportunityBatch.insert(otherSurfaceTrigger)
        let drainedBatch = opportunityBatch.drain()
        try require(
            selectedBatchTrigger.id == explicitBatchTrigger.id
                && drainedBatch.count == 2
                && Set(drainedBatch.map(\.id)) == Set([explicitBatchTrigger.id, otherSurfaceTrigger.id])
                && opportunityBatch.count == 0,
            "Concurrent context triggers must merge only within one operation bucket and preserve independent surfaces."
        )
        let acceptedForegroundMetadata = await p06Detector.ingestContextOpportunity(
            contextEvent("metadata", offset: 0, source: .foregroundApplication),
            now: base
        )
        try require(!acceptedForegroundMetadata, "P-06 must never trigger from foreground-application metadata alone.")
        let titleSupport = contextEvent(
            "window-title",
            offset: 0,
            source: .windowContext,
            provenance: .observed
        )
        let acceptedWindowContext = await p06Detector.ingestContextOpportunity(titleSupport, now: base)
        let clipboardTrigger = contextEvent("clipboard", offset: 0.2, source: .clipboard)
        let acceptedClipboardContext = await p06Detector.ingestContextOpportunity(
            clipboardTrigger,
            now: base.addingTimeInterval(0.2)
        )
        try require(
            acceptedClipboardContext && !acceptedWindowContext,
            "Explicit clipboard or selection evidence may trigger P-06; a window title is support only."
        )
        let contextualOpportunity = await p06Detector.flushContextOpportunity(
            trigger: clipboardTrigger,
            now: base.addingTimeInterval(1)
        )
        try require(
            contextualOpportunity?.patternType == .contextualOpportunity
                && contextualOpportunity?.evidenceCount == 2
                && contextualOpportunity?.sourceTypes == [.clipboard, .windowContext]
                && contextualOpportunity?.actionIDs == [.openQuickAction]
                && contextualOpportunity?.availableTaskKinds == TaskKind.interactiveCases.sorted { $0.rawValue < $1.rawValue }
                && contextualOpportunity?.surfaceID == "4242:7",
            "P-06 must fuse support by surface identity and keep actions owned by the explicit trigger."
        )
        try require(
            AssistantPatternType.contextualOpportunity.conservativeFallbackPresentation == .silent
                && AssistantPatternType.repeatedFailure.conservativeFallbackPresentation == .badge
                && AssistantPatternType.foreignClipboard.conservativeFallbackPresentation == .badge,
            "P-06 must stay silent when local semantic judgment is unavailable or invalid."
        )
        let emptyWindowDetector = AssistantPatternDetector()
        let emptyWindowResult = await emptyWindowDetector.flushContextOpportunityResult(now: base)
        try require(
            { if case .noEvidence = emptyWindowResult { return true }; return false }(),
            "P-06 diagnostics must distinguish a missing decision trigger."
        )

        let visualDetector = AssistantPatternDetector()
        let neutralVisual = contextEvent(
            "neutral-visual",
            offset: 0,
            source: .windowContext,
            provenance: .observed,
            contentType: .image,
            sceneSignal: "none"
        )
        let salientVisual = contextEvent(
            "success-visual",
            offset: 1,
            source: .windowContext,
            provenance: .observed,
            contentType: .image,
            sceneSignal: "success"
        )
        let neutralVisualTriggers = await visualDetector.ingestContextOpportunity(neutralVisual, now: base)
        let salientVisualTriggers = await visualDetector.ingestContextOpportunity(
            salientVisual,
            now: base.addingTimeInterval(1)
        )
        let visualOpportunity = await visualDetector.flushContextOpportunity(
            trigger: salientVisual,
            now: base.addingTimeInterval(1.8)
        )
        try require(
            !neutralVisualTriggers
                && salientVisualTriggers
                && visualOpportunity?.sceneSignal == "success"
                && visualOpportunity?.actionIDs.isEmpty == true
                && visualOpportunity?.availableTaskKinds.isEmpty == true,
            "Only a salient visual signal may trigger an actionless observation; neutral screenshots remain support only."
        )

        let activeVisualDetector = AssistantPatternDetector()
        let activeNeutralTriggers = await activeVisualDetector.ingestContextOpportunity(
            neutralVisual,
            activeCompanionMode: true,
            now: base
        )
        let activeNeutralIsThrottled = await activeVisualDetector.ingestContextOpportunity(
            contextEvent(
                "neutral-visual-again",
                offset: 1,
                source: .windowContext,
                provenance: .observed,
                contentType: .image,
                sceneSignal: "none"
            ),
            activeCompanionMode: true,
            now: base.addingTimeInterval(1)
        )
        let activeNeutralRetriesAfterInterval = await activeVisualDetector.ingestContextOpportunity(
            contextEvent(
                "neutral-visual-later",
                offset: AssistantPatternDetector.activeCompanionInterval,
                source: .windowContext,
                provenance: .observed,
                contentType: .image,
                sceneSignal: "none"
            ),
            activeCompanionMode: true,
            now: base.addingTimeInterval(AssistantPatternDetector.activeCompanionInterval)
        )
        try require(
            activeNeutralTriggers && !activeNeutralIsThrottled && activeNeutralRetriesAfterInterval,
            "Active mode must evaluate a routine visual opportunity at most once every five minutes."
        )

        let p06CooldownDetector = AssistantPatternDetector()
        let initialTrigger = contextEvent("stable", offset: 0, source: .clipboard)
        _ = await p06CooldownDetector.ingestContextOpportunity(initialTrigger, now: base)
        let initialCooldownCandidate = await p06CooldownDetector.flushContextOpportunity(trigger: initialTrigger, now: base)
        try require(
            initialCooldownCandidate != nil,
            "Expected an initial P-06 candidate before testing transactional cooldown."
        )
        let reservedTrigger = contextEvent("another-value", offset: 1, source: .selection)
        _ = await p06CooldownDetector.ingestContextOpportunity(reservedTrigger, now: base.addingTimeInterval(1))
        let reservedResult = await p06CooldownDetector.flushContextOpportunityResult(
            trigger: reservedTrigger,
            now: base.addingTimeInterval(1)
        )
        try require(
            { if case .duplicateCooldown = reservedResult { return true }; return false }(),
            "Different evidence from the same surface anchor must share one reserved P-06 decision."
        )
        if let initialCooldownCandidate {
            await p06CooldownDetector.settle(initialCooldownCandidate, delivered: false, now: base.addingTimeInterval(1))
        }
        let retryTrigger = contextEvent("stable", offset: 2, source: .clipboard)
        _ = await p06CooldownDetector.ingestContextOpportunity(retryTrigger, now: base.addingTimeInterval(2))
        let retryCandidate = await p06CooldownDetector.flushContextOpportunity(
            trigger: retryTrigger,
            now: base.addingTimeInterval(2)
        )
        try require(retryCandidate != nil, "A suppressed P-06 decision must be immediately eligible again.")
        if let retryCandidate {
            await p06CooldownDetector.settle(retryCandidate, delivered: true, now: base.addingTimeInterval(2))
        }
        await p06CooldownDetector.clearContextOpportunitySamples()
        let cooldownTrigger = contextEvent(
            "stable",
            offset: 3,
            source: .clipboard,
            anchorGeneration: 3
        )
        _ = await p06CooldownDetector.ingestContextOpportunity(cooldownTrigger, now: base.addingTimeInterval(3))
        let deliveredCooldownResult = await p06CooldownDetector.flushContextOpportunityResult(
            trigger: cooldownTrigger,
            now: base.addingTimeInterval(3)
        )
        try require(
            { if case .duplicateCooldown = deliveredCooldownResult { return true }; return false }(),
            "Only a delivered P-06 decision starts the ten-minute cooldown, which survives sample clearing."
        )
        let differentTrigger = contextEvent(
            "different",
            offset: 4,
            source: .selection,
            anchorGeneration: 2
        )
        _ = await p06CooldownDetector.ingestContextOpportunity(differentTrigger, now: base.addingTimeInterval(4))
        let differentContext = await p06CooldownDetector.flushContextOpportunity(
            trigger: differentTrigger,
            now: base.addingTimeInterval(4)
        )
        try require(differentContext != nil, "A different decision key must remain eligible during another context's cooldown.")
        let afterCooldownTrigger = contextEvent(
            "stable",
            offset: 602,
            source: .clipboard,
            anchorGeneration: 4
        )
        _ = await p06CooldownDetector.ingestContextOpportunity(afterCooldownTrigger, now: base.addingTimeInterval(602))
        let contextualAfterCooldown = await p06CooldownDetector.flushContextOpportunity(
            trigger: afterCooldownTrigger,
            now: base.addingTimeInterval(602)
        )
        try require(contextualAfterCooldown != nil, "P-06 must become eligible at the delivered cooldown boundary.")

        let p06IdentityDetector = AssistantPatternDetector()
        let oldRevisionTitle = contextEvent(
            "old-revision",
            offset: 0,
            source: .windowContext,
            surfaceRevision: 1,
            provenance: .observed
        )
        _ = await p06IdentityDetector.ingestContextOpportunity(oldRevisionTitle, now: base)
        let newRevisionTrigger = contextEvent(
            "new-revision",
            offset: 5,
            source: .selection,
            surfaceRevision: 2,
            anchorGeneration: 2
        )
        _ = await p06IdentityDetector.ingestContextOpportunity(newRevisionTrigger, now: base.addingTimeInterval(5))
        let boundedContext = await p06IdentityDetector.flushContextOpportunity(
            trigger: newRevisionTrigger,
            now: base.addingTimeInterval(5.8)
        )
        try require(
            boundedContext?.evidenceCount == 1 && boundedContext?.source == .selection,
            "A new surface revision must not absorb a stale title from the previous page state."
        )

        let clipboardBridgeDetector = AssistantPatternDetector()
        let bridgeClipboard = contextEvent(
            "bridge-copy",
            offset: 0,
            source: .clipboard,
            surfaceID: "111:1"
        )
        _ = await clipboardBridgeDetector.ingestContextOpportunity(
            bridgeClipboard,
            now: base
        )
        let pasteDestinationTrigger = contextEvent(
            "destination-selection",
            offset: 20,
            source: .selection,
            surfaceID: "222:2"
        )
        _ = await clipboardBridgeDetector.ingestContextOpportunity(
            pasteDestinationTrigger,
            now: base.addingTimeInterval(20)
        )
        let bridgedContext = await clipboardBridgeDetector.flushContextOpportunity(
            trigger: pasteDestinationTrigger,
            now: base.addingTimeInterval(20.8)
        )
        try require(
            bridgedContext?.evidenceCount == 2
                && bridgedContext?.sourceTypes == [.clipboard, .selection]
                && bridgedContext?.surfaceID == "222:2",
            "A recent explicit clipboard copy may bridge one app switch while the destination remains the decision owner."
        )
        if let bridgedContext {
            await clipboardBridgeDetector.settle(bridgedContext, delivered: true, now: base.addingTimeInterval(21))
        }
        let laterDestinationTrigger = contextEvent(
            "later-destination",
            offset: 25,
            source: .selection,
            surfaceID: "333:3",
            anchorGeneration: 3
        )
        _ = await clipboardBridgeDetector.ingestContextOpportunity(
            laterDestinationTrigger,
            now: base.addingTimeInterval(25)
        )
        let contextAfterBridgeConsumption = await clipboardBridgeDetector.flushContextOpportunity(
            trigger: laterDestinationTrigger,
            now: base.addingTimeInterval(25.8)
        )
        try require(
            contextAfterBridgeConsumption?.evidenceCount == 1,
            "Explicit clipboard evidence must be consumed after one delivered cross-app context instead of bridging repeatedly."
        )

        let latestVisualDetector = AssistantPatternDetector()
        let oldVisual = contextEvent(
            "old-visual",
            offset: 0,
            source: .windowContext,
            provenance: .observed,
            contentType: .image,
            sceneSignal: "blocked"
        )
        let currentVisual = contextEvent(
            "current-visual",
            offset: 1,
            source: .windowContext,
            provenance: .observed,
            contentType: .image,
            sceneSignal: "none"
        )
        let currentSelection = contextEvent("current-selection", offset: 1.2, source: .selection)
        _ = await latestVisualDetector.ingestContextOpportunity(oldVisual, now: base)
        _ = await latestVisualDetector.ingestContextOpportunity(currentVisual, now: base.addingTimeInterval(1))
        _ = await latestVisualDetector.ingestContextOpportunity(currentSelection, now: base.addingTimeInterval(1.2))
        let latestVisualContext = await latestVisualDetector.flushContextOpportunity(
            trigger: currentSelection,
            now: base.addingTimeInterval(2)
        )
        try require(
            latestVisualContext?.evidenceCount == 2,
            "Only the latest visual state from one surface operation may support the current explicit trigger."
        )

        let p06WindowOnlyDetector = AssistantPatternDetector()
        let windowOnlyTitle = contextEvent(
            "window-title-only",
            offset: 0,
            source: .windowContext,
            provenance: .observed
        )
        let windowOnlyTrigger = await p06WindowOnlyDetector.ingestContextOpportunity(
            windowOnlyTitle,
            now: base
        )
        try require(
            !windowOnlyTrigger,
            "A sanitized window-title change is supporting evidence and must never create a message on its own."
        )

        var queue = AssistantCandidateQueue()
        func candidate(_ pattern: AssistantPatternType, offset: TimeInterval, source: AssistantSource) -> AssistantPatternCandidate {
            AssistantPatternCandidate(
                createdAt: base.addingTimeInterval(offset),
                expiresAt: base.addingTimeInterval(600),
                patternType: pattern,
                source: source,
                evidenceSummary: "fixture",
                evidenceCount: 3,
                durationSeconds: 100,
                confidence: 1,
                actionIDs: pattern == .repeatedFailure ? [.explainError] : [.enableClipboardTranslation]
            )
        }
        try require(queue.enqueue(candidate(.foreignClipboard, offset: 0, source: .clipboard), now: base), "Expected queue insertion.")
        try require(queue.enqueue(candidate(.foreignClipboard, offset: 1, source: .clipboard), now: base), "Expected queue insertion.")
        try require(queue.enqueue(candidate(.foreignClipboard, offset: 2, source: .clipboard), now: base), "Expected queue insertion.")
        try require(!queue.enqueue(candidate(.foreignClipboard, offset: 3, source: .clipboard), now: base), "The judgment queue must stop at three candidates.")
        let replacement = queue.enqueueReportingRemovals(candidate(.repeatedFailure, offset: 4, source: .llmToolsTask), now: base)
        try require(replacement.inserted && replacement.removed.count == 1, "A task failure should report the lower-priority candidate it replaces.")
        try require(queue.count == 3 && queue.popNext(now: base)?.isTaskFailure == true, "Task failures must run before clipboard candidates.")

        var deduplicatingQueue = AssistantCandidateQueue()
        var firstDecision = candidate(.contextualOpportunity, offset: 0, source: .selection)
        firstDecision.decisionKey = "contextualOpportunity|same-surface-anchor"
        var updatedDecision = candidate(.contextualOpportunity, offset: 1, source: .selection)
        updatedDecision.decisionKey = firstDecision.decisionKey
        _ = deduplicatingQueue.enqueue(firstDecision, now: base)
        let deduplicated = deduplicatingQueue.enqueueReportingRemovals(updatedDecision, now: base)
        try require(
            deduplicated.inserted
                && deduplicated.removed.map(\.id) == [firstDecision.id]
                && deduplicatingQueue.count == 1
                && deduplicatingQueue.popNext(now: base)?.id == updatedDecision.id,
            "Concurrent triggers for the same decision key must update one queue slot instead of creating duplicate messages."
        )

        var session = AssistantSessionProactivityState(configured: .active)
        try require(!session.apply(.explicitNegative) && session.effective == .active, "One negative response must not lower proactivity.")
        try require(session.apply(.explicitNegative) && session.effective == .moderate, "Two consecutive explicit negatives must lower one level.")
        _ = session.apply(.noInteractionTimeout)
        _ = session.apply(.unfunny)
        _ = session.apply(.noInteractionTimeout)
        try require(!session.apply(.unopenedBadge), "An unopened badge must not count as ignored proactive content.")
        try require(session.apply(.noInteractionTimeout) && session.effective == .quiet, "Three no-interaction timeouts must lower one level.")
        try require(!session.apply(.explicitNegative) && !session.apply(.explicitNegative) && session.effective == .quiet, "Session lowering must stop at quiet.")
        session.updateConfigured(.active)
        _ = session.apply(.explicitNegative)
        _ = session.apply(.positive)
        try require(!session.apply(.explicitNegative) && session.effective == .active, "Positive interaction must reset consecutive negative counters.")

        var arbiter = AssistantBackgroundWorkArbiter()
        let judgmentLease = try requireNonNil(arbiter.claim(.judgment), "The first background model workflow should acquire the single lease.")
        try require(arbiter.claim(.qualification) == nil && arbiter.claim(.translation) == nil, "Qualification, judgment, and translation must share one background lease.")
        try require(!arbiter.release(AssistantBackgroundWorkLease(id: UUID(), kind: .judgment)), "A stale lease must not release active background work.")
        try require(arbiter.release(judgmentLease) && arbiter.claim(.translation) != nil, "Releasing the exact lease should unblock the next workflow.")

        var qualificationFlow = AssistantQualificationProgress()
        qualificationFlow.start(modelID: UUID(), modelName: "deterministic-fixture-model")
        qualificationFlow.beginRunning()
        for completed in 1...12 { qualificationFlow.recordCompleted(completed) }
        qualificationFlow.pause(message: "preempted by user task")
        try require(
            qualificationFlow.phase == .paused && qualificationFlow.completedCount == 12,
            "Qualification must retain completed fixtures when a user task preempts it."
        )
        qualificationFlow.prepare()
        qualificationFlow.beginRunning()
        for completed in 13...AssistantJudgmentFixtures.all.count { qualificationFlow.recordCompleted(completed) }
        qualificationFlow.finish(state: .qualified, message: "qualified")
        try require(
            qualificationFlow.phase == .qualified
                && qualificationFlow.completedCount == AssistantJudgmentFixtures.all.count,
            "The resumed deterministic qualification flow must reach 24/24 before becoming qualified."
        )
        var failedQualification = AssistantQualificationProgress()
        failedQualification.start(modelID: UUID(), modelName: "failing-fixture-model")
        failedQualification.fail(message: "local runner unavailable")
        try require(
            failedQualification.phase == .failed && failedQualification.completedCount == 0,
            "A failed qualification flow must not manufacture completed fixtures or qualified state."
        )
        var proactivityFlow = AssistantQualificationProactivityState()
        try require(
            proactivityFlow.request(.active, hasQualifiedJudgment: false) == .quiet
                && proactivityFlow.pendingProactivity == .active,
            "An unqualified Active request must remain pending while the effective setting stays Quiet."
        )
        let firstRunID = proactivityFlow.beginRun()
        _ = proactivityFlow.request(.moderate, hasQualifiedJudgment: false)
        try require(
            proactivityFlow.runningProactivity == .moderate
                && proactivityFlow.finishRun(id: firstRunID, state: .qualified) == .moderate,
            "A qualification run must apply the user's latest requested level, not its stale starting level."
        )
        _ = proactivityFlow.request(.active, hasQualifiedJudgment: false)
        let cancelledRunID = proactivityFlow.beginRun()
        proactivityFlow.cancelRun(clearPendingProactivity: true)
        try require(
            proactivityFlow.pendingProactivity == nil
                && proactivityFlow.finishRun(id: cancelledRunID, state: .qualified) == nil,
            "Cancelling or keeping Quiet must prevent a late successful run from restoring a pending level."
        )
        let failedRunID = proactivityFlow.beginRun()
        _ = proactivityFlow.request(.active, hasQualifiedJudgment: false)
        try require(
            proactivityFlow.finishRun(id: failedRunID, state: .unqualified) == .quiet,
            "A failed qualification must conservatively resolve a pending request to Quiet."
        )
        _ = proactivityFlow.request(.active, hasQualifiedJudgment: false)
        let staleRunID = proactivityFlow.beginRun()
        proactivityFlow.cancelRun(clearPendingProactivity: false)
        let replacementRunID = proactivityFlow.beginRun(pendingProactivity: .moderate)
        try require(
            proactivityFlow.finishRun(id: staleRunID, state: .unqualified) == nil
                && proactivityFlow.runID == replacementRunID
                && proactivityFlow.runningProactivity == .moderate,
            "A stale completion must not consume a replacement qualification run."
        )
        _ = proactivityFlow.finishRun(id: replacementRunID, state: .qualified)
        try require(
            proactivityFlow.request(.active, hasQualifiedJudgment: true) == .active
                && proactivityFlow.pendingProactivity == nil,
            "A currently qualified model must apply Moderate or Active without another pending check."
        )

        let unfunny = AssistantFeedbackTransition.resolve(wasProactivelyPresented: true, previous: nil, new: .unfunny)
        try require(unfunny.interaction == .unfunny && unfunny.retainsProactiveAttribution, "Unfunny feedback must affect wording without consuming proactive attribution.")
        let unfunnyThenIrrelevant = AssistantFeedbackTransition.resolve(wasProactivelyPresented: true, previous: .unfunny, new: .irrelevant)
        try require(unfunnyThenIrrelevant.interaction == .explicitNegative, "Unfunny followed by irrelevant must still count as explicit negative feedback.")
        let usefulThenIrrelevant = AssistantFeedbackTransition.resolve(wasProactivelyPresented: true, previous: .useful, new: .irrelevant)
        try require(usefulThenIrrelevant.interaction == .explicitNegative, "Changing useful to irrelevant must update the session outcome.")

        try require(AssistantJudgmentFixtures.all.count == 24, "The runtime fixture catalog must contain exactly 24 cases.")
        try require(AssistantJudgmentFixtures.all.filter(\.expectsPeek).count == 12, "The fixture catalog must contain 12 positive cases.")
        try require(AssistantJudgmentFixtures.all.filter { !$0.expectsPeek }.count == 12, "The fixture catalog must contain 12 negative cases.")
        let hasAppSwitchFixture = AssistantJudgmentFixtures.all.contains { $0.id == "n-normal-app-switch" }
        let hasVideoFixture = AssistantJudgmentFixtures.all.contains { $0.id == "n-watching-video" }
        let typingFixture = AssistantJudgmentFixtures.all.first { $0.id == "n-typing" }
        let longReadingFixture = AssistantJudgmentFixtures.all.first { $0.id == "n-history-irrelevant" }
        let hasLongReadingFixture = longReadingFixture?.input.ephemeralEvidenceTexts.count == 1
            && longReadingFixture?.input.historicalAggregate?.irrelevantCount == 5
        let contextualOpportunityPositives = AssistantJudgmentFixtures.all.filter {
            $0.expectsPeek && $0.input.patternType == .contextualOpportunity
        }
        let passiveReadingFixture = AssistantJudgmentFixtures.all.first { $0.id == "n-passive-reading" }
        let embeddedURLFixture = AssistantJudgmentFixtures.all.first { $0.id == "n-code-copy" }
        let explicitTaskVerbs = ["summarize", "explain", "translate", "turn", "extract"]
        let p06UsesImplicitEvidence = contextualOpportunityPositives.allSatisfy { fixture in
            fixture.input.ephemeralEvidenceTexts.allSatisfy { text in
                let lower = text.lowercased()
                return !explicitTaskVerbs.contains { lower.hasPrefix("\($0) ") }
            }
        }
        try require(
            hasAppSwitchFixture
                && hasVideoFixture
                && typingFixture?.input.userIsTyping == true
                && typingFixture?.isHardNegative == false
                && hasLongReadingFixture
                && contextualOpportunityPositives.count == 4
                && p06UsesImplicitEvidence
                && contextualOpportunityPositives.filter { $0.input.availableActionIDs == [.openQuickAction] }.count == 2
                && contextualOpportunityPositives.filter { $0.input.availableActionIDs.isEmpty }.count == 2
                && contextualOpportunityPositives.allSatisfy { !$0.input.allowedEvidenceQuotes.isEmpty }
                && passiveReadingFixture?.input.historicalAggregate == nil
                && passiveReadingFixture?.input.containsURL == false
                && passiveReadingFixture?.input.containsCode == false
                && embeddedURLFixture?.input.containsURL == true
                && embeddedURLFixture?.input.availableActionIDs.isEmpty == true,
            "Qualification fixtures must cover app switching, video watching, typing, passive reading, feedback, embedded URLs, and four implicit grounded P-06 positives."
        )
        try require(
            AssistantJudgmentFixtures.all.filter(\.expectsPeek).allSatisfy { !$0.input.ephemeralEvidenceTexts.isEmpty },
            "Every positive qualification fixture must require semantic evidence instead of threshold metadata alone."
        )
        let goodSamples = try AssistantJudgmentFixtures.all.map { fixture -> AssistantQualificationSample in
            let isContextualOpportunity = fixture.input.patternType == .contextualOpportunity
            let shouldLockContext = fixture.expectsPeek
                && isContextualOpportunity
                && fixture.input.availableActionIDs.contains(.openQuickAction)
            let output = AssistantJudgmentOutput(
                isHighValue: fixture.expectsPeek,
                valueScore: fixture.expectsPeek ? 0.9 : 0.1,
                confidence: fixture.expectsPeek ? 0.9 : 0.95,
                comment: fixture.expectsPeek ? "This is ready for the next step." : "",
                evidenceSufficient: fixture.expectsPeek,
                recommendedPresentation: fixture.expectsPeek ? .peek : .silent,
                suggestedActionIDs: fixture.expectsPeek ? Array(fixture.input.availableActionIDs.prefix(1)) : [],
                lockedEvidenceQuote: shouldLockContext ? fixture.input.allowedEvidenceQuotes[0] : "",
                suggestedTask: shouldLockContext ? fixture.input.availableTaskKinds[0] : nil
            )
            let data = try JSONEncoder().encode(output)
            return AssistantQualificationSample(
                fixtureID: fixture.id,
                output: String(decoding: data, as: UTF8.self),
                latencyMilliseconds: 100
            )
        }
        let modelID = UUID()
        let qualified = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: goodSamples,
            checkedAt: base
        )
        try require(
            qualified.state == .qualified
                && qualified.validJSONCount == 24
                && qualified.positivePassCount == 12
                && qualified.message.contains("P06 4/4"),
            "A conforming deterministic judge must qualify across P-01, P-03, and at least three P-06 positives."
        )
        let p06FixtureIndexes = goodSamples.indices.filter { index in
            let fixtureID = goodSamples[index].fixtureID
            return AssistantJudgmentFixtures.all.first(where: { $0.id == fixtureID })?.input.patternType == .contextualOpportunity
                && AssistantJudgmentFixtures.all.first(where: { $0.id == fixtureID })?.expectsPeek == true
        }
        let conservativeNegative = AssistantJudgmentOutput(
            isHighValue: false,
            valueScore: 0.1,
            confidence: 0.95,
            comment: "",
            evidenceSufficient: false,
            recommendedPresentation: .silent,
            suggestedActionIDs: []
        )
        var threeOfFourP06Samples = goodSamples
        threeOfFourP06Samples[p06FixtureIndexes[0]].output = String(
            decoding: try JSONEncoder().encode(conservativeNegative),
            as: UTF8.self
        )
        let threeOfFourP06 = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: threeOfFourP06Samples,
            checkedAt: base
        )
        try require(threeOfFourP06.state == .qualified && threeOfFourP06.message.contains("P06 3/4"), "Three of four grounded P-06 positives should satisfy the frozen family floor.")
        var twoOfFourP06Samples = threeOfFourP06Samples
        twoOfFourP06Samples[p06FixtureIndexes[1]].output = String(
            decoding: try JSONEncoder().encode(conservativeNegative),
            as: UTF8.self
        )
        let twoOfFourP06 = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: twoOfFourP06Samples,
            checkedAt: base
        )
        try require(
            twoOfFourP06.validJSONCount == 24
                && twoOfFourP06.positivePassCount >= 9
                && twoOfFourP06.message.contains("P06 2/4")
                && twoOfFourP06.state == .unqualified,
            "A model that misses half of P-06 must fail even when its aggregate positive score would otherwise pass."
        )
        try require(qualified.isCurrent(modelFingerprint: "fingerprint-v1") && !qualified.isCurrent(modelFingerprint: "changed"), "Qualification cache must bind model, prompt, and fixture identity.")
        var hardFailureSamples = goodSamples
        let hardFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: {
                $0.isHardNegative
                    && $0.input.patternType == .contextualOpportunity
                    && !$0.input.allowedEvidenceQuotes.isEmpty
                    && !$0.input.availableTaskKinds.isEmpty
            }),
            "Expected a grounded P-06 hard negative fixture."
        )
        let illegalPeek = AssistantJudgmentOutput(
            isHighValue: true,
            valueScore: 0.9,
            confidence: 0.9,
            comment: "This should not be shown.",
            evidenceSufficient: true,
            recommendedPresentation: .peek,
            suggestedActionIDs: Array(hardFixture.input.availableActionIDs.prefix(1)),
            lockedEvidenceQuote: hardFixture.input.allowedEvidenceQuotes[0],
            suggestedTask: hardFixture.input.availableTaskKinds[0]
        )
        hardFailureSamples[hardFailureSamples.firstIndex { $0.fixtureID == hardFixture.id }!] = AssistantQualificationSample(
            fixtureID: hardFixture.id,
            output: String(decoding: try JSONEncoder().encode(illegalPeek), as: UTF8.self),
            latencyMilliseconds: 100
        )
        let unqualified = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: hardFailureSamples,
            checkedAt: base
        )
        try require(unqualified.state == .unqualified && unqualified.hardFailureCount == 1, "A single hard-negative proactive error must fail qualification.")
        let partialQualification = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: Array(goodSamples.prefix(5)),
            checkedAt: base
        )
        try require(
            partialQualification.validJSONCount == 5
                && partialQualification.positivePassCount == 5
                && partialQualification.maximumLatencyMilliseconds == 100
                && partialQualification.message.contains("JSON 5/24"),
            "A partially failed qualification must retain real structure, positive, and latency metrics."
        )
        var timeoutSamples = Array(goodSamples.prefix(5))
        timeoutSamples[4].output = nil
        timeoutSamples[4].latencyMilliseconds = AssistantQualificationEvaluator.maximumFixtureLatencyMilliseconds
        let timedOutQualification = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: timeoutSamples,
            checkedAt: base
        )
        try require(
            timedOutQualification.validJSONCount == 4
                && timedOutQualification.maximumLatencyMilliseconds == 10_000
                && timedOutQualification.message.contains("max 10000ms"),
            "A timed-out hot fixture must retain its failed structure and real ten-second latency."
        )
        var slowButAllowedSamples = goodSamples
        slowButAllowedSamples[0].latencyMilliseconds = 10_000
        let slowButAllowed = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: slowButAllowedSamples,
            checkedAt: base
        )
        slowButAllowedSamples[0].latencyMilliseconds = 10_001
        let tooSlow = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "fingerprint-v1",
            samples: slowButAllowedSamples,
            checkedAt: base
        )
        try require(
            slowButAllowed.state == .qualified && tooSlow.state == .unqualified,
            "The shared hot-fixture latency gate must accept 10 seconds and reject anything slower."
        )
        try require(
            unqualified.matchesCurrentCacheKey(modelFingerprint: "fingerprint-v1")
                && !unqualified.isCurrent(modelFingerprint: "fingerprint-v1"),
            "A current unqualified cache entry must remain reusable without becoming an eligible judgment model."
        )
        let malformed = "{\"isHighValue\":true,\"suggestedActionIDs\":[\"openURL\"]}"
        try require(AssistantJudgmentContract.parse(malformed, input: AssistantJudgmentFixtures.all[0].input) == nil, "Judgment parsing must reject incomplete or invented actions.")
        let fenced = "```json\n\(goodSamples[0].output!)\n```"
        try require(AssistantJudgmentContract.parse(fenced, input: AssistantJudgmentFixtures.all[0].input) == nil, "Judgment parsing must reject fenced or trailing model prose.")
        var falseWithComment = conservativeNegative
        falseWithComment.comment = "The evidence does not justify an interruption."
        let falseWithCommentText = String(decoding: try JSONEncoder().encode(falseWithComment), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(
                falseWithCommentText,
                input: AssistantJudgmentFixtures.all.first { !$0.expectsPeek }!.input
            ) == nil,
            "A silent judgment must not leak its internal rationale into the bubble field."
        )
        let overlongComment = AssistantJudgmentOutput(
            isHighValue: true,
            valueScore: 0.9,
            confidence: 0.9,
            comment: String(repeating: "x", count: 81),
            evidenceSufficient: true,
            recommendedPresentation: .peek,
            suggestedActionIDs: []
        )
        let overlongCommentText = String(decoding: try JSONEncoder().encode(overlongComment), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(
                overlongCommentText,
                input: AssistantJudgmentFixtures.all.first { $0.id == "p06-progress" }!.input
            ) == nil,
            "Judgment parsing must enforce the same 80-character bubble limit advertised by the prompt."
        )
        try require(
            AssistantJudgmentContract.promptVersion == 26
                && AssistantJudgmentFixtures.version == 13
                && AssistantProactivity.active.hourlyPresentationLimit == 6
                && AssistantPersonality.allCases.count == 6
                && AssistantQualificationEvaluator.maximumFixtureLatencyMilliseconds == 10_000
                && AssistantJudgmentContract.systemPrompt.contains("Return exactly one JSON object")
                && AssistantJudgmentContract.systemPrompt.contains("comment (string; empty for false")
                && AssistantJudgmentContract.systemPrompt.contains("Never force a tool")
                && AssistantJudgmentContract.systemPrompt.contains("authoritative upstream facts")
                && AssistantJudgmentContract.systemPrompt.contains("rules and actions for other pattern types do not apply")
                && AssistantJudgmentContract.systemPrompt.contains("familiar desktop companion")
                && AssistantJudgmentContract.systemPrompt.contains("Never call them \"用户\"")
                && AssistantJudgmentContract.systemPrompt.contains("delivery timing only"),
            "The qualification cache version and strict structured-output contract must change together."
        )
        let p06PositiveFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: {
                $0.expectsPeek && $0.input.patternType == .contextualOpportunity
            }),
            "Expected a positive P-06 qualification fixture."
        )
        let p01PromptRecipe = AssistantJudgmentContract.userPrompt(for: AssistantJudgmentFixtures.all[0].input)
        let p03PromptRecipe = AssistantJudgmentContract.userPrompt(for: AssistantJudgmentFixtures.all[4].input)
        let p06PromptRecipe = AssistantJudgmentContract.userPrompt(for: p06PositiveFixture.input)
        let activeCompanionFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: { $0.id == "p06-active-companion" }),
            "Expected the active companion qualification fixture."
        )
        let activeP06PromptRecipe = AssistantJudgmentContract.userPrompt(for: activeCompanionFixture.input)
        try require(
            p01PromptRecipe.contains("evidenceCount, not evidenceTextCount")
                && p01PromptRecipe.contains("intentional tutorial/example")
                && p03PromptRecipe.contains("English may be foreign")
                && p03PromptRecipe.contains("weather, software news, and cooking")
                && p06PromptRecipe.contains("do not require an explicit request, error, tool, or next step")
                && p06PromptRecipe.contains("multiple blockers/tasks without owners")
                && p06PromptRecipe.contains("visible progress or a completed milestone")
                && p06PromptRecipe.contains("clear transition between work stages")
                && p06PromptRecipe.contains("never use an action from another pattern")
                && p06PromptRecipe.contains("confidence>=0.85")
                && activeP06PromptRecipe.contains("ACTIVE MODE is explicit opt-in")
                && activeP06PromptRecipe.contains("Routine active reading, comparing, editing")
                && activeP06PromptRecipe.contains("valueScore>=0.50")
                && activeP06PromptRecipe.contains("confidence>=0.75")
                && activeP06PromptRecipe.contains("VOICE: PLAYFUL GIRL")
                && activeP06PromptRecipe.contains("Do not explain, analyze, summarize, or advise on technical details")
                && activeP06PromptRecipe.contains("never repeat technical terms")
                && activeP06PromptRecipe.contains("PLAYFUL GIRL COMMENT OVERRIDE")
                && activeP06PromptRecipe.contains("ViewModel 刷新触发条件")
                && p06PromptRecipe.contains("FALSE RECIPE"),
            "Each pattern prompt must end with its exact action/field recipe and the shared false-output invariant."
        )
        try require(
            AssistantJudgmentFixtures.all.contains(where: { $0.id == "p06-progress" && $0.expectsPeek })
                && activeCompanionFixture.expectsPeek
                && activeCompanionFixture.input.proactivity == .active
                && activeCompanionFixture.input.personality == .playfulGirl,
            "Qualification must verify grounded progress and the more conversational Active policy."
        )
        let p06ProgressFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: { $0.id == "p06-progress" }),
            "Expected the grounded progress fixture."
        )
        let groundedP06Output = AssistantJudgmentOutput(
            isHighValue: true,
            valueScore: 0.9,
            confidence: 0.9,
            comment: "Five release-note items remain; start with a summary.",
            evidenceSufficient: true,
            recommendedPresentation: .peek,
            suggestedActionIDs: [.openQuickAction],
            lockedEvidenceQuote: p06PositiveFixture.input.allowedEvidenceQuotes[0],
            suggestedTask: p06PositiveFixture.input.availableTaskKinds[0]
        )
        let groundedP06Text = String(decoding: try JSONEncoder().encode(groundedP06Output), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(groundedP06Text, input: p06PositiveFixture.input) != nil,
            "P-06 must accept a quote, task, and action locked to supplied local evidence."
        )
        try require(
            p06PositiveFixture.input.allowedEvidenceQuotes.count == 1,
            "Only the primary explicit P-06 evidence may become an executable Quick Action quote."
        )
        if p06PositiveFixture.input.ephemeralEvidenceTexts.count > 1 {
            var supportQuoteOutput = groundedP06Output
            supportQuoteOutput.lockedEvidenceQuote = String(
                p06PositiveFixture.input.ephemeralEvidenceTexts[1].prefix(80)
            )
            let supportQuoteText = String(decoding: try JSONEncoder().encode(supportQuoteOutput), as: UTF8.self)
            try require(
                AssistantJudgmentContract.parse(supportQuoteText, input: p06PositiveFixture.input) == nil,
                "Window or visual support evidence must never become the parameter of a Quick Action."
            )
        }
        var unsafeFinalMessage = groundedP06Output
        unsafeFinalMessage.comment = "Open https://example.com and run func deploy() now."
        let unsafeFinalMessageText = String(decoding: try JSONEncoder().encode(unsafeFinalMessage), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(unsafeFinalMessageText, input: p06PositiveFixture.input) == nil,
            "The one-pass judgment boundary must reject a final bubble message containing a URL or code."
        )
        let actionlessP06Output = AssistantJudgmentOutput(
            isHighValue: true,
            valueScore: 0.86,
            confidence: 0.9,
            comment: "Five release-note items remain; start with the nearest deadline.",
            evidenceSufficient: true,
            recommendedPresentation: .peek,
            suggestedActionIDs: [],
            lockedEvidenceQuote: "",
            suggestedTask: nil
        )
        let actionlessP06Text = String(decoding: try JSONEncoder().encode(actionlessP06Output), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(actionlessP06Text, input: p06PositiveFixture.input) != nil
                && AssistantJudgmentContract.permitsPeek(
                    actionlessP06Output,
                    proactivity: .moderate,
                    input: p06PositiveFixture.input
                )
                && !AssistantJudgmentContract.permitsPeek(actionlessP06Output, proactivity: .moderate),
            "Only grounded P-06 context may present an actionless social comment."
        )
        for observerComment in [
            "用户正在查看技术文档，适合提供温和共鸣。",
            "这段内容适合提供温和共鸣。",
            "正在研究 ViewModel 刷新条件，这种技术细节需要耐心梳理。",
            "看到你在看安装指南，需要我帮你翻译吗？"
        ] {
            var observerNarration = actionlessP06Output
            observerNarration.comment = observerComment
            let observerNarrationText = String(decoding: try JSONEncoder().encode(observerNarration), as: UTF8.self)
            try require(
                AssistantJudgmentContract.parse(observerNarrationText, input: p06PositiveFixture.input) == nil,
                "A final bubble must reject third-person narration and internal value-judgment language."
            )
        }
        var redundantActionlessP06Output = actionlessP06Output
        redundantActionlessP06Output.lockedEvidenceQuote = p06PositiveFixture.input.ephemeralEvidenceTexts[0]
        redundantActionlessP06Output.suggestedTask = p06PositiveFixture.input.availableTaskKinds[0]
        let redundantActionlessP06Text = String(
            decoding: try JSONEncoder().encode(redundantActionlessP06Output),
            as: UTF8.self
        )
        let normalizedActionlessP06 = AssistantJudgmentContract.parse(
            redundantActionlessP06Text,
            input: p06PositiveFixture.input
        )
        try require(
            normalizedActionlessP06?.lockedEvidenceQuote == ""
                && normalizedActionlessP06?.suggestedTask == nil
                && normalizedActionlessP06?.suggestedActionIDs.isEmpty == true,
            "Grounded redundant fields on an actionless P-06 result must be discarded, never made actionable."
        )
        var structuredContextP06Output = actionlessP06Output
        structuredContextP06Output.lockedEvidenceQuote = "The build panel shows all 24 checks passing beside the current editor"
        let structuredContextP06Text = String(
            decoding: try JSONEncoder().encode(structuredContextP06Output),
            as: UTF8.self
        )
        try require(
            AssistantJudgmentContract.parse(
                structuredContextP06Text,
                input: p06ProgressFixture.input
            )?.lockedEvidenceQuote == "",
            "An actionless P-06 quote grounded inside a structured visual summary must be accepted and discarded."
        )
        let validSceneJSON = """
        {"activity":"coding","observation":"A build result is visible beside the current editor.","visibleText":["Build succeeded"],"signal":"success","confidence":0.91}
        """
        try require(
            AssistantSceneContract.promptVersion == 2
                && AssistantSceneContract.systemPrompt.contains("All five keys are required")
                && AssistantSceneContract.parse(validSceneJSON)?.signal == "success"
                && AssistantSceneContract.parse(
                    "{\"activity\":\"form\",\"observation\":\"password=secret\",\"visibleText\":[],\"signal\":\"none\",\"confidence\":0.9}"
                ) == nil,
            "Visual context must accept bounded grounded JSON and reject sensitive summaries."
        )
        let codeContextFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: { $0.id == "n-code-copy" }),
            "Expected the embedded URL and code qualification fixture."
        )
        var safeCodeObservation = actionlessP06Output
        safeCodeObservation.comment = "There is no clear milestone here yet; keep going."
        let safeCodeObservationText = String(decoding: try JSONEncoder().encode(safeCodeObservation), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(safeCodeObservationText, input: codeContextFixture.input) != nil,
            "Code and URL evidence may support a safe actionless judgment; upstream must remove its Quick Action entry."
        )
        var fullEvidenceP06Output = groundedP06Output
        fullEvidenceP06Output.lockedEvidenceQuote = p06PositiveFixture.input.ephemeralEvidenceTexts[0]
        let fullEvidenceP06Text = String(decoding: try JSONEncoder().encode(fullEvidenceP06Output), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(fullEvidenceP06Text, input: p06PositiveFixture.input)?.lockedEvidenceQuote
                == p06PositiveFixture.input.allowedEvidenceQuotes[0],
            "An exact full supplied P-06 value may be shortened, but invented or altered evidence must still fail."
        )
        let longP06Fixture = try requireNonNil(
            contextualOpportunityPositives.first(where: {
                $0.input.ephemeralEvidenceTexts[0].count > $0.input.allowedEvidenceQuotes[0].count
            }),
            "Expected a P-06 fixture whose frozen quote truncates a longer authorized value."
        )
        var extendedPrefixOutput = groundedP06Output
        extendedPrefixOutput.lockedEvidenceQuote = String(
            longP06Fixture.input.ephemeralEvidenceTexts[0]
                .prefix(longP06Fixture.input.allowedEvidenceQuotes[0].count + 1)
        )
        extendedPrefixOutput.suggestedTask = longP06Fixture.input.availableTaskKinds[0]
        let extendedPrefixText = String(decoding: try JSONEncoder().encode(extendedPrefixOutput), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(extendedPrefixText, input: longP06Fixture.input)?.lockedEvidenceQuote
                == longP06Fixture.input.allowedEvidenceQuotes[0],
            "A model-completed quote boundary may normalize only when it remains an anchored prefix of the exact evidence."
        )
        var groundedFalseP06Output = fullEvidenceP06Output
        groundedFalseP06Output.isHighValue = false
        groundedFalseP06Output.valueScore = 0
        groundedFalseP06Output.comment = ""
        groundedFalseP06Output.recommendedPresentation = .silent
        groundedFalseP06Output.suggestedActionIDs = []
        groundedFalseP06Output.suggestedTask = nil
        let groundedFalseP06Text = String(decoding: try JSONEncoder().encode(groundedFalseP06Output), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(groundedFalseP06Text, input: p06PositiveFixture.input)?.lockedEvidenceQuote == "",
            "A fully silent false result may discard an exact supplied redundant quote without making it actionable."
        )
        let passiveMediaFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: { $0.id == "n-watching-video" }),
            "Expected the passive-media negative fixture."
        )
        var groundedFragmentFalseOutput = conservativeNegative
        groundedFragmentFalseOutput.lockedEvidenceQuote = "no translation task was requested"
        let groundedFragmentFalseText = String(
            decoding: try JSONEncoder().encode(groundedFragmentFalseOutput),
            as: UTF8.self
        )
        try require(
            AssistantJudgmentContract.parse(
                groundedFragmentFalseText,
                input: passiveMediaFixture.input
            )?.lockedEvidenceQuote == "",
            "A fully silent false result may discard a grounded input fragment, but it must remain non-actionable."
        )
        var inventedQuoteOutput = groundedP06Output
        inventedQuoteOutput.lockedEvidenceQuote = "This sentence was never observed."
        let inventedQuoteText = String(decoding: try JSONEncoder().encode(inventedQuoteOutput), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(inventedQuoteText, input: p06PositiveFixture.input) == nil,
            "P-06 must reject a model observation that is not an exact supplied evidence quote."
        )
        var invalidTaskOutput = groundedP06Output
        invalidTaskOutput.suggestedTask = .ocr
        let invalidTaskText = String(decoding: try JSONEncoder().encode(invalidTaskOutput), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(invalidTaskText, input: p06PositiveFixture.input) == nil,
            "P-06 must reject tasks outside the existing interactive Quick Action set."
        )
        var lowModerateConfidence = groundedP06Output
        lowModerateConfidence.confidence = 0.84
        try require(
            !AssistantJudgmentContract.permitsPeek(lowModerateConfidence, proactivity: .moderate)
                && AssistantJudgmentContract.permitsPeek(lowModerateConfidence, proactivity: .active)
                && AssistantJudgmentContract.permitsPeek(
                    lowModerateConfidence,
                    proactivity: .moderate,
                    minimumConfidenceOverride: 0.80
                )
                && AssistantJudgmentContract.minimumConfidence(for: .active, override: 0.10) == 0.50
                && AssistantJudgmentContract.minimumConfidence(for: .active, override: 1.00) == 0.95,
            "Moderate and Active defaults must stay frozen while a custom confidence floor remains bounded."
        )
        let customThresholdSystemPrompt = AssistantJudgmentContract.runtimeSystemPrompt(
            minimumConfidenceOverride: 0.60
        )
        let customThresholdUserPrompt = AssistantJudgmentContract.userPrompt(
            for: p06PositiveFixture.input,
            minimumConfidenceOverride: 0.60
        )
        try require(
            AssistantJudgmentContract.runtimeSystemPrompt(minimumConfidenceOverride: nil)
                == AssistantJudgmentContract.systemPrompt
                && customThresholdSystemPrompt.contains("confidence>=0.60")
                && customThresholdSystemPrompt.contains("replaces the moderate and active defaults")
                && customThresholdUserPrompt.contains("confidence>=0.60"),
            "A custom confidence floor must reach both runtime prompts without changing the qualification prompt."
        )
        var falseBadgeOutput = conservativeNegative
        falseBadgeOutput.recommendedPresentation = .badge
        let falseBadgeText = String(decoding: try JSONEncoder().encode(falseBadgeOutput), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(falseBadgeText, input: p06PositiveFixture.input) == nil,
            "A rejected judgment must be structurally silent rather than fabricating a fallback badge."
        )
        var extraFieldObject = try JSONSerialization.jsonObject(with: Data(groundedP06Text.utf8)) as! [String: Any]
        extraFieldObject["unexpected"] = true
        let extraFieldText = String(decoding: try JSONSerialization.data(withJSONObject: extraFieldObject), as: UTF8.self)
        try require(
            AssistantJudgmentContract.parse(extraFieldText, input: p06PositiveFixture.input) == nil,
            "The P-06 judgment boundary must reject extra model fields."
        )
        let fullScreenFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: { $0.id == "n-fullscreen" }),
            "Expected the fullscreen qualification fixture."
        )
        try require(
            AssistantJudgmentContract.userPrompt(for: fullScreenFixture.input)
                .contains("mandatoryVetoReasons=none")
                && AssistantJudgmentContract.userPrompt(for: fullScreenFixture.input)
                    .contains("\"isFullScreen\":true")
                && AssistantJudgmentContract.userPrompt(for: typingFixture!.input)
                    .contains("mandatoryVetoReasons=none"),
            "Typing and full-screen state must remain delivery hints instead of value-judgment vetoes."
        )
        try require(
            AssistantJudgmentContract.userPrompt(for: AssistantJudgmentFixtures.all[0].input)
                .contains("mandatoryVetoReasons=none"),
            "Eligible semantic candidates must not acquire a fabricated mandatory veto."
        )
        let irrelevantHistoryFixture = try requireNonNil(
            AssistantJudgmentFixtures.all.first(where: { $0.id == "n-history-irrelevant" }),
            "Expected the irrelevant-history qualification fixture."
        )
        let irrelevantHistoryPrompt = AssistantJudgmentContract.userPrompt(for: irrelevantHistoryFixture.input)
        try require(
            irrelevantHistoryFixture.input.suppressesRepeatedlyIrrelevantFeedback
                && irrelevantHistoryPrompt.contains("evidenceTextCount=1")
                && irrelevantHistoryPrompt.contains("historicalIrrelevantCount=5")
                && irrelevantHistoryPrompt.contains("historicalActedCount=0")
                && irrelevantHistoryPrompt.contains("historyPolicy=suppressRepeatedlyIrrelevant")
                && irrelevantHistoryPrompt.contains("HISTORY VETO"),
            "Production judgment prompts must make semantic evidence count and repeated negative feedback salient."
        )
        let appSwitchPrompt = AssistantJudgmentContract.userPrompt(
            for: AssistantJudgmentFixtures.all.first(where: { $0.id == "n-normal-app-switch" })!.input
        )
        try require(
            appSwitchPrompt.contains("ineligibleSourceTypes"),
            "Foreground-application metadata without an authorized semantic source must be a deterministic P-06 veto."
        )
        let boundedJudgmentRequest = TaskRequest(
            task: .explain,
            inputText: "same error",
            systemPromptOverride: AssistantJudgmentContract.systemPrompt,
            thinkingModeOverride: false,
            maxOutputTokensOverride: 256
        )
        try require(
            boundedJudgmentRequest.thinkingModeOverride == false
                && boundedJudgmentRequest.maxOutputTokensOverride == 256
                && LocalGenerationPolicy.maxTokens(
                    for: .explain,
                    thinkingModeEnabled: false,
                    override: boundedJudgmentRequest.maxOutputTokensOverride
                ) == 256,
            "Strictly timed assistant judgment requests must disable thinking and tighten output without changing normal task limits."
        )

        let sanitizedHistoryInput = AssistantJudgmentInput(
            patternType: .repeatedFailure,
            evidenceSummary: "same error",
            ephemeralEvidenceTexts: [
                "Error at /Users/example/private/project token=do-not-keep-this " + String(repeating: "detail ", count: 300)
            ],
            sourceTypes: [.selection],
            appCategory: "development",
            evidenceCount: 3,
            durationSeconds: 60,
            recentBehaviorSummaries: [
                "password=do-not-keep-this", "one", "two", "three", "four", "five", "six"
            ],
            availableActionIDs: [.explainError]
        )
        try require(sanitizedHistoryInput.recentBehaviorSummaries.count == 5, "Judgment history must be capped at five sanitized summaries.")
        try require(
            !sanitizedHistoryInput.recentBehaviorSummaries.joined().contains("do-not-keep-this")
                && sanitizedHistoryInput.recentBehaviorSummaries.allSatisfy { $0.count <= 240 },
            "Judgment history must redact secrets and enforce the evidence length bound."
        )
        let judgmentPrompt = AssistantJudgmentContract.userPrompt(for: sanitizedHistoryInput)
        try require(
            judgmentPrompt.contains("ephemeralEvidenceTexts")
                && judgmentPrompt.contains("appCategory")
                && !judgmentPrompt.contains("/Users/example")
                && !judgmentPrompt.contains("do-not-keep-this"),
            "Production judgment prompts must carry sanitized semantic evidence and coarse app category without paths or secrets."
        )

        let commentInput = AssistantCommentInput(
            patternType: .repeatedFailure,
            personality: .gentle,
            language: "zh-Hans",
            evidenceCount: 3,
            durationSeconds: 120,
            allowedActionIDs: [.explainError]
        )
        let validComment = AssistantCommentOutput(
            comment: AssistantCommentTemplates.options(for: commentInput)[1],
            suggestedActionIDs: [.explainError],
            includesJoke: false
        )
        let validCommentText = String(decoding: try JSONEncoder().encode(validComment), as: UTF8.self)
        try require(
            AssistantCommentContract.parse(validCommentText, input: commentInput) != nil,
            "A factual comment using an allowed action should parse."
        )
        let inventedComment = AssistantCommentOutput(comment: "网络已经断开，文件已经损坏。", suggestedActionIDs: [.explainError], includesJoke: false)
        let inventedCommentText = String(decoding: try JSONEncoder().encode(inventedComment), as: UTF8.self)
        try require(
            AssistantCommentContract.parse(inventedCommentText, input: commentInput) == nil,
            "Comments must not invent facts even when they contain no names or numbers."
        )
        for comment in ["Ask Alice to inspect the same error.", "请在 Chrome 中处理这条错误。"] {
            let output = AssistantCommentOutput(comment: comment, suggestedActionIDs: [.explainError], includesJoke: false)
            let encoded = String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
            try require(
                AssistantCommentContract.parse(encoded, input: commentInput) == nil,
                "Comments must not invent people or application names."
            )
        }
        try require(!AssistantCommentTemplates.comment(for: commentInput).isEmpty, "Every personality needs a deterministic comment fallback.")
        let personalityComments = AssistantPersonality.allCases.map { personality in
            var input = commentInput
            input.personality = personality
            return AssistantCommentTemplates.comment(for: input)
        }
        try require(
            Set(personalityComments).count == AssistantPersonality.allCases.count
                && personalityComments.allSatisfy(AssistantJudgmentContract.isDirectBubbleComment),
            "Each selectable personality must have distinct, directly addressed fallback wording."
        )
        var playfulGirlInput = commentInput
        playfulGirlInput.personality = .playfulGirl
        let playfulGirlComment = AssistantCommentTemplates.comment(for: playfulGirlInput)
        try require(
            playfulGirlComment.contains("陪")
                && !playfulGirlComment.contains("根因")
                && !playfulGirlComment.contains("重试"),
            "The playful-girl fallback should offer companionship instead of technical analysis."
        )
        try require(
            AssistantCommentTemplates.options(for: commentInput).allSatisfy { !$0.contains("input.evidenceCount") },
            "Deterministic comment options must interpolate their structured count."
        )
        let p06CommentInput = AssistantCommentInput(
            patternType: .contextualOpportunity,
            personality: .gentle,
            language: "zh-Hans",
            evidenceCount: 2,
            durationSeconds: 8,
            evidenceQuote: p06PositiveFixture.input.allowedEvidenceQuotes[0],
            suggestedTask: .summarize,
            allowedActionIDs: [.openQuickAction]
        )
        let p06CommentOptions = AssistantCommentTemplates.options(for: p06CommentInput)
        try require(
            p06CommentOptions.count == 2
                && p06CommentOptions.allSatisfy {
                    !$0.contains(p06PositiveFixture.input.allowedEvidenceQuotes[0])
                        && $0.contains("总结")
                },
            "P-06 card comments must preserve the locked task without persisting the raw evidence quote."
        )
        let validP06Comment = AssistantCommentOutput(
            comment: p06CommentOptions[1],
            suggestedActionIDs: [.openQuickAction],
            includesJoke: false
        )
        let validP06CommentText = String(decoding: try JSONEncoder().encode(validP06Comment), as: UTF8.self)
        try require(
            AssistantCommentContract.parse(validP06CommentText, input: p06CommentInput) != nil,
            "The comment model must be able to select, but not rewrite, a grounded P-06 template."
        )
        let socialCommentInput = AssistantCommentInput(
            patternType: .contextualOpportunity,
            personality: .lightTeasing,
            language: "zh-Hans",
            evidenceCount: 1,
            durationSeconds: 0,
            allowedActionIDs: [],
            contextSummary: "activity=coding; signal=success; observation=构建结果已经通过"
        )
        let socialComment = AssistantCommentOutput(
            comment: "构建终于点头了，这次我先不替它鼓掌。",
            suggestedActionIDs: [],
            includesJoke: true
        )
        let socialCommentText = String(decoding: try JSONEncoder().encode(socialComment), as: UTF8.self)
        try require(
            AssistantCommentContract.parse(socialCommentText, input: socialCommentInput) != nil,
            "An actionless visual observation should support personality-driven wording."
        )
        var inventedP06Comment = validP06Comment
        inventedP06Comment.comment = "系统已自动修复并发布。"
        let inventedP06CommentText = String(decoding: try JSONEncoder().encode(inventedP06Comment), as: UTF8.self)
        try require(
            AssistantCommentContract.parse(inventedP06CommentText, input: p06CommentInput) == nil,
            "P-06 comments must reject facts outside the deterministic grounded options."
        )
        let teasingInput = AssistantCommentInput(
            patternType: .foreignClipboard,
            personality: .lightTeasing,
            language: "zh-Hans",
            evidenceCount: 3,
            durationSeconds: 120,
            allowedActionIDs: [.enableClipboardTranslation]
        )
        let falseJokeFlag = AssistantCommentOutput(
            comment: AssistantCommentTemplates.comment(for: teasingInput),
            suggestedActionIDs: teasingInput.allowedActionIDs,
            includesJoke: false
        )
        let falseJokeFlagText = String(decoding: try JSONEncoder().encode(falseJokeFlag), as: UTF8.self)
        try require(
            AssistantCommentContract.parse(falseJokeFlagText, input: teasingInput) == nil,
            "A teasing comment must not hide its unfunny-feedback affordance with a false model flag."
        )

        let fingerprintRoot = try makeTemporaryDirectory(name: "assistant-model-fingerprint")
        defer { try? FileManager.default.removeItem(at: fingerprintRoot) }
        let weight = fingerprintRoot.appendingPathComponent("model.gguf")
        try Data("first model payload".utf8).write(to: weight)
        let firstFingerprint = try AssistantModelFingerprint.fingerprint(at: weight)
        try Data("changed model payload".utf8).write(to: weight)
        let secondFingerprint = try AssistantModelFingerprint.fingerprint(at: weight)
        try require(firstFingerprint != secondFingerprint, "Changing local model bytes must invalidate the qualification fingerprint.")

        var translationSession = AssistantTemporaryTranslationSession()
        translationSession.start(language: "en-US", now: base)
        try require(!translationSession.accepts(language: "en", occurredAt: base.addingTimeInterval(-1), now: base), "A temporary translation session must not process historical clipboard content.")
        try require(translationSession.accepts(language: "en-GB", occurredAt: base.addingTimeInterval(1), now: base.addingTimeInterval(1)), "A temporary session should accept future text in the same base language.")
        try require(!translationSession.accepts(language: "fr", occurredAt: base.addingTimeInterval(2), now: base.addingTimeInterval(2)), "A temporary session must reject a different language.")
        try require(!translationSession.accepts(language: "en", occurredAt: base.addingTimeInterval(1_801), now: base.addingTimeInterval(1_801)), "A temporary session must expire after 30 minutes.")
        translationSession.start(language: "en", now: base)
        translationSession.fail()
        try require(!translationSession.accepts(language: "en", occurredAt: base.addingTimeInterval(1), now: base.addingTimeInterval(1)), "A local translation failure must end the temporary session.")
    }

    private static func checkMediaSubtitlePreferenceDefaultsDecodeFromOlderRegistry() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        try require(preferences.mediaSubtitles.isEnabled, "Expected media subtitles to default on.")
        try require(preferences.mediaSubtitles.defaultTargetLanguage == "zh-Hans", "Expected media subtitles to default to Simplified Chinese.")
        try require(preferences.mediaSubtitles.sourceLanguageHint == .auto, "Expected ASR source language hint to default to auto.")
        try require(preferences.mediaSubtitles.defaultSubtitleMode == .bilingual, "Expected media subtitles to default to bilingual display.")
        try require(!preferences.mediaSubtitles.saveTranscriptHistory, "Media transcript history must default off.")
        try require(!preferences.mediaSubtitles.saveTranslatedSubtitleHistory, "Translated subtitle history must default off.")
        try require(preferences.mediaSubtitles.funASRCommandTemplate.isEmpty, "Fun-ASR command should default empty.")
        try require(preferences.mediaSubtitles.senseVoiceCommandTemplate.isEmpty, "SenseVoice command should default empty.")
        try require(preferences.mediaSubtitles.qwen3ASRCommandTemplate.isEmpty, "Qwen3-ASR command should default empty.")
        try require(preferences.mediaSubtitles.whisperCommandTemplate.isEmpty, "Whisper command should default empty.")
        try require(preferences.mediaSubtitles.genericASRCommandTemplate.isEmpty, "Generic ASR command should default empty.")
        try require(preferences.mediaSubtitles.liveWindowWidth == MediaSubtitlePreferences.defaultLiveWindowWidth, "Expected live subtitle window width to use the default.")
        try require(preferences.mediaSubtitles.liveWindowHeight == MediaSubtitlePreferences.defaultLiveWindowHeight, "Expected live subtitle window height to use the default.")
        try require(preferences.mediaSubtitles.liveTextColorHex == MediaSubtitlePreferences.defaultLiveTextColorHex, "Expected live subtitle text color to default to white.")
        try require(preferences.mediaSubtitles.liveASRPartialMillisecondsByModelID.isEmpty, "Expected live ASR partial-window overrides to default empty.")
        try require(preferences.liveMeeting.defaultAudioSource == .microphone, "Expected live meeting input to default to microphone.")
        try require(preferences.liveMeeting.sourceLanguageHint == .auto, "Expected live meeting source language to default to auto.")
        try require(preferences.liveMeeting.realtimeASRModelID == nil && preferences.liveMeeting.fileASRModelID == nil && preferences.liveMeeting.notesModelID == nil, "Expected older registries to decode empty meeting model selections.")
        let invalidMeetingSource = LiveMeetingPreferences(defaultAudioSource: .localFile)
        try require(invalidMeetingSource.defaultAudioSource == .microphone, "Meeting defaults must reject local-file capture as a live source.")
        let tinyWindowPreferences = MediaSubtitlePreferences(liveWindowWidth: 10, liveWindowHeight: 10)
        try require(tinyWindowPreferences.liveWindowWidth == MediaSubtitlePreferences.minimumLiveWindowWidth, "Expected live subtitle window width to clamp to the minimum.")
        try require(tinyWindowPreferences.liveWindowHeight == MediaSubtitlePreferences.minimumLiveWindowHeight, "Expected live subtitle window height to clamp to the minimum.")
        try require(MediaSubtitlePreferences(liveTextColorHex: "12abEF").liveTextColorHex == "#12ABEF", "Expected live subtitle text color to normalize RGB hex values.")
        try require(MediaSubtitlePreferences(liveTextColorHex: "invalid").liveTextColorHex == MediaSubtitlePreferences.defaultLiveTextColorHex, "Expected invalid live subtitle text colors to fall back to white.")
        let asrModelID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var partialWindowPreferences = MediaSubtitlePreferences(
            liveASRPartialMillisecondsByModelID: [
                asrModelID.uuidString: 1_333,
                "not-a-uuid": 999
            ]
        )
        try require(partialWindowPreferences.liveASRPartialMillisecondsOverride(for: asrModelID) == 1_350, "Expected live ASR partial-window override to normalize to the nearest step.")
        try require(partialWindowPreferences.liveASRPartialMillisecondsByModelID.count == 1, "Expected invalid ASR partial-window override keys to be dropped.")
        partialWindowPreferences.setLiveASRPartialMillisecondsOverride(12_000, for: asrModelID)
        try require(partialWindowPreferences.liveASRPartialMillisecondsOverride(for: asrModelID) == MediaSubtitlePreferences.maximumLiveASRPartialMilliseconds, "Expected live ASR partial-window override to clamp to max.")
        partialWindowPreferences.setLiveASRPartialMillisecondsOverride(nil, for: asrModelID)
        try require(partialWindowPreferences.liveASRPartialMillisecondsOverride(for: asrModelID) == nil, "Expected live ASR partial-window override reset to remove the model key.")

        let qwenCapabilities = ModelCapabilities.speech(.qwen3ASR06B())
        let encoded = try JSONEncoder().encode(qwenCapabilities)
        let decoded = try JSONDecoder().decode(ModelCapabilities.self, from: encoded)
        try require(decoded.supportsSpeech, "Expected speech capabilities to round-trip as speech-capable.")
        try require(decoded.supportsFileSpeech, "Expected Qwen3-ASR-0.6B to support file transcription.")
        try require(decoded.supportsRealtimeSpeech, "Expected Qwen3-ASR-0.6B to support optional realtime subtitles.")
    }

    private static func checkPhase4XFoundationTypesAndPreferences() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        try require(!preferences.languageRouting.enabled, "Expected language routing to default off until the service is wired.")
        try require(preferences.languageRouting.modelVariant == .ftz, "Expected fastText ftz to be the default LID variant.")
        try require(preferences.languageRouting.shortTextMinimumCharactersLatin == 20, "Expected Latin short-text threshold to default to 20.")
        try require(preferences.languageRouting.shortTextMinimumCharactersCJK == 3, "Expected CJK short-text threshold to default to 3.")
        try require(preferences.languageRouting.lowConfidenceThreshold == 0.65, "Expected LID low-confidence threshold to default to 0.65.")
        try require(preferences.languageRouting.ocrConfidenceBoost == 0.1, "Expected OCR confidence boost to default to 0.1.")
        try require(preferences.languageRouting.ftzModelPath.isEmpty, "Expected LID FTZ model path to default empty.")
        try require(preferences.languageRouting.binModelPath.isEmpty, "Expected LID BIN model path to default empty.")
        try require(preferences.languageRouting.commandTemplate.isEmpty, "Expected LID command template to default empty.")
        try require(!preferences.speakerDiarization.enabledForFileSubtitles, "Expected speaker diarization file path to default off.")
        try require(!preferences.speakerDiarization.enabledForLiveSubtitles, "Expected live speaker diarization to default off.")
        try require(!preferences.speakerDiarization.persistSpeakerEmbeddings, "Expected speaker embeddings persistence to default off.")
        try require(SpeakerDiarizationTokenStore.tokenFileURL.lastPathComponent == "pyannote-hf-token", "Expected speaker diarization token to use the local token store.")
        try require(preferences.fastTranslation.subtitleEngine == .llm, "Expected subtitle fast translation to default to LLM.")
        try require(preferences.fastTranslation.webpageEngine == .llm, "Expected webpage fast translation to default to LLM.")
        try require(preferences.fastTranslation.textEngine == .llm, "Expected text translation to default to LLM.")
        try require(preferences.fastTranslation.modelVariant == .nllb200Distilled600M, "Expected NLLB 600M to be the default fast MT model.")
        try require(preferences.fastTranslation.fallbackPolicy == .fallbackToLLM, "Expected fast translation fallback to default to LLM.")
        try require(preferences.fastTranslation.maxConcurrentBatches == 1, "Expected fast translation concurrency to default to 1.")
        try require(!preferences.fastTranslation.forceLLM, "Expected fast translation killswitch to default off.")

        let languageRouting = LanguageRoutingPreferences(
            enabled: true,
            ftzModelPath: "  /models/lid.176.ftz  ",
            binModelPath: "  /models/lid.176.bin  ",
            shortTextMinimumCharactersLatin: 0,
            shortTextMinimumCharactersCJK: 0,
            lowConfidenceThreshold: 2,
            ocrConfidenceBoost: -1,
            commandTemplate: "  python lid.py  "
        )
        try require(languageRouting.shortTextMinimumCharactersLatin == 1, "Expected Latin threshold to clamp to at least 1.")
        try require(languageRouting.shortTextMinimumCharactersCJK == 1, "Expected CJK threshold to clamp to at least 1.")
        try require(languageRouting.lowConfidenceThreshold == 1, "Expected confidence threshold to clamp to 1.")
        try require(languageRouting.ocrConfidenceBoost == 0, "Expected OCR boost to clamp to 0.")
        try require(languageRouting.ftzModelPath == "/models/lid.176.ftz", "Expected FTZ model path to trim whitespace.")
        try require(languageRouting.binModelPath == "/models/lid.176.bin", "Expected BIN model path to trim whitespace.")
        try require(languageRouting.commandTemplate == "python lid.py", "Expected LID command template to trim whitespace.")
        try require(
            LanguageRoutingPreferences(shortTextMinimumCharactersLatin: 3).shouldSkipDetection(for: "hi"),
            "Expected short Latin text to skip LID."
        )
        try require(!LanguageRoutingPreferences().shouldSkipDetection(for: "你好世界"), "Expected non-short CJK text to allow LID.")

        let decodedLanguageRouting = try JSONDecoder().decode(LanguageRoutingPreferences.self, from: Data("""
        {
          "enabled": true,
          "modelVariant": "ftz"
        }
        """.utf8))
        try require(decodedLanguageRouting.ftzModelPath.isEmpty, "Expected older LID preferences to use an empty FTZ model path.")
        try require(decodedLanguageRouting.binModelPath.isEmpty, "Expected older LID preferences to use an empty BIN model path.")

        let speakerDiarization = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            enabledForLiveSubtitles: true,
            modelIdentifier: "  /models/pyannote/config.yaml  ",
            cacheDirectory: "  /models/hf-cache  ",
            commandTemplate: "  pyannote run  ",
            persistSpeakerEmbeddings: true
        )
        try require(speakerDiarization.modelIdentifier == "/models/pyannote/config.yaml", "Expected diarization model identifier to trim whitespace.")
        try require(speakerDiarization.cacheDirectory == "/models/hf-cache", "Expected diarization cache directory to trim whitespace.")
        try require(speakerDiarization.commandTemplate == "pyannote run", "Expected diarization command template to trim whitespace.")
        try require(!speakerDiarization.enabledForLiveSubtitles, "Live speaker diarization must remain hard-disabled before the realtime spike passes.")

        let decodedDiarization = try JSONDecoder().decode(SpeakerDiarizationPreferences.self, from: Data("""
        {
          "enabledForFileSubtitles": true,
          "enabledForLiveSubtitles": true
        }
        """.utf8))
        try require(decodedDiarization.enabledForFileSubtitles, "Expected file diarization preference to decode.")
        try require(!decodedDiarization.enabledForLiveSubtitles, "Expected live diarization decode to stay hard-disabled.")
        try require(decodedDiarization.modelIdentifier == SpeakerDiarizationPreferences.defaultModelIdentifier, "Expected older diarization preferences to use the default pyannote model.")

        let fastTranslation = FastTranslationPreferences(
            subtitleEngine: .fastMT,
            webpageEngine: .auto,
            textEngine: .fastMT,
            modelVariant: .nllb200Distilled600M,
            opusMTEnZhCT2ModelPath: "  /models/opus-ct2  ",
            nllb200Distilled600MCT2ModelPath: "  /models/nllb-ct2  ",
            maxConcurrentBatches: 99,
            forceLLM: true
        )
        try require(fastTranslation.textEngine == .fastMT, "Expected text translation engine to allow fast MT.")
        try require(fastTranslation.modelVariant == .nllb200Distilled600M, "Expected fast translation model variant to allow NLLB selection.")
        try require(fastTranslation.opusMTEnZhCT2ModelPath == "/models/opus-ct2", "Expected OPUS CT2 model path to trim whitespace.")
        try require(fastTranslation.nllb200Distilled600MCT2ModelPath == "/models/nllb-ct2", "Expected NLLB CT2 model path to trim whitespace.")
        try require(fastTranslation.maxConcurrentBatches == 8, "Expected fast translation concurrency to clamp to 8.")
        try require(fastTranslation.engineForSubtitles() == .llm, "Expected forceLLM to override subtitle engine.")
        try require(fastTranslation.engine(for: .webPageTranslate) == .llm, "Expected forceLLM to override webpage engine.")
        try require(fastTranslation.engine(for: .polish) == .llm, "Expected polish to stay on LLM even when text translation uses fast MT.")

        let decodedFastTranslation = try JSONDecoder().decode(FastTranslationPreferences.self, from: Data("""
        {
          "subtitleEngine": "auto",
          "modelVariant": "nllb200Distilled600M"
        }
        """.utf8))
        try require(decodedFastTranslation.opusMTEnZhCT2ModelPath.isEmpty, "Expected older fast MT preferences to use an empty OPUS model path.")
        try require(decodedFastTranslation.nllb200Distilled600MCT2ModelPath.isEmpty, "Expected older fast MT preferences to use an empty NLLB model path.")

        try require(LanguageCodeNormalizer.normalizedBCP47("__label__eng") == "en", "Expected fastText English label to normalize.")
        try require(LanguageCodeNormalizer.normalizedBCP47("zho_Hans") == "zh-Hans", "Expected NLLB Simplified Chinese to normalize.")
        try require(LanguageCodeNormalizer.normalizedBCP47("cmn_Hant") == "zh-Hant", "Expected Traditional Chinese alias to normalize.")
        try require(LanguageCodeNormalizer.nllbCode(for: "zh-Hans") == "zho_Hans", "Expected zh-Hans NLLB mapping.")
        try require(LanguageCodeNormalizer.argosCode(for: "zh-Hans") == "zh", "Expected zh-Hans Argos mapping.")
        try require(LanguageCodeNormalizer.asrHintCode(for: "zh-Hant") == "zh", "Expected zh-Hant ASR hint mapping.")
        let normalizedPair = LanguagePair(source: "__label__eng", target: "zho_Hans")
        try require(normalizedPair == LanguagePair(source: "en", target: "zh-Hans"), "Expected LanguagePair to normalize source and target.")

        let capabilities = ModelCapabilities(
            inputs: [.text],
            languageID: LanguageIDModelCapabilities(
                supportedLanguages: ["eng_Latn", "zho_Hans", "zh-Hant"],
                latencyMillisecondsPerKB: -10,
                source: .detected,
                confidence: 2
            ),
            speakerDiarization: SpeakerDiarizationModelCapabilities(
                supportsFile: true,
                supportsRealtime: false,
                requiresUserToken: true,
                source: .manual,
                confidence: -1
            ),
            fastTranslation: FastTranslationModelCapabilities(
                engineID: .ctranslate2,
                modelID: "  opus-mt-en-zh  ",
                supportedPairs: [
                    LanguagePair(source: "eng_Latn", target: "zho_Hans"),
                    LanguagePair(source: "en", target: "zh-Hans")
                ],
                source: .probePassed,
                confidence: 0.9
            )
        )
        try require(capabilities.supportsLanguageID, "Expected LID details to add languageID input capability.")
        try require(capabilities.supportsSpeakerDiarization, "Expected speaker details to add speakerDiarization input capability.")
        try require(capabilities.supportsFastTranslation, "Expected fast MT details to add fastTranslation input capability.")
        try require(capabilities.languageID?.supportedLanguages == ["en", "zh-Hans", "zh-Hant"], "Expected LID languages to normalize and sort.")
        try require(capabilities.languageID?.latencyMillisecondsPerKB == 0, "Expected LID latency to clamp to non-negative.")
        try require(capabilities.languageID?.confidence == 1, "Expected LID confidence to clamp to 1.")
        try require(capabilities.speakerDiarization?.confidence == 0, "Expected diarization confidence to clamp to 0.")
        try require(capabilities.fastTranslation?.modelID == "opus-mt-en-zh", "Expected fast MT model ID to trim whitespace.")
        try require(capabilities.fastTranslation?.supportedPairs.count == 1, "Expected duplicate fast MT pairs to deduplicate.")
        let decodedCapabilities = try JSONDecoder().decode(ModelCapabilities.self, from: JSONEncoder().encode(capabilities))
        try require(decodedCapabilities.supportsFastTranslation, "Expected fast MT capability to round-trip.")
        try require(decodedCapabilities.fastTranslation?.supports(LanguagePair(source: "en", target: "zh-Hans")) == true, "Expected fast MT pair support to round-trip.")

        let oldSegmentJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000301",
          "sessionID": "00000000-0000-0000-0000-000000000302",
          "index": 0,
          "startTime": 0.25,
          "originalText": "Hello",
          "sourceLanguage": "en",
          "languageConfidence": 0.92,
          "isFinal": true,
          "asrModelID": "asr-fixture",
          "translationModelID": "text-fixture"
        }
        """
        let oldSegment = try JSONDecoder().decode(SubtitleSegment.self, from: Data(oldSegmentJSON.utf8))
        try require(oldSegment.sourceLanguageDetectorModel == nil, "Expected old subtitle segments to decode without detector model.")
        try require(oldSegment.speakerID == nil, "Expected old subtitle segments to decode without speaker ID.")
        try require(oldSegment.translationEngineID == nil, "Expected old subtitle segments to decode without translation engine.")

        let enrichedSegment = SubtitleSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
            sessionID: oldSegment.sessionID,
            index: 1,
            startTime: 1,
            originalText: "World",
            sourceLanguage: "en",
            languageConfidence: 0.95,
            sourceLanguageDetectorModel: "fasttext/lid.176.ftz",
            speakerID: "spk-1",
            speakerLabel: "Speaker 1",
            speakerConfidence: 2,
            asrModelID: "asr-fixture",
            translationModelID: "text-fixture",
            translationEngineID: TranslationEngineID.llm.rawValue
        )
        try require(enrichedSegment.speakerConfidence == 1, "Expected speaker confidence to clamp to 1.")
        let decodedSegment = try JSONDecoder().decode(SubtitleSegment.self, from: JSONEncoder().encode(enrichedSegment))
        try require(decodedSegment.sourceLanguageDetectorModel == "fasttext/lid.176.ftz", "Expected detector model to round-trip.")
        try require(decodedSegment.speakerLabel == "Speaker 1", "Expected speaker label to round-trip.")
        try require(decodedSegment.translationEngineID == TranslationEngineID.llm.rawValue, "Expected translation engine ID to round-trip.")

        try require(Phase4XFixtureEnvironment.languageIDJSON == "LLMTOOLS_LID_FIXTURE_JSON", "Expected LID fixture env var name.")
        try require(Phase4XFixtureEnvironment.fastTranslationJSON == "LLMTOOLS_FAST_MT_FIXTURE_JSON", "Expected fast MT fixture env var name.")
        try require(Phase4XFixtureEnvironment.diarizationJSON == "LLMTOOLS_DIARIZATION_FIXTURE_JSON", "Expected diarization fixture env var name.")

        let lidRoot = try makeTemporaryDirectory(name: "lid-model-paths")
        defer { try? FileManager.default.removeItem(at: lidRoot) }
        let ftzModel = lidRoot.appendingPathComponent("lid.176.ftz")
        let binModel = lidRoot.appendingPathComponent("lid.176.bin")
        try Data().write(to: ftzModel)
        try Data().write(to: binModel)
        let ftzResolution = try FastTextLIDCommandRunner.commandResolution(
            preferences: LanguageRoutingPreferences(modelVariant: .ftz, ftzModelPath: ftzModel.path)
        )
        try require(ftzResolution.command.contains(ftzModel.path), "Expected explicit FTZ LID model path to be used in the command.")
        let binResolution = try FastTextLIDCommandRunner.commandResolution(
            preferences: LanguageRoutingPreferences(modelVariant: .bin, binModelPath: binModel.path)
        )
        try require(binResolution.command.contains(binModel.path), "Expected explicit BIN LID model path to be used in the command.")
    }

    private static func checkLiveMeetingTranscriptionFixtures() async throws {
        let root = try makeTemporaryDirectory(name: "live-meeting-fixture")
        defer { try? FileManager.default.removeItem(at: root) }

        let localModelID = UUID(uuidString: "00000000-0000-0000-0000-000000004001")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000004002")!
        var session = LiveMeetingSession(
            id: sessionID,
            source: .microphone,
            asrModelID: localModelID,
            asrModelName: "Fixture Local MLX",
            state: .running,
            temporaryAudioDirectory: root.appendingPathComponent("temporary-audio").path
        )
        session.startedAt = Date(timeIntervalSinceNow: -(60 * 60 + 1))
        try require(session.hasReachedLongSessionThreshold, "Expected microphone meeting session to show the 60-minute reminder without stopping.")
        try require(LiveMeetingAudioSource.allCases == [.microphone, .systemAudio, .localFile], "Meeting must support microphone, system-audio, and local-file sources without a mixed capture mode.")
        let systemAudioSession = LiveMeetingSession(
            source: .systemAudio,
            startedAt: Date(timeIntervalSinceNow: -(60 * 60 + 1)),
            asrModelID: localModelID,
            asrModelName: "Fixture Local MLX"
        )
        try require(systemAudioSession.hasReachedLongSessionThreshold, "Expected system-audio meeting sessions to retain the 60-minute reminder.")
        try require(LiveMeetingAudioSource.systemAudio.liveSubtitleCaptureSource == .systemAudio, "Expected system-audio meetings to reuse native system capture.")
        try require(LiveMeetingSpeakerCountHint.allCases.map(\.displayName) == ["Auto", "2", "3", "4", "5+"], "Expected V1 speaker-count hints.")

        let nativeSpeakerCapabilities = ModelCapabilities(
            inputs: [.speech],
            source: .manual,
            confidence: 1,
            speech: .vibeVoiceASR(source: .manual, confidence: 1)
        )
        try require(
            nativeSpeakerCapabilities.supportsMeetingCaptureSpeech
                && !nativeSpeakerCapabilities.supportsRealtimeSpeech
                && nativeSpeakerCapabilities.meetingCaptureRuntimeMode == .fileOnly,
            "A file-only native-speaker ASR such as VibeVoice must remain selectable for delayed meeting capture without becoming a Live Subtitles model."
        )
        try require(
            !LiveMeetingNativeBatchPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingNativeBatchPolicy.minimumSpeechMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.postTargetPauseMilliseconds,
                batchDurationMilliseconds: LiveMeetingNativeBatchPolicy.preferredBatchMilliseconds - 1
            ),
            "Native speaker ASR must keep a batch open before the preferred duration when there is no clear interruption."
        )
        try require(
            LiveMeetingNativeBatchPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingNativeBatchPolicy.minimumSpeechMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.clearInterruptionMilliseconds,
                batchDurationMilliseconds: 10_000
            ),
            "Native speaker ASR must flush after a clear 2.5-second audio interruption."
        )
        try require(
            !LiveMeetingNativeBatchPolicy.shouldFlush(
                speechMilliseconds: 30 * 60 * 1_000,
                trailingSilenceMilliseconds: 0,
                batchDurationMilliseconds: 30 * 60 * 1_000
            ),
            "A native logical turn must not close solely because continuous speech is long."
        )
        try require(
            !LiveMeetingNativeTechnicalWindowPolicy.shouldSeal(
                sourceDurationMilliseconds: LiveMeetingNativeTechnicalWindowPolicy.maximumInferenceWindowMilliseconds - 1
            ) && LiveMeetingNativeTechnicalWindowPolicy.shouldSeal(
                sourceDurationMilliseconds: LiveMeetingNativeTechnicalWindowPolicy.maximumInferenceWindowMilliseconds
            ),
            "Native speaker ASR must seal a bounded 120-second technical inference window without closing the logical turn."
        )
        try require(
            !LiveMeetingNativeBatchPolicy.shouldFlush(
                speechMilliseconds: 90_000,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.postTargetPauseMilliseconds - 1,
                batchDurationMilliseconds: LiveMeetingNativeBatchPolicy.preferredBatchMilliseconds
            ),
            "Native speaker ASR must wait for a reliable post-target pause instead of cutting at the preferred duration."
        )
        try require(
            LiveMeetingNativeBatchPolicy.shouldFlush(
                speechMilliseconds: 90_000,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.postTargetPauseMilliseconds,
                batchDurationMilliseconds: LiveMeetingNativeBatchPolicy.preferredBatchMilliseconds
            ),
            "Native speaker ASR must flush at the next short natural pause after the preferred duration."
        )
        try require(
            !LiveMeetingNativeBatchPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingNativeBatchPolicy.minimumSpeechMilliseconds - 1,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.clearInterruptionMilliseconds,
                batchDurationMilliseconds: LiveMeetingNativeBatchPolicy.preferredBatchMilliseconds
            ),
            "Silence-only or noise-only capture must not start a native ASR batch."
        )
        try require(
            LiveMeetingNativeBatchPolicy.shouldDiscardNoise(
                speechMilliseconds: LiveMeetingNativeBatchPolicy.minimumSpeechMilliseconds - 1,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.clearInterruptionMilliseconds
            ),
            "A sub-threshold noise burst must be discarded after a clear interruption instead of keeping the native batch open."
        )
        try require(
            !LiveMeetingNativeBatchPolicy.shouldDiscardNoise(
                speechMilliseconds: LiveMeetingNativeBatchPolicy.minimumSpeechMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingNativeBatchPolicy.clearInterruptionMilliseconds
            ),
            "A valid native speech batch must be flushed rather than discarded."
        )

        try require(
            LiveMeetingDelayedSpeakerPolicy.shouldFlushTranscript(
                speechMilliseconds: 4_000,
                trailingSilenceMilliseconds: LiveMeetingTurnSegmentationPolicy.pauseMilliseconds
            ),
            "Ordinary live ASR must flush on a natural pause without waiting for speaker stabilization."
        )
        try require(
            LiveMeetingDelayedSpeakerPolicy.stableThroughMilliseconds(
                capturedMilliseconds: 60_000,
                final: false
            ) == 30_000,
            "Delayed speaker labeling must keep only a bounded 30-second unstable tail."
        )
        try require(
            !LiveMeetingDelayedSpeakerPolicy.shouldRefreshSpeakerLabels(
                capturedMilliseconds: 59_999,
                lastAttemptMilliseconds: 0,
                labeledThroughMilliseconds: 0
            ) && LiveMeetingDelayedSpeakerPolicy.shouldRefreshSpeakerLabels(
                capturedMilliseconds: 60_000,
                lastAttemptMilliseconds: 0,
                labeledThroughMilliseconds: 0
            ),
            "Speaker labeling must start only after a complete stable window, independently of transcript flushing."
        )
        try require(
            LiveMeetingDelayedSpeakerPolicy.shouldRefreshSpeakerLabels(
                capturedMilliseconds: 10_000,
                lastAttemptMilliseconds: 0,
                labeledThroughMilliseconds: 0,
                final: true
            ),
            "Stopping must allow the final captured speaker window to be labeled immediately."
        )
        let delayedStrategy = LiveMeetingRecognitionStrategy.delayedSpeakerLabels
        try require(
            delayedStrategy.displayName.contains("Transcript first"),
            "Live ordinary ASR must expose transcript-first delayed speaker labeling as a distinct strategy."
        )
        try require(
            delayedStrategy.requiresFullSessionAudioBuffer
                && LiveMeetingRecognitionStrategy.diarizationFirst.requiresFullSessionAudioBuffer
                && !LiveMeetingRecognitionStrategy.nativeSpeakerASR.requiresFullSessionAudioBuffer
                && !LiveMeetingRecognitionStrategy.compositeSpeakerASR.requiresFullSessionAudioBuffer
                && !LiveMeetingRecognitionStrategy.transcriptOnly.requiresFullSessionAudioBuffer,
            "Only delayed diarization strategies may retain a full-session in-memory audio buffer."
        )
        try require(
            !LiveMeetingASRBackpressurePolicy.shouldStopCapture(pendingBatchCount: 1)
                && LiveMeetingASRBackpressurePolicy.shouldStopCapture(
                    pendingBatchCount: LiveMeetingASRBackpressurePolicy.maximumQueuedBatches
                ),
            "Meeting capture must stop before a slow ASR can build an unbounded in-memory batch queue."
        )

        let backToBackSlices = LiveMeetingSpeakerTurnPlanner.plan(
            turns: [
                SpeakerTurn(startTime: 0, endTime: 4, speakerID: "A", speakerLabel: "Speaker 1", confidence: 0.92),
                SpeakerTurn(startTime: 4, endTime: 8, speakerID: "B", speakerLabel: "Speaker 2", confidence: 0.91)
            ],
            processedThrough: 0,
            stableThrough: 8
        )
        try require(
            backToBackSlices.count == 2
                && backToBackSlices.map(\.speakerID) == ["A", "B"]
                && backToBackSlices[0].endTime == backToBackSlices[1].startTime,
            "Back-to-back speakers without silence must become separate ASR audio slices before transcription."
        )
        let fragmentedSameSpeakerSlices = LiveMeetingSpeakerTurnPlanner.plan(
            turns: [
                SpeakerTurn(startTime: 0, endTime: 4, speakerID: "A", confidence: 0.92),
                SpeakerTurn(startTime: 4.9, endTime: 10, speakerID: "A", confidence: 0.91),
                SpeakerTurn(startTime: 11.3, endTime: 15, speakerID: "A", confidence: 0.90)
            ],
            processedThrough: 0,
            stableThrough: 15
        )
        try require(
            fragmentedSameSpeakerSlices.count == 2
                && fragmentedSameSpeakerSlices[0].startTime == 0
                && fragmentedSameSpeakerSlices[0].endTime == 10
                && fragmentedSameSpeakerSlices[1].startTime == 11.3,
            "Sub-1.2-second VAD gaps from the same speaker must stay in one readable turn, while a longer real pause starts a new row."
        )
        let dominantOverlapSlices = LiveMeetingSpeakerTurnPlanner.plan(
            turns: [
                SpeakerTurn(startTime: 0, endTime: 8, speakerID: "A", confidence: 0.95),
                SpeakerTurn(startTime: 3, endTime: 4, speakerID: "B", confidence: 0.87)
            ],
            processedThrough: 0,
            stableThrough: 8
        )
        try require(
            dominantOverlapSlices.count == 1 && dominantOverlapSlices[0].speakerID == "A" && !dominantOverlapSlices[0].isLowConfidence,
            "Brief overlap must retain the clear primary speaker and stay as one readable turn."
        )
        let ambiguousOverlapSlices = LiveMeetingSpeakerTurnPlanner.plan(
            turns: [
                SpeakerTurn(startTime: 0, endTime: 4, speakerID: "A", confidence: 0.91),
                SpeakerTurn(startTime: 0, endTime: 4, speakerID: "B", confidence: 0.90)
            ],
            processedThrough: 0,
            stableThrough: 4
        )
        try require(
            ambiguousOverlapSlices.count == 1
                && ambiguousOverlapSlices[0].speakerID == nil
                && ambiguousOverlapSlices[0].speakerLabel == "Unknown"
                && ambiguousOverlapSlices[0].isLowConfidence,
            "Complex overlap must emit one Unknown low-confidence primary speaker in V1."
        )
        let longSpeakerSlices = LiveMeetingSpeakerTurnPlanner.plan(
            turns: [SpeakerTurn(startTime: 0, endTime: 305, speakerID: "A", confidence: 0.94)],
            processedThrough: 0,
            stableThrough: 305
        )
        try require(
            longSpeakerSlices.count == 3
                && longSpeakerSlices.allSatisfy { $0.speakerID == "A" && $0.endTime - $0.startTime <= 120 },
            "A long uninterrupted speaker turn may use bounded ASR slices while preserving one speaker identity for later paragraph collapse."
        )
        let groupedSpeakerSlice = LiveMeetingTranscriptReducer.groupSpeakerSlice(
            [
                LiveMeetingSegment(index: 0, startTime: 0, endTime: 1.8, text: "第一句", speakerID: "A"),
                LiveMeetingSegment(index: 1, startTime: 1.8, endTime: 4, text: "第二句", speakerID: "A")
            ],
            slice: LiveMeetingSpeakerAudioSlice(
                startTime: 0,
                endTime: 4,
                speakerID: "A",
                speakerLabel: "Speaker 1",
                confidence: 0.93
            ),
            index: 0
        )
        try require(
            groupedSpeakerSlice?.text == "第一句 第二句"
                && groupedSpeakerSlice?.startTime == 0
                && groupedSpeakerSlice?.endTime == 4
                && groupedSpeakerSlice?.speakerID == "A",
            "Technical ASR segments inside one diarized speaker slice must render as one meeting transcript row."
        )

        let wavFixture = root.appendingPathComponent("speaker-slice.wav")
        let pcmFixture = Data(repeating: 0x2A, count: 16_000 * 2 * 2)
        try LiveMeetingAudioStorage.writePCM16WAV(data: pcmFixture, to: wavFixture)
        let decodedPCM = try LiveMeetingAudioStorage.readPCM16WAV(at: wavFixture)
        let secondHalf = LiveMeetingAudioStorage.slicePCM16(
            decodedPCM.data,
            sampleRate: decodedPCM.sampleRate,
            startTime: 1,
            endTime: 2
        )
        try require(
            decodedPCM.sampleRate == 16_000 && decodedPCM.data == pcmFixture && secondHalf.count == 16_000 * 2,
            "Meeting speaker-turn WAV parsing and PCM slicing must preserve the exact local audio samples."
        )
        try require(
            !LiveMeetingTurnSegmentationPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingTurnSegmentationPolicy.minimumSpeechMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingTurnSegmentationPolicy.pauseMilliseconds - 1
            ),
            "Meeting transcription must keep an active turn open before the natural-pause threshold."
        )
        try require(
            LiveMeetingTurnSegmentationPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingTurnSegmentationPolicy.minimumSpeechMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingTurnSegmentationPolicy.pauseMilliseconds
            ),
            "Meeting transcription must flush a complete turn after the natural-pause threshold."
        )
        try require(
            !LiveMeetingTurnSegmentationPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingTurnSegmentationPolicy.preferredBatchMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingTurnSegmentationPolicy.postTargetPauseMilliseconds - 1
            ) && LiveMeetingTurnSegmentationPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingTurnSegmentationPolicy.preferredBatchMilliseconds,
                trailingSilenceMilliseconds: LiveMeetingTurnSegmentationPolicy.postTargetPauseMilliseconds
            ),
            "A long ordinary-ASR batch must use the next short pause instead of waiting for a full natural-pause threshold."
        )
        try require(
            LiveMeetingTurnSegmentationPolicy.shouldFlush(
                speechMilliseconds: LiveMeetingTurnSegmentationPolicy.maximumContinuousSpeechMilliseconds,
                trailingSilenceMilliseconds: 0
            ),
            "Ordinary meeting ASR must flush continuous speech at the 30-second latency ceiling."
        )
        let longTurnContext = ASRTranscriptionContext(
            mode: .realtime,
            maximumTokens: 1_024,
            chunkDurationSeconds: 30
        )
        try require(longTurnContext.maximumTokens == 1_024 && longTurnContext.chunkDurationSeconds == 30, "Expected transcript-only meeting ASR to retain a bounded local inference window.")

        var segments = [
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 1.2, text: "原始第一句", speakerID: "A", speakerLabel: "Speaker 1"),
            LiveMeetingSegment(index: 1, startTime: 1.4, endTime: 2.5, text: "原始第二句", speakerID: "B", speakerLabel: "Speaker 2"),
            LiveMeetingSegment(index: 2, startTime: 2.6, endTime: 2.9, text: "短句", speakerID: "B", speakerLabel: "Speaker 2")
        ]
        var speakers = [
            LiveMeetingSpeaker(id: "A", label: "Speaker 1"),
            LiveMeetingSpeaker(id: "B", label: "Speaker 2")
        ]
        let editedID = segments[0].id
        try require(LiveMeetingTranscriptReducer.editText(id: editedID, text: "用户修订后的第一句", segments: &segments), "Expected finalized transcript text editing.")
        try require(segments[0].userEditedText, "Expected transcript text edit marker.")

        LiveMeetingTranscriptReducer.applySpeakerTurns(
            [
                SpeakerTurn(startTime: 0, endTime: 1.2, speakerID: "B", speakerLabel: "Model Label", confidence: 0.9),
                SpeakerTurn(startTime: 1.4, endTime: 2.9, speakerID: "B", speakerLabel: "Model Label", confidence: 0.91)
            ],
            to: &segments,
            speakers: &speakers
        )
        try require(segments[0].text == "用户修订后的第一句", "Delayed speaker labels must never overwrite edited transcript text.")
        try require(segments[0].speakerID == "B", "Expected delayed speaker labels to backfill the existing row.")
        try require(segments[1].speakerID == "B", "Expected diarization to assign primary speaker.")

        var stabilizationSegments = [
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 10, text: "稳定内容"),
            LiveMeetingSegment(index: 1, startTime: 30, endTime: 40, text: "仍在稳定窗口内")
        ]
        var stabilizationSpeakers: [LiveMeetingSpeaker] = []
        LiveMeetingTranscriptReducer.applySpeakerTurns(
            [
                SpeakerTurn(startTime: 0, endTime: 10, speakerID: "A"),
                SpeakerTurn(startTime: 30, endTime: 40, speakerID: "B")
            ],
            to: &stabilizationSegments,
            speakers: &stabilizationSpeakers,
            through: 30
        )
        try require(
            stabilizationSegments[0].speakerID == "A" && stabilizationSegments[1].speakerID == nil,
            "Delayed diarization must backfill only rows outside the unstable speaker window."
        )

        var sequentialTurnSegments = [
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 8, text: "连续讲话的完整内容", state: .lowConfidence)
        ]
        var sequentialTurnSpeakers: [LiveMeetingSpeaker] = []
        LiveMeetingTranscriptReducer.applySpeakerTurns(
            [
                SpeakerTurn(startTime: 0, endTime: 2.4, speakerID: "A", speakerLabel: "Speaker 1"),
                SpeakerTurn(startTime: 2.4, endTime: 7.2, speakerID: "A", speakerLabel: "Speaker 1"),
                SpeakerTurn(startTime: 7.2, endTime: 8, speakerID: "B", speakerLabel: "Speaker 2")
            ],
            to: &sequentialTurnSegments,
            speakers: &sequentialTurnSpeakers
        )
        try require(sequentialTurnSegments[0].speakerID == "A" && sequentialTurnSegments[0].state == .final, "Sequential diarization turns must choose the dominant speaker instead of becoming Unknown.")

        var alternatingSpeakerSplitSpeakers: [LiveMeetingSpeaker] = []
        let alternatingSpeakerSplit = LiveMeetingTranscriptReducer.splitSegmentBySpeakerTurns(
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 8, text: "甲方提问乙方回答", state: .final),
            turns: [
                SpeakerTurn(startTime: 0, endTime: 3.8, speakerID: "A", speakerLabel: "Speaker 1", confidence: 0.92),
                SpeakerTurn(startTime: 3.8, endTime: 8, speakerID: "B", speakerLabel: "Speaker 2", confidence: 0.91)
            ],
            speakers: &alternatingSpeakerSplitSpeakers,
            through: 8
        )
        try require(
            alternatingSpeakerSplit.count == 2
                && alternatingSpeakerSplit.map(\.speakerID) == ["A", "B"]
                && alternatingSpeakerSplitSpeakers.map(\.id) == ["A", "B"],
            "A transcript-first row spanning two alternating speakers must be split at diarization boundaries instead of assigning one dominant speaker."
        )

        var dominantSpeakerSplitSpeakers: [LiveMeetingSpeaker] = []
        let dominantSpeakerSplit = LiveMeetingTranscriptReducer.splitSegmentBySpeakerTurns(
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 8, text: "主讲人持续发言", state: .final),
            turns: [
                SpeakerTurn(startTime: 0, endTime: 7, speakerID: "A", speakerLabel: "Speaker 1", confidence: 0.92),
                SpeakerTurn(startTime: 7, endTime: 8, speakerID: "A", speakerLabel: "Speaker 1", confidence: 0.91)
            ],
            speakers: &dominantSpeakerSplitSpeakers,
            through: 8
        )
        try require(
            dominantSpeakerSplit.count == 1 && dominantSpeakerSplit[0].speakerID == nil,
            "A row containing only one confirmed speaker must stay intact for normal overlap assignment."
        )

        var dominantOverlapSegments = [
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 8, text: "主讲人内容", state: .lowConfidence)
        ]
        var dominantOverlapSpeakers: [LiveMeetingSpeaker] = []
        LiveMeetingTranscriptReducer.applySpeakerTurns(
            [
                SpeakerTurn(startTime: 0, endTime: 8, speakerID: "A", speakerLabel: "Speaker 1"),
                SpeakerTurn(startTime: 3, endTime: 4, speakerID: "B", speakerLabel: "Speaker 2")
            ],
            to: &dominantOverlapSegments,
            speakers: &dominantOverlapSpeakers
        )
        try require(dominantOverlapSegments[0].speakerID == "A" && dominantOverlapSegments[0].state == .final, "A clear primary speaker must survive brief overlap instead of becoming Unknown.")

        let longSpeakerText = String(repeating: "长", count: 160)
        let collapsedTurns = LiveMeetingTranscriptReducer.collapseAdjacentSpeakerSegments(
            [
                LiveMeetingSegment(index: 0, startTime: 0, endTime: 4, text: longSpeakerText, speakerID: "A", speakerLabel: "Speaker 1"),
                LiveMeetingSegment(index: 1, startTime: 4.1, endTime: 8, text: longSpeakerText, speakerID: "A", speakerLabel: "Speaker 1")
            ],
            speakers: [LiveMeetingSpeaker(id: "A", label: "Speaker 1")]
        )
        try require(collapsedTurns.count == 1 && collapsedTurns[0].text.count > 220, "Confirmed adjacent speaker turns must be allowed to form a readable long paragraph rather than retaining the old short subtitle cap.")
        let recentTurns = LiveMeetingTranscriptReducer.collapseAdjacentSpeakerSegments(
            [
                LiveMeetingSegment(index: 0, startTime: 0, endTime: 4, text: "稳定段", speakerID: "A", speakerLabel: "Speaker 1"),
                LiveMeetingSegment(index: 1, startTime: 4.1, endTime: 8, text: "仍在标签稳定窗口", speakerID: "A", speakerLabel: "Speaker 1")
            ],
            speakers: [LiveMeetingSpeaker(id: "A", label: "Speaker 1")],
            collapseThrough: 6
        )
        try require(recentTurns.count == 2, "Live speaker grouping must not collapse a row that still extends into the stabilization window.")
        var editedCollapseSegments = [
            LiveMeetingSegment(index: 0, startTime: 0, endTime: 4, text: "用户编辑", speakerID: "A", speakerLabel: "Speaker 1"),
            LiveMeetingSegment(index: 1, startTime: 4.1, endTime: 8, text: "后续内容", speakerID: "A", speakerLabel: "Speaker 1")
        ]
        let editedCollapseID = editedCollapseSegments[0].id
        try require(LiveMeetingTranscriptReducer.editText(id: editedCollapseID, text: "用户编辑后的内容", segments: &editedCollapseSegments), "Expected edited grouping fixture.")
        let protectedEditedTurns = LiveMeetingTranscriptReducer.collapseAdjacentSpeakerSegments(
            editedCollapseSegments,
            speakers: [LiveMeetingSpeaker(id: "A", label: "Speaker 1")]
        )
        try require(protectedEditedTurns.count == 2 && protectedEditedTurns[0].text == "用户编辑后的内容", "Speaker grouping must preserve user-edited rows without merging or rewriting them.")

        LiveMeetingTranscriptReducer.applySpeakerTurns(
            [
                SpeakerTurn(startTime: 1.4, endTime: 2.5, speakerID: "A", confidence: 0.92),
                SpeakerTurn(startTime: 1.45, endTime: 2.4, speakerID: "B", confidence: 0.9)
            ],
            to: &segments,
            speakers: &speakers
        )
        try require(segments[1].speakerLabel == "Unknown" && segments[1].state == .lowConfidence, "Overlap must render a single Unknown/low-confidence primary speaker in V1.")

        try require(LiveMeetingTranscriptReducer.renameSpeaker(id: "B", name: "王工", speakers: &speakers), "Expected speaker rename.")
        try require(LiveMeetingTranscriptReducer.mergeSpeaker(sourceID: "A", into: "B", speakers: &speakers, segments: &segments), "Expected speaker merge.")
        try require(speakers.first(where: { $0.id == "A" })?.mergedIntoSpeakerID == "B", "Expected merge overlay to retain source speaker ID.")
        try require(segments[0].text == "用户修订后的第一句", "Speaker merge must preserve user-edited transcript text.")

        let beforeFinalize = segments.map(\.text)
        let finalized = LiveMeetingTranscriptReducer.finalize(segments, speakers: speakers)
        try require(finalized.first?.text == "用户修订后的第一句", "Manual finalization must preserve transcript edits.")
        try require(finalized.first?.state == .final, "Manual finalization must only clean completed segments.")
        try require(beforeFinalize.contains("用户修订后的第一句"), "Finalize fixture must not rerun ASR.")

        var notes: MeetingNoteState? = MeetingNoteState(
            summary: "中文摘要",
            decisions: ["采用本地方案"],
            actionItems: ["补充检查"],
            openQuestions: ["是否需要更多模型"],
            topics: ["本地转写"],
            sourceSegmentCount: finalized.count,
            generationState: .completed,
            chunkCount: 3
        )
        LiveMeetingTranscriptReducer.markNotesStale(&notes, reason: "文本已编辑")
        try require(notes?.isStale == true && notes?.chunkCount == 3, "Expected chunked Chinese notes to become stale after transcript changes.")
        let cancelledFinalize = finalized
        let cancelledNotes = notes
        try require(cancelledFinalize == finalized && cancelledNotes == notes, "Cancelling finalize/notes must preserve current transcript and notes.")
        let finalizationCancellation = Task<Void, Error> {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
        }
        finalizationCancellation.cancel()
        do {
            _ = try await finalizationCancellation.value
            throw CheckError("Expected finalization fixture task cancellation.")
        } catch is CancellationError {
        }
        try require(finalized == cancelledFinalize, "Cancelled finalization must not replace the existing transcript.")
        let notesCancellation = Task<Void, Error> {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
        }
        notesCancellation.cancel()
        do {
            _ = try await notesCancellation.value
            throw CheckError("Expected notes fixture task cancellation.")
        } catch is CancellationError {
        }
        try require(notes == cancelledNotes, "Cancelled notes generation must not delete the existing notes.")

        session.state = .stopped
        session.stoppedAt = Date()
        let markdown = LiveMeetingMarkdownExporter.markdown(session: session, segments: finalized, speakers: speakers, notes: notes)
        try require(markdown.hasPrefix("# 会议纪要\n\n## 元信息"), "Expected fixed Chinese Markdown export template.")
        try require(markdown.contains("## 关键决策") && markdown.contains("## 待办事项") && markdown.contains("## 完整转写"), "Expected all fixed meeting-note sections.")
        try require(markdown.contains("用户修订后的第一句"), "Export must use edited finalized transcript text.")
        let exportName = LiveMeetingMarkdownExporter.baseFileName(session: session, date: Date(timeIntervalSince1970: 1_720_000_000))
        try require(exportName.hasPrefix("meeting-notes-") && exportName.count == "meeting-notes-YYYYMMDD-HHMM".count, "Expected deterministic microphone export name.")
        var fileSession = session
        fileSession.source = .localFile
        fileSession.sourceFileName = "客户访谈.mp4"
        fileSession.sourceMediaKind = .video
        let fileExportName = LiveMeetingMarkdownExporter.baseFileName(session: fileSession, date: Date(timeIntervalSince1970: 1_720_000_000))
        try require(fileExportName.hasPrefix("客户访谈-meeting-notes-"), "Expected deterministic Local File export name.")

        let temporaryAudioRoot = root.appendingPathComponent("temporary-audio", isDirectory: true)
        let sessionAudioDirectory = try LiveMeetingAudioStorage.makeTemporaryDirectory(
            sessionID: session.id,
            rootDirectory: temporaryAudioRoot,
            ownerProcessIdentifier: Int32.max
        )
        let sessionAudioFile = sessionAudioDirectory.appendingPathComponent("private-audio.wav")
        let ownerMarkerFile = sessionAudioDirectory.appendingPathComponent(".owner.json")
        try LiveMeetingAudioStorage.writePCM16WAV(data: Data(repeating: 0, count: 320), to: sessionAudioFile)
        let temporaryAudioRootPermissions = try posixPermissions(at: temporaryAudioRoot)
        let sessionAudioDirectoryPermissions = try posixPermissions(at: sessionAudioDirectory)
        let sessionAudioFilePermissions = try posixPermissions(at: sessionAudioFile)
        let ownerMarkerFilePermissions = try posixPermissions(at: ownerMarkerFile)
        try require(temporaryAudioRootPermissions == 0o700, "Meeting temporary-audio root must be owner-only.")
        try require(sessionAudioDirectoryPermissions == 0o700, "Meeting session audio directory must be owner-only.")
        try require(sessionAudioFilePermissions == 0o600, "Meeting temporary WAV files must be owner-only.")
        try require(ownerMarkerFilePermissions == 0o600, "Meeting temporary-audio owner markers must be owner-only.")

        let recoveryDirectory = root.appendingPathComponent("recovery", isDirectory: true)
        let recoveryFile = recoveryDirectory.appendingPathComponent("recovery-draft.json")
        let draftStore = LiveMeetingRecoveryStore(
            fileURL: recoveryFile,
            temporaryAudioRootURL: temporaryAudioRoot
        )
        let draft = LiveMeetingRecoveryDraft(session: session, segments: finalized, speakers: speakers, notes: notes)
        try draftStore.save(draft)
        let recoveryDirectoryPermissions = try posixPermissions(at: recoveryDirectory)
        let recoveryFilePermissions = try posixPermissions(at: recoveryFile)
        try require(recoveryDirectoryPermissions == 0o700, "Meeting recovery directory must be owner-only.")
        try require(recoveryFilePermissions == 0o600, "Meeting recovery draft must be owner-only.")
        let recoveryJSON = try String(contentsOf: recoveryFile, encoding: .utf8)
        try require(!recoveryJSON.contains(root.path), "Recovery storage must strip temporary-audio paths before encoding the draft.")
        let restored = try draftStore.loadDiscardingTemporaryAudio()
        try require(restored?.segments.first?.text == "用户修订后的第一句", "Recovery draft must preserve edited transcript text.")
        try require(restored?.speakers.first(where: { $0.id == "A" })?.mergedIntoSpeakerID == "B", "Recovery draft must preserve speaker merge edits.")
        try require(restored?.session.temporaryAudioDirectory == nil, "Recovery drafts must never persist a temporary-audio path.")
        try require(!FileManager.default.fileExists(atPath: sessionAudioDirectory.path), "Loading a crash-recovery draft must discard matching temporary audio.")

        let recreatedSessionAudioDirectory = try LiveMeetingAudioStorage.makeTemporaryDirectory(
            sessionID: session.id,
            rootDirectory: temporaryAudioRoot,
            ownerProcessIdentifier: Int32.max
        )
        try draftStore.save(draft)
        try draftStore.delete()
        let deletedDraft = try draftStore.load()
        try require(deletedDraft == nil, "Recovery draft delete must remove the local draft.")
        try require(!FileManager.default.fileExists(atPath: recreatedSessionAudioDirectory.path), "Deleting a recovery draft must discard matching temporary audio.")

        let staleSessionID = UUID()
        let freshSessionID = UUID()
        let staleDirectory = temporaryAudioRoot.appendingPathComponent(staleSessionID.uuidString, isDirectory: true)
        let freshDirectory = temporaryAudioRoot.appendingPathComponent(freshSessionID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staleDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: freshDirectory, withIntermediateDirectories: true)
        let liveOwnerDirectory = try LiveMeetingAudioStorage.makeTemporaryDirectory(
            sessionID: UUID(),
            rootDirectory: temporaryAudioRoot,
            ownerProcessIdentifier: getpid()
        )
        let deadOwnerDirectory = try LiveMeetingAudioStorage.makeTemporaryDirectory(
            sessionID: UUID(),
            rootDirectory: temporaryAudioRoot,
            ownerProcessIdentifier: Int32.max
        )
        let unrelatedDirectory = temporaryAudioRoot.appendingPathComponent("keep-me", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: true)
        let oldDate = Date(timeIntervalSinceNow: -(48 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: staleDirectory.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelatedDirectory.path)
        try LiveMeetingAudioStorage.deleteOrphanedTemporaryDirectories(
            olderThan: Date(timeIntervalSinceNow: -(24 * 60 * 60)),
            rootDirectory: temporaryAudioRoot
        )
        try require(!FileManager.default.fileExists(atPath: staleDirectory.path), "Old UUID-named meeting audio directories must be removed as orphans.")
        try require(FileManager.default.fileExists(atPath: freshDirectory.path), "Recent meeting audio directories must not be removed as orphans.")
        try require(FileManager.default.fileExists(atPath: liveOwnerDirectory.path), "Orphan cleanup must preserve a meeting directory owned by a live process.")
        try require(!FileManager.default.fileExists(atPath: deadOwnerDirectory.path), "Orphan cleanup must remove a meeting directory owned by a dead process.")
        try require(FileManager.default.fileExists(atPath: unrelatedDirectory.path), "Orphan cleanup must ignore non-session directories.")

        let diagnostics = LiveMeetingDiagnostics(
            session: session,
            transcriptSegmentCount: finalized.count,
            speakerCount: 1,
            recoveryDraftState: "deleted"
        )
        let diagnosticsJSON = String(data: try JSONEncoder().encode(diagnostics), encoding: .utf8) ?? ""
        try require(!diagnosticsJSON.contains("用户修订后的第一句") && !diagnosticsJSON.contains("王工") && !diagnosticsJSON.contains(root.path), "Meeting diagnostics must redact transcript, speaker names, and paths.")

        setenv("LLMTOOLS_MEETING_DIARIZATION_FIXTURE_JSON", """
        {"turns":[{"startTime":0,"endTime":1,"speakerID":"FIXTURE_A","confidence":0.93}],"modelID":"fixture-diart","runtimeSource":"fixtureJSON"}
        """, 1)
        defer { unsetenv("LLMTOOLS_MEETING_DIARIZATION_FIXTURE_JSON") }
        let diarization = LiveMeetingDiarizationService()
        let health = await diarization.health()
        try require(health.isReady && health.source == .fixtureJSON, "Expected fixture meeting diarization to be ready without a real runtime.")
        let diarizationResult = try await diarization.diarize(audioURL: root.appendingPathComponent("missing.wav"))
        try require(diarizationResult.turns.first?.speakerID == "FIXTURE_A", "Expected fixture delayed-speaker contract.")
        unsetenv("LLMTOOLS_MEETING_DIARIZATION_FIXTURE_JSON")

        let fileDiarizationWAV = root.appendingPathComponent("local-only-diarization.wav")
        try writePCM16WAV(url: fileDiarizationWAV, duration: 0.2)
        let localOnlyPreferences = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            commandTemplate: #"/usr/bin/env | /usr/bin/grep HF_HUB_OFFLINE > /dev/null && /bin/echo '{"turns":[]}'"#
        )
        let localOnlyResult = try await SpeakerDiarizationService().diarize(
            audioURL: fileDiarizationWAV,
            preferences: localOnlyPreferences
        )
        try require(localOnlyResult.turns.isEmpty, "Expected local-only diarization environment guard to execute.")

        let arbitraryMeetingCommand = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            commandTemplate: "/bin/echo '{\"turns\":[]}'"
        )
        do {
            _ = try await LiveMeetingDiarizationService().diarize(
                audioURL: fileDiarizationWAV,
                preferences: arbitraryMeetingCommand
            )
            throw CheckError("Expected meeting diarization to reject arbitrary configured commands.")
        } catch let error as LiveMeetingDiarizationError {
            try require(error.localizedDescription.contains("不使用自定义"), "Expected meeting diarization to preserve the local-only command boundary.")
        }

        let localModel = ModelDescriptor(
            id: localModelID,
            name: "Local Notes",
            sourcePath: root.appendingPathComponent("local-model"),
            format: .mlx,
            sizeClass: "4b",
            role: .default,
            contextLength: 4096,
            capabilities: .textOnly(source: .manual)
        )
        let remoteModel = ModelDescriptor(
            name: "Remote Notes",
            sourcePath: URL(fileURLWithPath: "/remote"),
            format: .openAICompatible,
            sizeClass: "remote",
            role: .default,
            contextLength: 4096,
            providerConfiguration: ProviderConfiguration(
                providerID: .customOpenAICompatible,
                apiStyle: .openAICompatible,
                baseURL: URL(string: "https://example.invalid"),
                modelID: "remote"
            )
        )
        try FileManager.default.createDirectory(at: localModel.sourcePath, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: localModel.sourcePath.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: localModel.sourcePath.appendingPathComponent("tokenizer.json"))
        FileManager.default.createFile(
            atPath: localModel.sourcePath.appendingPathComponent("model.safetensors").path,
            contents: Data()
        )
        let runner = StubRunner(output: """
        ## 摘要
        本地中文纪要
        ## 关键决策
        - 保持 local-only
        ## 待办事项
        - 补充测试
        ## 开放问题
        - 无
        ## 讨论主题
        - 会议转写
        """)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        try await engine.addModelDescriptorForTesting(localModel)
        try await engine.addModelDescriptorForTesting(remoteModel)
        try await engine.updatePreferences { preferences in
            preferences.liveMeeting.notesModelID = localModelID
            preferences.liveMeeting.defaultAudioSource = .systemAudio
        }
        let meetingPreferences = await engine.registry().preferences.liveMeeting
        try require(meetingPreferences.notesModelID == localModelID && meetingPreferences.defaultAudioSource == .systemAudio, "Expected independent meeting settings to persist a local notes model and system-audio default.")
        let generatedNotes = try await engine.generateLocalMeetingNotes(segments: finalized, speakers: speakers, modelID: localModelID)
        try require(generatedNotes.summary == "本地中文纪要" && generatedNotes.language == "zh-Hans", "Expected Chinese notes from the local model only.")
        do {
            _ = try await engine.generateLocalMeetingNotes(segments: finalized, speakers: speakers, modelID: remoteModel.id)
            throw CheckError("Expected remote meeting-note provider to be rejected.")
        } catch LiveMeetingError.remoteTextModelForbidden {
        }
        try await engine.updatePreferences { preferences in
            preferences.liveMeeting.notesModelID = remoteModel.id
        }
        let sanitizedMeetingPreferences = await engine.registry().preferences.liveMeeting
        try require(sanitizedMeetingPreferences.notesModelID == nil, "Meeting settings must reject remote note models.")
        try await engine.updatePreferences { preferences in
            preferences.speakerDiarization.commandTemplate = "/bin/echo '{\"turns\":[]}'"
        }
        do {
            _ = try await engine.diarizeMeetingFile(at: fileDiarizationWAV)
            throw CheckError("Expected meeting diarization to reject arbitrary configured commands.")
        } catch SpeakerDiarizationError.runtimeMissing(let message) {
            try require(message.contains("does not use arbitrary"), "Expected explicit local-only meeting diarization rejection.")
        }
    }

    private static func checkLanguageDetectionFixture() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureURL = root.appendingPathComponent("lid-fixture.json")
        try Data("""
        {
          "type": "result",
          "language": "__label__eng",
          "confidence": 0.91,
          "model": "fixture/lid.176.ftz",
          "latencyMilliseconds": 4
        }
        """.utf8).write(to: fixtureURL)
        setenv(Phase4XFixtureEnvironment.languageIDJSON, fixtureURL.path, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.languageIDJSON)
        }

        let preferences = LanguageRoutingPreferences(
            enabled: true,
            lowConfidenceThreshold: 0.65
        )
        let service = LanguageDetectionService()
        let detected = try await service.detect(
            text: "This is long enough for language detection.",
            preferences: preferences
        )
        try require(detected.language == "en", "Expected LID fixture language to normalize to en.")
        try require(detected.rawLanguage == "__label__eng", "Expected LID fixture raw language to be preserved.")
        try require(detected.confidence == 0.91, "Expected LID fixture confidence to decode.")
        try require(detected.detectorModel == "fixture/lid.176.ftz", "Expected LID fixture model to decode.")
        try require(detected.source == .fixtureJSON, "Expected LID fixture source.")
        try require(detected.isReliable, "Expected LID fixture to be reliable above threshold.")

        let shortText = try await service.detect(
            text: "hi",
            preferences: LanguageRoutingPreferences(enabled: true, shortTextMinimumCharactersLatin: 3)
        )
        try require(shortText.language == nil, "Expected short LID text to skip detection.")
        try require(!shortText.isReliable, "Expected skipped short text to be unreliable.")

        let health = await service.health(
            preferences: preferences,
            sampleText: "Bonjour, this sentence is intentionally long enough."
        )
        try require(health.status == .ready, "Expected LID fixture health to be ready.")
        try require(health.source == .fixtureJSON, "Expected LID fixture health source.")
        try require(health.sampleResult?.language == "en", "Expected LID fixture health sample result.")

        setenv(Phase4XFixtureEnvironment.languageIDJSON, """
        {"type":"result","language":"zho_Hans","confidence":0.88,"model":"inline-fixture"}
        """, 1)
        let inlineFixture = try await LanguageDetectionService().detect(
            text: "这是一段足够长的中文。",
            preferences: preferences
        )
        try require(inlineFixture.language == "zh-Hans", "Expected inline LID fixture JSON to decode and normalize.")

        unsetenv(Phase4XFixtureEnvironment.languageIDJSON)
        let scriptURL = root.appendingPathComponent("blocking-lid-sidecar.zsh")
        let pidURL = root.appendingPathComponent("lid-pid")
        let requestURL = root.appendingPathComponent("lid-request-started")
        let blockFIFOURL = root.appendingPathComponent("lid-block.fifo")
        guard mkfifo(blockFIFOURL.path, 0o600) == 0 else {
            throw CheckError("Could not create language detection blocking FIFO.")
        }
        try """
        #!/bin/zsh
        print -r -- $$ > "$1"
        print -r -- '{"protocol":"llmtools.lid/v1","type":"ready","model":"lifecycle-fixture"}'
        while IFS= read -r request; do
            print -r -- started > "$2"
            IFS= read -r blocked < "$3"
        done
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        let escapedLIDArguments = [scriptURL, pidURL, requestURL, blockFIFOURL].map {
            "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let blockingPreferences = LanguageRoutingPreferences(
            enabled: true,
            shortTextMinimumCharactersLatin: 1,
            commandTemplate: "/bin/zsh \(escapedLIDArguments.joined(separator: " "))"
        )
        let blockingService = LanguageDetectionService()
        let blockingTask = Task {
            try await blockingService.detect(text: "blocked language request", preferences: blockingPreferences)
        }
        let requestDeadline = Date(timeIntervalSinceNow: 2)
        while !FileManager.default.fileExists(atPath: requestURL.path), Date() < requestDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            await blockingService.stop()
            throw CheckError("Expected the language detection request to block.")
        }
        blockingTask.cancel()
        let processIdentifier = try requireNonNil(
            Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)),
            "Language detection fixture did not record a valid PID."
        )
        let exitDeadline = Date(timeIntervalSinceNow: 4)
        while Darwin.kill(processIdentifier, 0) == 0, Date() < exitDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if Darwin.kill(processIdentifier, 0) == 0 { await blockingService.stop() }
        try require(
            Darwin.kill(processIdentifier, 0) != 0,
            "Cancelling language detection must terminate its blocked sidecar."
        )
        guard case .failure = await blockingTask.result else {
            throw CheckError("Cancelled language detection must fail instead of returning a stale result.")
        }
    }

    private static func checkLanguageRoutingCallerWiring() async throws {
        setenv(Phase4XFixtureEnvironment.languageIDJSON, """
        {"type":"result","language":"__label__eng","confidence":0.93,"model":"fixture/lid.176.ftz"}
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.languageIDJSON)
        }

        try await checkLanguageRoutingTextCaller()
        try await checkLanguageRoutingWebpageCaller()
        try await checkLanguageRoutingOCRCaller()
        try await checkLanguageRoutingSubtitleCaller()
    }

    private static func checkLanguageRoutingTextCaller() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = StubRunner(format: .mlx)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let modelDirectory = try makeMLXModelDirectory(root: root)
        let model = try await engine.addModel(from: modelDirectory)
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.defaultTranslationTarget = "auto"
            preferences.languageRouting = LanguageRoutingPreferences(
                enabled: true,
                useForTextTasks: true
            )
        }

        let routedResult = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "This sentence is long enough for language detection.",
                targetLanguage: "auto"
            ),
            modelID: model.id,
            persistHistory: false
        )
        try require(routedResult.sourceLanguage == "en", "Expected text result to expose detected source language.")
        var requests = await runner.recordedRequests()
        try require(requests.last?.sourceLanguage == "en", "Expected text caller to receive detected source language.")

        _ = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "This sentence is long enough for language detection.",
                sourceLanguage: "ja",
                targetLanguage: "auto"
            ),
            modelID: model.id,
            persistHistory: false
        )
        requests = await runner.recordedRequests()
        try require(requests.last?.sourceLanguage == "ja", "Expected explicit text source language to win over LID.")
    }

    private static func checkLanguageRoutingWebpageCaller() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = StubRunner(output: """
        [
          {"id":"s1","translation":"网页译文。"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMLXModelDirectory(root: root))
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.languageRouting = LanguageRoutingPreferences(
                enabled: true,
                useForWebpage: true
            )
        }
        _ = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "lid-webpage",
                sourceLanguage: "auto",
                targetLanguage: "zh-Hans",
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "This webpage sentence is long enough for language detection.")
                ]
            ),
            modelID: model.id
        )
        let requests = await runner.recordedRequests()
        try require(requests.first?.task == .webPageTranslate, "Expected webpage caller to keep webpage translation task.")
        try require(requests.first?.sourceLanguage == "en", "Expected webpage caller to receive detected source language.")

        _ = try await engine.translateWebPageSegments(
            payload: WebPageTranslateSegmentsPayload(
                jobID: "script-lid-webpage",
                sourceLanguage: "auto",
                targetLanguage: "zh-Hans",
                segments: [
                    WebPageTranslationSegment(segmentID: "s1", text: "設定を変更すると、次回の翻訳から新しいモデルが使われます。")
                ]
            ),
            modelID: model.id
        )
        let scriptRequests = await runner.recordedRequests()
        try require(scriptRequests.last?.sourceLanguage == "ja", "Expected webpage script heuristic to detect Japanese source language.")
    }

    private static func checkLanguageRoutingOCRCaller() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = StubVisionRunner(output: "This OCR sentence is long enough for language detection.")
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.openAICompatible: runner]
        )
        let model = try await engine.addProviderModel(
            providerID: .siliconFlow,
            name: "Vision provider",
            modelID: "gpt-4o",
            apiKey: "test-key",
            baseURL: "https://api.siliconflow.cn/v1",
            contextLength: 8192
        )
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.defaultTranslationTarget = "auto"
            preferences.ocr.modelID = model.id
            preferences.languageRouting = LanguageRoutingPreferences(
                enabled: true,
                useForOCR: true
            )
        }
        let result = try await engine.runOCR(
            image: OCRImageInput(
                data: Data("fake-image".utf8),
                mimeType: "image/png",
                contentHash: "h-lid-ocr"
            ),
            mode: .extractThenTranslate,
            modelID: model.id,
            persistHistory: false
        )
        try require(result.sourceLanguage == "en", "Expected OCR result to expose detected source language.")
        let requests = await runner.recordedRequests()
        try require(requests.last?.task == .translate, "Expected OCR extract-then-translate to call text translation.")
        try require(requests.last?.sourceLanguage == "en", "Expected OCR translation caller to receive detected source language.")
    }

    private static func checkLanguageRoutingSubtitleCaller() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let runner = StubRunner(output: """
        [
          {"id":"\(segmentID.uuidString)","translation":"字幕译文。"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMLXModelDirectory(root: root))
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.mediaSubtitles.defaultTargetLanguage = "auto"
            preferences.languageRouting = LanguageRoutingPreferences(
                enabled: true,
                useForSubtitles: true
            )
        }
        let translated = try await engine.translateSubtitleSegments(
            [
                SubtitleSegment(
                    id: segmentID,
                    sessionID: UUID(),
                    index: 0,
                    startTime: 0,
                    endTime: 1,
                    originalText: "This subtitle sentence is long enough for language detection.",
                    asrModelID: "asr-fixture"
                )
            ],
            targetLanguage: "auto",
            modelID: model.id
        )
        try require(translated.first?.sourceLanguage == "en", "Expected subtitle segment to receive detected source language.")
        try require(translated.first?.sourceLanguageDetectorModel == "fixture/lid.176.ftz", "Expected subtitle segment to record detector model.")
        try require(translated.first?.languageConfidence == 0.93, "Expected subtitle segment to record detector confidence.")
    }

    private static func checkSpeakerDiarizationFixtureAndMapping() async throws {
        setenv(Phase4XFixtureEnvironment.diarizationJSON, """
        {
          "model": "fixture-pyannote",
          "turns": [
            {"start": 0.0, "end": 1.4, "speakerID": "SPEAKER_A", "confidence": 0.91},
            {"start": 1.4, "end": 3.0, "speakerID": "SPEAKER_B", "confidence": 0.87}
          ],
          "latencyMilliseconds": 12
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.diarizationJSON)
        }

        let preferences = SpeakerDiarizationPreferences(enabledForFileSubtitles: true)
        let health = await SpeakerDiarizationService().health(preferences: preferences)
        try require(health.status == .ready, "Expected diarization fixture health to be ready.")
        try require(health.source == .fixtureJSON, "Expected diarization fixture health source.")
        try require(health.tokenPresent, "Expected diarization fixture to bypass token requirements.")

        let result = try await SpeakerDiarizationService().diarize(
            audioURL: URL(fileURLWithPath: "/tmp/nonexistent-fixture.wav"),
            preferences: preferences
        )
        try require(result.modelID == "fixture-pyannote", "Expected diarization fixture model ID.")
        try require(result.turns.count == 2, "Expected two diarization fixture turns.")

        let sessionID = UUID()
        let mapped = SpeakerTurnMapper.apply(
            turns: result.turns,
            to: [
                SubtitleSegment(id: UUID(), sessionID: sessionID, index: 0, startTime: 0.1, endTime: 1.0, originalText: "first", asrModelID: "asr"),
                SubtitleSegment(id: UUID(), sessionID: sessionID, index: 1, startTime: 1.6, endTime: 2.5, originalText: "second", asrModelID: "asr")
            ]
        )
        try require(mapped.map(\.speakerID) == ["SPEAKER_A", "SPEAKER_B"], "Expected speaker IDs to map by midpoint.")
        try require(mapped.map(\.speakerLabel) == ["Speaker 1", "Speaker 2"], "Expected stable speaker labels.")
        try require(mapped.map(\.speakerConfidence) == [0.91, 0.87], "Expected speaker confidences to map.")
        try require(SpeakerTurnMapper.speakerCount(in: mapped) == 2, "Expected speaker count from mapped segments.")
    }

    private static func checkSubtitleExportWithSpeakers() throws {
        let sessionID = UUID()
        let segments = [
            SubtitleSegment(
                id: UUID(),
                sessionID: sessionID,
                index: 0,
                startTime: 0,
                endTime: 1,
                originalText: "Hello.",
                translatedText: "你好。",
                speakerID: "speaker-a",
                speakerLabel: "Speaker 1",
                asrModelID: "asr"
            ),
            SubtitleSegment(
                id: UUID(),
                sessionID: sessionID,
                index: 1,
                startTime: 1,
                endTime: 2,
                originalText: "World.",
                translatedText: "世界。",
                speakerID: "speaker-b",
                speakerLabel: "Speaker 2",
                asrModelID: "asr"
            )
        ]
        let srt = try SubtitleExporter.render(segments: segments, format: .srt, mode: .bilingual)
        try require(srt.contains("Speaker 1: Hello.\n你好。"), "Expected speaker label in bilingual SRT.")
        let vtt = try SubtitleExporter.render(segments: segments, format: .vtt, mode: .translated)
        try require(vtt.contains("Speaker 2: 世界。"), "Expected speaker label in translated VTT.")
        let txt = try SubtitleExporter.render(
            segments: segments,
            format: .txt,
            mode: .original,
            options: SubtitleExportOptions(includeSpeakerLabels: true, speakerFormat: .bracketed)
        )
        try require(txt.contains("[Speaker 1] Hello."), "Expected bracketed speaker label in TXT.")
        let markdown = try SubtitleExporter.render(
            segments: segments,
            format: .markdown,
            mode: .bilingual,
            options: SubtitleExportOptions(includeSpeakerLabels: false)
        )
        try require(!markdown.contains("Speaker 1:"), "Expected export option to hide speaker labels.")
    }

    private static func checkSpeakerDiarizationFailureMessageSanitization() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelConfigURL = root.appendingPathComponent("pyannote-config.yaml")
        try Data("pipeline:\n  name: pyannote.audio.pipelines.SpeakerDiarization\n".utf8).write(to: modelConfigURL)
        let bundledResolution = try SpeakerDiarizationCommandRunner.commandResolution(
            preferences: SpeakerDiarizationPreferences(
                enabledForFileSubtitles: true,
                modelIdentifier: modelConfigURL.path
            )
        )
        try require(bundledResolution.command.contains("--model {diarization_model}"), "Expected bundled diarization command to pass the configured model.")

        let wavURL = root.appendingPathComponent("speaker-failure.wav")
        try writePCM16WAV(url: wavURL, duration: 0.2)
        let preferences = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            commandTemplate: #"/bin/sh -c 'printf "%s\n" "Traceback (most recent call last):" "requests.exceptions.ConnectionError: [Errno 65] No route to host thrown while requesting HEAD https://huggingface.co/pyannote/speaker-diarization-3.1/resolve/main/config.yaml" >&2; exit 1'"#
        )

        do {
            _ = try await SpeakerDiarizationService().diarize(audioURL: wavURL, preferences: preferences)
            try require(false, "Expected pyannote command failure to throw.")
        } catch SpeakerDiarizationError.runtimeFailed(let message) {
            try require(message.contains("pyannote model is not ready"), "Expected pyannote setup failure to be productized.")
            try require(message.contains("Settings > Models > Model Settings > Speaker Diarization"), "Expected failure to point to model settings.")
            try require(!message.contains("Traceback"), "Expected Python traceback to be hidden.")
            try require(!message.contains("requests.exceptions"), "Expected low-level requests error to be hidden.")
        }
    }

    private static func checkSpeakerDiarizationCommandDrainsLargeStderr() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wavURL = root.appendingPathComponent("speaker-pipe-drain.wav")
        try writePCM16WAV(url: wavURL, duration: 0.2)
        let preferences = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            commandTemplate: #"/usr/bin/python3 -c 'import pathlib, sys; sys.stderr.write("x" * 200000); pathlib.Path(sys.argv[1]).write_text("{\"model\":\"pipe-fixture\",\"turns\":[{\"start\":0.0,\"end\":0.2,\"speakerID\":\"SPEAKER_A\"}]}", encoding="utf-8")' {output_json}"#
        )

        let result = try await SpeakerDiarizationService().diarize(
            audioURL: wavURL,
            preferences: preferences
        )
        try require(result.modelID == "pipe-fixture", "Expected diarization command result after large stderr output.")
        try require(result.turns.first?.speakerID == "SPEAKER_A", "Expected pipe-drain command output to be parsed.")
    }

    private static func checkSpeakerDiarizationCommandCancellation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wavURL = root.appendingPathComponent("speaker-cancellation.wav")
        try writePCM16WAV(url: wavURL, duration: 0.2)
        let preferences = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            commandTemplate: "exec /bin/sleep 10"
        )
        let task = Task {
            try await SpeakerDiarizationService().diarize(
                audioURL: wavURL,
                preferences: preferences
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancellationStarted = Date()
        task.cancel()
        do {
            _ = try await task.value
            try require(false, "Expected speaker diarization cancellation to throw.")
        } catch is CancellationError {
        }
        try require(
            Date().timeIntervalSince(cancellationStarted) < 2,
            "Speaker diarization cancellation must terminate the local process promptly."
        )
    }

    private static func checkSpeakerDiarizationRejectsTokenInCommand() throws {
        let secret = "hf-secret-must-not-reach-argv"
        let previousToken = ProcessInfo.processInfo.environment["PYANNOTE_AUTH_TOKEN"]
        setenv("PYANNOTE_AUTH_TOKEN", secret, 1)
        defer {
            if let previousToken {
                setenv("PYANNOTE_AUTH_TOKEN", previousToken, 1)
            } else {
                unsetenv("PYANNOTE_AUTH_TOKEN")
            }
        }
        let preferences = SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            commandTemplate: "/bin/echo {hf_token}"
        )
        do {
            _ = try SpeakerDiarizationCommandRunner.commandResolution(preferences: preferences)
            throw CheckError("Expected diarization token placeholder to be rejected.")
        } catch let error as SpeakerDiarizationError {
            try require(error.localizedDescription.contains("PYANNOTE_AUTH_TOKEN"), "Expected command error to direct callers to the environment variable.")
            try require(!error.localizedDescription.contains(secret), "Diarization command error must not reveal the saved token.")
        }
    }

    private static func checkProcessOutputCollectorDrainsLargePipes() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            "import sys; sys.stdout.write('o' * 200000); sys.stdout.flush(); sys.stderr.write('e' * 200000); sys.stderr.flush()"
        ]
        let result = try await ProcessOutputCollector.run(process, maximumCapturedBytes: 64 * 1_024)
        try require(result.terminationStatus == 0, "Expected large-output fixture process to exit successfully.")
        try require(result.standardOutput.count == 64 * 1_024, "Expected stdout capture to retain only the bounded tail.")
        try require(result.standardError.count == 64 * 1_024, "Expected stderr capture to retain only the bounded tail.")
        try require(result.standardOutput.allSatisfy { $0 == 0x6f }, "Expected stdout tail contents.")
        try require(result.standardError.allSatisfy { $0 == 0x65 }, "Expected stderr tail contents.")
    }

    private static func checkSpeakerDiarizationFilePipeline() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        setenv(Phase4XFixtureEnvironment.diarizationJSON, """
        {
          "model": "fixture-pyannote",
          "turns": [
            {"start": 0.0, "end": 0.8, "speakerID": "SPEAKER_A"},
            {"start": 0.8, "end": 1.8, "speakerID": "SPEAKER_B"}
          ]
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.diarizationJSON)
        }

        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        )
        let senseDirectory = root.appendingPathComponent("SenseVoiceSmall", isDirectory: true)
        try FileManager.default.createDirectory(at: senseDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: senseDirectory.appendingPathComponent("model.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: senseDirectory.appendingPathComponent("tokens.txt").path, contents: Data("stub".utf8))
        let speechModel = try await engine.addModel(from: senseDirectory)
        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.fileASRModelID = speechModel.id
            preferences.mediaSubtitles.realtimeASRModelID = speechModel.id
            preferences.mediaSubtitles.senseVoiceCommandTemplate = #"/bin/echo '{"segments":[{"start":0,"end":0.7,"text":"first speaker","language":"en"},{"start":1.0,"end":1.5,"text":"second speaker","language":"en"}]}'"#
            preferences.speakerDiarization.enabledForFileSubtitles = true
        }
        let wavURL = root.appendingPathComponent("speaker-fixture.wav")
        try writePCM16WAV(url: wavURL, duration: 1.6)
        let fileResult = try await engine.transcribeMediaFile(at: wavURL, modelID: speechModel.id)
        try require(fileResult.segments.map(\.speakerLabel) == ["Speaker 1", "Speaker 2"], "Expected file subtitle pipeline to map speaker labels.")
        try require(fileResult.diagnostics.speakerCount == 2, "Expected diagnostics to record speaker count.")
        try require(fileResult.diagnostics.diarizationModelID == "fixture-pyannote", "Expected diagnostics to record diarization model ID.")
        let srt = try await engine.exportSubtitleSegments(fileResult.segments, format: .srt, mode: .original)
        try require(srt.contains("Speaker 1: first speaker"), "Expected exported file subtitles to include speaker labels.")

        unsetenv(Phase4XFixtureEnvironment.diarizationJSON)
        try await engine.updatePreferences { preferences in
            preferences.speakerDiarization.commandTemplate = "/bin/false"
        }
        let failedDiarization = try await engine.transcribeMediaFile(at: wavURL, modelID: speechModel.id)
        try require(failedDiarization.segments.map(\.originalText) == ["first speaker", "second speaker"], "Diarization failure must not drop transcript segments.")
        try require(failedDiarization.diagnostics.diarizationErrorCode != nil, "Expected diarization failure to be recorded in diagnostics.")
        try require(failedDiarization.diagnostics.diarizationErrorMessage?.isEmpty == false, "Expected diarization failure message to be recorded in diagnostics.")

        let generatedFiles = (FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]) ?? []
        try require(
            !generatedFiles.contains { $0.localizedCaseInsensitiveContains("embedding") },
            "Speaker embeddings must not be persisted by the fixture pipeline."
        )
    }

    private static func checkFastMTFixtureRoundTrip() async throws {
        setenv(Phase4XFixtureEnvironment.fastTranslationJSON, """
        {
          "protocol": "llmtools.fastmt/v1",
          "type": "translation",
          "engine": "ctranslate2",
          "model": "fixture-opus-mt-en-zh",
          "supportedPairs": [{"source":"en","target":"zh-Hans"}],
          "segments": [
            {"id":"seg-2","translation":"第二段"},
            {"id":"seg-1","translation":"第一段"}
          ],
          "latencyMilliseconds": 9
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        }

        let service = FastTranslationCommandRunner()
        let preferences = FastTranslationPreferences(subtitleEngine: .fastMT)
        let health = await service.probe(preferences: preferences)
        try require(health.status == .ready, "Expected fast MT fixture health to be ready.")
        try require(health.source == .fixtureJSON, "Expected fast MT fixture health source.")
        try require(health.engineID == .ctranslate2, "Expected fast MT fixture engine.")
        try require(health.modelID == "fixture-opus-mt-en-zh", "Expected fast MT fixture model.")
        try require(health.supportedPairs == [LanguagePair(source: "en", target: "zh-Hans")], "Expected fast MT fixture supported pair.")
        let pairs = await service.supportedPairs(preferences: preferences)
        try require(pairs == [LanguagePair(source: "en", target: "zh-Hans")], "Expected fast MT fixture supported pairs.")
        let translated = try await service.translate(
            batch: [
                FastTranslationSegment(id: "seg-1", text: "Hello."),
                FastTranslationSegment(id: "seg-2", text: "World.")
            ],
            pair: LanguagePair(source: "en", target: "zh-Hans"),
            preferences: preferences
        )
        try require(translated.map(\.id) == ["seg-1", "seg-2"], "Expected fast MT fixture to preserve request order.")
        try require(translated.map(\.translation) == ["第一段", "第二段"], "Expected fast MT fixture translations.")
        do {
            _ = try await service.translate(
                batch: [FastTranslationSegment(id: "seg-1", text: "Hello.")],
                pair: LanguagePair(source: "ja", target: "zh-Hans"),
                preferences: preferences
            )
            throw CheckError("Expected unsupported fast MT fixture pair to throw.")
        } catch FastTranslationError.unsupportedLanguagePair {
        }
    }

    private static func checkFastMTDegenerateOutputGuard() async throws {
        setenv(Phase4XFixtureEnvironment.fastTranslationJSON, """
        {
          "type": "translation",
          "engine": "ctranslate2",
          "model": "fixture-degenerate-fastmt",
          "supportedPairs": [{"source":"en","target":"zh-Hans"}],
          "segments": [{"id":"text","translation":"注注注注注注注注注注注注注注注注注注注注注注注注注注注注注注"}],
          "latencyMilliseconds": 5
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        }

        let service = FastTranslationCommandRunner()
        do {
            _ = try await service.translate(
                batch: [FastTranslationSegment(id: "text", text: "Note")],
                pair: LanguagePair(source: "en", target: "zh-Hans"),
                preferences: FastTranslationPreferences(textEngine: .fastMT)
            )
            throw CheckError("Expected degenerate fast MT fixture output to throw.")
        } catch FastTranslationError.runtimeFailed(let message) {
            try require(message.contains("degenerate repeated output"), "Expected degenerate fast MT error message.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = StubRunner(output: "LLM fallback translation")
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMLXModelDirectory(root: root))
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.fastTranslation.textEngine = .fastMT
            preferences.fastTranslation.fallbackPolicy = .fallbackToLLM
        }
        let fallback = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "Note",
                sourceLanguage: "en",
                targetLanguage: "zh-Hans"
            ),
            modelID: model.id
        )
        try require(fallback.text == "LLM fallback translation", "Expected degenerate fast MT output to fall back to LLM.")
        let fallbackRequestCount = await runner.generatedRequestCount()
        try require(fallbackRequestCount == 1, "Expected degenerate fast MT fallback to use LLM runner.")
    }

    private static func checkFastMTPreferencesMigration() throws {
        let empty = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        try require(empty.fastTranslation.modelVariant == .nllb200Distilled600M, "Expected older preferences to default fast MT model to NLLB 600M.")
        try require(empty.fastTranslation.commandTemplates.ctranslate2.contains("llmtools-fastmt-sidecar.py") || empty.fastTranslation.commandTemplates.ctranslate2.contains("{sidecar}"), "Expected default CTranslate2 fast MT command template.")
        try require(empty.fastTranslation.commandTemplates.argos.contains("--engine argos"), "Expected default Argos fast MT command template.")

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data("""
        {
          "fastTranslation": {
            "subtitleEngine": "auto",
            "webpageEngine": "fastMT",
            "textEngine": "fastMT",
            "modelVariant": "nllb200Distilled600M",
            "fallbackPolicy": "showError",
            "commandTemplates": {
              "ctranslate2": "  ct2-sidecar  ",
              "argos": "  argos-sidecar  ",
              "generic": "  generic-sidecar  "
            },
            "maxConcurrentBatches": 99,
            "forceLLM": true
          }
        }
        """.utf8))
        try require(decoded.fastTranslation.subtitleEngine == .auto, "Expected subtitle fast MT engine to decode.")
        try require(decoded.fastTranslation.webpageEngine == .fastMT, "Expected webpage fast MT engine to decode.")
        try require(decoded.fastTranslation.textEngine == .fastMT, "Expected text translation engine to decode.")
        try require(decoded.fastTranslation.modelVariant == .nllb200Distilled600M, "Expected NLLB fast MT model variant to decode.")
        try require(decoded.fastTranslation.fallbackPolicy == .showError, "Expected fast MT fallback policy to decode.")
        try require(decoded.fastTranslation.commandTemplates.ctranslate2 == "ct2-sidecar", "Expected CTranslate2 command to trim.")
        try require(decoded.fastTranslation.commandTemplates.argos == "argos-sidecar", "Expected Argos command to trim.")
        try require(decoded.fastTranslation.commandTemplates.generic == "generic-sidecar", "Expected generic command to trim.")
        try require(decoded.fastTranslation.maxConcurrentBatches == 8, "Expected fast MT concurrency to clamp to 8.")
        try require(decoded.fastTranslation.engineForSubtitles() == .llm, "Expected forceLLM to override subtitle auto routing.")
        try require(decoded.fastTranslation.engine(for: .webPageTranslate) == .llm, "Expected forceLLM to override webpage fast MT routing.")
        try require(decoded.fastTranslation.engine(for: .translate) == .llm, "Expected forceLLM to override text translation fast MT routing.")
        try require(decoded.fastTranslation.engine(for: .summarize) == .llm, "Expected summary to stay on LLM.")

        let nllbRoot = try makeTemporaryDirectory(name: "nllb-200-distilled-600m-ct2-int8")
        defer { try? FileManager.default.removeItem(at: nllbRoot) }
        setenv("LLMTOOLS_FASTMT_NLLB_600M_MODEL", nllbRoot.path, 1)
        defer { unsetenv("LLMTOOLS_FASTMT_NLLB_600M_MODEL") }
        let nllbResolution = try FastTranslationCommandRunner.commandResolution(
            preferences: FastTranslationPreferences(modelVariant: .nllb200Distilled600M)
        )
        try require(nllbResolution.command.contains(nllbRoot.path), "Expected NLLB fast MT selection to resolve the NLLB model path.")

        let explicitNLLBRoot = try makeTemporaryDirectory(name: "explicit-nllb-200-distilled-600m-ct2-int8")
        defer { try? FileManager.default.removeItem(at: explicitNLLBRoot) }
        let explicitNLLBResolution = try FastTranslationCommandRunner.commandResolution(
            preferences: FastTranslationPreferences(
                modelVariant: .nllb200Distilled600M,
                nllb200Distilled600MCT2ModelPath: explicitNLLBRoot.path
            )
        )
        try require(
            explicitNLLBResolution.command.contains(explicitNLLBRoot.path),
            "Expected explicit NLLB fast MT model path to be used in the command."
        )

        let explicitOPUSRoot = try makeTemporaryDirectory(name: "explicit-opus-mt-en-zh-ct2")
        defer { try? FileManager.default.removeItem(at: explicitOPUSRoot) }
        let explicitOPUSResolution = try FastTranslationCommandRunner.commandResolution(
            preferences: FastTranslationPreferences(
                modelVariant: .opusMTEnZh,
                opusMTEnZhCT2ModelPath: explicitOPUSRoot.path
            )
        )
        try require(
            explicitOPUSResolution.command.contains(explicitOPUSRoot.path),
            "Expected explicit OPUS fast MT model path to be used in the command."
        )
    }

    private static func checkTranslationRoutingDecisionTable() throws {
        let pair = LanguagePair(source: "en", target: "zh-Hans")
        let supported = [pair]
        let auto = FastTranslationPreferences(subtitleEngine: .auto, webpageEngine: .auto)
        let explicitLLM = TranslationRoutingService.decide(
            surface: .subtitle,
            preferences: auto,
            pair: pair,
            supportedPairs: supported,
            detectedConfidence: 0.99,
            lowConfidenceThreshold: 0.65,
            explicitEngineID: .llm
        )
        try require(explicitLLM.engineID == .llm && explicitLLM.reason == "explicitEngine", "Expected explicit LLM route to win.")

        let autoFast = TranslationRoutingService.decide(
            surface: .subtitle,
            preferences: auto,
            pair: pair,
            supportedPairs: supported,
            detectedConfidence: 0.99,
            lowConfidenceThreshold: 0.65
        )
        try require(autoFast.usesFastMT && autoFast.reason == "autoFastMT", "Expected high-confidence supported auto route to use fast MT.")

        let lowConfidence = TranslationRoutingService.decide(
            surface: .subtitle,
            preferences: auto,
            pair: pair,
            supportedPairs: supported,
            detectedConfidence: 0.4,
            lowConfidenceThreshold: 0.65
        )
        try require(lowConfidence.engineID == .llm && lowConfidence.reason == "lowConfidence", "Expected low-confidence auto route to use LLM.")

        let unsupported = TranslationRoutingService.decide(
            surface: .webpage,
            preferences: auto,
            pair: LanguagePair(source: "ja", target: "zh-Hans"),
            supportedPairs: supported,
            detectedConfidence: 0.99,
            lowConfidenceThreshold: 0.65
        )
        try require(unsupported.engineID == .llm && unsupported.reason == "unsupportedLanguagePair", "Expected unsupported auto pair to use LLM.")

        let forced = TranslationRoutingService.decide(
            surface: .subtitle,
            preferences: FastTranslationPreferences(subtitleEngine: .fastMT),
            pair: pair,
            supportedPairs: [],
            detectedConfidence: nil,
            lowConfidenceThreshold: 0.65
        )
        try require(forced.usesFastMT && forced.reason == "preferenceFastMT", "Expected explicit fast MT preference to route fast.")

        let textFast = TranslationRoutingService.decide(
            surface: .text,
            preferences: FastTranslationPreferences(textEngine: .fastMT),
            pair: pair,
            supportedPairs: supported,
            detectedConfidence: 0.99,
            lowConfidenceThreshold: 0.65
        )
        try require(textFast.usesFastMT, "Expected text translation fast MT route to be allowed.")
        let nonTranslateLocked = FastTranslationPreferences(textEngine: .fastMT)
        try require(nonTranslateLocked.engine(for: .polish) == .llm, "Expected non-translation text tasks to stay locked to LLM.")
    }

    private static func checkTextTranslateFastMTPipeline() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        setenv(Phase4XFixtureEnvironment.fastTranslationJSON, """
        {
          "type": "translation",
          "engine": "ctranslate2",
          "model": "fixture-text-fastmt",
          "supportedPairs": [{"source":"en","target":"zh-Hans"}],
          "segments": [{"id":"text","translation":"文本快速译文"}],
          "latencyMilliseconds": 5
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        }
        let runner = StubRunner(output: "LLM polished")
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMLXModelDirectory(root: root))
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.fastTranslation.textEngine = .fastMT
            preferences.fastTranslation.fallbackPolicy = .showError
        }
        let translated = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "Hello text translation.",
                sourceLanguage: "en",
                targetLanguage: "zh-Hans"
            ),
            modelID: model.id
        )
        try require(translated.text == "文本快速译文", "Expected text translate to use fast MT.")
        try require(translated.modelName == "Fast MT (CTranslate2)", "Expected text fast MT model display name.")
        let fastTextRequestCount = await runner.generatedRequestCount()
        try require(fastTextRequestCount == 0, "Expected text fast MT path to avoid LLM runner.")

        let polished = try await engine.run(
            request: TaskRequest(task: .polish, inputText: "Hello text polishing."),
            modelID: model.id
        )
        try require(polished.text == "LLM polished", "Expected polish to keep using LLM runner.")
        let polishedRequestCount = await runner.generatedRequestCount()
        try require(polishedRequestCount == 1, "Expected only non-translation text task to use LLM runner.")
    }

    private static func checkPersistentSidecarCancellationInterruptsBlockedRequest() async throws {
        let root = try makeTemporaryDirectory(name: "persistent-sidecar-stop")
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("blocking-sidecar.zsh")
        let pidURL = root.appendingPathComponent("pid")
        let requestURL = root.appendingPathComponent("request-started")
        let blockFIFOURL = root.appendingPathComponent("block.fifo")
        guard mkfifo(blockFIFOURL.path, 0o600) == 0 else {
            throw CheckError("Could not create persistent sidecar blocking FIFO.")
        }
        try """
        #!/bin/zsh
        print -r -- $$ > "$1"
        print -r -- '{"protocol":"llmtools.fastmt/v1","type":"ready","engine":"customCommand","model":"lifecycle-fixture","available":true,"supportedPairs":[{"source":"en","target":"zh-Hans"}]}'
        while IFS= read -r request; do
            print -r -- started > "$2"
            IFS= read -r blocked < "$3"
        done
        """.write(to: scriptURL, atomically: true, encoding: .utf8)

        let escaped = [scriptURL, pidURL, requestURL, blockFIFOURL].map {
            "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let runner = FastTranslationCommandRunner()
        let preferences = FastTranslationPreferences(
            commandTemplates: FastTranslationCommandTemplates(
                ctranslate2: "",
                argos: "",
                generic: "/bin/zsh \(escaped.joined(separator: " "))"
            )
        )
        let task = Task {
            try await runner.translate(
                batch: [FastTranslationSegment(id: "blocked", text: "blocked request")],
                pair: LanguagePair(source: "en", target: "zh-Hans"),
                preferences: preferences
            )
        }
        let requestDeadline = Date(timeIntervalSinceNow: 2)
        while !FileManager.default.fileExists(atPath: requestURL.path), Date() < requestDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            await runner.stop()
            throw CheckError("Expected the persistent sidecar request to block.")
        }

        task.cancel()
        let pidText = try String(contentsOf: pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let processIdentifier = Int32(pidText) else {
            throw CheckError("Persistent sidecar fixture did not record a valid PID.")
        }
        let exitDeadline = Date(timeIntervalSinceNow: 4)
        while Darwin.kill(processIdentifier, 0) == 0, Date() < exitDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try require(
            Darwin.kill(processIdentifier, 0) != 0,
            "Cancelling FastTranslation must terminate its blocked sidecar."
        )
        guard case .failure = await task.result else {
            throw CheckError("Blocked sidecar request must fail after the process stops.")
        }
    }

    private static func checkSubtitleFastMTPipeline() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        setenv(Phase4XFixtureEnvironment.fastTranslationJSON, """
        {
          "type": "translation",
          "engine": "ctranslate2",
          "model": "fixture-opus-mt-en-zh",
          "supportedPairs": [{"source":"en","target":"zh-Hans"}],
          "segments": [{"id":"\(segmentID.uuidString)","translation":"你好，快速翻译。"}],
          "latencyMilliseconds": 7
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        }
        let runner = StubRunner(output: """
        [
          {"id":"\(segmentID.uuidString)","translation":"你好，LLM 回退。"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMLXModelDirectory(root: root))
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.fastTranslation.subtitleEngine = .fastMT
            preferences.fastTranslation.fallbackPolicy = .showError
        }
        let sourceSegment = SubtitleSegment(
            id: segmentID,
            sessionID: UUID(),
            index: 0,
            startTime: 0,
            endTime: 1,
            originalText: "Hello fast translation.",
            sourceLanguage: "en",
            languageConfidence: 0.99,
            asrModelID: "asr-fixture"
        )
        let fastTranslated = try await engine.translateSubtitleSegments([sourceSegment], targetLanguage: "zh-Hans", modelID: model.id)
        try require(fastTranslated.first?.translatedText == "你好，快速翻译。", "Expected subtitle fast MT fixture translation.")
        try require(fastTranslated.first?.translationEngineID == TranslationEngineID.ctranslate2.rawValue, "Expected subtitle fast MT engine metadata.")
        try require(fastTranslated.first?.translationModelID == "fixture-opus-mt-en-zh", "Expected subtitle fast MT model metadata.")
        let fastMTRequestCount = await runner.generatedRequestCount()
        try require(fastMTRequestCount == 0, "Expected fast MT subtitle path to avoid LLM runner.")

        let vtt = try await engine.exportSubtitleSegments(fastTranslated, format: .vtt, mode: .translated)
        try require(vtt.contains("NOTE Translation engine: ctranslate2; model: fixture-opus-mt-en-zh"), "Expected VTT export metadata for fast MT.")
        let markdown = try await engine.exportSubtitleSegments(fastTranslated, format: .markdown, mode: .translated)
        try require(markdown.contains("translationEngine: ctranslate2"), "Expected Markdown front-matter translation engine.")
        try require(markdown.contains("translationModel: fixture-opus-mt-en-zh"), "Expected Markdown front-matter translation model.")
        let srt = try await engine.exportSubtitleSegments(fastTranslated, format: .srt, mode: .translated)
        try require(srt.hasPrefix("# Translation engine: ctranslate2; model: fixture-opus-mt-en-zh"), "Expected SRT metadata header.")

        unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        try await engine.updatePreferences { preferences in
            preferences.fastTranslation.subtitleEngine = .fastMT
            preferences.fastTranslation.modelVariant = .opusMTEnZh
            preferences.fastTranslation.fallbackPolicy = .fallbackToLLM
        }
        let llmFallback = try await engine.translateSubtitleSegments([sourceSegment], targetLanguage: "ja", modelID: model.id)
        try require(llmFallback.first?.translatedText == "你好，LLM 回退。", "Expected unsupported fast MT runtime to fall back to LLM.")
        try require(llmFallback.first?.translationEngineID == TranslationEngineID.llm.rawValue, "Expected fallback translation engine metadata to be LLM.")
        let fallbackRequestCount = await runner.generatedRequestCount()
        try require(fallbackRequestCount == 1, "Expected fallback path to use LLM runner once.")
    }

    private static func checkWebPageFastMTRouting() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        setenv(Phase4XFixtureEnvironment.fastTranslationJSON, """
        {
          "type": "translation",
          "engine": "ctranslate2",
          "model": "fixture-web-fastmt",
          "supportedPairs": [{"source":"en","target":"zh-Hans"}],
          "segments": [{"id":"web-1","translation":"网页快速译文"}],
          "latencyMilliseconds": 6
        }
        """, 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        }
        let runner = StubRunner(output: """
        [
          {"id":"web-1","translation":"网页 LLM 回退"}
        ]
        """)
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMLXModelDirectory(root: root))
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = model.id
            preferences.fastTranslation.webpageEngine = .fastMT
            preferences.fastTranslation.fallbackPolicy = .showError
        }
        let payload = WebPageTranslateSegmentsPayload(
            jobID: "web-fastmt",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            translationEngine: .fastMT,
            segments: [
                WebPageTranslationSegment(segmentID: "web-1", text: "Hello webpage.", textHash: "h-web-1")
            ]
        )
        let fastResult = try await engine.translateWebPageSegments(payload: payload, modelID: model.id)
        try require(fastResult.translations.first?.translation == "网页快速译文", "Expected webpage fast MT fixture translation.")
        try require(fastResult.translationEngineID == TranslationEngineID.ctranslate2.rawValue, "Expected webpage fast MT engine metadata.")
        try require(fastResult.translationModelID == "fixture-web-fastmt", "Expected webpage fast MT model metadata.")
        try require(fastResult.detectedSourceLanguage == "en", "Expected webpage source language metadata.")
        try require(fastResult.elapsedMilliseconds != nil, "Expected webpage elapsed metadata.")
        let fastRequestCount = await runner.generatedRequestCount()
        try require(fastRequestCount == 0, "Expected webpage fast MT path to avoid LLM runner.")

        unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        try await engine.updatePreferences { preferences in
            preferences.fastTranslation.webpageEngine = .fastMT
            preferences.fastTranslation.modelVariant = .opusMTEnZh
            preferences.fastTranslation.fallbackPolicy = .fallbackToLLM
        }
        let fallbackPayload = WebPageTranslateSegmentsPayload(
            jobID: "web-fastmt-fallback",
            sourceLanguage: "en",
            targetLanguage: "ja",
            translationEngine: .fastMT,
            segments: [
                WebPageTranslationSegment(segmentID: "web-1", text: "Hello webpage.", textHash: "h-web-1")
            ]
        )
        let fallback = try await engine.translateWebPageSegments(payload: fallbackPayload, modelID: model.id)
        try require(fallback.translations.first?.translation == "网页 LLM 回退", "Expected webpage fast MT failure to fall back to LLM.")
        try require(fallback.translationEngineID == TranslationEngineID.llm.rawValue, "Expected webpage fallback engine metadata.")
        let fallbackCount = await runner.generatedRequestCount()
        try require(fallbackCount == 1, "Expected webpage fallback to use LLM runner once.")
    }

    private static func checkTextTaskModePreferencesAndPrompts() throws {
        let json = """
        {
          "defaultSummaryMode": "meetingNotes",
          "defaultExplanationMode": "errorDiagnosis",
          "defaultTodoExtractionMode": "table"
        }
        """
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        try require(preferences.defaultSummaryMode == .meetingNotes, "Expected summary mode preference to decode.")
        try require(preferences.defaultExplanationMode == .errorDiagnosis, "Expected explanation mode preference to decode.")
        try require(preferences.defaultTodoExtractionMode == .table, "Expected TODO mode preference to decode.")
        try require(preferences.defaultTranslationQuality == .natural, "Expected missing translation quality to default to natural.")

        let qualityPreferences = try JSONDecoder().decode(AppPreferences.self, from: Data("""
        {
          "defaultTranslationQuality": "technical"
        }
        """.utf8))
        try require(qualityPreferences.defaultTranslationQuality == .technical, "Expected translation quality preference to decode.")

        let technicalTranslationPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .translate, inputText: "Open the API reference."),
            preferences: qualityPreferences
        )
        try require(technicalTranslationPrompt.contains("Preserve technical terminology"), "Expected technical translation quality to affect normal translation prompt.")
        let routedTranslationPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(
                task: .translate,
                inputText: "Open the API reference.",
                sourceLanguage: "en",
                targetLanguage: "zh-Hans"
            ),
            preferences: qualityPreferences
        )
        try require(routedTranslationPrompt.contains("Translate from English to Simplified Chinese."), "Expected detected source language to affect normal translation prompt.")

        let englishWebPagePrompt = try PromptTemplates.webPageBatchPrompt(
            segments: [WebPageTranslationSegment(segmentID: "web-en", text: "模型与价格")],
            targetLanguage: "en",
            isRetry: false
        )
        let englishWebPageSystemPrompt = PromptTemplates.defaultSystemPrompt(for: .webPageTranslate)
        let wrappedEnglishWebPagePrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .webPageTranslate, inputText: englishWebPagePrompt),
            preferences: preferences
        )
        try require(englishWebPagePrompt.contains("Translate each item to English."), "Expected webpage translation prompt to use the selected English target.")
        try require(!englishWebPagePrompt.contains("Chinese"), "English webpage translation rules must not force Chinese wording.")
        try require(!englishWebPageSystemPrompt.contains("Simplified Chinese"), "Webpage system prompt must not override the selected target language.")
        try require(!wrappedEnglishWebPagePrompt.contains("Simplified Chinese"), "Wrapped webpage prompt must preserve the selected target language.")

        let summaryPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .summarize, inputText: "Discuss launch follow-up."),
            preferences: preferences
        )
        try require(summaryPrompt.contains("会议纪要"), "Expected summary prompt to use configured meeting-notes mode.")
        try require(summaryPrompt.contains("行动项"), "Expected meeting-notes summary prompt to preserve action items.")

        let summaryOverridePrompt = PromptTemplates.userPrompt(
            for: TaskRequest(
                task: .summarize,
                inputText: "Discuss launch follow-up.",
                summaryMode: .oneSentence
            ),
            preferences: preferences
        )
        try require(summaryOverridePrompt.contains("一句中文总结"), "Expected request summary mode to override preferences.")
        try require(!summaryOverridePrompt.contains("会议纪要格式"), "Expected request summary override to avoid preference mode instructions.")

        let explanationPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .explain, inputText: "ERROR timeout"),
            preferences: preferences
        )
        try require(explanationPrompt.contains("排查步骤"), "Expected error-diagnosis explanation prompt.")

        let codePrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .explain, inputText: "func run() {}", explanationMode: .code),
            preferences: preferences
        )
        try require(codePrompt.contains("代码解释"), "Expected request explanation mode to override preferences.")

        let todoPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .extractTodos, inputText: "Alice should send the report."),
            preferences: preferences
        )
        try require(todoPrompt.contains("Markdown 表格"), "Expected table TODO prompt.")

        let todoOverridePrompt = PromptTemplates.userPrompt(
            for: TaskRequest(
                task: .extractTodos,
                inputText: "Alice should send the report.",
                todoExtractionMode: .byOwner
            ),
            preferences: preferences
        )
        try require(todoOverridePrompt.contains("按负责人分组"), "Expected request TODO mode to override preferences.")
        try require(!todoOverridePrompt.contains("Markdown 表格"), "Expected request TODO override to avoid preference mode instructions.")
    }

    private static func checkCustomPromptTemplates() throws {
        var preferences = AppPreferences(defaultTranslationTarget: "Chinese")
        preferences.promptTemplates.translate.systemPrompt = "System target: {targetLanguage}"
        preferences.defaultTranslationQuality = .literal
        preferences.promptTemplates.translate.userPrompt = "Custom translate to {targetLanguage} as {translationQualityValue}: {input}"
        let systemPrompt = PromptTemplates.systemPrompt(for: .translate, preferences: preferences)
        try require(systemPrompt == "System target: Simplified Chinese", "Expected custom translation system prompt to render target language.")

        let userPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .translate, inputText: "hello", targetLanguage: "English"),
            preferences: preferences
        )
        try require(userPrompt == "Custom translate to English as literal: hello", "Expected custom translation prompt to replace quality variables.")

        preferences.promptTemplates.polish.userPrompt = "Rewrite as {polishStyleValue}:"
        let polishPrompt = PromptTemplates.userPrompt(
            for: TaskRequest(task: .polish, inputText: "keep this", polishStyle: "formal"),
            preferences: preferences
        )
        try require(polishPrompt.contains("Rewrite as formal:"), "Expected custom polish prompt to render style value.")
        try require(polishPrompt.hasSuffix("keep this"), "Expected custom text prompt without {input} to append the source text.")

        preferences.promptTemplates.ocrSystemPrompt = "OCR system target: {targetLanguage}"
        let ocrSystemPrompt = PromptTemplates.systemPrompt(for: .ocr, preferences: preferences)
        try require(ocrSystemPrompt == "OCR system target: Simplified Chinese", "Expected custom OCR system prompt to render target language.")

        preferences.promptTemplates.ocrExplainImagePrompt = "Explain image in {targetLanguage}. Mode: {modeName}"
        let imagePrompt = PromptTemplates.ocrPrompt(
            mode: .explainImage,
            targetLanguage: "English",
            preferences: preferences
        )
        try require(imagePrompt == "Explain image in English. Mode: Explain image", "Expected custom OCR mode prompt to render variables.")

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data("""
        {
          "promptTemplates": {
            "translate": {
              "userPrompt": "Translate: {input}"
            },
            "ocrPlainTextPrompt": "Read the visible text."
          }
        }
        """.utf8))
        try require(decoded.promptTemplates.translate.userPrompt == "Translate: {input}", "Expected custom text prompt to decode.")
        try require(decoded.promptTemplates.ocrPrompt(for: .plainText) == "Read the visible text.", "Expected custom OCR prompt to decode.")
    }

    private static func checkOCRCapabilityDefaultsDecodeFromOlderRegistry() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("""
        {
          "defaultTranslationTarget": "English"
        }
        """.utf8))
        try require(preferences.ocr.enabled, "Expected OCR preferences to default enabled.")
        try require(preferences.ocr.modelID == nil, "Expected OCR model to default empty.")
        try require(preferences.ocr.postProcessingModelID == nil, "Expected older OCR preferences to follow the text default model.")
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
        try require(!localDescriptor.thinkingModeEnabled, "Expected older model registries to default thinking mode off.")

        var thinkingDescriptor = localDescriptor
        thinkingDescriptor.thinkingModeEnabled = true
        let thinkingRoundTrip = try JSONDecoder().decode(
            ModelDescriptor.self,
            from: JSONEncoder().encode(thinkingDescriptor)
        )
        try require(thinkingRoundTrip.thinkingModeEnabled, "Expected thinking mode to persist in the model registry.")

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
        try require(explain.contains("Do not enumerate the same word"), "Expected image explanation prompt to discourage repeated labels.")
        let probe = PromptTemplates.visionProbePrompt()
        try require(probe.contains("VISION_OK"), "Expected deterministic vision probe output.")

        let glmPrompt = PromptTemplates.ocrPrompt(mode: .plainText, dedicatedOCR: true)
        try require(glmPrompt == "Text Recognition:", "GLM-OCR must receive its dedicated text-recognition prompt.")
        try require(PromptTemplates.ocrPrompt(mode: .structured, dedicatedOCR: true) == "Text Recognition:", "GLM-OCR structured OCR must retain its dedicated prompt.")
        try require(PromptTemplates.glmOCRPrompt(mode: .explainImage).isEmpty, "GLM-OCR must not advertise generic image explanation mode.")

        var customPreferences = AppPreferences()
        customPreferences.promptTemplates.ocrPlainTextPrompt = "Generic custom vision prompt"
        try require(
            PromptTemplates.ocrPrompt(mode: .plainText, preferences: customPreferences, dedicatedOCR: true) == "Text Recognition:",
            "GLM-OCR must retain its required recognition protocol even when a generic OCR prompt is configured."
        )
        let structuredPostProcessing = PromptTemplates.glmOCRTextPostProcessingPrompt(
            mode: .structured,
            recognizedText: "Title\\nValue: 42"
        )
        try require(structuredPostProcessing.contains("faithful Markdown"), "Expected GLM-OCR structured mode to use text post-processing.")
        try require(structuredPostProcessing.contains("Value: 42"), "Expected structured post-processing to include recognized text.")
        let explanationPostProcessing = PromptTemplates.glmOCRTextPostProcessingPrompt(
            mode: .explainImage,
            recognizedText: "Error 404",
            targetLanguage: "zh-Hans"
        )
        try require(explanationPostProcessing.contains("Simplified Chinese"), "Expected GLM-OCR explanation to honor the target language.")
        try require(explanationPostProcessing.contains("Do not guess colors"), "Expected GLM-OCR explanation to forbid unsupported visual guesses.")
    }

    private static func checkLocalGenerationTokenLimits() throws {
        try require(
            LocalGenerationPolicy.maxTokens(
                for: .translate,
                thinkingModeEnabled: false,
                override: LocalGenerationPolicy.maximumDetailedTranslationTokens
            ) == 8_192,
            "Expected detailed translation to allow its full local output budget."
        )
        try require(
            LocalGenerationPolicy.maxTokens(for: .translate, thinkingModeEnabled: true)
                == LocalGenerationPolicy.maximumThinkingTokens,
            "Expected thinking mode to use a bounded first-pass budget before the non-thinking retry."
        )
        try require(
            LocalGenerationPolicy.shouldRetryThinkingGeneration(visibleOutput: "partial answer", reachedTokenLimit: true),
            "Expected a token-limited thinking pass to retry even after producing partial visible text."
        )
        try require(
            LocalGenerationPolicy.shouldRetryThinkingGeneration(visibleOutput: "", reachedTokenLimit: false),
            "Expected a thinking-only pass to retry."
        )
        try require(
            !LocalGenerationPolicy.shouldRetryThinkingGeneration(visibleOutput: "complete answer", reachedTokenLimit: false),
            "Expected a completed thinking pass with visible text to stay accepted."
        )
        try require(
            LocalGenerationPolicy.maxTokens(for: OCRMode.structured) > 0,
            "Expected structured OCR to have a local generation token limit."
        )
        try require(
            LocalGenerationPolicy.maxTokens(for: OCRMode.extractThenTranslate) <= LocalGenerationPolicy.maxTokens(for: .webPageTranslate),
            "Expected local OCR generation to be bounded below webpage batch generation."
        )
        try require(
            LocalGenerationPolicy.maxTokens(for: .webPageTranslate) >= LocalGenerationPolicy.maxTokens(for: .translate),
            "Expected webpage batches to allow at least as many local output tokens as normal translation."
        )
        try require(
            LocalGenerationPolicy.maxTokens(for: OCRMode.explainImage) <= LocalGenerationPolicy.maxTokens(for: OCRMode.structured),
            "Expected local image explanation generation to stay no larger than structured OCR."
        )
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

        // 本地粘贴和拖放可能产生很大的 TIFF/位图数据，不应在解码前按原始字节数拒绝。
        var oversizedSource = OCRImagePreprocessor.probeImage.data
        oversizedSource.append(Data(repeating: 0, count: 32_000_000))
        let normalizedOversizedSource = try OCRImagePreprocessor.normalizeImageData(
            oversizedSource,
            preferences: OCRPreferences(),
            fileName: "oversized-source.png",
            sourceDescription: "Oversized source fixture"
        )
        try require(
            normalizedOversizedSource.pixelWidth == 64 && normalizedOversizedSource.pixelHeight == 64,
            "Local image normalization must accept source payloads above the former 32 MB limit."
        )

        let oversizedFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-oversized-image-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: oversizedFileURL) }
        try oversizedSource.write(to: oversizedFileURL, options: .atomic)
        let normalizedOversizedFile = try OCRImagePreprocessor.normalizeImageFile(
            at: oversizedFileURL,
            preferences: OCRPreferences(),
            sourceDescription: "Oversized file fixture"
        )
        try require(
            normalizedOversizedFile.pixelWidth == 64 && normalizedOversizedFile.pixelHeight == 64,
            "Local image files above the former 32 MB limit must be decoded directly from their URL."
        )
    }

    private static func checkRemoteImageURLPolicy() throws {
        try require(RemoteImageURLPolicy.isPublicIPAddress("8.8.8.8"), "Expected a public IPv4 address to be allowed.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("127.0.0.1"), "Expected IPv4 loopback to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("10.0.0.1"), "Expected private IPv4 to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("169.254.169.254"), "Expected link-local metadata IPv4 to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("192.0.2.1"), "Expected documentation IPv4 to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("198.18.0.1"), "Expected benchmark IPv4 to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("::1"), "Expected IPv6 loopback to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("fd00::1"), "Expected private IPv6 to be rejected.")
        try require(!RemoteImageURLPolicy.isPublicIPAddress("2001:db8::1"), "Expected documentation IPv6 to be rejected.")
        do {
            _ = try RemoteImageURLPolicy.validatedURL("http://8.8.8.8/image.png")
            throw CheckError("Expected an insecure remote image URL to be rejected.")
        } catch let error as OCRTaskError {
            guard case .remoteImageURLUnsupported = error else {
                throw error
            }
        }
        do {
            _ = try RemoteImageURLPolicy.validatedURL("https://127.0.0.1/image.png")
            throw CheckError("Expected a loopback remote image URL to be rejected.")
        } catch let error as OCRTaskError {
            guard case .remoteImageURLUnsupported = error else {
                throw error
            }
        }
        let hostilePreferences = try JSONDecoder().decode(
            OCRPreferences.self,
            from: Data("{\"maximumImageBytes\":9223372036854775807,\"maximumPixelCount\":9223372036854775807}".utf8)
        )
        try require(hostilePreferences.maximumImageBytes == 16_000_000, "Expected OCR byte preferences to have a hard upper bound.")
        try require(hostilePreferences.maximumPixelCount == 100_000_000, "Expected OCR pixel preferences to have a hard upper bound.")
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

    private static func checkManualVisionOverrideForLocalModel() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelDirectory = root.appendingPathComponent("Qwen-VL-Local-MLX")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let descriptor = try await engine.addModel(from: modelDirectory)
        try require(!descriptor.capabilities.supportsImage, "Expected local models to remain text-only until manually overridden.")

        let visionDescriptor = try await engine.markModelVisionCapable(id: descriptor.id)
        try require(visionDescriptor.capabilities.supportsImage, "Expected manual override to mark a local model vision-capable.")
        try require(visionDescriptor.capabilities.source == .manual, "Expected manual vision override source.")

        try await engine.updatePreferences { preferences in
            preferences.ocr.modelID = descriptor.id
        }
        let selectablePreference = await engine.registry().preferences.ocr.modelID
        try require(selectablePreference == descriptor.id, "Expected manually marked local vision model to remain selectable for OCR.")

        _ = try await engine.markModelTextOnly(id: descriptor.id)
        let clearedPreference = await engine.registry().preferences.ocr.modelID
        try require(clearedPreference == nil, "Expected OCR preference to clear after manually marking the local model text-only.")
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

        _ = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .structured,
            modelID: descriptor.id,
            persistHistory: false
        )
        _ = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .explainImage,
            modelID: descriptor.id,
            persistHistory: false
        )
        let directOCRRequests = await runner.recordedOCRRequests()
        try require(directOCRRequests.map(\.mode) == [.plainText, .structured, .explainImage], "Expected a general vision model to handle OCR modes directly.")
        let directTextRequests = await runner.recordedRequests()
        try require(directTextRequests.isEmpty, "General vision structured and explanation modes must not invoke an extra text stage.")
    }

    private static func checkDedicatedOCRTextProcessingPipeline() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let defaultTextRunner = StubRunner(output: "WRONG DEFAULT MODEL")
        let postProcessingRunner = StubRunner(
            outputs: ["# Title\n\nValue: 42", "这是一个 404 错误。", "标题\n数值：42"],
            format: .gguf
        )
        let visionRunner = StubVisionRunner(output: "Title\nValue: 42")
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: defaultTextRunner, .gguf: postProcessingRunner, .openAICompatible: visionRunner]
        )
        let defaultTextModel = try await engine.addModel(from: try makeMLXModelDirectory(root: root, name: "Qwen3.5-0.8B-MLX-8bit"))
        let postProcessingModel = ModelDescriptor(
            name: "OCR post-processing model",
            sourcePath: root.appendingPathComponent("ocr-post-processing.gguf"),
            format: .gguf,
            sizeClass: "1b",
            role: .fast,
            contextLength: 8_192,
            validationState: .valid,
            capabilities: .textOnly(source: .detected)
        )
        FileManager.default.createFile(atPath: postProcessingModel.sourcePath.path, contents: Data())
        try await engine.addModelDescriptorForTesting(postProcessingModel)
        let glmDirectory = root.appendingPathComponent("GLM-OCR-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: glmDirectory, withIntermediateDirectories: true)
        try Data(#"{"model_type":"glm_ocr"}"#.utf8).write(to: glmDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: glmDirectory.appendingPathComponent("tokenizer.json"))
        FileManager.default.createFile(
            atPath: glmDirectory.appendingPathComponent("model.safetensors").path,
            contents: Data()
        )
        let glmModel = ModelDescriptor(
            name: "GLM-OCR-4bit",
            sourcePath: glmDirectory,
            resolvedPath: glmDirectory,
            format: .openAICompatible,
            sizeClass: "0.9b",
            role: .fast,
            contextLength: 131_072,
            validationState: .valid,
            capabilities: .ocrOnly(source: .detected, confidence: 1)
        )
        try await engine.addModelDescriptorForTesting(glmModel)
        try await engine.updatePreferences { preferences in
            preferences.defaultModelID = defaultTextModel.id
            preferences.ocr.modelID = glmModel.id
            preferences.ocr.postProcessingModelID = postProcessingModel.id
            preferences.ocr.persistHistory = false
            preferences.fastTranslation.forceLLM = true
        }
        let persistedPreferences = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONEncoder().encode(await engine.registry().preferences)
        )
        try require(
            persistedPreferences.ocr.postProcessingModelID == postProcessingModel.id,
            "Expected the OCR post-processing model to survive preference round-trip."
        )

        let plain = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .plainText,
            persistHistory: false
        )
        try require(plain.text == "Title\nValue: 42", "Expected dedicated OCR plain mode to return recognition directly.")
        let plainTextRequestCount = await postProcessingRunner.generatedRequestCount()
        try require(plainTextRequestCount == 0, "Dedicated OCR plain mode must not invoke the text model.")

        let structured = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .structured,
            persistHistory: true
        )
        try require(structured.text.hasPrefix("# Title"), "Expected dedicated OCR structured mode to return text-model Markdown.")
        try require(structured.modelName == "Vision Stub -> Stub", "Expected dedicated OCR result to expose both model stages.")
        try require(structured.rawText.contains("OCR raw output:"), "Expected dedicated OCR result to retain raw recognition output.")
        try require(structured.rawText.contains("Text processing raw output:"), "Expected dedicated OCR result to retain raw post-processing output.")

        let explanation = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .explainImage,
            persistHistory: false
        )
        try require(explanation.text == "这是一个 404 错误。", "Expected dedicated OCR explanation to come from the text model.")

        let translation = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .extractThenTranslate,
            persistHistory: false
        )
        try require(translation.text == "标题\n数值：42", "Expected dedicated OCR translation to use the existing text translation route.")

        let visionRequests = await visionRunner.recordedOCRRequests()
        try require(
            visionRequests.map(\.mode) == [.plainText, .structured, .plainText, .plainText],
            "Expected GLM-OCR to receive structured recognition only for structured mode and plain recognition otherwise."
        )
        try require(visionRequests.allSatisfy { $0.prompt == "Text Recognition:" }, "Expected every GLM-OCR request to use its dedicated protocol.")

        let textRequests = await postProcessingRunner.recordedRequests()
        try require(textRequests.map(\.task) == [.ocr, .ocr, .translate], "Expected GLM-OCR modes to route through the correct text tasks.")
        try require(textRequests[0].inputText.contains("faithful Markdown"), "Expected structured mode to request faithful Markdown.")
        try require(textRequests[1].inputText.contains("Do not guess colors"), "Expected explanation mode to forbid unsupported visual guesses.")
        let defaultTextRequests = await defaultTextRunner.recordedRequests()
        try require(defaultTextRequests.isEmpty, "Configured OCR post-processing must not fall back to the global text default model.")
        let history = await engine.recentHistory()
        try require(history.count == 1, "Expected one combined history entry for the two-stage OCR request.")
        try require(history.first?.modelName == structured.modelName, "Expected OCR history to record the full model chain.")

        let longStructuredText = String(
            repeating: "文",
            count: LocalGenerationPolicy.maximumStructuredOCRPostProcessingCharacters + 1
        )
        await visionRunner.setOutput(longStructuredText)
        let postProcessingCountBeforeLongDocument = await postProcessingRunner.generatedRequestCount()
        let longStructured = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .structured,
            persistHistory: false
        )
        try require(longStructured.text == longStructuredText, "Long structured OCR must preserve the dedicated model output without truncating it in a second stage.")
        let postProcessingCountAfterLongDocument = await postProcessingRunner.generatedRequestCount()
        try require(
            postProcessingCountAfterLongDocument == postProcessingCountBeforeLongDocument,
            "Long structured OCR must skip bounded text post-processing."
        )
        await visionRunner.setOutput("Title\nValue: 42")

        try await engine.removeModel(id: postProcessingModel.id)
        let cleanedPreference = await engine.registry().preferences.ocr.postProcessingModelID
        try require(cleanedPreference == nil, "Removing the OCR post-processing model must restore text-default fallback.")

        let defaultProcessed = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .structured,
            persistHistory: false
        )
        try require(defaultProcessed.text == "WRONG DEFAULT MODEL", "Unset OCR post-processing must use the text default model.")

        try await engine.removeModel(id: defaultTextModel.id)
        let structuredWithoutTextModel = try await engine.runOCR(
            image: OCRImagePreprocessor.probeImage,
            mode: .structured,
            persistHistory: false
        )
        try require(
            structuredWithoutTextModel.text == "Title\nValue: 42",
            "Dedicated structured OCR must remain usable without a text model."
        )
        do {
            _ = try await engine.runOCR(
                image: OCRImagePreprocessor.probeImage,
                mode: .explainImage,
                persistHistory: false
            )
            throw CheckError("Expected dedicated OCR explanation to require a text model.")
        } catch let error as OCRTaskError {
            try require(error == .missingPostProcessingModel, "Expected a specific missing OCR post-processing model error.")
        }

        let replacementModel = ModelDescriptor(
            name: "Replacement vision model",
            sourcePath: root.appendingPathComponent("replacement-vision"),
            format: .openAICompatible,
            sizeClass: "remote",
            role: .default,
            contextLength: 8_192,
            capabilities: .vision(source: .manual, confidence: 1)
        )
        try await visionRunner.load(model: replacementModel)
        await visionRunner.unloadIfLoaded(modelID: glmModel.id)
        let remainingVisionModelID = await visionRunner.loadedModelID()
        try require(
            remainingVisionModelID == replacementModel.id,
            "An older OCR request must not unload a newer model from the shared vision runner."
        )
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

    private static func checkSpeechModelDetectionPreferencesAndHealth() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let senseDirectory = root.appendingPathComponent("SenseVoiceSmall", isDirectory: true)
        try FileManager.default.createDirectory(at: senseDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: senseDirectory.appendingPathComponent("model.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: senseDirectory.appendingPathComponent("tokens.txt").path, contents: Data("stub".utf8))

        let funMLTDirectory = root.appendingPathComponent("Fun-ASR-MLT-Nano-2512", isDirectory: true)
        try FileManager.default.createDirectory(at: funMLTDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: funMLTDirectory.appendingPathComponent("model.pt").path, contents: Data())
        FileManager.default.createFile(atPath: funMLTDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))

        let officialFunNanoDirectory = root.appendingPathComponent("Fun-ASR-Nano-2512", isDirectory: true)
        try FileManager.default.createDirectory(at: officialFunNanoDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: officialFunNanoDirectory.appendingPathComponent("model.pt").path, contents: Data())
        FileManager.default.createFile(atPath: officialFunNanoDirectory.appendingPathComponent("config.yaml").path, contents: Data("model: FunASRNano\n".utf8))

        let qwenDirectory = root.appendingPathComponent("Qwen3-ASR-0.6B", isDirectory: true)
        try FileManager.default.createDirectory(at: qwenDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: qwenDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: qwenDirectory.appendingPathComponent("model.safetensors").path, contents: Data())

        let sherpaQwenDirectory = root.appendingPathComponent("sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25", isDirectory: true)
        try FileManager.default.createDirectory(at: sherpaQwenDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sherpaQwenDirectory.appendingPathComponent("conv_frontend.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaQwenDirectory.appendingPathComponent("encoder.int8.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaQwenDirectory.appendingPathComponent("decoder.int8.onnx").path, contents: Data())
        let sherpaTokenizer = sherpaQwenDirectory.appendingPathComponent("tokenizer", isDirectory: true)
        try FileManager.default.createDirectory(at: sherpaTokenizer, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sherpaTokenizer.appendingPathComponent("vocab.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: sherpaTokenizer.appendingPathComponent("merges.txt").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaTokenizer.appendingPathComponent("tokenizer_config.json").path, contents: Data("{}".utf8))

        let sherpaQwenFP32Directory = root.appendingPathComponent("Qwen3-ASR-1.7B-onnx-fp32", isDirectory: true)
        try FileManager.default.createDirectory(at: sherpaQwenFP32Directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sherpaQwenFP32Directory.appendingPathComponent("conv_frontend.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaQwenFP32Directory.appendingPathComponent("encoder.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaQwenFP32Directory.appendingPathComponent("encoder.onnx.data").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaQwenFP32Directory.appendingPathComponent("decoder.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaQwenFP32Directory.appendingPathComponent("decoder.onnx.data").path, contents: Data())
        let sherpaFP32Tokenizer = sherpaQwenFP32Directory.appendingPathComponent("tokenizer", isDirectory: true)
        try FileManager.default.createDirectory(at: sherpaFP32Tokenizer, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sherpaFP32Tokenizer.appendingPathComponent("vocab.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: sherpaFP32Tokenizer.appendingPathComponent("merges.txt").path, contents: Data())
        FileManager.default.createFile(atPath: sherpaFP32Tokenizer.appendingPathComponent("tokenizer_config.json").path, contents: Data("{}".utf8))

        let whisperDirectory = root.appendingPathComponent("whisper-base-en-coreml", isDirectory: true)
        try FileManager.default.createDirectory(at: whisperDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: whisperDirectory.appendingPathComponent("ggml-base.en.bin").path, contents: Data())
        try FileManager.default.createDirectory(
            at: whisperDirectory.appendingPathComponent("ggml-base.en-encoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )

        let nemotronDirectory = root
            .appendingPathComponent("Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML", isDirectory: true)
            .appendingPathComponent("multilingual", isDirectory: true)
            .appendingPathComponent("1120ms", isDirectory: true)
        try FileManager.default.createDirectory(at: nemotronDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: nemotronDirectory.appendingPathComponent("metadata.json"))
        try Data("{}".utf8).write(to: nemotronDirectory.appendingPathComponent("tokenizer.json"))
        try FileManager.default.createDirectory(
            at: nemotronDirectory.appendingPathComponent("encoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: nemotronDirectory.appendingPathComponent("decoder_joint.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )

        let detectedSense = try requireNonNil(ModelDetection.detectSpeechModel(at: senseDirectory), "Expected SenseVoiceSmall speech detection.")
        try require(detectedSense.family == .senseVoiceSmall, "Expected SenseVoiceSmall family detection.")
        try require(detectedSense.supports(.realtime), "SenseVoiceSmall must be realtime-capable.")
        try require(detectedSense.supports(.fileOnly), "SenseVoiceSmall must also support file transcription.")

        let detectedFunMLT = try requireNonNil(ModelDetection.detectSpeechModel(at: funMLTDirectory), "Expected Fun-ASR-MLT-Nano speech detection.")
        try require(detectedFunMLT.family == .funASRMLTNano, "Expected Fun-ASR-MLT-Nano family detection.")
        try require(detectedFunMLT.supports(.realtime), "Fun-ASR-MLT-Nano must be realtime-capable through a local streaming runtime.")
        try require(detectedFunMLT.supports(.fileOnly), "Fun-ASR-MLT-Nano must also support file transcription.")
        // FunASR 工具箱可组合 CAM++，但不能因此把 Nano/MLT 的 ASR 权重标成原生说话人模型。
        try require(!detectedFunMLT.canEmitSpeakerLabels, "Fun-ASR-MLT-Nano must keep speaker diarization as a separate pipeline capability.")
        try require(!SpeechModelCapabilities.funASRNano().canEmitSpeakerLabels, "Fun-ASR-Nano must not claim native speaker labels without the separate CAM++ pipeline.")
        try require(SpeechModelFamily.funASRNano.displayName == "Fun-ASR-Nano", "Speech model families must expose stable product names instead of raw enum values.")

        let detectedOfficialFunNano = try requireNonNil(
            ModelDetection.detectSpeechModel(at: officialFunNanoDirectory),
            "Expected official Fun-ASR-Nano speech detection."
        )
        try require(detectedOfficialFunNano.family == .funASRNano, "Expected the official Fun-ASR-Nano family.")
        try require(detectedOfficialFunNano.supports(.fileOnly), "The official FunASR composite pipeline must support file transcription.")
        try require(detectedOfficialFunNano.supports(.realtime), "The official Fun-ASR-Nano model must expose its persistent Torch/MPS realtime path.")
        try require(!detectedOfficialFunNano.canEmitSpeakerLabels, "CAM++ output is a runtime capability, not a native Nano model claim.")
        let officialFunNanoDescriptor = ModelDescriptor(
            name: "Fun-ASR-Nano-2512",
            sourcePath: officialFunNanoDirectory,
            format: .speech,
            sizeClass: "large",
            role: .default,
            contextLength: 2_048,
            capabilities: ModelCapabilities.speech(detectedOfficialFunNano)
        )
        try require(
            !officialFunNanoDescriptor.supportsMeetingCaptureSpeech
                && officialFunNanoDescriptor.capabilities.speech?.supports(.realtime) == true
                && officialFunNanoDescriptor.capabilities.speech?.supports(.fileOnly) == true
                && officialFunNanoDescriptor.meetingCaptureRuntimeMode == nil,
            "The official Nano model.pt must stay available for realtime subtitles/files but be excluded from realtime meeting capture."
        )

        let detectedQwen = try requireNonNil(ModelDetection.detectSpeechModel(at: qwenDirectory), "Expected Qwen3-ASR speech detection.")
        try require(detectedQwen.family == .qwen3ASR06B, "Expected Qwen3-ASR-0.6B family detection.")
        try require(detectedQwen.supports(.fileOnly), "Qwen3-ASR-0.6B must support file transcription.")
        try require(detectedQwen.supports(.realtime), "Qwen3-ASR-0.6B should be selectable for experimental realtime subtitles.")

        try require(ModelDetection.detectSpeechModel(at: sherpaQwenDirectory) == nil, "sherpa-onnx Qwen3-ASR int8 directories should no longer auto-register as speech models.")
        try require(ModelDetection.detectSpeechModel(at: sherpaQwenFP32Directory) == nil, "sherpa-onnx Qwen3-ASR fp32 directories should no longer auto-register as speech models.")

        let detectedWhisper = try requireNonNil(ModelDetection.detectSpeechModel(at: whisperDirectory), "Expected whisper.cpp CoreML speech detection.")
        try require(detectedWhisper.family == .whisperCppCoreML, "Expected whisper.cpp CoreML family detection.")
        try require(detectedWhisper.supports(.fileOnly), "whisper.cpp CoreML must support file transcription.")
        try require(detectedWhisper.supports(.realtime), "whisper.cpp CoreML must be selectable for realtime subtitles through its persistent sidecar.")

        let nemotronRepositoryDirectory = root
            .appendingPathComponent("Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML", isDirectory: true)
        let detectedNemotron = try requireNonNil(
            ModelDetection.detectSpeechModel(at: nemotronRepositoryDirectory),
            "Expected Nemotron Core ML streaming speech detection."
        )
        try require(detectedNemotron.family == .nemotron35ASRStreaming06B, "Expected Nemotron streaming ASR family detection.")
        try require(detectedNemotron.supports(.realtime), "Nemotron must be realtime-capable.")
        try require(!detectedNemotron.supports(.fileOnly), "Nemotron must not claim file transcription capability.")

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)

        let sense = try await engine.addModel(from: senseDirectory)
        let qwen = try await engine.addModel(from: qwenDirectory)
        let funMLT = try await engine.addModel(from: funMLTDirectory)
        let whisper = try await engine.addModel(from: whisperDirectory)
        let nemotron = try await engine.addModel(from: nemotronRepositoryDirectory)
        try require(sense.format == .speech, "Expected SenseVoiceSmall to register as speech format.")
        try require(qwen.format == .speech, "Expected Qwen3-ASR-0.6B to register as speech format.")
        try require(funMLT.format == .speech, "Expected Fun-ASR-MLT-Nano to register as speech format.")
        try require(whisper.format == .speech, "Expected whisper.cpp CoreML to register as speech format.")
        try require(nemotron.format == .speech, "Expected Nemotron Core ML model to register as speech format.")
        try require(nemotron.sourcePath == nemotronRepositoryDirectory, "Nemotron must retain the user-selected repository directory.")
        try require(
            nemotron.resolvedPath?.standardizedFileURL.resolvingSymlinksInPath().path
                == nemotronDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
            "Nemotron must resolve the repository to its executable 1120ms Core ML assets; got \(nemotron.resolvedPath?.path ?? "nil")."
        )
        let speechModels = await engine.speechCapableModels()
        let realtimeSpeechModels = await engine.realtimeSpeechModels()
        let fileSpeechModels = await engine.fileSpeechModels()
        try require(speechModels.count == 5, "Expected five speech-capable models after adding the Nemotron streaming Core ML model.")
        try require(realtimeSpeechModels.map(\.id).contains(sense.id), "SenseVoiceSmall should be realtime-capable.")
        try require(realtimeSpeechModels.map(\.id).contains(funMLT.id), "Fun-ASR-MLT-Nano should be realtime-capable.")
        try require(realtimeSpeechModels.map(\.id).contains(qwen.id), "Qwen3-ASR-0.6B should be selectable for realtime subtitles.")
        try require(realtimeSpeechModels.map(\.id).contains(whisper.id), "whisper.cpp CoreML should be selectable for realtime subtitles.")
        try require(realtimeSpeechModels.map(\.id).contains(nemotron.id), "Nemotron must be selectable for realtime subtitles.")
        try require(fileSpeechModels.map(\.id).contains(funMLT.id), "Fun-ASR-MLT-Nano should be selectable for file subtitles.")
        try require(fileSpeechModels.map(\.id).contains(qwen.id), "Qwen3-ASR-0.6B should be selectable for file subtitles.")
        try require(fileSpeechModels.map(\.id).contains(whisper.id), "whisper.cpp CoreML should be selectable for file subtitles.")
        try require(!fileSpeechModels.map(\.id).contains(nemotron.id), "Nemotron must never enter file subtitle routing.")
        try require(!nemotron.capabilities.supportsFileSpeech, "Nemotron descriptor must not expose file speech capability.")
        try require(!nemotron.supportsMeetingCaptureSpeech, "Nemotron must stay out of the meeting capture pipeline.")

        var mediaPreferences = await engine.registry().preferences.mediaSubtitles
        try require(mediaPreferences.realtimeASRModelID == sense.id, "Adding later ASR models must not replace the existing realtime ASR preference automatically.")
        try require(mediaPreferences.fileASRModelID == sense.id, "Expected first file-capable ASR to seed file preference.")

        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.realtimeASRModelID = qwen.id
            preferences.mediaSubtitles.fileASRModelID = qwen.id
        }
        mediaPreferences = await engine.registry().preferences.mediaSubtitles
        try require(mediaPreferences.realtimeASRModelID == qwen.id, "Realtime preference should accept Qwen3-ASR when selected.")
        try require(mediaPreferences.fileASRModelID == qwen.id, "File subtitle preference should accept Qwen3-ASR.")

        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.fileASRModelID = nemotron.id
        }
        mediaPreferences = await engine.registry().preferences.mediaSubtitles
        try require(mediaPreferences.fileASRModelID != nemotron.id, "File subtitle preference must reject realtime-only Nemotron.")

        let health = try await engine.checkASRHealth(modelID: sense.id, mode: .realtime)
        try require(health.family == .senseVoiceSmall, "Expected SenseVoiceSmall ASR health family.")
        try require(health.isRealtimeCapable, "Expected SenseVoiceSmall health to report realtime capability.")
        try require(health.status == .runtimeMissing || health.status == .ready, "Expected health to be local-runtime missing or ready, got \(health.status).")
        if health.status == .runtimeMissing {
            try require(health.runtimeSource == .unavailable, "Missing ASR runtime should report unavailable runtime source.")
        }
        let healthMessage = health.message.lowercased()
        try require(!healthMessage.contains("cloud") && !healthMessage.contains("remote"), "ASR health must not suggest a cloud fallback.")

        let nemotronHealth = try await engine.checkASRHealth(modelID: nemotron.id, mode: .realtime)
        try require(nemotronHealth.status == .ready, "Expected local Nemotron Core ML health to be ready.")
        try require(nemotronHealth.runtimeSource == .fluidAudioNemotronCoreML, "Expected FluidAudio Core ML Nemotron runtime source.")
        try require(nemotronHealth.isRealtimeCapable && !nemotronHealth.isFileCapable, "Nemotron health must report realtime-only capability.")

        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.sourceLanguageHint = .zh
            preferences.mediaSubtitles.senseVoiceCommandTemplate = #"/usr/bin/printf '{"segments":[{"start":0,"end":1.25,"text":"hello from local command","language":"%s","confidence":0.9}]}' {language}"#
            preferences.mediaSubtitles.realtimeASRModelID = sense.id
            preferences.mediaSubtitles.fileASRModelID = sense.id
        }
        let configuredHealth = try await engine.checkASRHealth(modelID: sense.id, mode: .fileOnly)
        try require(configuredHealth.status == .ready, "Expected settings ASR command to make SenseVoice file ASR health ready.")
        try require(configuredHealth.runtimeSource == .settingsCommand, "Expected configured ASR runtime source to come from Settings.")
        let audioURL = root.appendingPathComponent("fixture.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data("stub".utf8))
        let configuredPreferences = await engine.registry().preferences.mediaSubtitles
        let fixtureSegments = try await LocalASRProcessRunner().transcribe(
            audioURL: audioURL,
            model: sense,
            sessionID: UUID(),
            duration: 1.25,
            preferences: configuredPreferences
        )
        try require(fixtureSegments.count == 1, "Expected settings ASR command to return one fixture subtitle segment.")
        try require(fixtureSegments.first?.originalText == "hello from local command", "Expected fixture transcript from settings ASR command.")
        try require(fixtureSegments.first?.sourceLanguage == "zh", "Expected ASR command template to receive source language hint.")

        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.funASRCommandTemplate = #"/usr/bin/printf '{"segments":[{"start":0,"end":1.0,"text":"fun asr local command","language":"%s"}]}' {language}"#
            preferences.mediaSubtitles.realtimeASRModelID = funMLT.id
            preferences.mediaSubtitles.fileASRModelID = funMLT.id
        }
        let funHealth = try await engine.checkASRHealth(modelID: funMLT.id, mode: .fileOnly)
        try require(funHealth.status == .ready, "Expected settings ASR command to make Fun-ASR file ASR health ready.")
        try require(funHealth.runtimeSource == .settingsCommand, "Expected Fun-ASR runtime source to come from Settings.")

        let minimalLivePayload = try JSONDecoder().decode(
            CreateLiveSubtitleSessionPayload.self,
            from: Data(#"{"tabID":7}"#.utf8)
        )
        try require(minimalLivePayload.tabID == 7, "Expected live subtitle payload to preserve tabID.")
        try require(minimalLivePayload.targetLanguage == "zh-Hans", "Expected live subtitle payload to default target language.")
        try require(minimalLivePayload.displayMode == .bilingual, "Expected live subtitle payload to default display mode.")
        try require(minimalLivePayload.sampleRate == 16_000, "Expected live subtitle payload to default sample rate.")
        try require(minimalLivePayload.channelCount == 1, "Expected live subtitle payload to default channel count.")
    }

    private static func checkSubtitleTranslationCoordinatorUsesTextRunner() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let runner = StubRunner(output: """
        [
          {"id":"\(firstID.uuidString)","translation":"你好。"},
          {"id":"\(secondID.uuidString)","translation":"世界。"}
        ]
        """)
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
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

        let sessionID = UUID()
        let translated = try await engine.translateSubtitleSegments([
            SubtitleSegment(id: firstID, sessionID: sessionID, index: 0, startTime: 0, endTime: 1.5, originalText: "Hello.", asrModelID: "asr-fixture"),
            SubtitleSegment(id: secondID, sessionID: sessionID, index: 1, startTime: 1.5, endTime: 3, originalText: "World.", asrModelID: "asr-fixture")
        ])
        try require(translated.map(\.translatedText) == ["你好。", "世界。"], "Expected subtitle coordinator to apply text-model JSON translations.")
        try require(translated.allSatisfy { $0.translationModelID != nil }, "Expected translated subtitle segments to record translation model IDs.")

        let requests = await runner.recordedRequests()
        try require(requests.count == 1, "Expected one subtitle translation batch request.")
        try require(requests[0].task == .webPageTranslate, "Expected subtitle translation to reuse JSON-capable text translation path.")
        try require(requests[0].inputText.contains("Subtitle translation rules"), "Expected subtitle-specific prompt rules.")
        try require(requests[0].targetLanguage == "zh-Hans", "Expected subtitle translation to default to Simplified Chinese.")
        let history = await engine.recentHistory()
        try require(history.isEmpty, "Subtitle translation history must default off.")
    }

    private static func checkSubtitleTranslationSplitsLongLLMBatches() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = SubtitleJSONEchoRunner(format: .openAICompatible)
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.openAICompatible: runner]
        )
        let descriptor = try await engine.addProviderModel(
            providerID: .customOpenAICompatible,
            name: "Small subtitle translator",
            modelID: "subtitle-json-echo",
            apiKey: "test-key",
            baseURL: "https://example.com/v1",
            contextLength: 4_096
        )

        let sessionID = UUID()
        let sourceText = String(repeating: "Long subtitle phrase. ", count: 26)
        let segments = (0..<10).map { index in
            SubtitleSegment(
                id: UUID(),
                sessionID: sessionID,
                index: index,
                startTime: Double(index),
                endTime: Double(index + 1),
                originalText: "\(index): \(sourceText)",
                asrModelID: "asr-fixture"
            )
        }

        let translated = try await engine.translateSubtitleSegments(
            segments,
            targetLanguage: "zh-Hans",
            modelID: descriptor.id
        )
        try require(translated.count == segments.count, "Expected every subtitle segment to survive batched translation.")
        try require(
            translated.allSatisfy { ($0.translatedText ?? "").hasPrefix("译文：") },
            "Expected echo runner to translate every subtitle segment."
        )

        let requests = await runner.recordedRequests()
        try require(requests.count > 1, "Expected long subtitle translation to split into multiple model requests.")
        let limit = InputSizePolicy.maximumInputCharacters(forContextLength: descriptor.contextLength)
        try require(
            requests.allSatisfy { $0.inputText.count <= limit },
            "Expected every subtitle translation batch to stay within the selected model input limit."
        )
        try require(
            requests.allSatisfy { $0.task == .webPageTranslate },
            "Expected split subtitle translation batches to keep using the JSON-capable text translation task."
        )
    }

    private static func checkSubtitleTranslationSplitsOversizedSingleSegment() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = StubRunner(
            outputs: (1...8).map { "part \($0)" },
            format: .openAICompatible
        )
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.openAICompatible: runner]
        )
        let descriptor = try await engine.addProviderModel(
            providerID: .customOpenAICompatible,
            name: "Tiny subtitle translator",
            modelID: "subtitle-text-chunker",
            apiKey: "test-key",
            baseURL: "https://example.com/v1",
            contextLength: 2_048
        )

        let segment = SubtitleSegment(
            id: UUID(),
            sessionID: UUID(),
            index: 0,
            startTime: 0,
            endTime: 60,
            originalText: String(repeating: "One very long subtitle sentence. ", count: 90),
            asrModelID: "asr-fixture"
        )
        let translated = try await engine.translateSubtitleSegments(
            [segment],
            targetLanguage: "zh-Hans",
            modelID: descriptor.id
        )
        let requests = await runner.recordedRequests()
        try require(requests.count > 1, "Expected oversized single subtitle segment to split into text translation chunks.")
        try require(requests.allSatisfy { $0.task == .translate }, "Expected oversized single subtitle segment fallback to use text translation chunks.")
        let limit = InputSizePolicy.maximumInputCharacters(forContextLength: descriptor.contextLength)
        try require(requests.allSatisfy { $0.inputText.count <= limit }, "Expected oversized subtitle text chunks to fit the model input limit.")
        try require(translated.first?.translatedText?.contains("part 1") == true, "Expected chunked text translation output to be applied to the subtitle segment.")
    }

    private static func checkMediaFileSubtitlePipelineWithConfiguredLocalCommand() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let textRunner = SubtitleJSONEchoRunner()
        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(
            registryStore: registryStore,
            historyStore: historyStore,
            runners: [.mlx: textRunner]
        )

        let textModelDirectory = root.appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: textModelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: textModelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: textModelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: textModelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())
        _ = try await engine.addModel(from: textModelDirectory)

        let senseDirectory = root.appendingPathComponent("SenseVoiceSmall", isDirectory: true)
        try FileManager.default.createDirectory(at: senseDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: senseDirectory.appendingPathComponent("model.onnx").path, contents: Data())
        FileManager.default.createFile(atPath: senseDirectory.appendingPathComponent("tokens.txt").path, contents: Data("stub".utf8))
        let speechModel = try await engine.addModel(from: senseDirectory)

        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.fileASRModelID = speechModel.id
            preferences.mediaSubtitles.realtimeASRModelID = speechModel.id
            preferences.mediaSubtitles.senseVoiceCommandTemplate = #"/bin/echo '{"segments":[{"start":0,"end":1.5,"text":"file pipeline transcript","language":"en","confidence":0.98}]}'"#
        }

        let wavURL = root.appendingPathComponent("sample-audio.wav")
        try writePCM16WAV(url: wavURL, duration: 0.4)
        let fileResult = try await engine.transcribeMediaFile(at: wavURL, modelID: speechModel.id)
        try require(fileResult.descriptor.mediaKind == "audio", "Expected WAV file intake to be treated as audio.")
        try require(fileResult.normalizedAudioURL.lastPathComponent == "normalized-16k-mono.wav", "Expected file pipeline to normalize audio for ASR.")
        try require(fileResult.segments.map(\.originalText) == ["file pipeline transcript"], "Expected file ASR command transcript segment.")
        try require(fileResult.diagnostics.segmentCount == 1, "Expected diagnostics to count subtitle segments.")
        try require(fileResult.diagnostics.targetLanguage == "zh-Hans", "Expected file diagnostics target language to default to Simplified Chinese.")

        let translated = try await engine.translateSubtitleSegments(fileResult.segments)
        try require(translated.first?.translatedText == "译文：file pipeline transcript", "Expected subtitle translation coordinator in file pipeline.")

        let srt = try await engine.exportSubtitleSegments(translated, format: .srt, mode: .bilingual)
        let vtt = try await engine.exportSubtitleSegments(translated, format: .vtt, mode: .translated)
        let txt = try await engine.exportSubtitleSegments(translated, format: .txt, mode: .original)
        let markdown = try await engine.exportSubtitleSegments(translated, format: .markdown, mode: .bilingual)
        try require(srt.contains("file pipeline transcript\n译文：file pipeline transcript"), "Expected bilingual SRT export.")
        try require(vtt.hasPrefix("WEBVTT"), "Expected VTT export.")
        try require(vtt.contains("译文：file pipeline transcript"), "Expected translated VTT export.")
        try require(txt.contains("# Translation engine: llm"), "Expected original TXT export to include translation metadata.")
        try require(txt.hasSuffix("file pipeline transcript\n"), "Expected original TXT export body.")
        try require(markdown.contains("file pipeline transcript<br>译文：file pipeline transcript"), "Expected bilingual Markdown export.")

        let diagnosticsJSON = String(data: try JSONEncoder().encode(fileResult.diagnostics), encoding: .utf8) ?? ""
        try require(!diagnosticsJSON.contains("file pipeline transcript"), "File diagnostics must not include transcript text.")
        try require(!diagnosticsJSON.contains(wavURL.path), "File diagnostics must not include full media path.")
        let history = await engine.recentHistory()
        try require(history.isEmpty, "File subtitle pipeline must not persist history by default.")

        let meetingWorkspaceRoot = root.appendingPathComponent("meeting-workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: meetingWorkspaceRoot, withIntermediateDirectories: true)
        let meetingResult = try await engine.transcribeMeetingFile(
            at: wavURL,
            modelID: speechModel.id,
            temporaryDirectory: meetingWorkspaceRoot
        )
        try require(meetingResult.segments.map { $0.text } == ["file pipeline transcript"], "Expected meeting-file ASR transcript fixture.")
        let successfulMeetingWorkspaceContents = try FileManager.default.contentsOfDirectory(atPath: meetingWorkspaceRoot.path)
        try require(
            successfulMeetingWorkspaceContents.isEmpty,
            "Successful meeting-file transcription must remove its normalized-audio workspace."
        )

        try await engine.updatePreferences { preferences in
            preferences.mediaSubtitles.senseVoiceCommandTemplate = "/bin/false"
        }
        do {
            _ = try await engine.transcribeMeetingFile(
                at: wavURL,
                modelID: speechModel.id,
                temporaryDirectory: meetingWorkspaceRoot
            )
            throw CheckError("Expected meeting-file ASR fixture failure.")
        } catch let error as CheckError {
            throw error
        } catch {
        }
        let failedMeetingWorkspaceContents = try FileManager.default.contentsOfDirectory(atPath: meetingWorkspaceRoot.path)
        try require(
            failedMeetingWorkspaceContents.isEmpty,
            "Failed meeting-file transcription must remove its normalized-audio workspace."
        )
    }

    private static func checkAudioExtractionWorkspaceCleanup() async throws {
        let root = try makeTemporaryDirectory(name: "audio-extraction-cleanup")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceRoot = root.appendingPathComponent("workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        let invalidWAV = root.appendingPathComponent("invalid.wav")
        try Data("not-a-wave-file".utf8).write(to: invalidWAV)

        do {
            _ = try await AudioExtractionService.normalizeMediaFile(
                at: invalidWAV,
                temporaryDirectory: workspaceRoot
            )
            throw CheckError("Expected invalid WAV normalization to fail.")
        } catch let error as CheckError {
            throw error
        } catch {
        }
        let failedExtractionWorkspaceContents = try FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)
        try require(
            failedExtractionWorkspaceContents.isEmpty,
            "Failed audio normalization must remove its temporary workspace."
        )
    }

    private static func checkAudioExtractionCancellationCleanup() async throws {
        let root = try makeTemporaryDirectory(name: "audio-extraction-cancellation")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceRoot = root.appendingPathComponent("workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        let inputWAV = root.appendingPathComponent("input.wav")
        try writePCM16WAV(url: inputWAV, duration: 0.2)
        let markerURL = root.appendingPathComponent("converter-started")
        let converterURL = root.appendingPathComponent("slow-afconvert")
        let markerPath = markerURL.path.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\n: > '\(markerPath)'\nexec /bin/sleep 10\n"
            .write(to: converterURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: converterURL.path)

        let task = Task {
            try await AudioExtractionService.normalizeMediaFile(
                at: inputWAV,
                temporaryDirectory: workspaceRoot,
                audioConverterPath: converterURL.path
            )
        }
        let markerDeadline = Date(timeIntervalSinceNow: 2)
        while !FileManager.default.fileExists(atPath: markerURL.path), Date() < markerDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try require(FileManager.default.fileExists(atPath: markerURL.path), "Expected the cancellable audio converter fixture to start.")
        let cancellationStarted = Date()
        task.cancel()
        do {
            _ = try await task.value
            throw CheckError("Expected audio normalization cancellation.")
        } catch let error as CheckError {
            throw error
        } catch is CancellationError {
        }
        try require(
            Date().timeIntervalSince(cancellationStarted) < 2,
            "Audio normalization cancellation must terminate the converter promptly."
        )
        let remainingWorkspaces = try FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)
        try require(remainingWorkspaces.isEmpty, "Cancelled audio normalization must remove its temporary workspace.")
    }

    private static func checkLocalASRCommandCancellation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelDirectory = root.appendingPathComponent("cancellable-asr", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("cancellable-asr.wav")
        try writePCM16WAV(url: audioURL, duration: 0.2)
        let model = ModelDescriptor(
            name: "Cancellation ASR Fixture",
            sourcePath: modelDirectory,
            format: .speech,
            sizeClass: "fixture",
            role: .fast,
            contextLength: 4_096,
            capabilities: .speech(.senseVoiceSmall(source: .manual, confidence: 1))
        )
        let preferences = MediaSubtitlePreferences(
            senseVoiceCommandTemplate: "exec /bin/sleep 10"
        )
        let task = Task {
            try await LocalASRProcessRunner().transcribe(
                audioURL: audioURL,
                model: model,
                sessionID: UUID(),
                duration: 0.2,
                preferences: preferences
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancellationStarted = Date()
        task.cancel()
        do {
            _ = try await task.value
            try require(false, "Expected local ASR cancellation to throw.")
        } catch is CancellationError {
        }
        try require(
            Date().timeIntervalSince(cancellationStarted) < 2,
            "Local ASR cancellation must terminate the local process promptly."
        )
    }

    private static func checkSubtitlePromptExporterAndPrivacyDefaults() throws {
        let sessionID = UUID()
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let segments = [
            SubtitleSegment(id: firstID, sessionID: sessionID, index: 0, startTime: 1.25, endTime: 3, originalText: "Hello | world.", translatedText: "你好，世界。", sourceLanguage: "en", asrModelID: "asr-fixture"),
            SubtitleSegment(id: secondID, sessionID: sessionID, index: 1, startTime: 3.5, endTime: 5, originalText: "Second line.", translatedText: "第二行。", sourceLanguage: "en", asrModelID: "asr-fixture")
        ]

        let prompt = try PromptTemplates.subtitleBatchPrompt(segments: segments, targetLanguage: "zh-Hans", isRetry: false)
        try require(prompt.contains("Subtitle translation rules"), "Expected subtitle prompt to include subtitle-specific rules.")
        try require(prompt.contains(firstID.uuidString) && prompt.contains(secondID.uuidString), "Expected subtitle prompt to preserve segment IDs.")
        try require(prompt.contains("Simplified Chinese"), "Expected zh-Hans target to render as Simplified Chinese.")

        let srt = try SubtitleExporter.render(segments: segments, format: .srt, mode: .bilingual)
        try require(srt.contains("00:00:01,250 --> 00:00:03,000"), "Expected SRT timestamp formatting.")
        try require(srt.contains("Hello | world.\n你好，世界。"), "Expected bilingual SRT text.")

        let vtt = try SubtitleExporter.render(segments: segments, format: .vtt, mode: .translated)
        try require(vtt.hasPrefix("WEBVTT"), "Expected VTT header.")
        try require(vtt.contains("00:00:01.250 --> 00:00:03.000"), "Expected VTT timestamp formatting.")
        try require(!vtt.contains("Hello | world."), "Translated VTT mode should prefer translated subtitles.")

        let markdown = try SubtitleExporter.render(segments: segments, format: .markdown, mode: .bilingual)
        try require(markdown.contains("Hello \\| world.<br>你好，世界。"), "Expected Markdown export to escape pipes and keep bilingual line breaks.")

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("private-source-title.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data())
        let descriptor = try MediaIntakeService.descriptor(for: audioURL)
        try require(MediaIntakeService.isSupportedMediaFile(audioURL), "Expected WAV media file to be supported.")
        try require(!MediaIntakeService.isSupportedMediaFile(root.appendingPathComponent("notes.txt")), "Plain text must not be treated as Phase 4 media.")
        try require(descriptor.mediaKind == "audio", "Expected WAV descriptor to be audio.")
        try require(descriptor.redactedPathHash.hasPrefix("h"), "Expected descriptor to contain a redacted path hash.")
        try require(!descriptor.redactedPathHash.contains(root.path), "Redacted media diagnostics must not contain the full file path.")

        let diagnostics = MediaSubtitleDiagnostics(
            mediaKind: "audio",
            fileType: "wav",
            durationBucket: "short",
            sampleRate: 16_000,
            asrModelID: "asr-fixture",
            targetLanguage: "zh-Hans",
            elapsedMilliseconds: 25,
            segmentCount: 2,
            errorCode: nil,
            urlHash: nil,
            domainHash: nil
        )
        let diagnosticsJSON = String(data: try JSONEncoder().encode(diagnostics), encoding: .utf8) ?? ""
        try require(!diagnosticsJSON.contains("Hello | world."), "Diagnostics must not include transcript text.")
        try require(!diagnosticsJSON.contains("你好，世界。"), "Diagnostics must not include translated subtitle text.")
        try require(!diagnosticsJSON.contains(audioURL.path), "Diagnostics must not include full media paths.")
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

    private static func checkDetailedTranslationResultContract() throws {
        let request = TaskRequest(
            task: .translate,
            inputText: "The launch was a turning point.",
            targetLanguage: "Chinese",
            translationOutputMode: .detailed
        )
        let prompt = PromptTemplates.userPrompt(for: request, preferences: AppPreferences())
        try require(prompt.contains("\"translation\""), "Detailed translation prompt must require a primary translation.")
        try require(prompt.contains("\"keyTerms\""), "Detailed translation prompt must require key vocabulary.")
        try require(prompt.contains("\"exampleTranslation\""), "Detailed translation prompt must require translated examples.")
        try require(
            !prompt.contains("important source-language word or phrase")
                && !prompt.contains("standard IPA for one word only"),
            "Detailed translation prompt must not contain semantic placeholders that small models can echo."
        )

        // 覆盖小模型常见的 Markdown 围栏，并验证重复、空值和数量上限会被收敛。
        let parsed = try requireNonNil(
            TranslationStudyResult.parse(modelText: """
            ```json
            {
              "translation": "这次发布是一个转折点。",
              "alternatives": ["这次发布成为了转折点。", "这次发布成为了转折点。", ""],
              "keyTerms": [
                {
                  "term": "turning point",
                  "pronunciation": "/ˈtɜːrnɪŋ pɔɪnt/",
                  "partOfSpeech": "noun phrase",
                  "meaning": "转折点",
                  "usage": "表示带来重大变化的时刻",
                  "example": "This decision was a turning point.",
                  "exampleTranslation": "这个决定是一个转折点。"
                }
              ],
              "notes": ["launch 在这里表示产品发布。"]
            }
            ```
            """),
            "Expected fenced detailed translation JSON to decode."
        )
        try require(parsed.translation == "这次发布是一个转折点。", "Expected primary translation to decode.")
        try require(parsed.alternatives == ["这次发布成为了转折点。"], "Expected alternatives to be normalized and deduplicated.")
        try require(parsed.keyTerms.first?.term == "turning point", "Expected key term to decode.")
        try require(parsed.keyTerms.first?.exampleTranslation == "这个决定是一个转折点。", "Expected translated example to decode.")

        // MiniCPM 偶尔会把 alternatives 错写成词条对象；可选字段异常不能拖垮整份详解结果。
        let malformedAlternatives = try requireNonNil(
            TranslationStudyResult.parse(modelText: """
            ```json
            {
              "translation": "精度与召回率之间需要权衡。",
              "alternatives": [
                {
                  "term": "precision vs recall trade-off",
                  "meaning": "精度与召回率之间的权衡"
                }
              ],
              "keyTerms": [
                {
                  "term": "false positive",
                  "meaning": "假阳性"
                }
              ],
              "notes": ["这是影响分析中的常用表达。"]
            }
            ```
            """),
            "Expected malformed optional alternatives to preserve the detailed translation."
        )
        try require(malformedAlternatives.translation == "精度与召回率之间需要权衡。", "Expected the valid primary translation to survive malformed alternatives.")
        try require(malformedAlternatives.alternatives.isEmpty, "Expected object-valued alternatives to be ignored.")
        try require(malformedAlternatives.keyTerms.first?.term == "false positive", "Expected valid key terms to remain available.")
        try require(malformedAlternatives.notes == ["这是影响分析中的常用表达。"], "Expected valid notes to remain available.")

        try require(
            TranslationStudyResult.parse(modelText: """
            {
              "translation": "译文",
              "alternatives": [],
              "keyTerms": [{"term": "important source-language word or phrase"}],
              "notes": []
            }
            """) == nil,
            "Prompt placeholders must not be accepted as detailed vocabulary."
        )
        try require(
            TranslationStudyResult.parse(
                modelText: """
                {"translation":"浏览器扩展","alternatives":[],"keyTerms":[{"term":"浏览器扩展"}],"notes":[]}
                """,
                sourceText: "browser extension"
            ) == nil,
            "Detailed vocabulary must come from the source text instead of the translation."
        )

        let thinkingOnly = """
        Thinking Process:
        The requested schema is {"translation":"placeholder","alternatives":[],"keyTerms":[],"notes":[]}.
        """
        try require(
            TranslationStudyResult.parse(modelText: thinkingOnly) == nil,
            "Thinking-only schema examples must not be accepted as the detailed translation body."
        )

        let finalResult = try requireNonNil(
            TranslationStudyResult.parse(modelText: """
            Thinking Process:
            Analyze the translation request.
            Final Answer:
            {"translation":"正文译文","alternatives":[],"keyTerms":[],"notes":[]}
            """),
            "Expected detailed translation JSON after a final-answer marker to decode."
        )
        try require(finalResult.translation == "正文译文", "Expected only the final detailed translation body.")
    }

    private static func checkTaskEngineReturnsRawModelOutput() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let invalidDetailedOutput = """
        {"translation":"结构化译文","alternatives":[],"keyTerms":[{"term":"important source-language word or phrase"}],"notes":[]}
        """
        let runner = StubRunner(outputs: [
            """
            Thinking Process:
            The translation of "hello" in Chinese is "你好".
            """,
            invalidDetailedOutput,
            "结构化失败后的普通译文"
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
        let result = try await engine.run(request: TaskRequest(task: .translate, inputText: "hello"))
        try require(
            result.text == "Thinking Process:\nThe translation of \"hello\" in Chinese is \"你好\".",
            "Expected raw model output to be preserved, got \(result.text)."
        )
        try require(result.rawText == result.text, "Stub runner output should be raw and visible.")

        let fallbackResult = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "detailed",
                translationOutputMode: .detailed
            )
        )
        try require(
            fallbackResult.text == "结构化失败后的普通译文"
                && fallbackResult.translationStudy?.translation == fallbackResult.text,
            "Invalid detailed JSON must fall back to a clean plain translation."
        )
        try require(
            fallbackResult.rawText == invalidDetailedOutput,
            "Detailed fallback should retain the malformed response only as opt-in raw output."
        )
        let recordedRequests = await runner.recordedRequests()
        try require(
            recordedRequests.map(\.translationOutputMode) == [.plain, .detailed, .plain]
                && recordedRequests[1].maxOutputTokensOverride == 8_192
                && recordedRequests[2].maxOutputTokensOverride == nil,
            "Detailed translation must use the larger output budget and make exactly one bounded plain retry."
        )
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
        let textualThinking = """
        Thinking Process:
        Analyze the request.
        Final Answer:
        你好
        """
        try require(VisibleOutput.from(rawText: textualThinking) == "你好", "Expected output after a textual final-answer marker.")
        try require(
            VisibleOutput.from(rawText: "Thinking Process:\nAnalyze the request.").isEmpty,
            "Expected thinking-only output to stay hidden."
        )
        try require(VisibleOutput.from(rawText: "你好") == "你好", "Expected text without think block to stay unchanged.")
    }

    private static func checkGeneratedOutputGuardTrimsDegenerateTail() throws {
        let looped = """
        这张图片展示了一个训练进度图，图表包含“Training”、“Training”、“Training”、“Training”、“Training”、“Training”、“Training”、“Training”、“Training”、“Training”。
        """
        let trimmed = GeneratedOutputGuard.trimDegenerateTail(looped)
        try require(trimmed == "这张图片展示了一个训练进度图，图表包含“Training”", "Expected repeated Training tail to be trimmed.")
        try require(GeneratedOutputGuard.hasDegenerateTail(looped), "Expected repeated Training tail to be detected.")

        let normal = "这张图片展示了一个训练进度图，并包含 Training、Validation 和 Accuracy 三类指标。"
        try require(GeneratedOutputGuard.trimDegenerateTail(normal) == normal, "Expected normal explanation to stay unchanged.")
        try require(!GeneratedOutputGuard.hasDegenerateTail(normal), "Expected normal explanation not to be flagged.")
    }

    private static func makeTemporaryDirectory(name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmTools-checks", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            throw CheckError("Missing POSIX permissions for \(url.lastPathComponent).")
        }
        return permissions.intValue & 0o777
    }

    private static func makeMLXModelDirectory(root: URL, name: String = "Qwen3.5-4B-MLX-4bit") throws -> URL {
        let modelDirectory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.safetensors").path, contents: Data())
        return modelDirectory
    }

    private static func writePCM16WAV(
        url: URL,
        duration: TimeInterval,
        sampleRate: UInt32 = 16_000,
        amplitude: Int16 = 8_000
    ) throws {
        let sampleCount = max(Int(duration * Double(sampleRate)), 1)
        let dataSize = UInt32(sampleCount * 2)
        var data = Data()
        appendASCII("RIFF", to: &data)
        appendUInt32LE(36 + dataSize, to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendUInt32LE(16, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt32LE(sampleRate, to: &data)
        appendUInt32LE(sampleRate * 2, to: &data)
        appendUInt16LE(2, to: &data)
        appendUInt16LE(16, to: &data)
        appendASCII("data", to: &data)
        appendUInt32LE(dataSize, to: &data)
        for _ in 0..<sampleCount {
            appendInt16LE(amplitude, to: &data)
        }
        try data.write(to: url, options: [.atomic])
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendInt16LE(_ value: Int16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw CheckError(message)
        }
    }

    private static func requireNonNil<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw CheckError(message)
        }
        return value
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

private actor SubtitleJSONEchoRunner: ModelRunner {
    private let format: ModelFormat
    private var loadedID: UUID?
    private var requests: [TaskRequest] = []

    init(format: ModelFormat = .mlx) {
        self.format = format
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
        "Subtitle JSON Echo"
    }

    func load(model: ModelDescriptor) async throws {
        loadedID = model.id
    }

    func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        requests.append(request)
        let marker = "Items:"
        guard let markerRange = request.inputText.range(of: marker) else {
            throw CheckError("Subtitle prompt did not contain Items marker.")
        }
        let jsonText = request.inputText[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8),
              let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CheckError("Subtitle prompt items were not valid JSON.")
        }
        let translations = items.compactMap { item -> [String: String]? in
            guard let id = item["id"] as? String,
                  let text = item["text"] as? String else {
                return nil
            }
            return [
                "id": id,
                "translation": "译文：\(text)"
            ]
        }
        let outputData = try JSONSerialization.data(withJSONObject: translations, options: [.sortedKeys])
        let output = String(data: outputData, encoding: .utf8) ?? "[]"
        return TaskResult(text: output, modelName: "Subtitle JSON Echo", task: request.task)
    }

    func unload() async {
        loadedID = nil
    }

    func recordedRequests() -> [TaskRequest] {
        requests
    }
}

private actor StubVisionRunner: VisionModelRunner {
    private var loadedID: UUID?
    private var output: String
    private var ocrCount = 0
    private var requests: [TaskRequest] = []
    private var ocrRequests: [OCRTaskRequest] = []

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
        requests.append(request)
        return TaskResult(text: "text stub result", modelName: "Vision Stub", task: request.task)
    }

    func generateOCR(request: OCRTaskRequest, preferences: AppPreferences) async throws -> OCRTaskResult {
        ocrCount += 1
        ocrRequests.append(request)
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

    func recordedRequests() -> [TaskRequest] {
        requests
    }

    func recordedOCRRequests() -> [OCRTaskRequest] {
        ocrRequests
    }

    func setOutput(_ output: String) {
        self.output = output
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
