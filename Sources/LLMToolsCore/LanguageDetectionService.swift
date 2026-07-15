import Darwin
import Foundation

public enum LanguageDetectionRuntimeSource: String, Codable, Sendable, Hashable {
    case fixtureJSON
    case settingsCommand
    case bundledFastTextSidecar
    case unavailable
}

public enum LanguageDetectionHealthStatus: String, Codable, Sendable, Hashable {
    case ready
    case disabled
    case skippedShortText
    case modelMissing
    case runtimeMissing
    case failed
}

public struct LanguageDetectionResult: Codable, Hashable, Sendable {
    public var language: String?
    public var rawLanguage: String?
    public var confidence: Double
    public var detectorModel: String?
    public var source: LanguageDetectionRuntimeSource
    public var latencyMilliseconds: Int?
    public var isReliable: Bool
    public var message: String?

    public init(
        language: String?,
        rawLanguage: String? = nil,
        confidence: Double = 0,
        detectorModel: String? = nil,
        source: LanguageDetectionRuntimeSource,
        latencyMilliseconds: Int? = nil,
        isReliable: Bool,
        message: String? = nil
    ) {
        self.language = LanguageCodeNormalizer.normalizedBCP47(language)
        self.rawLanguage = rawLanguage
        self.confidence = Self.normalizedConfidence(confidence)
        self.detectorModel = detectorModel
        self.source = source
        self.latencyMilliseconds = latencyMilliseconds.map { max(0, $0) }
        self.isReliable = isReliable
        self.message = message
    }

    public static func skippedShortText(message: String = "Text is below the configured language-detection threshold.") -> LanguageDetectionResult {
        LanguageDetectionResult(
            language: nil,
            confidence: 0,
            source: .unavailable,
            isReliable: false,
            message: message
        )
    }

    private static func normalizedConfidence(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }
}

public struct LanguageDetectionHealth: Codable, Hashable, Sendable {
    public var status: LanguageDetectionHealthStatus
    public var source: LanguageDetectionRuntimeSource
    public var message: String
    public var sampleResult: LanguageDetectionResult?
    public var checkedAt: Date

    public init(
        status: LanguageDetectionHealthStatus,
        source: LanguageDetectionRuntimeSource,
        message: String,
        sampleResult: LanguageDetectionResult? = nil,
        checkedAt: Date = .now
    ) {
        self.status = status
        self.source = source
        self.message = message
        self.sampleResult = sampleResult
        self.checkedAt = checkedAt
    }
}

public enum LanguageDetectionError: Error, LocalizedError, Sendable {
    case runtimeMissing(String)
    case modelMissing(String)
    case runtimeFailed(String)
    case invalidFixture(String)

    public var errorDescription: String? {
        switch self {
        case .runtimeMissing(let message), .modelMissing(let message), .runtimeFailed(let message), .invalidFixture(let message):
            return message
        }
    }
}

public actor LanguageDetectionService {
    private var session: LanguageDetectionProcessSession?
    private var sessionKey: String?

    public init() {}

    public func detect(
        text: String,
        preferences: LanguageRoutingPreferences = LanguageRoutingPreferences()
    ) async throws -> LanguageDetectionResult {
        if preferences.shouldSkipDetection(for: text) {
            return .skippedShortText()
        }
        if let fixture = try FastTextLIDCommandRunner.fixtureResult(preferences: preferences) {
            return fixture
        }
        let resolution = try FastTextLIDCommandRunner.commandResolution(preferences: preferences)
        let activeSession = try await processSession(for: resolution)
        return try await activeSession.detect(text: text, preferences: preferences)
    }

    public func health(
        preferences: LanguageRoutingPreferences = LanguageRoutingPreferences(),
        sampleText: String = "This is a language detection health check."
    ) async -> LanguageDetectionHealth {
        guard preferences.enabled else {
            return LanguageDetectionHealth(
                status: .disabled,
                source: .unavailable,
                message: "Language routing is disabled."
            )
        }
        do {
            let result = try await detect(text: sampleText, preferences: preferences)
            if result.language == nil {
                return LanguageDetectionHealth(
                    status: .skippedShortText,
                    source: result.source,
                    message: result.message ?? "Language detection skipped the sample.",
                    sampleResult: result
                )
            }
            return LanguageDetectionHealth(
                status: .ready,
                source: result.source,
                message: "Language detection runtime is ready.",
                sampleResult: result
            )
        } catch let error as LanguageDetectionError {
            return LanguageDetectionHealth(
                status: error.healthStatus,
                source: .unavailable,
                message: error.localizedDescription
            )
        } catch {
            return LanguageDetectionHealth(
                status: .failed,
                source: .unavailable,
                message: error.localizedDescription
            )
        }
    }

    public func stop() {
        session?.stop()
        session = nil
        sessionKey = nil
    }

    private func processSession(for resolution: FastTextLIDCommandRunner.CommandResolution) async throws -> LanguageDetectionProcessSession {
        if let session, sessionKey == resolution.key, session.isRunning {
            return session
        }
        session?.stop()
        let newSession = try LanguageDetectionProcessSession(resolution: resolution)
        try await newSession.waitUntilReady()
        session = newSession
        sessionKey = resolution.key
        return newSession
    }
}

