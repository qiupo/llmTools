import Foundation
import LLMToolsCore

@main
struct LLMToolsSmoke {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let path = args.first else {
            print("Usage: LLMToolsSmoke <model-path> [prompt]")
            throw SmokeError("Missing model path.")
        }

        let prompt = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let input = prompt.isEmpty ? "Reply with one short sentence: local model smoke test passed." : prompt
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmTools-smoke", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let model = try await engine.addModel(from: URL(fileURLWithPath: path))

        print("Detected model: \(model.name)")
        print("Format: \(model.format.rawValue)")
        print("Size: \(model.sizeClass)")
        print("Path: \(model.displayPath)")
        print("Loading and generating...")

        let result = try await engine.run(
            request: TaskRequest(
                task: .explain,
                inputText: input
            ),
            modelID: model.id
        )
        await engine.unloadAll()

        let output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw SmokeError("Model returned an empty result.")
        }

        print("Output:")
        print(output)
    }
}

private struct SmokeError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
