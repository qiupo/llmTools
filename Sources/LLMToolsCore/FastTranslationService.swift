import Foundation

public struct FastTranslationSegment: Codable, Hashable, Sendable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text
    }
}

public struct FastTranslatedSegment: Codable, Hashable, Sendable {
    public var id: String
    public var translation: String
    public var engineID: TranslationEngineID
    public var modelID: String?
    public var latencyMilliseconds: Int?

    public init(
        id: String,
        translation: String,
        engineID: TranslationEngineID,
        modelID: String? = nil,
        latencyMilliseconds: Int? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.engineID = engineID
        self.modelID = Self.nonEmpty(modelID)
        self.latencyMilliseconds = latencyMilliseconds.map { max(0, $0) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum FastTranslationRuntimeSource: String, Codable, Sendable, Hashable {
    case fixtureJSON
    case settingsCommand
    case bundledCTranslate2Sidecar
    case bundledArgosSidecar
    case unavailable
}

public enum FastTranslationHealthStatus: String, Codable, Sendable, Hashable {
    case ready
    case disabled
    case runtimeMissing
    case unsupportedLanguagePair
    case failed
}

public struct FastTranslationHealth: Codable, Hashable, Sendable {
    public var status: FastTranslationHealthStatus
    public var source: FastTranslationRuntimeSource
    public var engineID: TranslationEngineID?
    public var modelID: String?
    public var supportedPairs: [LanguagePair]
    public var firstProbeMilliseconds: Int?
    public var steadyStateMilliseconds: Int?
    public var message: String
    public var checkedAt: Date

    public init(
        status: FastTranslationHealthStatus,
        source: FastTranslationRuntimeSource,
        engineID: TranslationEngineID? = nil,
        modelID: String? = nil,
        supportedPairs: [LanguagePair] = [],
        firstProbeMilliseconds: Int? = nil,
        steadyStateMilliseconds: Int? = nil,
        message: String,
        checkedAt: Date = .now
    ) {
        self.status = status
        self.source = source
        self.engineID = engineID
        self.modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil
        self.supportedPairs = Self.normalizedPairs(supportedPairs)
        self.firstProbeMilliseconds = firstProbeMilliseconds.map { max(0, $0) }
        self.steadyStateMilliseconds = steadyStateMilliseconds.map { max(0, $0) }
        self.message = message
        self.checkedAt = checkedAt
    }

    private static func normalizedPairs(_ pairs: [LanguagePair]) -> [LanguagePair] {
        var seen = Set<LanguagePair>()
        return pairs.filter { seen.insert($0).inserted }
    }
}

public enum FastTranslationError: Error, LocalizedError, Sendable {
    case disabled
    case runtimeMissing(String)
    case unsupportedLanguagePair(LanguagePair)
    case runtimeFailed(String)
    case invalidFixture(String)
    case incompleteResponse(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Fast translation is disabled."
        case .runtimeMissing(let message), .runtimeFailed(let message), .invalidFixture(let message), .incompleteResponse(let message):
            return message
        case .unsupportedLanguagePair(let pair):
            return "Fast translation does not support \(pair.source) to \(pair.target)."
        }
    }
}

public protocol FastTranslationService: Sendable {
    func probe() async -> FastTranslationHealth
    func supportedPairs() async -> [LanguagePair]
    func translate(batch: [FastTranslationSegment], pair: LanguagePair) async throws -> [FastTranslatedSegment]
    func cancel(requestID: String) async
}

public actor FastTranslationCommandRunner: FastTranslationService {
    private var session: FastTranslationProcessSession?
    private var sessionKey: String?

    public init() {}

    public func probe() async -> FastTranslationHealth {
        await probe(preferences: FastTranslationPreferences())
    }

    public func supportedPairs() async -> [LanguagePair] {
        await supportedPairs(preferences: FastTranslationPreferences())
    }

    public func translate(batch: [FastTranslationSegment], pair: LanguagePair) async throws -> [FastTranslatedSegment] {
        try await translate(batch: batch, pair: pair, preferences: FastTranslationPreferences())
    }

    public func probe(preferences: FastTranslationPreferences) async -> FastTranslationHealth {
        guard !preferences.forceLLM else {
            return FastTranslationHealth(
                status: .disabled,
                source: .unavailable,
                message: "Fast translation is disabled by the forceLLM killswitch."
            )
        }
        if let fixture = try? Self.fixtureEvent() {
            return FastTranslationHealth(
                status: .ready,
                source: .fixtureJSON,
                engineID: fixture.engineID ?? .ctranslate2,
                modelID: fixture.model,
                supportedPairs: fixture.supportedPairs ?? [LanguagePair(source: "en", target: "zh-Hans")],
                firstProbeMilliseconds: fixture.latencyMilliseconds,
                steadyStateMilliseconds: fixture.latencyMilliseconds,
                message: "Fast translation fixture is ready."
            )
        }
        do {
            let resolution = try Self.commandResolution(preferences: preferences)
            let activeSession = try await processSession(for: resolution)
            let ready = activeSession.readyEvent
            return FastTranslationHealth(
                status: .ready,
                source: resolution.source,
                engineID: ready?.engineID ?? resolution.engineID,
                modelID: ready?.model ?? resolution.modelID,
                supportedPairs: ready?.supportedPairs ?? [],
                firstProbeMilliseconds: ready?.latencyMilliseconds,
                steadyStateMilliseconds: nil,
                message: "Fast translation runtime is configured."
            )
        } catch let error as FastTranslationError {
            return FastTranslationHealth(
                status: error.healthStatus,
                source: .unavailable,
                message: error.localizedDescription
            )
        } catch {
            return FastTranslationHealth(
                status: .failed,
                source: .unavailable,
                message: error.localizedDescription
            )
        }
    }

    public func supportedPairs(preferences: FastTranslationPreferences) async -> [LanguagePair] {
        guard !preferences.forceLLM else {
            return []
        }
        if let fixture = try? Self.fixtureEvent() {
            return fixture.supportedPairs ?? [LanguagePair(source: "en", target: "zh-Hans")]
        }
        do {
            let resolution = try Self.commandResolution(preferences: preferences)
            let activeSession = try await processSession(for: resolution)
            return activeSession.readyEvent?.supportedPairs ?? []
        } catch {
            return []
        }
    }

    public func translate(
        batch: [FastTranslationSegment],
        pair: LanguagePair,
        preferences: FastTranslationPreferences
    ) async throws -> [FastTranslatedSegment] {
        guard !preferences.forceLLM else {
            throw FastTranslationError.disabled
        }
        guard !batch.isEmpty else {
            return []
        }
        if let fixture = try Self.fixtureEvent() {
            return try Self.translatedSegments(from: fixture, batch: batch, pair: pair)
        }
        let resolution = try Self.commandResolution(preferences: preferences)
        let activeSession = try await processSession(for: resolution)
        return try await activeSession.translate(batch: batch, pair: pair, resolution: resolution)
    }

    public func cancel(requestID: String) async {
        session?.cancel(requestID: requestID)
    }

    public func stop() {
        session?.stop()
        session = nil
        sessionKey = nil
    }

    private func processSession(for resolution: CommandResolution) async throws -> FastTranslationProcessSession {
        if let session, sessionKey == resolution.key, session.isRunning {
            return session
        }
        session?.stop()
        let newSession = try FastTranslationProcessSession(resolution: resolution)
        let ready = try await newSession.waitUntilReady()
        newSession.readyEvent = ready
        session = newSession
        sessionKey = resolution.key
        return newSession
    }

    public struct CommandResolution: Sendable, Hashable {
        public var command: String
        public var source: FastTranslationRuntimeSource
        public var engineID: TranslationEngineID
        public var modelID: String?
        public var key: String
    }

    public static var defaultOPUSCT2ModelPath: String {
        AppPaths.fastTranslationRuntimeDirectory
            .appendingPathComponent("opus-mt-en-zh-ct2", isDirectory: true)
            .path
    }

    public static var defaultNLLB600MCT2ModelPath: String {
        AppPaths.fastTranslationRuntimeDirectory
            .appendingPathComponent("nllb-200-distilled-600m-ct2-int8", isDirectory: true)
            .path
    }

    public static func commandResolution(preferences: FastTranslationPreferences) throws -> CommandResolution {
        if let template = preferences.commandTemplates.template(for: .customCommand) {
            let command = renderCommandTemplate(
                template,
                engineID: .customCommand,
                modelVariant: preferences.modelVariant,
                preferences: preferences
            )
            return CommandResolution(command: command, source: .settingsCommand, engineID: .customCommand, modelID: nil, key: "settings:\(command)")
        }
        guard let sidecarPath = sidecarPath() else {
            throw FastTranslationError.runtimeMissing("Bundled fast translation sidecar was not found.")
        }
        guard let pythonPath = pythonPath() else {
            throw FastTranslationError.runtimeMissing("Python runtime was not found for fast translation.")
        }
        if let template = preferences.commandTemplates.template(for: .ctranslate2) {
            if let configuredModelPath = configuredCTranslate2ModelPath(
                for: preferences.modelVariant,
                preferences: preferences
            ), !FileManager.default.fileExists(atPath: configuredModelPath) {
                throw FastTranslationError.runtimeMissing("Configured fast translation model was not found: \(configuredModelPath). Choose an existing CTranslate2 model folder under Models > Model Settings.")
            }
            guard let modelPath = ctranslate2ModelPath(for: preferences.modelVariant, preferences: preferences) else {
                if preferences.modelVariant != .opusMTEnZh {
                    throw FastTranslationError.runtimeMissing("Selected fast translation model is missing: \(preferences.modelVariant.rawValue). Configure the model folder under Models > Model Settings or install the Fast MT runtime.")
                }
                return try argosCommandResolution(
                    preferences: preferences,
                    pythonPath: pythonPath,
                    sidecarPath: sidecarPath
                )
            }
            let command = renderCommandTemplate(
                template,
                engineID: .ctranslate2,
                pythonPath: pythonPath,
                sidecarPath: sidecarPath,
                ctranslate2ModelPath: modelPath,
                modelVariant: preferences.modelVariant,
                preferences: preferences
            )
            return CommandResolution(
                command: command,
                source: .bundledCTranslate2Sidecar,
                engineID: .ctranslate2,
                modelID: modelPath,
                key: "ctranslate2:\(command)"
            )
        }
        return try argosCommandResolution(
            preferences: preferences,
            pythonPath: pythonPath,
            sidecarPath: sidecarPath
        )
    }

    private static func argosCommandResolution(
        preferences: FastTranslationPreferences,
        pythonPath: String,
        sidecarPath: String
    ) throws -> CommandResolution {
        if let template = preferences.commandTemplates.template(for: .argos) {
            let command = renderCommandTemplate(
                template,
                engineID: .argos,
                pythonPath: pythonPath,
                sidecarPath: sidecarPath,
                modelVariant: preferences.modelVariant,
                preferences: preferences
            )
            return CommandResolution(
                command: command,
                source: .bundledArgosSidecar,
                engineID: .argos,
                modelID: nil,
                key: "argos:\(command)"
            )
        }
        throw FastTranslationError.runtimeMissing("Fast translation runtime is missing. Install CTranslate2 or Argos runtime, or configure a custom command.")
    }

    public static func fixtureEvent() throws -> FastTranslationSidecarEvent? {
        guard let value = environmentValue(Phase4XFixtureEnvironment.fastTranslationJSON) else {
            return nil
        }
        let data: Data
        if value.hasPrefix("{") || value.hasPrefix("[") {
            data = Data(value.utf8)
        } else {
            let url = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
            data = try Data(contentsOf: url)
        }
        let event = try JSONDecoder().decode(FastTranslationSidecarEvent.self, from: data)
        if event.type == "error" {
            throw FastTranslationError.runtimeFailed(event.message ?? "Fast translation fixture returned an error.")
        }
        return event
    }

    fileprivate static func translatedSegments(
        from event: FastTranslationSidecarEvent,
        batch: [FastTranslationSegment],
        pair: LanguagePair
    ) throws -> [FastTranslatedSegment] {
        if let supportedPairs = event.supportedPairs, !supportedPairs.isEmpty, !supportedPairs.contains(pair) {
            throw FastTranslationError.unsupportedLanguagePair(pair)
        }
        guard let segments = event.segments, !segments.isEmpty else {
            throw FastTranslationError.invalidFixture("Fast translation fixture must include translated segments.")
        }
        let expectedIDs = batch.map(\.id)
        let expectedIDSet = Set(expectedIDs)
        var sourceTextByID: [String: String] = [:]
        for item in batch {
            sourceTextByID[item.id] = item.text
        }
        var translationsByID: [String: FastTranslatedSegment] = [:]
        for item in segments where expectedIDSet.contains(item.id) {
            let translation = item.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !translation.isEmpty else {
                continue
            }
            if isDegenerateTranslation(translation, sourceText: sourceTextByID[item.id] ?? "") {
                throw FastTranslationError.runtimeFailed("Fast translation produced a degenerate repeated output for segment \(item.id).")
            }
            translationsByID[item.id] = FastTranslatedSegment(
                id: item.id,
                translation: translation,
                engineID: event.engineID ?? .ctranslate2,
                modelID: event.model,
                latencyMilliseconds: event.latencyMilliseconds
            )
        }
        let ordered = expectedIDs.compactMap { translationsByID[$0] }
        guard ordered.count == expectedIDs.count else {
            throw FastTranslationError.incompleteResponse("Fast translation did not return all requested segments.")
        }
        return ordered
    }

    private static func isDegenerateTranslation(_ translation: String, sourceText: String) -> Bool {
        let outputCharacters = normalizedDegeneracyCharacters(in: translation)
        guard outputCharacters.count >= 6 else {
            return false
        }
        if longestRepeatedRun(in: outputCharacters) >= 8 {
            return true
        }
        if isShortPatternRepeated(outputCharacters) {
            return true
        }
        if dominantCharacterRatio(in: outputCharacters) >= 0.7, outputCharacters.count >= 16 {
            return true
        }

        let sourceCharacters = normalizedDegeneracyCharacters(in: sourceText)
        if !sourceCharacters.isEmpty,
           sourceCharacters.count <= 12,
           outputCharacters.count >= 24,
           outputCharacters.count > sourceCharacters.count * 6 {
            return true
        }
        return false
    }

    private static func normalizedDegeneracyCharacters(in text: String) -> [Character] {
        text.filter { character in
            let scalars = character.unicodeScalars
            guard !scalars.isEmpty else {
                return false
            }
            return !scalars.allSatisfy { scalar in
                CharacterSet.whitespacesAndNewlines.contains(scalar)
                    || CharacterSet.punctuationCharacters.contains(scalar)
                    || CharacterSet.symbols.contains(scalar)
            }
        }
    }

    private static func longestRepeatedRun(in characters: [Character]) -> Int {
        var longest = 0
        var current = 0
        var previous: Character?
        for character in characters {
            if character == previous {
                current += 1
            } else {
                current = 1
                previous = character
            }
            longest = max(longest, current)
        }
        return longest
    }

    private static func isShortPatternRepeated(_ characters: [Character]) -> Bool {
        guard characters.count >= 6 else {
            return false
        }
        let maximumPatternLength = min(4, characters.count / 3)
        guard maximumPatternLength >= 1 else {
            return false
        }
        for patternLength in 1...maximumPatternLength where characters.count % patternLength == 0 {
            let pattern = Array(characters.prefix(patternLength))
            var matches = true
            for index in characters.indices where characters[index] != pattern[index % patternLength] {
                matches = false
                break
            }
            if matches {
                return true
            }
        }
        return false
    }

    private static func dominantCharacterRatio(in characters: [Character]) -> Double {
        guard !characters.isEmpty else {
            return 0
        }
        var counts: [Character: Int] = [:]
        for character in characters {
            counts[character, default: 0] += 1
        }
        let maximum = counts.values.max() ?? 0
        return Double(maximum) / Double(characters.count)
    }

    private static func renderCommandTemplate(
        _ template: String,
        engineID: TranslationEngineID,
        pythonPath: String? = nil,
        sidecarPath: String? = nil,
        ctranslate2ModelPath: String? = nil,
        modelVariant: FastTranslationModelVariant = .opusMTEnZh,
        preferences: FastTranslationPreferences = FastTranslationPreferences()
    ) -> String {
        template
            .replacingOccurrences(of: "{python}", with: shellEscape(pythonPath ?? Self.pythonPath() ?? "python3"))
            .replacingOccurrences(of: "{sidecar}", with: shellEscape(sidecarPath ?? Self.sidecarPath() ?? "llmtools-fastmt-sidecar.py"))
            .replacingOccurrences(of: "{engine}", with: engineID.rawValue)
            .replacingOccurrences(of: "{model_ct2}", with: shellEscape(ctranslate2ModelPath ?? Self.ctranslate2ModelPath(for: modelVariant, preferences: preferences) ?? ""))
            .replacingOccurrences(of: "{model_variant}", with: modelVariant.rawValue)
    }

    private static func ctranslate2ModelPath(
        for variant: FastTranslationModelVariant,
        preferences: FastTranslationPreferences = FastTranslationPreferences()
    ) -> String? {
        switch variant {
        case .opusMTEnZh:
            return firstExistingPath([
                configuredCTranslate2ModelPath(for: .opusMTEnZh, preferences: preferences),
                environmentValue("LLMTOOLS_FASTMT_CT2_MODEL"),
                defaultOPUSCT2ModelPath,
                "~/Library/Application Support/llmTools/fastmt-runtime/opus-mt-en-zh-ct2"
            ])
        case .nllb200Distilled600M:
            return firstExistingPath([
                configuredCTranslate2ModelPath(for: .nllb200Distilled600M, preferences: preferences),
                environmentValue("LLMTOOLS_FASTMT_NLLB_600M_MODEL"),
                defaultNLLB600MCT2ModelPath,
                "~/Library/Application Support/llmTools/fastmt-runtime/nllb-200-distilled-600m-ct2-int8"
            ])
        }
    }

    private static func configuredCTranslate2ModelPath(
        for variant: FastTranslationModelVariant,
        preferences: FastTranslationPreferences
    ) -> String? {
        let rawValue: String
        switch variant {
        case .opusMTEnZh:
            rawValue = preferences.opusMTEnZhCT2ModelPath
        case .nllb200Distilled600M:
            rawValue = preferences.nllb200Distilled600MCT2ModelPath
        }
        return expandedNonEmptyPath(rawValue)
    }

    private static func pythonPath() -> String? {
        firstExecutablePath([
            environmentValue("LLMTOOLS_FASTMT_PYTHON"),
            AppPaths.fastTranslationRuntimeDirectory
                .appendingPathComponent("venv/bin/python3")
                .path,
            AppPaths.fastTranslationRuntimeDirectory
                .appendingPathComponent("venv/bin/python")
                .path,
            "/usr/bin/python3"
        ])
    }

    private static func sidecarPath() -> String? {
        firstExistingPath([
            environmentValue("LLMTOOLS_FASTMT_SIDECAR"),
            Bundle.main.resourceURL?
                .appendingPathComponent("fastmt", isDirectory: true)
                .appendingPathComponent("llmtools-fastmt-sidecar.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("llmtools-fastmt-sidecar.py")
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

    private static func expandedNonEmptyPath(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return nil
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension FastTranslationError {
    fileprivate var healthStatus: FastTranslationHealthStatus {
        switch self {
        case .disabled:
            return .disabled
        case .runtimeMissing:
            return .runtimeMissing
        case .unsupportedLanguagePair:
            return .unsupportedLanguagePair
        case .runtimeFailed, .invalidFixture, .incompleteResponse:
            return .failed
        }
    }
}

public enum TranslationRoutingSurface: String, Codable, Sendable, Hashable {
    case text
    case webpage
    case subtitle
}

public struct TranslationRoutingDecision: Codable, Hashable, Sendable {
    public var surface: TranslationRoutingSurface
    public var engineID: TranslationEngineID
    public var modelID: String?
    public var pair: LanguagePair?
    public var reason: String
    public var fallbackReason: String?

    public var usesFastMT: Bool {
        engineID == .ctranslate2 || engineID == .argos || engineID == .customCommand
    }

    public init(
        surface: TranslationRoutingSurface,
        engineID: TranslationEngineID,
        modelID: String? = nil,
        pair: LanguagePair? = nil,
        reason: String,
        fallbackReason: String? = nil
    ) {
        self.surface = surface
        self.engineID = engineID
        self.modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil
        self.pair = pair
        self.reason = reason
        self.fallbackReason = fallbackReason?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil
    }
}

public enum TranslationRoutingService {
    public static func decide(
        surface: TranslationRoutingSurface,
        preferences: FastTranslationPreferences,
        pair: LanguagePair?,
        supportedPairs: [LanguagePair],
        detectedConfidence: Double?,
        lowConfidenceThreshold: Double,
        explicitEngineID: TranslationEngineID? = nil,
        domainOverride: FastTranslationSurfaceEngine? = nil
    ) -> TranslationRoutingDecision {
        if let explicitEngineID {
            return TranslationRoutingDecision(
                surface: surface,
                engineID: explicitEngineID,
                pair: pair,
                reason: "explicitEngine"
            )
        }
        if let domainOverride, domainOverride != .auto {
            return decision(
                surface: surface,
                surfaceEngine: domainOverride,
                pair: pair,
                supportedPairs: supportedPairs,
                reason: "domainOverride"
            )
        }
        let configured = surfaceEngine(for: surface, preferences: preferences)
        switch configured {
        case .llm:
            return TranslationRoutingDecision(surface: surface, engineID: .llm, pair: pair, reason: "preferenceLLM")
        case .fastMT:
            return TranslationRoutingDecision(surface: surface, engineID: .ctranslate2, pair: pair, reason: "preferenceFastMT")
        case .auto:
            guard let pair else {
                return TranslationRoutingDecision(
                    surface: surface,
                    engineID: .llm,
                    reason: "missingLanguagePair",
                    fallbackReason: "source or target language is unknown"
                )
            }
            guard (detectedConfidence ?? 0) >= lowConfidenceThreshold else {
                return TranslationRoutingDecision(
                    surface: surface,
                    engineID: .llm,
                    pair: pair,
                    reason: "lowConfidence",
                    fallbackReason: "detected source language confidence is below threshold"
                )
            }
            guard supportedPairs.contains(pair) else {
                return TranslationRoutingDecision(
                    surface: surface,
                    engineID: .llm,
                    pair: pair,
                    reason: "unsupportedLanguagePair",
                    fallbackReason: "fast MT does not support this pair"
                )
            }
            return TranslationRoutingDecision(surface: surface, engineID: .ctranslate2, pair: pair, reason: "autoFastMT")
        }
    }

    private static func decision(
        surface: TranslationRoutingSurface,
        surfaceEngine: FastTranslationSurfaceEngine,
        pair: LanguagePair?,
        supportedPairs: [LanguagePair],
        reason: String
    ) -> TranslationRoutingDecision {
        switch surfaceEngine {
        case .llm, .auto:
            return TranslationRoutingDecision(surface: surface, engineID: .llm, pair: pair, reason: reason)
        case .fastMT:
            let engineID: TranslationEngineID = supportedPairs.isEmpty || pair.map({ supportedPairs.contains($0) }) == true
                ? .ctranslate2
                : .ctranslate2
            return TranslationRoutingDecision(surface: surface, engineID: engineID, pair: pair, reason: reason)
        }
    }

    private static func surfaceEngine(
        for surface: TranslationRoutingSurface,
        preferences: FastTranslationPreferences
    ) -> FastTranslationSurfaceEngine {
        switch surface {
        case .text:
            return preferences.engine(for: .translate)
        case .webpage:
            return preferences.engine(for: .webPageTranslate)
        case .subtitle:
            return preferences.engineForSubtitles()
        }
    }
}

private final class FastTranslationProcessSession: @unchecked Sendable {
    private let resolution: FastTranslationCommandRunner.CommandResolution
    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let requestLock = NSLock()
    private let processLifecycle = PersistentProcessLifecycle()
    private let stderrLock = NSLock()
    private var stderrData = Data()

    var readyEvent: FastTranslationSidecarEvent?

    var isRunning: Bool {
        process.isRunning && !processLifecycle.isStopped
    }

    init(resolution: FastTranslationCommandRunner.CommandResolution) throws {
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
            throw FastTranslationError.runtimeFailed(error.localizedDescription)
        }
    }

    deinit {
        stop()
    }

    func waitUntilReady() async throws -> FastTranslationSidecarEvent {
        try await Task.detached(priority: .userInitiated) { [self] in
            while true {
                let event = try readEvent()
                switch event.type {
                case "ready":
                    if event.available == false {
                        throw FastTranslationError.runtimeMissing(event.message ?? "Fast translation sidecar is unavailable.")
                    }
                    return event
                case "error":
                    if event.code == "unsupportedLanguagePair" {
                        throw FastTranslationError.unsupportedLanguagePair(
                            event.supportedPairs?.first ?? LanguagePair(source: "en", target: "zh-Hans")
                        )
                    }
                    if event.code == "runtimeUnavailable" {
                        throw FastTranslationError.runtimeMissing(event.message ?? "Fast translation runtime is unavailable.")
                    }
                    throw FastTranslationError.runtimeFailed(event.message ?? "Fast translation sidecar failed to start.")
                default:
                    continue
                }
            }
        }.value
    }

    func translate(
        batch: [FastTranslationSegment],
        pair: LanguagePair,
        resolution: FastTranslationCommandRunner.CommandResolution
    ) async throws -> [FastTranslatedSegment] {
        try await Task.detached(priority: .userInitiated) { [self] in
            try translateSync(batch: batch, pair: pair, resolution: resolution)
        }.value
    }

    func cancel(requestID: String) {
        requestLock.lock()
        defer { requestLock.unlock() }
        guard !processLifecycle.isStopped, process.isRunning else {
            return
        }
        try? writeJSONLine(FastTranslationCancelCommand(command: "cancel", requestID: requestID))
    }

    func stop() {
        processLifecycle.stop(
            process: process,
            inputHandle: inputHandle,
            errorHandle: errorHandle
        )
    }

    private func translateSync(
        batch: [FastTranslationSegment],
        pair: LanguagePair,
        resolution: FastTranslationCommandRunner.CommandResolution
    ) throws -> [FastTranslatedSegment] {
        requestLock.lock()
        defer { requestLock.unlock() }
        guard !processLifecycle.isStopped, process.isRunning else {
            throw FastTranslationError.runtimeFailed("Fast translation sidecar is not running.")
        }
        let requestID = UUID().uuidString
        try writeJSONLine(
            FastTranslationCommand(
                command: "translate",
                requestID: requestID,
                sourceLanguage: pair.source,
                targetLanguage: pair.target,
                segments: batch
            )
        )
        while true {
            let event = try readEvent()
            if event.type == "error", event.requestID == nil || event.requestID == requestID {
                if event.code == "unsupportedLanguagePair" {
                    throw FastTranslationError.unsupportedLanguagePair(pair)
                }
                throw FastTranslationError.runtimeFailed(event.message ?? "Fast translation sidecar failed.")
            }
            guard event.requestID == nil || event.requestID == requestID else {
                continue
            }
            if event.type == "translation" {
                let enriched = FastTranslationSidecarEvent(
                    protocolName: event.protocolName,
                    type: event.type,
                    requestID: event.requestID,
                    engine: event.engine ?? resolution.engineID.rawValue,
                    model: event.model ?? resolution.modelID,
                    available: event.available,
                    supportedPairs: event.supportedPairs,
                    segments: event.segments,
                    latencyMilliseconds: event.latencyMilliseconds,
                    code: event.code,
                    message: event.message
                )
                return try FastTranslationCommandRunner.translatedSegments(from: enriched, batch: batch, pair: pair)
            }
        }
    }

    private func writeJSONLine<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        var line = data
        line.append(0x0A)
        try inputHandle.write(contentsOf: line)
    }

    private func readEvent() throws -> FastTranslationSidecarEvent {
        let line = try readLineSync()
        guard let data = line.data(using: .utf8) else {
            throw FastTranslationError.runtimeFailed("Fast translation sidecar returned invalid UTF-8.")
        }
        return try JSONDecoder().decode(FastTranslationSidecarEvent.self, from: data)
    }

    private func readLineSync() throws -> String {
        var data = Data()
        while true {
            let byte = outputHandle.readData(ofLength: 1)
            if byte.isEmpty {
                let message = lastStderr()
                throw FastTranslationError.runtimeFailed(
                    message.isEmpty ? "Fast translation sidecar exited unexpectedly." : message
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
        defer { stderrLock.unlock() }
        let suffix = Data(stderrData.suffix(4_096))
        return String(data: suffix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct FastTranslationCommand: Encodable {
    var protocolName = "llmtools.fastmt/v1"
    var command: String
    var requestID: String
    var sourceLanguage: String
    var targetLanguage: String
    var segments: [FastTranslationSegment]

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case command
        case requestID
        case sourceLanguage
        case targetLanguage
        case segments
    }
}

private struct FastTranslationCancelCommand: Encodable {
    var protocolName = "llmtools.fastmt/v1"
    var command: String
    var requestID: String

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case command
        case requestID
    }
}

public struct FastTranslationSidecarEvent: Decodable, Sendable, Hashable {
    public var protocolName: String?
    public var type: String?
    public var requestID: String?
    public var engine: String?
    public var model: String?
    public var available: Bool?
    public var supportedPairs: [LanguagePair]?
    public var segments: [FastTranslationSidecarSegment]?
    public var latencyMilliseconds: Int?
    public var code: String?
    public var message: String?

    public var engineID: TranslationEngineID? {
        guard let engine else {
            return nil
        }
        return TranslationEngineID(rawValue: engine)
    }

    public init(
        protocolName: String? = nil,
        type: String? = nil,
        requestID: String? = nil,
        engine: String? = nil,
        model: String? = nil,
        available: Bool? = nil,
        supportedPairs: [LanguagePair]? = nil,
        segments: [FastTranslationSidecarSegment]? = nil,
        latencyMilliseconds: Int? = nil,
        code: String? = nil,
        message: String? = nil
    ) {
        self.protocolName = protocolName
        self.type = type
        self.requestID = requestID
        self.engine = engine
        self.model = model
        self.available = available
        self.supportedPairs = supportedPairs
        self.segments = segments
        self.latencyMilliseconds = latencyMilliseconds
        self.code = code
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case type
        case requestID
        case engine
        case model
        case available
        case supportedPairs
        case segments
        case latencyMilliseconds
        case code
        case message
    }
}

public struct FastTranslationSidecarSegment: Codable, Sendable, Hashable {
    public var id: String
    public var translation: String?

    public init(id: String, translation: String?) {
        self.id = id
        self.translation = translation
    }
}

private extension String {
    var emptyAsNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