extension LanguageDetectionError {
    fileprivate var healthStatus: LanguageDetectionHealthStatus {
        switch self {
        case .runtimeMissing:
            return .runtimeMissing
        case .modelMissing:
            return .modelMissing
        case .runtimeFailed, .invalidFixture:
            return .failed
        }
    }
}

public struct FastTextLIDCommandRunner: Sendable {
    public struct CommandResolution: Sendable, Hashable {
        public var command: String
        public var source: LanguageDetectionRuntimeSource
        public var key: String
    }

    public static var defaultFTZModelPath: String {
        AppPaths.languageDetectionRuntimeDirectory
            .appendingPathComponent("lid.176.ftz")
            .path
    }

    public static var defaultBINModelPath: String {
        AppPaths.languageDetectionRuntimeDirectory
            .appendingPathComponent("lid.176.bin")
            .path
    }

    public static func fixtureResult(preferences: LanguageRoutingPreferences) throws -> LanguageDetectionResult? {
        guard let value = environmentValue(Phase4XFixtureEnvironment.languageIDJSON) else {
            return nil
        }
        let data: Data
        if value.hasPrefix("{") || value.hasPrefix("[") {
            data = Data(value.utf8)
        } else {
            let url = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
            data = try Data(contentsOf: url)
        }
        return try fixtureResult(data: data, preferences: preferences)
    }

    public static func fixtureResult(
        data: Data,
        preferences: LanguageRoutingPreferences = LanguageRoutingPreferences()
    ) throws -> LanguageDetectionResult {
        let event = try JSONDecoder().decode(LanguageDetectionSidecarEvent.self, from: data)
        return try result(from: event, source: .fixtureJSON, preferences: preferences)
    }

    public static func commandResolution(preferences: LanguageRoutingPreferences) throws -> CommandResolution {
        if let template = nonEmpty(preferences.commandTemplate) {
            let command = renderCommandTemplate(template, preferences: preferences)
            return CommandResolution(command: command, source: .settingsCommand, key: "settings:\(command)")
        }
        guard let sidecarPath = sidecarPath() else {
            throw LanguageDetectionError.runtimeMissing("Bundled language detection sidecar was not found.")
        }
        guard let pythonPath = pythonPath() else {
            throw LanguageDetectionError.runtimeMissing("Python runtime was not found for language detection.")
        }
        if let configuredModelPath = configuredModelPath(for: preferences.modelVariant, preferences: preferences),
           !FileManager.default.fileExists(atPath: configuredModelPath) {
            throw LanguageDetectionError.modelMissing("Configured fastText language ID model was not found: \(configuredModelPath). Choose an existing model under Models > Model Settings.")
        }
        guard modelPath(for: preferences.modelVariant, preferences: preferences) != nil else {
            throw LanguageDetectionError.modelMissing("fastText language ID model is missing. Run scripts/install-phase4x-fasttext-lid.sh, configure the model path under Models > Model Settings, or configure a custom command.")
        }
        let modelPlaceholder = preferences.modelVariant == .bin ? "{model_bin}" : "{model_ftz}"
        let template = "{python} {sidecar} --model \(modelPlaceholder)"
        let command = renderCommandTemplate(
            template,
            preferences: preferences,
            pythonPath: pythonPath,
            sidecarPath: sidecarPath
        )
        return CommandResolution(command: command, source: .bundledFastTextSidecar, key: "bundled:\(command)")
    }

