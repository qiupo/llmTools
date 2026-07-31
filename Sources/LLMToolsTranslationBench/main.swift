import Foundation
import LLMToolsCore

@main
struct LLMToolsTranslationBench {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--fast-mt-nllb" {
            try await runFastMTNLLBBenchmark()
            return
        }
        if args.first == "--detailed", args.count >= 2 {
            try await runDetailedTranslationSmoke(modelPath: args[1])
            return
        }
        if args.first == "--text-suite", args.count >= 3 {
            try await runTextFeatureSuite(modelPath: args[1], outputPath: args[2])
            return
        }
        if args.first == "--replacement-suite", args.count >= 3 {
            try await runReplacementSuite(modelPath: args[1], outputPath: args[2])
            return
        }
        guard let modelPath = args.first else {
            print("Usage: LLMToolsTranslationBench <model-path>")
            print("       LLMToolsTranslationBench --fast-mt-nllb")
            print("       LLMToolsTranslationBench --detailed <model-path>")
            print("       LLMToolsTranslationBench --text-suite <model-path> <output.json>")
            print("       LLMToolsTranslationBench --replacement-suite <model-path> <output.json>")
            throw BenchError("Missing model path.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-translation-bench", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        )
        var preferences = await engine.registry().preferences
        preferences.fastTranslation.forceLLM = true
        preferences.defaultTranslationQuality = .natural
        try await engine.setPreferences(preferences)

        let model = try await engine.addModel(from: URL(fileURLWithPath: modelPath))
        print("model=\(model.name)")
        print("format=\(model.format.rawValue)")
        print("path=\(model.displayPath)")

        let samples: [BenchSample] = [
            BenchSample(id: "en_zh_short", source: "en", target: "zh-Hans", text: "Note"),
            BenchSample(id: "en_zh_ui", source: "en", target: "zh-Hans", text: "Click the toolbar button again to restore the original page content."),
            BenchSample(id: "en_zh_product", source: "en", target: "zh-Hans", text: "The browser extension translates visible page text while preserving links, form fields, and table layout."),
            BenchSample(id: "zh_en", source: "zh-Hans", target: "en", text: "浏览器扩展会翻译当前可见的网页文本，并保留链接、表单字段和表格布局。"),
            BenchSample(id: "ja_zh", source: "ja", target: "zh-Hans", text: "設定を変更すると、次回の翻訳から新しいモデルが使われます。"),
            BenchSample(id: "ko_zh", source: "ko", target: "zh-Hans", text: "설정을 변경하면 다음 번역부터 새 모델이 사용됩니다."),
            BenchSample(id: "fr_zh", source: "fr", target: "zh-Hans", text: "Cette option permet de traduire rapidement le texte visible de la page."),
            BenchSample(id: "es_zh", source: "es", target: "zh-Hans", text: "Esta opción traduce rápidamente el texto visible de la página.")
        ]

        var timings: [Double] = []
        for sample in samples {
            let started = Date()
            let result = try await engine.run(
                request: TaskRequest(
                    task: .translate,
                    inputText: sample.text,
                    sourceLanguage: sample.source,
                    targetLanguage: sample.target,
                    translationQuality: .natural
                ),
                modelID: model.id,
                persistHistory: false
            )
            let elapsed = Date().timeIntervalSince(started)
            timings.append(elapsed)
            print("BEGIN_SAMPLE \(sample.id)")
            print("source=\(sample.source) target=\(sample.target) seconds=\(String(format: "%.3f", elapsed))")
            print("input=\(sample.text)")
            print("output=\(result.text.trimmingCharacters(in: .whitespacesAndNewlines))")
            print("END_SAMPLE \(sample.id)")
        }

        await engine.unloadAll()
        let total = timings.reduce(0, +)
        let average = total / Double(max(1, timings.count))
        print("summary count=\(timings.count) totalSeconds=\(String(format: "%.3f", total)) averageSeconds=\(String(format: "%.3f", average))")

        let webpageSegments = (0..<20).map { index in
            WebPageTranslationSegment(
                segmentID: "web-\(index)",
                text: webpageTexts[index % webpageTexts.count],
                textHash: "bench-\(index)"
            )
        }
        let payload = WebPageTranslateSegmentsPayload(
            jobID: "bench-webpage",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            segments: webpageSegments
        )
        let webStarted = Date()
        let webResult = try await engine.translateWebPageSegments(
            payload: payload,
            modelID: model.id
        )
        let webElapsed = Date().timeIntervalSince(webStarted)
        let translatedCount = webResult.translations.filter {
            $0.status == WebPageSegmentTranslationStatus.translated && !$0.translation.isEmpty
        }.count
        print("BEGIN_WEBPAGE_BATCH")
        print("segments=\(webpageSegments.count) translated=\(translatedCount) seconds=\(String(format: "%.3f", webElapsed))")
        for item in webResult.translations.prefix(4) {
            print("\(item.segmentID)=\(item.translation)")
        }
        print("END_WEBPAGE_BATCH")
    }

    private static func runDetailedTranslationSmoke(modelPath: String) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-detailed-translation-smoke", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        )
        var preferences = await engine.registry().preferences
        preferences.fastTranslation.forceLLM = true
        preferences.defaultTranslationQuality = .natural
        try await engine.setPreferences(preferences)
        let model = try await engine.addModel(from: URL(fileURLWithPath: modelPath))

        let inputText = "The browser extension preserves links and form fields, but the first launch can still feel overwhelming to new users."
        let started = Date()
        let result = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: inputText,
                sourceLanguage: "en",
                targetLanguage: "zh-Hans",
                translationQuality: .natural,
                translationOutputMode: .detailed
            ),
            modelID: model.id,
            persistHistory: false
        )
        await engine.unloadAll()

        guard let study = result.translationStudy,
              !study.alternatives.isEmpty,
              (3...8).contains(study.keyTerms.count),
              study.keyTerms.allSatisfy({
                  inputText.range(of: $0.term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
              }) else {
            throw BenchError("Detailed translation output did not satisfy the structured contract: \(result.rawText)")
        }
        print("model=\(model.name)")
        print("seconds=\(String(format: "%.3f", Date().timeIntervalSince(started)))")
        print("translation=\(study.translation)")
        print("alternatives=\(study.alternatives.count) keyTerms=\(study.keyTerms.count) notes=\(study.notes.count)")
        for term in study.keyTerms {
            print("term=\(term.term) pronunciation=\(term.pronunciation) meaning=\(term.meaning)")
        }
    }

    private static func runTextFeatureSuite(modelPath: String, outputPath: String) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-text-feature-suite", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        )
        var preferences = await engine.registry().preferences
        preferences.fastTranslation.forceLLM = true
        preferences.defaultTranslationQuality = .natural
        try await engine.setPreferences(preferences)
        let model = try await engine.addModel(from: URL(fileURLWithPath: modelPath))

        // 预热单独执行，避免把首次装载模型的成本混入功能延迟对比。
        _ = try await engine.run(
            request: TaskRequest(task: .explain, inputText: "用中文回答：预热完成。只输出这四个字。"),
            modelID: model.id,
            persistHistory: false
        )

        let cases = textFeatureSuiteCases
        var results: [TextFeatureSuiteResult] = []
        for item in cases {
            let started = Date()
            do {
                let result = try await engine.run(
                    request: item.request,
                    modelID: model.id,
                    persistHistory: false
                )
                let output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(
                    TextFeatureSuiteResult(
                        id: item.id,
                        title: item.title,
                        task: item.request.task.rawValue,
                        input: item.request.inputText,
                        output: output,
                        elapsedMilliseconds: Int((Date().timeIntervalSince(started) * 1_000).rounded()),
                        error: nil
                    )
                )
            } catch {
                results.append(
                    TextFeatureSuiteResult(
                        id: item.id,
                        title: item.title,
                        task: item.request.task.rawValue,
                        input: item.request.inputText,
                        output: nil,
                        elapsedMilliseconds: Int((Date().timeIntervalSince(started) * 1_000).rounded()),
                        error: error.localizedDescription
                    )
                )
            }
        }
        await engine.unloadAll()

        let report = TextFeatureSuiteReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            modelName: model.name,
            modelPath: model.displayPath,
            contextLength: model.contextLength,
            warmupTask: "explain",
            results: results
        )
        let destination = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: destination, options: .atomic)
        print("Wrote text feature suite: \(destination.path)")
        print("model=\(model.name) completed=\(results.filter { $0.error == nil }.count)/\(results.count)")
    }

    private static func runReplacementSuite(modelPath: String, outputPath: String) async throws {
        let suiteStarted = Date()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-model-replacement-suite", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        )
        var preferences = await engine.registry().preferences
        preferences.fastTranslation.forceLLM = true
        preferences.defaultTranslationQuality = .natural
        try await engine.setPreferences(preferences)
        let model = try await engine.addModel(from: URL(fileURLWithPath: modelPath))

        let fingerprintStarted = Date()
        let fingerprint = try AssistantModelFingerprint.fingerprint(for: model)
        let fingerprintMilliseconds = elapsedMilliseconds(since: fingerprintStarted)

        let loadStarted = Date()
        try await engine.warmUpLocalTextModel(id: model.id)
        let coldLoadMilliseconds = elapsedMilliseconds(since: loadStarted)

        // 直接复用产品的六项文本夹具，确保与历史报告的输入、提示词和输出预算一致。
        var textResults: [TextFeatureSuiteResult] = []
        for item in textFeatureSuiteCases {
            let started = Date()
            do {
                let result = try await engine.run(
                    request: item.request,
                    modelID: model.id,
                    persistHistory: false
                )
                textResults.append(TextFeatureSuiteResult(
                    id: item.id,
                    title: item.title,
                    task: item.request.task.rawValue,
                    input: item.request.inputText,
                    output: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    elapsedMilliseconds: elapsedMilliseconds(since: started),
                    error: nil
                ))
            } catch {
                textResults.append(TextFeatureSuiteResult(
                    id: item.id,
                    title: item.title,
                    task: item.request.task.rawValue,
                    input: item.request.inputText,
                    output: nil,
                    elapsedMilliseconds: elapsedMilliseconds(since: started),
                    error: error.localizedDescription
                ))
            }
        }

        let detailedInput = "The browser extension preserves links and form fields, but the first launch can still feel overwhelming to new users."
        let detailedStarted = Date()
        let detailedTranslation: ReplacementDetailedTranslationResult
        do {
            let result = try await engine.run(
                request: TaskRequest(
                    task: .translate,
                    inputText: detailedInput,
                    sourceLanguage: "en",
                    targetLanguage: "zh-Hans",
                    translationQuality: .natural,
                    translationOutputMode: .detailed
                ),
                modelID: model.id,
                persistHistory: false
            )
            let study = result.translationStudy
            let contractPassed = study.map {
                !$0.alternatives.isEmpty
                    && (3...8).contains($0.keyTerms.count)
                    && $0.keyTerms.allSatisfy { term in
                        detailedInput.range(of: term.term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
            } ?? false
            detailedTranslation = ReplacementDetailedTranslationResult(
                elapsedMilliseconds: elapsedMilliseconds(since: detailedStarted),
                contractPassed: contractPassed,
                translation: result.text,
                alternatives: study?.alternatives ?? [],
                keyTerms: study?.keyTerms.map(\.term) ?? [],
                rawOutput: result.rawText,
                error: nil
            )
        } catch {
            detailedTranslation = ReplacementDetailedTranslationResult(
                elapsedMilliseconds: elapsedMilliseconds(since: detailedStarted),
                contractPassed: false,
                translation: nil,
                alternatives: [],
                keyTerms: [],
                rawOutput: nil,
                error: error.localizedDescription
            )
        }

        // 产品资格检查在计时前先执行一次判断预热，再按冻结顺序运行全部 24 个夹具。
        if let warmupInput = AssistantJudgmentFixtures.all.first?.input {
            _ = try await runAssistantJudgment(engine: engine, modelID: model.id, input: warmupInput)
        }
        var qualificationSamples: [AssistantQualificationSample] = []
        var fixtureResults: [ReplacementAssistantFixtureResult] = []
        for fixture in AssistantJudgmentFixtures.all {
            let started = Date()
            do {
                let output = try await runAssistantJudgment(engine: engine, modelID: model.id, input: fixture.input)
                let latency = elapsedMilliseconds(since: started)
                let parsed = AssistantJudgmentContract.parse(output, input: fixture.input)
                qualificationSamples.append(AssistantQualificationSample(
                    fixtureID: fixture.id,
                    output: output,
                    latencyMilliseconds: latency
                ))
                fixtureResults.append(ReplacementAssistantFixtureResult(
                    id: fixture.id,
                    expectsPeek: fixture.expectsPeek,
                    isHardNegative: fixture.isHardNegative,
                    elapsedMilliseconds: latency,
                    validJSON: parsed != nil,
                    permitsPeek: AssistantJudgmentContract.permitsPeek(
                        parsed,
                        proactivity: fixture.input.proactivity,
                        input: fixture.input
                    ),
                    output: output,
                    error: nil
                ))
            } catch {
                let latency = elapsedMilliseconds(since: started)
                qualificationSamples.append(AssistantQualificationSample(
                    fixtureID: fixture.id,
                    output: nil,
                    latencyMilliseconds: latency
                ))
                fixtureResults.append(ReplacementAssistantFixtureResult(
                    id: fixture.id,
                    expectsPeek: fixture.expectsPeek,
                    isHardNegative: fixture.isHardNegative,
                    elapsedMilliseconds: latency,
                    validJSON: false,
                    permitsPeek: false,
                    output: nil,
                    error: error.localizedDescription
                ))
            }
        }
        let qualification = AssistantQualificationEvaluator.evaluate(
            modelID: model.id,
            modelFingerprint: fingerprint,
            samples: qualificationSamples
        )

        let (meetingSegments, meetingSpeakers) = replacementMeetingFixture()
        let meetingStarted = Date()
        let meetingNotes: ReplacementMeetingNotesResult
        do {
            let notes = try await engine.generateLocalMeetingNotes(
                segments: meetingSegments,
                speakers: meetingSpeakers,
                modelID: model.id
            )
            meetingNotes = ReplacementMeetingNotesResult(
                elapsedMilliseconds: elapsedMilliseconds(since: meetingStarted),
                sourceCharacterCount: meetingSegments.map(\.text).joined().count,
                sourceSegmentCount: meetingSegments.count,
                chunkCount: notes.chunkCount,
                hasContent: notes.hasContent,
                summary: notes.summary,
                decisions: notes.decisions,
                actionItems: notes.actionItems,
                openQuestions: notes.openQuestions,
                topics: notes.topics,
                error: nil
            )
        } catch {
            meetingNotes = ReplacementMeetingNotesResult(
                elapsedMilliseconds: elapsedMilliseconds(since: meetingStarted),
                sourceCharacterCount: meetingSegments.map(\.text).joined().count,
                sourceSegmentCount: meetingSegments.count,
                chunkCount: 0,
                hasContent: false,
                summary: nil,
                decisions: [],
                actionItems: [],
                openQuestions: [],
                topics: [],
                error: error.localizedDescription
            )
        }

        let ttsSource = "雨停后，林夏推开会议室的门。\n“构建终于通过了。”林夏松了口气。\n周然摇头：“先别发布，我们还要确认内存卸载。”\n窗外传来下班提示音，林夏回答：“我今晚补完报告，明早一起复核。”"
        let ttsStarted = Date()
        let ttsAnalysis: ReplacementTTSAnalysisResult
        do {
            let analysis = try await engine.analyzeTTSScript(source: ttsSource, modelID: model.id)
            ttsAnalysis = ReplacementTTSAnalysisResult(
                elapsedMilliseconds: elapsedMilliseconds(since: ttsStarted),
                sourceCharacterCount: ttsSource.count,
                voices: analysis.voices.map(\.name),
                segments: analysis.segments.map {
                    ReplacementTTSSegmentResult(
                        index: $0.index,
                        kind: $0.kind.rawValue,
                        speakerName: $0.speakerName,
                        sourceText: $0.sourceText,
                        deliveryStyle: $0.deliveryStyle,
                        pauseAfterMilliseconds: $0.pauseAfterMilliseconds
                    )
                },
                error: nil
            )
        } catch {
            ttsAnalysis = ReplacementTTSAnalysisResult(
                elapsedMilliseconds: elapsedMilliseconds(since: ttsStarted),
                sourceCharacterCount: ttsSource.count,
                voices: [],
                segments: [],
                error: error.localizedDescription
            )
        }

        let loadedBeforeUnload = await engine.loadedLocalTextModelID() == model.id
        await engine.unloadAll()
        let unloadedAfterUnload = await engine.loadedLocalTextModelID() == nil

        let report = ReplacementSuiteReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            modelName: model.name,
            modelPath: model.displayPath,
            modelFormat: model.format.rawValue,
            modelRole: model.role.rawValue,
            modelSizeClass: model.sizeClass,
            contextLength: model.contextLength,
            fingerprintPrefix: String(fingerprint.prefix(16)),
            fingerprintMilliseconds: fingerprintMilliseconds,
            coldLoadMilliseconds: coldLoadMilliseconds,
            totalElapsedMilliseconds: elapsedMilliseconds(since: suiteStarted),
            textResults: textResults,
            detailedTranslation: detailedTranslation,
            assistantQualification: ReplacementAssistantQualificationResult(
                state: qualification.state.rawValue,
                message: qualification.message,
                validJSONCount: qualification.validJSONCount,
                positivePassCount: qualification.positivePassCount,
                negativeFalsePositiveCount: qualification.negativeFalsePositiveCount,
                hardFailureCount: qualification.hardFailureCount,
                maximumLatencyMilliseconds: qualification.maximumLatencyMilliseconds,
                fixtures: fixtureResults
            ),
            meetingNotes: meetingNotes,
            ttsAnalysis: ttsAnalysis,
            lifecycle: ReplacementLifecycleResult(
                loadedBeforeUnload: loadedBeforeUnload,
                unloadedAfterUnload: unloadedAfterUnload
            )
        )
        let destination = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: destination, options: .atomic)
        print("Wrote replacement suite: \(destination.path)")
        print("model=\(model.name) assistant=\(qualification.message) detailed=\(detailedTranslation.contractPassed) meeting=\(meetingNotes.hasContent) tts=\(ttsAnalysis.segments.count)")
    }

    private static func runAssistantJudgment(
        engine: TaskEngine,
        modelID: UUID,
        input: AssistantJudgmentInput
    ) async throws -> String {
        let result = try await engine.runExactLocalText(
            request: TaskRequest(
                task: .explain,
                inputText: input.evidenceSummary,
                systemPromptOverride: AssistantJudgmentContract.runtimeSystemPrompt(minimumConfidenceOverride: nil),
                userPromptOverride: AssistantJudgmentContract.userPrompt(for: input, minimumConfidenceOverride: nil),
                thinkingModeOverride: false,
                maxOutputTokensOverride: 256
            ),
            modelID: modelID
        )
        return result.text
    }

    private static func replacementMeetingFixture() -> ([LiveMeetingSegment], [LiveMeetingSpeaker]) {
        let speakers = [
            LiveMeetingSpeaker(id: "pm", label: "产品", displayName: "林夏"),
            LiveMeetingSpeaker(id: "eng", label: "工程", displayName: "周然"),
            LiveMeetingSpeaker(id: "qa", label: "测试", displayName: "陈宁")
        ]
        var lines: [(String, String, String)] = [
            ("pm", "产品", "本次评审目标是决定候选文本模型是否能成为 llmTools 的优先推荐。最终决定：只有全部结构化链路和二十四项助手资格都通过，才允许替换现有 Qwen3.5-9B。"),
            ("eng", "工程", "模型测试统一在 Apple M5 Pro、64GB 内存上执行，固定 temperature 为零，并保存原始 JSON，不使用远程回退。")
        ]
        for index in 1...50 {
            lines.append((
                index.isMultiple(of: 2) ? "eng" : "qa",
                index.isMultiple(of: 2) ? "工程" : "测试",
                "第 \(index) 轮状态复核覆盖翻译、润色、摘要、技术解释、待办提取、结构化输出、热请求延迟和模型卸载。所有观察必须记录输入、输出和毫秒耗时，不能因为单项速度快就跳过质量检查；重复核对用于形成超过单个提示词的长会议上下文。"
            ))
            if index == 10 {
                lines.append(("qa", "测试", "待办一：陈宁在本周五前跑完二十四项助手夹具并记录所有假阳性。待办二：周然记录冷启动、最大常驻内存和 unload 后状态。"))
            }
            if index == 35 {
                lines.append(("pm", "产品", "发布目标暂定八月八日，但只要任一硬负例失败就阻断切换。网页翻译继续使用 MiniCPM5-1B，不受本次 8B 候选评估影响。"))
            }
        }
        lines.append(("pm", "产品", "开放问题：16GB 内存的基础款 Mac 是否能稳定运行 8B 模型，当前这台 64GB 机器无法直接回答，需要后续单独验证。林夏负责把结论和证据整理进 docs。"))
        let segments = lines.enumerated().map { index, value in
            LiveMeetingSegment(
                index: index,
                startTime: Double(index * 20),
                endTime: Double(index * 20 + 18),
                text: value.2,
                speakerID: value.0,
                speakerLabel: value.1,
                confidence: 0.98
            )
        }
        return (segments, speakers)
    }

    private static func elapsedMilliseconds(since started: Date) -> Int {
        Int((Date().timeIntervalSince(started) * 1_000).rounded())
    }

    private static func runFastMTNLLBBenchmark() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-fastmt-nllb-bench", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = BenchUnusedRunner()
        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: root.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
            runners: [.mlx: runner]
        )
        let model = try await engine.addModel(from: try makeMinimalMLXModelDirectory(root: root))
        var preferences = await engine.registry().preferences
        preferences.defaultModelID = model.id
        preferences.fastTranslation.textEngine = .fastMT
        preferences.fastTranslation.webpageEngine = .fastMT
        preferences.fastTranslation.modelVariant = .nllb200Distilled600M
        preferences.fastTranslation.fallbackPolicy = .showError
        try await engine.setPreferences(preferences)

        let started = Date()
        let translated = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "設定を変更すると、次回の翻訳から新しいモデルが使われます。",
                sourceLanguage: "ja",
                targetLanguage: "zh-Hans"
            ),
            modelID: model.id,
            persistHistory: false
        )
        print("BEGIN_FASTMT_NLLB_TEXT")
        print("seconds=\(String(format: "%.3f", Date().timeIntervalSince(started))) generatedRequests=\(await runner.generatedRequestCount())")
        print("output=\(translated.text)")
        print("END_FASTMT_NLLB_TEXT")

        let payload = WebPageTranslateSegmentsPayload(
            jobID: "fastmt-nllb-web",
            sourceLanguage: "fr",
            targetLanguage: "zh-Hans",
            translationEngine: .fastMT,
            segments: [
                WebPageTranslationSegment(segmentID: "fr-1", text: "Cette option permet de traduire rapidement le texte visible de la page.", textHash: "fr-1")
            ]
        )
        let webStarted = Date()
        let web = try await engine.translateWebPageSegments(payload: payload, modelID: model.id)
        print("BEGIN_FASTMT_NLLB_WEB")
        print("seconds=\(String(format: "%.3f", Date().timeIntervalSince(webStarted))) generatedRequests=\(await runner.generatedRequestCount())")
        print("output=\(web.translations.first?.translation ?? "")")
        print("engine=\(web.translationEngineID) model=\(web.translationModelID ?? "")")
        print("END_FASTMT_NLLB_WEB")
    }

    private static func makeMinimalMLXModelDirectory(root: URL) throws -> URL {
        let directory = root.appendingPathComponent("Bench-MLX", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: directory.appendingPathComponent("config.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: directory.appendingPathComponent("tokenizer.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: directory.appendingPathComponent("model.safetensors").path, contents: Data())
        return directory
    }
}

