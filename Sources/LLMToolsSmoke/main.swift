import Foundation
import LLMToolsCore

@main
struct LLMToolsSmoke {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let runsAssistantJudgment = args.first == "--assistant-judgment"
        let remainingArgs = runsAssistantJudgment ? Array(args.dropFirst()) : args
        guard let path = remainingArgs.first else {
            print("Usage: LLMToolsSmoke [--assistant-judgment] <model-path> [prompt]")
            throw SmokeError("Missing model path.")
        }

        let prompt = remainingArgs.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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

        if runsAssistantJudgment {
            do {
                try await runAssistantQualification(engine: engine, model: model)
                await engine.unloadAll()
            } catch {
                await engine.unloadAll()
                throw error
            }
            return
        }

        let result = try await engine.run(
            request: TaskRequest(task: .explain, inputText: input),
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

    private static func runAssistantQualification(engine: TaskEngine, model: ModelDescriptor) async throws {
        let modelID = model.id
        print("Preparing assistant judgment model...")
        try await withTimeout(seconds: 120) {
            try await engine.warmUpLocalTextModel(id: modelID)
        }
        if let warmupInput = AssistantJudgmentFixtures.all.first?.input {
            _ = try await withTimeout(seconds: 30) {
                try await engine.runExactLocalText(
                    request: judgmentRequest(for: warmupInput),
                    modelID: modelID
                )
            }
        }

        var samples: [AssistantQualificationSample] = []
        for fixture in AssistantJudgmentFixtures.all {
            let startedAt = Date()
            let output: String?
            do {
                let input = fixture.input
                let result = try await withTimeout(seconds: 5) {
                    try await engine.runExactLocalText(
                        request: judgmentRequest(for: input),
                        modelID: modelID
                    )
                }
                output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch is SmokeTimeoutError {
                throw SmokeError("Hot-inference fixture \(fixture.id) exceeded 5 seconds.")
            } catch {
                output = nil
                print("FAIL \(fixture.id): \(error)")
            }
            let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
            samples.append(AssistantQualificationSample(
                fixtureID: fixture.id,
                output: output,
                latencyMilliseconds: latency
            ))
            let parsed = output.flatMap {
                AssistantJudgmentContract.parse($0, input: fixture.input)
            }
            let permitsPeek = parsed.map {
                AssistantJudgmentContract.permitsPeek(
                    $0,
                    proactivity: fixture.input.proactivity,
                    input: fixture.input
                )
            } ?? false
            if parsed == nil || permitsPeek != fixture.expectsPeek {
                print("FAIL \(fixture.id): expectedPeek=\(fixture.expectsPeek), permitsPeek=\(permitsPeek), latency=\(latency)ms")
                print(output ?? "<no output>")
            }
        }
        let summary = AssistantQualificationEvaluator.evaluate(
            modelID: modelID,
            modelFingerprint: "smoke",
            samples: samples
        )
        print("Qualification: \(summary.state.rawValue) · \(summary.message)")
        guard summary.state == .qualified else {
            throw SmokeError("Assistant judgment qualification failed.")
        }
    }

    private static func judgmentRequest(for input: AssistantJudgmentInput) -> TaskRequest {
        TaskRequest(
            task: .explain,
            inputText: input.evidenceSummary,
            systemPromptOverride: AssistantJudgmentContract.systemPrompt,
            userPromptOverride: AssistantJudgmentContract.userPrompt(for: input),
            thinkingModeOverride: false,
            maxOutputTokensOverride: 256
        )
    }

    private static func withTimeout<Value: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        // 与应用内资格检查一致：超时立即取消生成，不让失控的模型阻塞后续验证。
        let race = SmokeTimeoutRace<Value>()
        let operationTask = Task {
            do {
                await race.resolve(.success(try await operation()))
            } catch {
                await race.resolve(.failure(error))
            }
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            operationTask.cancel()
            await race.resolve(.failure(SmokeTimeoutError()))
        }
        return try await withTaskCancellationHandler {
            defer { timeoutTask.cancel() }
            return try await race.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task { await race.resolve(.failure(CancellationError())) }
        }
    }
}

private actor SmokeTimeoutRace<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
}

private struct SmokeTimeoutError: Error {}

private struct SmokeError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
