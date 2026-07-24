import Foundation
import LLMToolsCore

@main
struct LLMToolsRealtimeASRBench {
    static func main() async throws {
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        let outputDirectory = URL(fileURLWithPath: options.outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: outputDirectory.path)

        let fixturesDirectory = outputDirectory.appendingPathComponent("fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true)
        let fixtures = try makeFixtures(in: fixturesDirectory)

        let registryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-realtime-asr-bench", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: registryDirectory) }

        let engine = TaskEngine(
            registryStore: RegistryStore(fileURL: registryDirectory.appendingPathComponent("registry.json")),
            historyStore: HistoryStore(fileURL: registryDirectory.appendingPathComponent("history.json"))
        )
        let qwen = try await engine.addModel(from: URL(fileURLWithPath: options.qwenModelPath))
        let nemotron = try await engine.addModel(from: URL(fileURLWithPath: options.nemotronModelPath))

        let qwenReport = try await benchmarkQwen(model: qwen, fixtures: fixtures)
        let nemotronReport = try await benchmarkNemotron(model: nemotron, fixtures: fixtures)
        await engine.unloadAll()

        let report = RealtimeASRBenchmarkReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            chunkMilliseconds: 1_120,
            fixtures: fixtures.map(FixtureReport.init),
            backends: [qwenReport, nemotronReport]
        )
        let reportURL = outputDirectory.appendingPathComponent("asr-realtime-benchmark.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)

        print("Wrote realtime ASR benchmark: \(reportURL.path)")
        for backend in report.backends {
            print("\(backend.backend) startup=\(backend.startupMilliseconds)ms")
            for result in backend.results {
                let accuracy = String(format: "%.3f", result.errorRate)
                print("  \(result.fixtureID) first=\(result.firstResponseMilliseconds)ms final=\(result.finalResponseMilliseconds)ms \(result.accuracyMetric)=\(accuracy)")
            }
        }
    }

    private static func benchmarkQwen(
        model: ModelDescriptor,
        fixtures: [Fixture]
    ) async throws -> BackendReport {
        let started = Date()
        let session = try await StreamingASRProcessSession.start(
            model: model,
            sourceLanguageHint: .auto
        )
        let startupMilliseconds = milliseconds(since: started)
        defer { session.stop() }
        let results = try await benchmark(session: session, fixtures: fixtures)
        return BackendReport(
            backend: "Qwen3-ASR-0.6B-8bit",
            modelName: model.name,
            modelPath: model.displayPath,
            startupMilliseconds: startupMilliseconds,
            results: results
        )
    }

    private static func benchmarkNemotron(
        model: ModelDescriptor,
        fixtures: [Fixture]
    ) async throws -> BackendReport {
        let started = Date()
        let session = try await NemotronStreamingASRSession.start(
            model: model,
            sourceLanguageHint: .auto
        )
        let startupMilliseconds = milliseconds(since: started)
        defer { session.stop() }
        let results = try await benchmark(session: session, fixtures: fixtures)
        return BackendReport(
            backend: "Nemotron-3.5-ASR-Streaming-0.6B Core ML",
            modelName: model.name,
            modelPath: model.displayPath,
            startupMilliseconds: startupMilliseconds,
            results: results
        )
    }

    private static func benchmark(
        session: any RealtimeASRSession,
        fixtures: [Fixture]
    ) async throws -> [BackendFixtureResult] {
        try await fixtures.asyncMap { fixture in
            let pcm = try LiveMeetingAudioStorage.readPCM16WAV(at: fixture.url)
            guard pcm.sampleRate == 16_000 else {
                throw BenchmarkError("Fixture \(fixture.id) is not 16 kHz PCM audio.")
            }
            let firstChunkByteCount = min(pcm.data.count, 1_120 * pcm.sampleRate * 2 / 1_000)
            let firstChunk = Data(pcm.data.prefix(firstChunkByteCount - firstChunkByteCount % 2))
            let sessionID = UUID()
            let duration = Double(pcm.data.count) / Double(pcm.sampleRate * 2)

            let firstStarted = Date()
            let partialSegments = try await session.transcribe(
                pcm16Data: firstChunk,
                sampleRate: pcm.sampleRate,
                sessionID: sessionID,
                duration: Double(firstChunk.count) / Double(pcm.sampleRate * 2),
                sourceLanguageHint: fixture.language,
                isFinal: false
            )
            let firstResponseMilliseconds = milliseconds(since: firstStarted)

            let finalStarted = Date()
            let finalSegments = try await session.transcribe(
                pcm16Data: pcm.data,
                sampleRate: pcm.sampleRate,
                sessionID: sessionID,
                duration: duration,
                sourceLanguageHint: fixture.language,
                isFinal: true
            )
            let finalResponseMilliseconds = milliseconds(since: finalStarted)
            let finalText = transcript(from: finalSegments)
            let metric = fixture.language == .zh ? "character_error_rate" : "word_error_rate"
            let errorRate = fixture.language == .zh
                ? characterErrorRate(reference: fixture.reference, hypothesis: finalText)
                : wordErrorRate(reference: fixture.reference, hypothesis: finalText)
            return BackendFixtureResult(
                fixtureID: fixture.id,
                language: fixture.language.rawValue,
                reference: fixture.reference,
                firstChunkMilliseconds: 1_120,
                firstPartialTranscript: transcript(from: partialSegments),
                firstResponseMilliseconds: firstResponseMilliseconds,
                finalTranscript: finalText,
                finalResponseMilliseconds: finalResponseMilliseconds,
                accuracyMetric: metric,
                errorRate: errorRate
            )
        }
    }

    private static func makeFixtures(in directory: URL) throws -> [Fixture] {
        let definitions: [(id: String, voice: String, language: ASRSourceLanguageHint, text: String)] = [
            ("zh_cn", "Tingting", .zh, "本地实时字幕需要保留模型状态并降低延迟。"),
            ("en_us", "Samantha", .en, "Local realtime captions should keep decoder state and reduce latency.")
        ]
        return try definitions.map { definition in
            let aiffURL = directory.appendingPathComponent("\(definition.id).aiff")
            let wavURL = directory.appendingPathComponent("\(definition.id).wav")
            try runProcess("/usr/bin/say", ["-v", definition.voice, "-o", aiffURL.path, definition.text])
            try runProcess(
                "/usr/bin/afconvert",
                [aiffURL.path, wavURL.path, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"]
            )
            try? FileManager.default.removeItem(at: aiffURL)
            return Fixture(id: definition.id, language: definition.language, reference: definition.text, url: wavURL)
        }
    }

    private static func runProcess(_ executablePath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw BenchmarkError("\(URL(fileURLWithPath: executablePath).lastPathComponent) failed: \(message)")
        }
    }

    private static func transcript(from segments: [SubtitleSegment]) -> String {
        segments.map(\.originalText).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func milliseconds(since date: Date) -> Int {
        Int((Date().timeIntervalSince(date) * 1_000).rounded())
    }

    private static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let referenceTokens = Array(reference.filter { $0.isLetter || $0.isNumber })
        let hypothesisTokens = Array(hypothesis.filter { $0.isLetter || $0.isNumber })
        return normalizedEditDistance(reference: referenceTokens, hypothesis: hypothesisTokens)
    }

    private static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let referenceTokens = normalizedEnglishWords(reference)
        let hypothesisTokens = normalizedEnglishWords(hypothesis)
        return normalizedEditDistance(reference: referenceTokens, hypothesis: hypothesisTokens)
    }