private struct BenchSample {
    var id: String
    var source: String
    var target: String
    var text: String
}

private struct TextFeatureSuiteCase {
    var id: String
    var title: String
    var request: TaskRequest
}

private struct TextFeatureSuiteReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var modelName: String
    var modelPath: String
    var contextLength: Int
    var warmupTask: String
    var results: [TextFeatureSuiteResult]
}

private struct TextFeatureSuiteResult: Encodable {
    var id: String
    var title: String
    var task: String
    var input: String
    var output: String?
    var elapsedMilliseconds: Int
    var error: String?
}

private struct ReplacementSuiteReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var modelName: String
    var modelPath: String
    var modelFormat: String
    var modelRole: String
    var modelSizeClass: String
    var contextLength: Int
    var fingerprintPrefix: String
    var fingerprintMilliseconds: Int
    var coldLoadMilliseconds: Int
    var totalElapsedMilliseconds: Int
    var textResults: [TextFeatureSuiteResult]
    var detailedTranslation: ReplacementDetailedTranslationResult
    var assistantQualification: ReplacementAssistantQualificationResult
    var meetingNotes: ReplacementMeetingNotesResult
    var ttsAnalysis: ReplacementTTSAnalysisResult
    var lifecycle: ReplacementLifecycleResult
}