    fileprivate static func result(
        from event: LanguageDetectionSidecarEvent,
        source: LanguageDetectionRuntimeSource,
        preferences: LanguageRoutingPreferences
    ) throws -> LanguageDetectionResult {
        if event.type == "error" {
            throw LanguageDetectionError.runtimeFailed(event.message ?? "Language detection sidecar failed.")
        }
        let rawLanguage = event.language ?? event.rawLanguage
        let language = LanguageCodeNormalizer.normalizedBCP47(rawLanguage)
        let confidence = event.confidence ?? 0
        return LanguageDetectionResult(
            language: language,
            rawLanguage: rawLanguage,
            confidence: confidence,
            detectorModel: event.model ?? event.detectorModel,
            source: source,
            latencyMilliseconds: event.latencyMilliseconds,
            isReliable: language != nil && confidence >= preferences.lowConfidenceThreshold,
            message: event.message
        )
    }

    private static func renderCommandTemplate(
        _ template: String,
        preferences: LanguageRoutingPreferences,
        pythonPath: String? = nil,
        sidecarPath: String? = nil
    ) -> String {
        template
            .replacingOccurrences(of: "{python}", with: shellEscape(pythonPath ?? Self.pythonPath() ?? "python3"))
            .replacingOccurrences(of: "{sidecar}", with: shellEscape(sidecarPath ?? Self.sidecarPath() ?? "llmtools-lid-sidecar.py"))
            .replacingOccurrences(of: "{model_ftz}", with: shellEscape(modelPath(for: .ftz, preferences: preferences) ?? ""))
            .replacingOccurrences(of: "{model_bin}", with: shellEscape(modelPath(for: .bin, preferences: preferences) ?? ""))
            .replacingOccurrences(of: "{variant}", with: preferences.modelVariant.rawValue)
    }

    private static func modelPath(
        for variant: LanguageIDModelVariant,
        preferences: LanguageRoutingPreferences = LanguageRoutingPreferences()
    ) -> String? {
        switch variant {
        case .ftz, .customCommand:
            return firstExistingPath([
                configuredModelPath(for: .ftz, preferences: preferences),
                environmentValue("LLMTOOLS_LID_MODEL_FTZ"),
                defaultFTZModelPath,
                "~/Library/Application Support/llmTools/lid-runtime/lid.176.ftz"
            ])
        case .bin:
            return firstExistingPath([
                configuredModelPath(for: .bin, preferences: preferences),
                environmentValue("LLMTOOLS_LID_MODEL_BIN"),
                defaultBINModelPath,
                "~/Library/Application Support/llmTools/lid-runtime/lid.176.bin"
            ])
        }
    }

    private static func configuredModelPath(
        for variant: LanguageIDModelVariant,
        preferences: LanguageRoutingPreferences
    ) -> String? {
        let rawValue: String
        switch variant {
        case .ftz, .customCommand:
            rawValue = preferences.ftzModelPath
        case .bin:
            rawValue = preferences.binModelPath
        }
        return expandedNonEmptyPath(rawValue)
    }

    private static func pythonPath() -> String? {
        firstExecutablePath([
            environmentValue("LLMTOOLS_LID_PYTHON"),
            AppPaths.languageDetectionRuntimeDirectory
                .appendingPathComponent("venv/bin/python3")
                .path,
            AppPaths.languageDetectionRuntimeDirectory
                .appendingPathComponent("venv/bin/python")
                .path,
            "/usr/bin/python3"
        ])
    }

