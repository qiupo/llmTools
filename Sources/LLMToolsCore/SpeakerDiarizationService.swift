import Foundation

public enum SpeakerDiarizationRuntimeSource: String, Codable, Sendable, Hashable {
    case fixtureJSON
    case settingsCommand
    case bundledPyannoteSidecar
    case unavailable
}

public enum SpeakerDiarizationHealthStatus: String, Codable, Sendable, Hashable {
    case ready
    case disabled
    case requiresUserToken
    case runtimeMissing
    case failed
}

public struct SpeakerTurn: Codable, Hashable, Sendable {
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var speakerID: String
    public var speakerLabel: String?
    public var confidence: Double?

    public init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: String,
        speakerLabel: String? = nil,
        confidence: Double? = nil
    ) {
        let normalizedStart = max(0, startTime)
        self.startTime = normalizedStart
        self.endTime = max(normalizedStart, endTime)
        self.speakerID = speakerID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.speakerLabel = speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.confidence = confidence.map { min(max($0, 0), 1) }
    }
}

public struct SpeakerDiarizationResult: Codable, Hashable, Sendable {
    public var turns: [SpeakerTurn]
    public var modelID: String?
    public var runtimeSource: SpeakerDiarizationRuntimeSource
    public var latencyMilliseconds: Int?

    public init(
        turns: [SpeakerTurn],
        modelID: String? = nil,
        runtimeSource: SpeakerDiarizationRuntimeSource,
        latencyMilliseconds: Int? = nil
    ) {
        self.turns = turns.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        self.modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.runtimeSource = runtimeSource
        self.latencyMilliseconds = latencyMilliseconds.map { max(0, $0) }
    }
}

public struct SpeakerDiarizationHealth: Codable, Hashable, Sendable {
    public var status: SpeakerDiarizationHealthStatus
    public var source: SpeakerDiarizationRuntimeSource
    public var requiresUserToken: Bool
    public var tokenPresent: Bool
    public var tokenAcceptedRecently: Bool
    public var message: String
    public var checkedAt: Date

    public init(
        status: SpeakerDiarizationHealthStatus,
        source: SpeakerDiarizationRuntimeSource,
        requiresUserToken: Bool,
        tokenPresent: Bool,
        tokenAcceptedRecently: Bool,
        message: String,
        checkedAt: Date = .now
    ) {
        self.status = status
        self.source = source
        self.requiresUserToken = requiresUserToken
        self.tokenPresent = tokenPresent
        self.tokenAcceptedRecently = tokenAcceptedRecently
        self.message = message
        self.checkedAt = checkedAt
    }
}

public enum SpeakerDiarizationError: Error, LocalizedError, Sendable {
    case disabled
    case tokenMissing(String)
    case runtimeMissing(String)
    case runtimeFailed(String)
    case invalidFixture(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Speaker diarization is disabled."
        case .tokenMissing(let message), .runtimeMissing(let message), .runtimeFailed(let message), .invalidFixture(let message):
            return message
        }
    }
}