private struct ReplacementDetailedTranslationResult: Encodable {
    var elapsedMilliseconds: Int
    var contractPassed: Bool
    var translation: String?
    var alternatives: [String]
    var keyTerms: [String]
    var rawOutput: String?
    var error: String?
}

private struct ReplacementAssistantQualificationResult: Encodable {
    var state: String
    var message: String
    var validJSONCount: Int
    var positivePassCount: Int
    var negativeFalsePositiveCount: Int
    var hardFailureCount: Int
    var maximumLatencyMilliseconds: Int
    var fixtures: [ReplacementAssistantFixtureResult]
}

private struct ReplacementAssistantFixtureResult: Encodable {
    var id: String
    var expectsPeek: Bool
    var isHardNegative: Bool
    var elapsedMilliseconds: Int
    var validJSON: Bool
    var permitsPeek: Bool
    var output: String?
    var error: String?
}

private struct ReplacementMeetingNotesResult: Encodable {
    var elapsedMilliseconds: Int
    var sourceCharacterCount: Int
    var sourceSegmentCount: Int
    var chunkCount: Int
    var hasContent: Bool
    var summary: String?
    var decisions: [String]
    var actionItems: [String]
    var openQuestions: [String]
    var topics: [String]
    var error: String?
}

private struct ReplacementTTSAnalysisResult: Encodable {
    var elapsedMilliseconds: Int
    var sourceCharacterCount: Int
    var voices: [String]
    var segments: [ReplacementTTSSegmentResult]
    var error: String?
}

