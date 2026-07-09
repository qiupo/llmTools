import Foundation
import LLMToolsCore

@main
struct LLMToolsMediaSmoke {
    static func main() async throws {
        let options = SmokeOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        let root = try makeTemporaryDirectory()
        defer {
            if !options.keepTemporaryFiles {
                try? FileManager.default.removeItem(at: root)
            }
        }

        let registry = try await RegistryStore().load()
        let speechSource = try options.speechModelPath.map(URL.init(fileURLWithPath:))
            ?? requireSpeechModelPath(from: registry)
        let textSource = try options.textModelPath.map(URL.init(fileURLWithPath:))
            ?? requireTextModelPath(from: registry)
        let audioURL = try options.audioPath.map(URL.init(fileURLWithPath:))
            ?? generateSpeechFixture(in: root)
        let outputDirectory = options.outputDirectory.map(URL.init(fileURLWithPath:))
            ?? root.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let registryStore = RegistryStore(fileURL: root.appendingPathComponent("registry.json"))
        let historyStore = HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let setupEngine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        let textModel = try await setupEngine.addModel(from: textSource)
        let speechModel = try await setupEngine.addModel(from: speechSource)
        var setupSnapshot = await setupEngine.registry()
        setupSnapshot.preferences.defaultModelID = textModel.id
        setupSnapshot.preferences.mediaSubtitles.isEnabled = true
        setupSnapshot.preferences.mediaSubtitles.fileASRModelID = speechModel.id
        if speechModel.capabilities.supportsRealtimeSpeech {
            setupSnapshot.preferences.mediaSubtitles.realtimeASRModelID = speechModel.id
        }
        setupSnapshot.preferences.mediaSubtitles.defaultTargetLanguage = "zh-Hans"
        setupSnapshot.preferences.mediaSubtitles.defaultSubtitleMode = .bilingual
        setupSnapshot.preferences.mediaSubtitles.saveTranscriptHistory = false
        setupSnapshot.preferences.mediaSubtitles.saveTranslatedSubtitleHistory = false
        try await registryStore.save(setupSnapshot)

        let engine = TaskEngine(registryStore: registryStore, historyStore: historyStore)
        await engine.bootstrap()

        let health = try await engine.checkASRHealth(modelID: speechModel.id, mode: .fileOnly)
        guard health.status == .ready else {
            throw SmokeError("ASR runtime is not ready: \(health.message)")
        }

        let fileResult = try await engine.transcribeMediaFile(at: audioURL, modelID: speechModel.id)
        guard !fileResult.segments.isEmpty else {
            throw SmokeError("ASR produced no subtitle segments.")
        }
        let translated = try await engine.translateSubtitleSegments(fileResult.segments, targetLanguage: "zh-Hans")
        guard translated.contains(where: { ($0.translatedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
            throw SmokeError("Subtitle translation produced no translated text.")
        }
        let fastMTFixture = FastMTFixture(
            engine: TranslationEngineID.ctranslate2.rawValue,
            model: "fixture-opus-mt-en-zh",
            supportedPairs: [LanguagePair(source: "en", target: "zh-Hans")],
            segments: fileResult.segments.map {
                FastMTFixtureSegment(id: $0.id.uuidString, translation: "fast fixture \($0.index)")
            },
            latencyMilliseconds: 12
        )
        let fastMTFixtureData = try JSONEncoder().encode(fastMTFixture)
        setenv(Phase4XFixtureEnvironment.fastTranslationJSON, String(data: fastMTFixtureData, encoding: .utf8) ?? "{}", 1)
        defer {
            unsetenv(Phase4XFixtureEnvironment.fastTranslationJSON)
        }
        var fastMTPreferences = await engine.registry().preferences
        fastMTPreferences.fastTranslation.subtitleEngine = .fastMT
        fastMTPreferences.fastTranslation.fallbackPolicy = .showError
        try await engine.setPreferences(fastMTPreferences)
        let fastMTInput = fileResult.segments.map { segment -> SubtitleSegment in
            var updated = segment
            updated.sourceLanguage = "en"
            updated.languageConfidence = 0.99
            return updated
        }
        let fastMTTranslated = try await engine.translateSubtitleSegments(fastMTInput, targetLanguage: "zh-Hans")
        guard fastMTTranslated.allSatisfy({ $0.translationEngineID == TranslationEngineID.ctranslate2.rawValue }) else {
            throw SmokeError("Fast MT fixture path did not mark subtitle translations with the fast MT engine.")
        }

        var exported: [String: String] = [:]
        for format in SubtitleExportFormat.allCases {
            let text = try await engine.exportSubtitleSegments(translated, format: format, mode: .bilingual)
            let url = outputDirectory.appendingPathComponent("phase4-media-smoke.\(format.fileExtension)")
            try text.write(to: url, atomically: true, encoding: .utf8)
            exported[format.rawValue] = url.path
        }

        let summary = MediaSmokeSummary(
            audioPath: audioURL.path,
            speechModel: speechModel.name,
            textModel: textModel.name,
            runtimeSource: health.runtimeSource.rawValue,
            segmentCount: fileResult.segments.count,
            firstTranscript: fileResult.segments.first?.originalText ?? "",
            firstTranslation: translated.first?.translatedText ?? "",
            fastMTFirstTranslation: fastMTTranslated.first?.translatedText ?? "",
            exported: exported,
            diagnostics: fileResult.diagnostics
        )
        let data = try JSONEncoder.pretty.encode(summary)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func requireSpeechModelPath(from registry: RegistrySnapshot) throws -> URL {
        let preferred = registry.models.first {
            $0.enabled && $0.capabilities.speech?.family == .qwen3ASR06B && $0.resolvedPath != nil
        } ?? registry.models.first {
            $0.enabled && $0.capabilities.supportsFileSpeech && $0.resolvedPath != nil
        }
        guard let path = preferred?.resolvedPath ?? preferred?.sourcePath else {
            throw SmokeError("No registered local speech model path found. Pass --speech-model <path>.")
        }
        return path
    }

    private static func requireTextModelPath(from registry: RegistrySnapshot) throws -> URL {
        let preferred = registry.models.first {
            $0.enabled && !$0.isRemoteProvider && $0.capabilities.supportsText && $0.resolvedPath != nil
        }
        guard let path = preferred?.resolvedPath ?? preferred?.sourcePath else {
            throw SmokeError("No registered local text model path found. Pass --text-model <path>.")
        }
        return path
    }

    private static func generateSpeechFixture(in root: URL) throws -> URL {
        let aiffURL = root.appendingPathComponent("phase4-media-smoke.aiff")
        let wavURL = root.appendingPathComponent("phase4-media-smoke.wav")
        try runProcess(
            executablePath: "/usr/bin/say",
            arguments: ["-v", "Samantha", "-o", aiffURL.path, "hello from llm tools media subtitles"]
        )
        try runProcess(
            executablePath: "/usr/bin/afconvert",
            arguments: [aiffURL.path, wavURL.path, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"]
        )
        return wavURL
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-media-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func runProcess(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SmokeError("\(URL(fileURLWithPath: executablePath).lastPathComponent) failed: \(message)")
        }
    }
}

private struct SmokeOptions {
    var speechModelPath: String?
    var textModelPath: String?
    var audioPath: String?
    var outputDirectory: String?
    var keepTemporaryFiles = false

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--speech-model":
                speechModelPath = arguments[safe: index + 1]
                index += 2
            case "--text-model":
                textModelPath = arguments[safe: index + 1]
                index += 2
            case "--audio":
                audioPath = arguments[safe: index + 1]
                index += 2
            case "--output-dir":
                outputDirectory = arguments[safe: index + 1]
                index += 2
            case "--keep-temporary-files":
                keepTemporaryFiles = true
                index += 1
            default:
                index += 1
            }
        }
    }
}

private struct MediaSmokeSummary: Encodable {
    var audioPath: String
    var speechModel: String
    var textModel: String
    var runtimeSource: String
    var segmentCount: Int
    var firstTranscript: String
    var firstTranslation: String
    var fastMTFirstTranslation: String
    var exported: [String: String]
    var diagnostics: MediaSubtitleDiagnostics
}

private struct FastMTFixture: Encodable {
    var protocolName = "llmtools.fastmt/v1"
    var type = "translation"
    var engine: String
    var model: String
    var supportedPairs: [LanguagePair]
    var segments: [FastMTFixtureSegment]
    var latencyMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case type
        case engine
        case model
        case supportedPairs
        case segments
        case latencyMilliseconds
    }
}

private struct FastMTFixtureSegment: Encodable {
    var id: String
    var translation: String
}

private struct SmokeError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
