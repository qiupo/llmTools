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
        guard let modelPath = args.first else {
            print("Usage: LLMToolsTranslationBench <model-path>")
            print("       LLMToolsTranslationBench --fast-mt-nllb")
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