private struct ReplacementTTSSegmentResult: Encodable {
    var index: Int
    var kind: String
    var speakerName: String?
    var sourceText: String
    var deliveryStyle: String?
    var pauseAfterMilliseconds: Int
}

private struct ReplacementLifecycleResult: Encodable {
    var loadedBeforeUnload: Bool
    var unloadedAfterUnload: Bool
}

private let textFeatureSuiteCases: [TextFeatureSuiteCase] = [
    TextFeatureSuiteCase(
        id: "translate_en_zh",
        title: "English to Simplified Chinese translation",
        request: TaskRequest(
            task: .translate,
            inputText: "The release keeps local data on this Mac and applies the new model setting to the next request.",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            translationQuality: .natural
        )
    ),
    TextFeatureSuiteCase(
        id: "translate_zh_en",
        title: "Simplified Chinese to English translation",
        request: TaskRequest(
            task: .translate,
            inputText: "实时字幕应先显示原文，再在本地模型完成后补充译文，并且不能上传音频。",
            sourceLanguage: "zh-Hans",
            targetLanguage: "en",
            translationQuality: .natural
        )
    ),
    TextFeatureSuiteCase(
        id: "polish_zh",
        title: "Chinese polishing",
        request: TaskRequest(
            task: .polish,
            inputText: "这个功能现在已经可以用了但是第一次打开可能有点慢用户可以等一下再试。",
            polishStyle: "professional"
        )
    ),
    TextFeatureSuiteCase(
        id: "summarize_zh",
        title: "Chinese summarization",
        request: TaskRequest(
            task: .summarize,
            inputText: "本次更新新增了本地实时字幕模型，并将其与文件转写路径分开。实时模式持续保留模型缓存以降低后续片段延迟；文件模式仍使用适合完整音频的转写模型。所有语音数据只在本机处理，模型切换后新的会话才会采用新设置。"
        )
    ),
    TextFeatureSuiteCase(
        id: "explain_en",
        title: "Technical explanation",
        request: TaskRequest(
            task: .explain,
            inputText: "Explain in Chinese why a streaming ASR decoder should retain state between consecutive audio chunks. Limit the answer to three sentences."
        )
    ),
    TextFeatureSuiteCase(
        id: "extract_todos",
        title: "TODO extraction",
        request: TaskRequest(
            task: .extractTodos,
            inputText: "发布前请完成三件事：下载 8bit ASR 权重，跑完中英文延迟测试，并把报告放进 docs。产品同学下周再确认默认模型文案。"
        )
    )
]

private let webpageTexts = [
    "Click the toolbar button again to restore the original page content.",
    "The browser extension translates visible page text while preserving links and form fields.",
    "Settings changes apply to the next translation request.",
    "Use fast machine translation for broad page coverage and the LLM for higher quality."
]

private struct BenchError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private actor BenchUnusedRunner: ModelRunner {
    private var requestCount = 0
    private var loadedID: UUID?

    func modelFormat() async -> ModelFormat {
        .mlx
    }

    func loadedState() async -> Bool {
        loadedID != nil
    }

    func loadedModelID() async -> UUID? {
        loadedID
    }

    func loadedModelName() async -> String? {
        "Bench unused runner"
    }

    func load(model: ModelDescriptor) async throws {
        loadedID = model.id
    }

    func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        requestCount += 1
        return TaskResult(text: "unexpected LLM fallback", modelName: "Bench unused runner", task: request.task)
    }

    func unload() async {
        loadedID = nil
    }

    func generatedRequestCount() -> Int {
        requestCount
    }
}