    private static func normalizedEnglishWords(_ value: String) -> [String] {
        value.lowercased()
            // 连字符是词内拼写差异，不应把 real-time 与 realtime 当成 ASR 替换错误。
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
    }

    private static func normalizedEditDistance<Token: Equatable>(reference: [Token], hypothesis: [Token]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        var previous = Array(0...hypothesis.count)
        for (referenceIndex, referenceToken) in reference.enumerated() {
            var current = [referenceIndex + 1]
            for (hypothesisIndex, hypothesisToken) in hypothesis.enumerated() {
                let substitutionCost = referenceToken == hypothesisToken ? 0 : 1
                current.append(min(
                    previous[hypothesisIndex + 1] + 1,
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex] + substitutionCost
                ))
            }
            previous = current
        }
        return Double(previous[hypothesis.count]) / Double(reference.count)
    }
}

private struct Options {
    var qwenModelPath: String
    var nemotronModelPath: String
    var outputDirectory: String

    static func parse(_ arguments: [String]) throws -> Options {
        guard arguments.count == 3 else {
            throw BenchmarkError("Usage: LLMToolsRealtimeASRBench <qwen-8bit-model-path> <nemotron-coreml-repository-or-variant-path> <output-directory>")
        }
        return Options(
            qwenModelPath: arguments[0],
            nemotronModelPath: arguments[1],
            outputDirectory: arguments[2]
        )
    }
}

private struct Fixture: Sendable {
    var id: String
    var language: ASRSourceLanguageHint
    var reference: String
    var url: URL
}

private struct FixtureReport: Encodable {
    var id: String
    var language: String
    var reference: String
    var wavPath: String
    var durationMilliseconds: Int

    init(_ fixture: Fixture) {
        id = fixture.id
        language = fixture.language.rawValue
        reference = fixture.reference
        wavPath = fixture.url.path
        let data = (try? LiveMeetingAudioStorage.readPCM16WAV(at: fixture.url).data) ?? Data()
        durationMilliseconds = data.count / 32
    }
}

private struct RealtimeASRBenchmarkReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var chunkMilliseconds: Int
    var fixtures: [FixtureReport]
    var backends: [BackendReport]
}

private struct BackendReport: Encodable {
    var backend: String
    var modelName: String
    var modelPath: String
    var startupMilliseconds: Int
    var results: [BackendFixtureResult]
}

private struct BackendFixtureResult: Encodable {
    var fixtureID: String
    var language: String
    var reference: String
    var firstChunkMilliseconds: Int
    var firstPartialTranscript: String
    var firstResponseMilliseconds: Int
    var finalTranscript: String
    var finalResponseMilliseconds: Int
    var accuracyMetric: String
    var errorRate: Double
}

private struct BenchmarkError: Error, LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private extension Array {
    func asyncMap<T: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