public actor SpeakerDiarizationService {
    public init() {}

    public func diarize(
        audioURL: URL,
        preferences: SpeakerDiarizationPreferences = SpeakerDiarizationPreferences(),
        expectedSpeakerCount: Int? = nil
    ) async throws -> SpeakerDiarizationResult {
        guard preferences.enabledForFileSubtitles else {
            throw SpeakerDiarizationError.disabled
        }
        if let fixture = try SpeakerDiarizationCommandRunner.fixtureResult() {
            return fixture
        }
        let resolution = try SpeakerDiarizationCommandRunner.commandResolution(preferences: preferences)
        return try await SpeakerDiarizationCommandRunner.run(
            audioURL: audioURL,
            resolution: resolution,
            preferences: preferences,
            expectedSpeakerCount: expectedSpeakerCount
        )
    }

    public func health(
        preferences: SpeakerDiarizationPreferences = SpeakerDiarizationPreferences()
    ) async -> SpeakerDiarizationHealth {
        guard preferences.enabledForFileSubtitles else {
            return SpeakerDiarizationHealth(
                status: .disabled,
                source: .unavailable,
                requiresUserToken: true,
                tokenPresent: SpeakerDiarizationCommandRunner.tokenPresent(preferences: preferences),
                tokenAcceptedRecently: false,
                message: "Speaker diarization is disabled."
            )
        }
        if (try? SpeakerDiarizationCommandRunner.fixtureResult()) != nil {
            return SpeakerDiarizationHealth(
                status: .ready,
                source: .fixtureJSON,
                requiresUserToken: false,
                tokenPresent: true,
                tokenAcceptedRecently: true,
                message: "Speaker diarization fixture is ready."
            )
        }
        let tokenPresent = SpeakerDiarizationCommandRunner.tokenPresent(preferences: preferences)
        let localModel = SpeakerDiarizationCommandRunner.modelReferenceIsLocal(preferences.modelIdentifier)
        if SpeakerDiarizationCommandRunner.modelReferenceLooksLocal(preferences.modelIdentifier), !localModel {
            return SpeakerDiarizationHealth(
                status: .failed,
                source: .unavailable,
                requiresUserToken: false,
                tokenPresent: tokenPresent,
                tokenAcceptedRecently: false,
                message: "Configured pyannote model path was not found: \(preferences.modelIdentifier)"
            )
        }
        guard tokenPresent || localModel || SpeakerDiarizationCommandRunner.hasCustomCommand(preferences: preferences) else {
            return SpeakerDiarizationHealth(
                status: .requiresUserToken,
                source: .unavailable,
                requiresUserToken: !localModel,
                tokenPresent: false,
                tokenAcceptedRecently: false,
                message: "pyannote speaker diarization requires a Hugging Face token and accepted model terms."
            )
        }
        do {
            let resolution = try SpeakerDiarizationCommandRunner.commandResolution(preferences: preferences)
            return SpeakerDiarizationHealth(
                status: .ready,
                source: resolution.source,
                requiresUserToken: resolution.source != .settingsCommand && !localModel,
                tokenPresent: tokenPresent,
                tokenAcceptedRecently: false,
                message: "Speaker diarization runtime is configured."
            )
        } catch {
            return SpeakerDiarizationHealth(
                status: .runtimeMissing,
                source: .unavailable,
                requiresUserToken: true,
                tokenPresent: tokenPresent,
                tokenAcceptedRecently: false,
                message: error.localizedDescription
            )
        }
    }
}

public enum SpeakerTurnMapper {
    public static func apply(turns: [SpeakerTurn], to segments: [SubtitleSegment]) -> [SubtitleSegment] {
        guard !turns.isEmpty, !segments.isEmpty else {
            return segments
        }
        let normalizedTurns = stableLabeledTurns(turns)
        return segments.map { segment in
            guard let turn = bestTurn(for: segment, turns: normalizedTurns) else {
                return segment
            }
            var updated = segment
            updated.speakerID = turn.speakerID
            updated.speakerLabel = turn.speakerLabel
            updated.speakerConfidence = turn.confidence
            return updated
        }
    }

    public static func speakerCount(in segments: [SubtitleSegment]) -> Int {
        Set(segments.compactMap { $0.speakerID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }).count
    }

    private static func stableLabeledTurns(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        var labelsByID: [String: String] = [:]
        var nextIndex = 1
        return turns.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }.map { turn in
            var updated = turn
            if updated.speakerLabel == nil {
                if labelsByID[updated.speakerID] == nil {
                    labelsByID[updated.speakerID] = "Speaker \(nextIndex)"
                    nextIndex += 1
                }
                updated.speakerLabel = labelsByID[updated.speakerID]
            }
            return updated
        }
    }

    private static func bestTurn(for segment: SubtitleSegment, turns: [SpeakerTurn]) -> SpeakerTurn? {
        let end = segment.endTime ?? (segment.startTime + 2)
        let midpoint = (segment.startTime + end) / 2
        if let midpointMatch = turns.first(where: { $0.startTime <= midpoint && midpoint <= $0.endTime }) {
            return midpointMatch
        }
        return turns.max { left, right in
            overlapRatio(segmentStart: segment.startTime, segmentEnd: end, turn: left)
                < overlapRatio(segmentStart: segment.startTime, segmentEnd: end, turn: right)
        }.flatMap { turn in
            overlapRatio(segmentStart: segment.startTime, segmentEnd: end, turn: turn) > 0 ? turn : nil
        }
    }

    private static func overlapRatio(segmentStart: TimeInterval, segmentEnd: TimeInterval, turn: SpeakerTurn) -> Double {
        let overlap = max(0, min(segmentEnd, turn.endTime) - max(segmentStart, turn.startTime))
        let union = max(segmentEnd, turn.endTime) - min(segmentStart, turn.startTime)
        guard union > 0 else {
            return 0
        }
        return overlap / union
    }
}