    private static func sidecarPath() -> String? {
        firstExistingPath([
            environmentValue("LLMTOOLS_LID_SIDECAR"),
            Bundle.main.resourceURL?
                .appendingPathComponent("lid", isDirectory: true)
                .appendingPathComponent("llmtools-lid-sidecar.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-lid-sidecar.py")
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

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func expandedNonEmptyPath(_ value: String?) -> String? {
        guard let trimmed = nonEmpty(value) else {
            return nil
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private final class LanguageDetectionProcessSession: @unchecked Sendable {
    private let resolution: FastTextLIDCommandRunner.CommandResolution
    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let requestLock = NSLock()
    private let processLifecycle = PersistentProcessLifecycle()
    private let stderrLock = NSLock()
    private var stderrData = Data()

    var isRunning: Bool {
        process.isRunning && !processLifecycle.isStopped
    }

    init(resolution: FastTextLIDCommandRunner.CommandResolution) throws {
        self.resolution = resolution
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \(resolution.command)"]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        self.inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputPipe.fileHandleForReading
        self.errorHandle = errorPipe.fileHandleForReading
        self.errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.appendStderr(data)
        }

        do {
            try process.run()
        } catch {
            self.errorHandle.readabilityHandler = nil
            throw LanguageDetectionError.runtimeFailed(error.localizedDescription)
        }
    }

    deinit {
        stop()
    }

    func waitUntilReady() async throws {
        try await Task.detached(priority: .userInitiated) { [self] in
            while true {
                let event = try readEvent()
                switch event.type {
                case "ready":
                    return
                case "error":
                    throw LanguageDetectionError.runtimeFailed(event.message ?? "Language detection sidecar failed to start.")
                default:
                    continue
                }
            }
        }.value
    }

    func detect(text: String, preferences: LanguageRoutingPreferences) async throws -> LanguageDetectionResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try detectSync(text: text, preferences: preferences)
        }.value
    }

    private func detectSync(text: String, preferences: LanguageRoutingPreferences) throws -> LanguageDetectionResult {
        requestLock.lock()
        defer {
            requestLock.unlock()
        }
        guard !processLifecycle.isStopped, process.isRunning else {
            throw LanguageDetectionError.runtimeFailed("Language detection sidecar is not running.")
        }
        let requestID = UUID().uuidString
        try writeJSONLine(LanguageDetectionCommand(command: "detect", requestID: requestID, text: text))
        while true {
            let event = try readEvent()
            if event.type == "error" {
                throw LanguageDetectionError.runtimeFailed(event.message ?? "Language detection sidecar failed.")
            }
            guard event.requestID == nil || event.requestID == requestID else {
                continue
            }
            if event.type == "result" || event.type == "language" {
                return try FastTextLIDCommandRunner.result(from: event, source: resolution.source, preferences: preferences)
            }
        }
    }

    func stop() {
        processLifecycle.stop(
            process: process,
            inputHandle: inputHandle,
            errorHandle: errorHandle
        )
    }

    private func writeJSONLine<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        var line = data
        line.append(0x0A)
        try inputHandle.write(contentsOf: line)
    }

    private func readEvent() throws -> LanguageDetectionSidecarEvent {
        let line = try readLineSync()
        guard let data = line.data(using: .utf8) else {
            throw LanguageDetectionError.runtimeFailed("Language detection sidecar returned invalid UTF-8.")
        }
        return try JSONDecoder().decode(LanguageDetectionSidecarEvent.self, from: data)
    }

    private func readLineSync() throws -> String {
        var data = Data()
        while true {
            let byte = outputHandle.readData(ofLength: 1)
            if byte.isEmpty {
                let message = lastStderr()
                throw LanguageDetectionError.runtimeFailed(
                    message.isEmpty ? "Language detection sidecar exited unexpectedly." : message
                )
            }
            if byte.first == 0x0A {
                break
            }
            data.append(byte)
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func appendStderr(_ data: Data) {
        stderrLock.lock()
        stderrData.append(data)
        if stderrData.count > 16_384 {
            stderrData.removeFirst(stderrData.count - 16_384)
        }
        stderrLock.unlock()
    }

    private func lastStderr() -> String {
        stderrLock.lock()
        defer {
            stderrLock.unlock()
        }
        let suffix = Data(stderrData.suffix(4_096))
        return String(data: suffix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct LanguageDetectionCommand: Encodable {
    var protocolName = "llmtools.lid/v1"
    var command: String
    var requestID: String
    var text: String

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case command
        case requestID
        case text
    }
}

private struct LanguageDetectionSidecarEvent: Decodable {
    var protocolName: String?
    var type: String?
    var requestID: String?
    var language: String?
    var rawLanguage: String?
    var confidence: Double?
    var model: String?
    var detectorModel: String?
    var latencyMilliseconds: Int?
    var code: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case type
        case requestID
        case language
        case rawLanguage
        case confidence
        case model
        case detectorModel
        case latencyMilliseconds
        case code
        case message
    }
}
