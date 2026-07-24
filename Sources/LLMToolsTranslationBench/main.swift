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
        guard let modelPath = args.first else {
            print("Usage: LLMToolsTranslationBench <model-path>")
            print("       LLMToolsTranslationBench --fast-mt-nllb")
            print("       LLMToolsTranslationBench --detailed <model-path>")
            print("       LLMToolsTranslationBench --text-suite <model-path> <output.json>")
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

        let started = Date()
        let result = try await engine.run(
            request: TaskRequest(
                task: .translate,
                inputText: "The browser extension preserves links and form fields, but the first launch can still feel overwhelming to new users.",
                sourceLanguage: "en",
                targetLanguage: "zh-Hans",
                translationQuality: .natural,
                translationOutputMode: .detailed
            ),
            modelID: model.id,
            persistHistory: false
        )
        await engine.unloadAll()

        guard let study = result.translationStudy, !study.keyTerms.isEmpty else {
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