public struct SpeakerDiarizationCommandRunner: Sendable {
    public struct CommandResolution: Sendable, Hashable {
        public var command: String
        public var source: SpeakerDiarizationRuntimeSource
    }

    public static var defaultHFHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    public static func hasCustomCommand(preferences: SpeakerDiarizationPreferences) -> Bool {
        !preferences.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func tokenPresent(preferences: SpeakerDiarizationPreferences) -> Bool {
        if environmentValue("PYANNOTE_AUTH_TOKEN") != nil || environmentValue("HF_TOKEN") != nil {
            return true
        }
        return SpeakerDiarizationTokenStore.tokenPresent()
    }

    public static func fixtureResult() throws -> SpeakerDiarizationResult? {
        guard let value = environmentValue(Phase4XFixtureEnvironment.diarizationJSON) else {
            return nil
        }
        let data: Data
        if value.hasPrefix("{") || value.hasPrefix("[") {
            data = Data(value.utf8)
        } else {
            data = try Data(contentsOf: URL(fileURLWithPath: NSString(string: value).expandingTildeInPath))
        }
        return try parseResult(data: data, source: .fixtureJSON)
    }

    public static func commandResolution(preferences: SpeakerDiarizationPreferences) throws -> CommandResolution {
        if hasCustomCommand(preferences: preferences) {
            return CommandResolution(command: preferences.commandTemplate, source: .settingsCommand)
        }
        if modelReferenceLooksLocal(preferences.modelIdentifier), !modelReferenceIsLocal(preferences.modelIdentifier) {
            throw SpeakerDiarizationError.runtimeMissing("Configured pyannote model path was not found: \(preferences.modelIdentifier)")
        }
        guard let sidecarPath = sidecarPath() else {
            throw SpeakerDiarizationError.runtimeMissing("Bundled speaker diarization sidecar was not found.")
        }
        guard let pythonPath = pythonPath() else {
            throw SpeakerDiarizationError.runtimeMissing("Python runtime was not found for speaker diarization.")
        }
        let command = "{python} {sidecar} --model {diarization_model} --audio {audio_wav_16k_mono} --output {output_json}"
            .replacingOccurrences(of: "{python}", with: shellEscape(pythonPath))
            .replacingOccurrences(of: "{sidecar}", with: shellEscape(sidecarPath))
        return CommandResolution(command: command, source: .bundledPyannoteSidecar)
    }

    public static func run(
        audioURL: URL,
        resolution: CommandResolution,
        preferences: SpeakerDiarizationPreferences,
        expectedSpeakerCount: Int? = nil
    ) async throws -> SpeakerDiarizationResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmtools-diarization-\(UUID().uuidString)")
            .appendingPathExtension("json")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        var command = renderCommand(
            resolution.command,
            audioURL: audioURL,
            outputURL: outputURL,
            preferences: preferences
        )
        if resolution.source == .bundledPyannoteSidecar,
           let expectedSpeakerCount,
           expectedSpeakerCount > 0 {
            command += " --speaker-count-hint \(shellEscape(String(expectedSpeakerCount)))"
        }
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var environment = ProcessInfo.processInfo.environment
        // File and meeting diarization execute only against already-local model files.
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        if environment["PYANNOTE_AUTH_TOKEN"] == nil, let token = token(preferences: preferences) {
            environment["PYANNOTE_AUTH_TOKEN"] = token
        }
        if let cacheDirectory = cacheDirectory(preferences: preferences) {
            try? FileManager.default.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true)
            environment["HF_HOME"] = cacheDirectory
        }
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let processHandle = CancellableProcessHandle(process: process)
        return try await withTaskCancellationHandler {
            do {
                try processHandle.run()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SpeakerDiarizationError.runtimeFailed(userVisibleRuntimeFailure(error.localizedDescription))
            }
            async let stdoutData = readPipeToEnd(stdout)
            async let stderrData = readPipeToEnd(stderr)
            process.waitUntilExit()
            let capturedStdout = await stdoutData
            let capturedStderr = await stderrData
            try Task.checkCancellation()
            let stderrText = String(data: capturedStderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                throw SpeakerDiarizationError.runtimeFailed(
                    userVisibleRuntimeFailure(stderrText.isEmpty ? "Speaker diarization command failed." : stderrText)
                )
            }
            let data: Data
            if FileManager.default.fileExists(atPath: outputURL.path) {
                data = try Data(contentsOf: outputURL)
            } else {
                data = capturedStdout
            }
            var result = try parseResult(data: data, source: resolution.source)
            result.latencyMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
            return result
        } onCancel: {
            processHandle.cancel()
        }
    }

    private static func readPipeToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached(priority: .utility) {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }

    private static func parseResult(data: Data, source: SpeakerDiarizationRuntimeSource) throws -> SpeakerDiarizationResult {
        if let envelope = try? JSONDecoder().decode(SpeakerDiarizationEnvelope.self, from: data) {
            return SpeakerDiarizationResult(
                turns: envelope.turns.map(\.turn),
                modelID: envelope.model ?? envelope.modelID,
                runtimeSource: source,
                latencyMilliseconds: envelope.latencyMilliseconds
            )
        }
        if let turns = try? JSONDecoder().decode([SpeakerDiarizationTurnPayload].self, from: data) {
            return SpeakerDiarizationResult(turns: turns.map(\.turn), runtimeSource: source)
        }
        throw SpeakerDiarizationError.invalidFixture("Speaker diarization JSON must contain turns.")
    }

    private static func renderCommand(
        _ template: String,
        audioURL: URL,
        outputURL: URL,
        preferences: SpeakerDiarizationPreferences
    ) -> String {
        template
            .replacingOccurrences(of: "{diarization_model}", with: shellEscape(preferences.modelIdentifier))
            .replacingOccurrences(of: "{model}", with: shellEscape(preferences.modelIdentifier))
            .replacingOccurrences(of: "{hf_cache}", with: shellEscape(cacheDirectory(preferences: preferences) ?? ""))
            .replacingOccurrences(of: "{audio_wav_16k_mono}", with: shellEscape(audioURL.path))
            .replacingOccurrences(of: "{output_json}", with: shellEscape(outputURL.path))
            .replacingOccurrences(of: "{hf_token}", with: shellEscape(token(preferences: preferences) ?? ""))
    }

    private static func token(preferences: SpeakerDiarizationPreferences) -> String? {
        if let token = environmentValue("PYANNOTE_AUTH_TOKEN") ?? environmentValue("HF_TOKEN") {
            return token
        }
        return try? SpeakerDiarizationTokenStore.read()
    }

    public static func modelReferenceIsLocal(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }
        let expanded = NSString(string: normalized).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    public static func modelReferenceLooksLocal(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }
        return normalized.hasPrefix("/")
            || normalized.hasPrefix("./")
            || normalized.hasPrefix("../")
            || normalized.hasPrefix("~")
    }

    private static func cacheDirectory(preferences: SpeakerDiarizationPreferences) -> String? {
        let normalized = preferences.cacheDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        return NSString(string: normalized).expandingTildeInPath
    }

    private static func pythonPath() -> String? {
        firstExecutablePath([
            environmentValue("LLMTOOLS_DIARIZATION_PYTHON"),
            AppPaths.applicationSupportDirectory
                .appendingPathComponent("diarization-runtime", isDirectory: true)
                .appendingPathComponent("venv/bin/python3")
                .path,
            AppPaths.applicationSupportDirectory
                .appendingPathComponent("diarization-runtime", isDirectory: true)
                .appendingPathComponent("venv/bin/python")
                .path,
            "/usr/bin/python3"
        ])
    }

    private static func sidecarPath() -> String? {
        firstExistingPath([
            environmentValue("LLMTOOLS_DIARIZATION_SIDECAR"),
            Bundle.main.resourceURL?
                .appendingPathComponent("diarization", isDirectory: true)
                .appendingPathComponent("llmtools-pyannote-diarization-sidecar.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-pyannote-diarization-sidecar.py")
                .path
        ])
    }

    private static func firstExistingPath(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { NSString(string: $0).expandingTildeInPath }
            .first { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
    }

    private static func firstExecutablePath(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { NSString(string: $0).expandingTildeInPath }
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func environmentValue(_ key: String) -> String? {
        guard let rawValue = getenv(key) else {
            return nil
        }
        let value = String(cString: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func userVisibleRuntimeFailure(_ rawMessage: String) -> String {
        let normalized = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "Speaker diarization command failed."
        }
        let lowercased = normalized.lowercased()
        if isPyannoteSetupFailure(lowercased) {
            return "pyannote model is not ready. Open Settings > Models > Model Settings > Speaker Diarization, complete the pyannote setup, then regenerate subtitles. If this Mac cannot reach huggingface.co, pre-cache pyannote/speaker-diarization-3.1 first."
        }
        guard lowercased.contains("traceback") else {
            return normalized
        }
        if let usefulLine = lastUsefulTracebackLine(in: normalized) {
            return "Speaker diarization command failed: \(usefulLine)"
        }
        return "Speaker diarization command failed."
    }

    private static func isPyannoteSetupFailure(_ lowercased: String) -> Bool {
        let mentionsPyannoteModel = lowercased.contains("pyannote")
            || lowercased.contains("speaker-diarization")
        let mentionsHuggingFaceAccess = lowercased.contains("huggingface")
            || lowercased.contains("hf_token")
            || lowercased.contains("pyannote_auth_token")
            || lowercased.contains("use_auth_token")
            || lowercased.contains("gated")
            || lowercased.contains("model terms")
            || lowercased.contains("repository")
            || lowercased.contains("resolve/main")
        let mentionsNetworkFailure = lowercased.contains("no route")
            || lowercased.contains("cannot send a request")
            || lowercased.contains("connection")
            || lowercased.contains("timed out")
            || lowercased.contains("network")
        return mentionsPyannoteModel && (mentionsHuggingFaceAccess || mentionsNetworkFailure)
    }

    private static func lastUsefulTracebackLine(in message: String) -> String? {
        message
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .reversed()
            .first { line in
                guard !line.isEmpty else {
                    return false
                }
                let lowercased = line.lowercased()
                return !lowercased.hasPrefix("traceback")
                    && !lowercased.hasPrefix("file ")
                    && !lowercased.hasPrefix("from ")
                    && !lowercased.hasPrefix("return ")
            }
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct SpeakerDiarizationEnvelope: Decodable {
    var turns: [SpeakerDiarizationTurnPayload]
    var model: String?
    var modelID: String?
    var latencyMilliseconds: Int?
}

private struct SpeakerDiarizationTurnPayload: Decodable {
    var start: TimeInterval?
    var startTime: TimeInterval?
    var end: TimeInterval?
    var endTime: TimeInterval?
    var speaker: String?
    var speakerID: String?
    var speakerLabel: String?
    var label: String?
    var confidence: Double?

    var turn: SpeakerTurn {
        SpeakerTurn(
            startTime: startTime ?? start ?? 0,
            endTime: endTime ?? end ?? 0,
            speakerID: speakerID ?? speaker ?? speakerLabel ?? label ?? "speaker",
            speakerLabel: speakerLabel ?? label,
            confidence: confidence
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
