import Foundation
import LLMTranslateCore

@main
struct LLMTranslateChecks {
    static func main() async throws {
        try checkGGUFDetectionChoosesPrimaryModel()
        try checkMLXDetection()
        try await checkModelDisplayName()
        try await checkHistoryLimit()
        try checkPreferenceDefaultsDecodeFromOlderRegistry()
        try await checkTaskEngineReturnsRawModelOutput()
        try checkVisibleOutputHidesThinkBlock()
        try checkPromptsStayCompact()
        print("LLMTranslateChecks passed")
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
        try require(preferences.defaultTranslationTarget == "English", "Expected existing target language value to be preserved.")
        try require(preferences.defaultPolishStyle == "formal", "Expected existing polish style value to be preserved.")
        try require(preferences.recentHistoryLimit == 8, "Expected existing history limit to be preserved.")
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
            .appendingPathComponent("llmTranslate-checks", isDirectory: true)
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
    private var loadedID: UUID?
    private let output: String?

    init(output: String? = nil) {
        self.output = output
    }

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
        "Stub"
    }

    func load(model: ModelDescriptor) async throws {
        loadedID = model.id
    }

    func generate(request: TaskRequest, preferences: AppPreferences) async throws -> TaskResult {
        TaskResult(text: output ?? "result \(request.inputText)", modelName: "Stub", task: request.task)
    }

    func unload() async {
        loadedID = nil
    }
}
