import Foundation

public enum SpeechRuntimeMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case realtime
    case fileOnly

    public var id: String { rawValue }
}

public enum SpeechModelFamily: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case funASRNano
    case funASRMLTNano
    case senseVoiceSmall
    case qwen3ASR06B
    case qwen3ASRSherpaOnnx
    case vibeVoiceASR
    case whisperCppCoreML
    case customLocal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .funASRNano:
            return "Fun-ASR-Nano"
        case .funASRMLTNano:
            return "Fun-ASR-MLT-Nano"
        case .senseVoiceSmall:
            return "SenseVoiceSmall"
        case .qwen3ASR06B:
            return "Qwen3-ASR"
        case .qwen3ASRSherpaOnnx:
            return "Qwen3-ASR (sherpa-onnx)"
        case .vibeVoiceASR:
            return "VibeVoice-ASR"
        case .whisperCppCoreML:
            return "whisper.cpp Core ML"
        case .customLocal:
            return "Custom local ASR"
        }
    }
}

public enum ASRSourceLanguageHint: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case auto
    case zh
    case yue
    case en
    case ja
    case ko
    case vi
    case id
    case th
    case ms
    case fil
    case ar
    case hi
    case de
    case fr
    case es
    case pt
    case it
    case ru

    public var id: String { rawValue }
}

public struct SpeechModelCapabilities: Codable, Hashable, Sendable {
    public var family: SpeechModelFamily
    public var modes: [SpeechRuntimeMode]
    public var supportedLanguageHints: [String]
    public var requiresLocalSidecar: Bool
    public var canEmitSpeakerLabels: Bool
    public var source: ModelCapabilitySource
    public var confidence: Double
    public var note: String?
    public var lastCheckedAt: Date?
    public var lastFailureMessage: String?

    public init(
        family: SpeechModelFamily,
        modes: [SpeechRuntimeMode],
        supportedLanguageHints: [String] = [],
        requiresLocalSidecar: Bool = true,
        canEmitSpeakerLabels: Bool = false,
        source: ModelCapabilitySource = .unknown,
        confidence: Double = 0.5,
        note: String? = nil,
        lastCheckedAt: Date? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.family = family
        self.modes = SpeechModelCapabilities.normalizedModes(modes)
        self.supportedLanguageHints = Array(Set(supportedLanguageHints)).sorted()
        self.requiresLocalSidecar = requiresLocalSidecar
        self.canEmitSpeakerLabels = canEmitSpeakerLabels
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.note = note
        self.lastCheckedAt = lastCheckedAt
        self.lastFailureMessage = lastFailureMessage
    }

    private enum CodingKeys: String, CodingKey {
        case family
        case modes
        case supportedLanguageHints
        case requiresLocalSidecar
        case canEmitSpeakerLabels
        case source
        case confidence
        case note
        case lastCheckedAt
        case lastFailureMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decode(SpeechModelFamily.self, forKey: .family)
        modes = SpeechModelCapabilities.normalizedModes(
            try container.decodeIfPresent([SpeechRuntimeMode].self, forKey: .modes) ?? []
        )
        supportedLanguageHints = Array(Set(
            try container.decodeIfPresent([String].self, forKey: .supportedLanguageHints) ?? []
        )).sorted()
        requiresLocalSidecar = try container.decodeIfPresent(Bool.self, forKey: .requiresLocalSidecar) ?? true
        canEmitSpeakerLabels = try container.decodeIfPresent(Bool.self, forKey: .canEmitSpeakerLabels) ?? false
        source = try container.decodeIfPresent(ModelCapabilitySource.self, forKey: .source) ?? .unknown
        confidence = min(max(try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5, 0), 1)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastFailureMessage = try container.decodeIfPresent(String.self, forKey: .lastFailureMessage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(family, forKey: .family)
        try container.encode(modes, forKey: .modes)
        try container.encode(supportedLanguageHints, forKey: .supportedLanguageHints)
        try container.encode(requiresLocalSidecar, forKey: .requiresLocalSidecar)
        try container.encode(canEmitSpeakerLabels, forKey: .canEmitSpeakerLabels)
        try container.encode(source, forKey: .source)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
        try container.encodeIfPresent(lastFailureMessage, forKey: .lastFailureMessage)
    }

    public func supports(_ mode: SpeechRuntimeMode) -> Bool {
        modes.contains(mode)
    }

    public var isSelectableASRBackend: Bool {
        family != .qwen3ASRSherpaOnnx
    }

    public static func senseVoiceSmall(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.8,
        note: String? = "SenseVoiceSmall local ASR model. Low-latency short-window ASR when a local sidecar runtime is configured."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .senseVoiceSmall,
            modes: [.realtime, .fileOnly],
            supportedLanguageHints: ["auto", "zh", "yue", "en", "ja", "ko"],
            requiresLocalSidecar: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func funASRNano(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.86,
        note: String? = "Fun-ASR-Nano local ASR model. The current llmTools MLX/GGUF routes provide ASR only; the official FunASR pipeline can compose Nano with a separate CAM++ speaker model."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .funASRNano,
            modes: [.realtime, .fileOnly],
            supportedLanguageHints: ["auto", "zh", "yue", "en", "ja"],
            requiresLocalSidecar: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func funASRMLTNano(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.84,
        note: String? = "Fun-ASR-MLT-Nano local multilingual ASR model. The current llmTools MLX route provides ASR only and requires separate speaker processing."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .funASRMLTNano,
            modes: [.realtime, .fileOnly],
            supportedLanguageHints: [
                "auto", "ko", "vi", "id", "th", "ms", "fil", "ar", "hi",
                "de", "fr", "es", "pt", "it", "ru", "ja", "en"
            ],
            requiresLocalSidecar: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func qwen3ASR06B(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.75,
        note: String? = "Qwen3-ASR-0.6B local ASR model. Strong file transcription and experimental realtime only through a local vLLM/streaming sidecar."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .qwen3ASR06B,
            modes: [.realtime, .fileOnly],
            supportedLanguageHints: ["auto", "zh", "en"],
            requiresLocalSidecar: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func qwen3ASRSherpaOnnx(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.82,
        note: String? = "Deprecated sherpa-onnx Qwen3-ASR backend. It remains decodable for older registries but is no longer offered because MLX Qwen3-ASR is faster on Apple Silicon."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .qwen3ASRSherpaOnnx,
            modes: [],
            supportedLanguageHints: [
                "auto", "zh", "yue", "en", "ar", "de", "fr", "es", "pt", "id",
                "it", "ko", "ru", "th", "vi", "ja", "tr", "hi", "ms"
            ],
            requiresLocalSidecar: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func whisperCppCoreML(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.78,
        note: String? = "whisper.cpp Core ML local ASR model. Realtime subtitles run through a persistent whisper-server/Core ML sidecar; file transcription uses whisper-cli with an adjacent compiled Core ML encoder."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .whisperCppCoreML,
            modes: [.realtime, .fileOnly],
            supportedLanguageHints: [
                "auto", "zh", "yue", "en", "ja", "ko", "vi", "id", "th", "ms",
                "fil", "ar", "hi", "de", "fr", "es", "pt", "it", "ru"
            ],
            requiresLocalSidecar: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    public static func vibeVoiceASR(
        source: ModelCapabilitySource = .inferred,
        confidence: Double = 0.8,
        note: String? = "VibeVoice-ASR local ASR model. Heavy file-only rich transcription model that can emit text with speaker and timestamp metadata when the configured runtime preserves it."
    ) -> SpeechModelCapabilities {
        SpeechModelCapabilities(
            family: .vibeVoiceASR,
            modes: [.fileOnly],
            supportedLanguageHints: ["auto", "zh", "en"],
            requiresLocalSidecar: true,
            canEmitSpeakerLabels: true,
            source: source,
            confidence: confidence,
            note: note
        )
    }

    private static func normalizedModes(_ modes: [SpeechRuntimeMode]) -> [SpeechRuntimeMode] {
        let unique = Set(modes)
        return SpeechRuntimeMode.allCases.filter { unique.contains($0) }
    }
}

public enum SubtitleDisplayMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case original
    case translated
    case bilingual

    public var id: String { rawValue }
}

public enum SubtitleExportFormat: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case srt
    case vtt
    case txt
    case markdown

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .txt: return "txt"
        case .markdown: return "md"
        }
    }
}

public enum SpeakerPrefixFormat: String, Codable, Sendable, CaseIterable, Hashable {
    case colon
    case bracketed
}

public struct SubtitleExportOptions: Codable, Hashable, Sendable {
    public var includeSpeakerLabels: Bool
    public var speakerFormat: SpeakerPrefixFormat
    public var includeTranslationMetadata: Bool

    public init(
        includeSpeakerLabels: Bool = true,
        speakerFormat: SpeakerPrefixFormat = .colon,
        includeTranslationMetadata: Bool = true
    ) {
        self.includeSpeakerLabels = includeSpeakerLabels
        self.speakerFormat = speakerFormat
        self.includeTranslationMetadata = includeTranslationMetadata
    }
}

public enum ASRRuntimeSource: String, Codable, Sendable, Hashable {
    case settingsCommand
    case environmentCommand
    case fixtureTranscript
    case mlxAudioRunner
    case sherpaOnnxAuto
    case sherpaOnnxQwen3Runner
    case whisperCppCoreMLRunner
    case funASRGGUFAuto
    case funASRTorchStreaming
    case funASRCompositePipeline
    case vibeVoiceASRRunner
    case unavailable
}

public struct MediaSubtitlePreferences: Codable, Equatable, Sendable, Hashable {
    public static let defaultLiveWindowWidth: Double = 980
    public static let defaultLiveWindowHeight: Double = 220
    public static let defaultLiveTextColorHex = "#FFFFFF"
    public static let minimumLiveWindowWidth: Double = 860
    public static let minimumLiveWindowHeight: Double = 180
    public static let minimumLiveASRPartialMilliseconds = 500
    public static let maximumLiveASRPartialMilliseconds = 6_000
    public static let liveASRPartialStepMilliseconds = 50

    public var isEnabled: Bool
    public var realtimeASRModelID: UUID?
    public var fileASRModelID: UUID?
    public var defaultTargetLanguage: String
    public var sourceLanguageHint: ASRSourceLanguageHint
    public var defaultSubtitleMode: SubtitleDisplayMode
    public var saveTranscriptHistory: Bool
    public var saveTranslatedSubtitleHistory: Bool
    public var senseVoiceCommandTemplate: String
    public var funASRCommandTemplate: String
    public var qwen3ASRCommandTemplate: String
    public var vibeVoiceASRCommandTemplate: String
    public var whisperCommandTemplate: String
    public var genericASRCommandTemplate: String
    public var liveAudioSource: LiveSubtitleAudioSource
    public var liveWindowOpacity: Double
    public var liveTextColorHex: String
    public var liveWindowWidth: Double
    public var liveWindowHeight: Double
    public var liveASRPartialMillisecondsByModelID: [String: Int]
    public var exportDirectoryBookmark: Data?

    public init(
        isEnabled: Bool = true,
        realtimeASRModelID: UUID? = nil,
        fileASRModelID: UUID? = nil,
        defaultTargetLanguage: String = "zh-Hans",
        sourceLanguageHint: ASRSourceLanguageHint = .auto,
        defaultSubtitleMode: SubtitleDisplayMode = .bilingual,
        saveTranscriptHistory: Bool = false,
        saveTranslatedSubtitleHistory: Bool = false,
        senseVoiceCommandTemplate: String = "",
        funASRCommandTemplate: String = "",
        qwen3ASRCommandTemplate: String = "",
        vibeVoiceASRCommandTemplate: String = "",
        whisperCommandTemplate: String = "",
        genericASRCommandTemplate: String = "",
        liveAudioSource: LiveSubtitleAudioSource = .systemAndMicrophone,
        liveWindowOpacity: Double = 0.82,
        liveTextColorHex: String = Self.defaultLiveTextColorHex,
        liveWindowWidth: Double = Self.defaultLiveWindowWidth,
        liveWindowHeight: Double = Self.defaultLiveWindowHeight,
        liveASRPartialMillisecondsByModelID: [String: Int] = [:],
        exportDirectoryBookmark: Data? = nil
    ) {
        self.isEnabled = isEnabled
        self.realtimeASRModelID = realtimeASRModelID
        self.fileASRModelID = fileASRModelID
        self.defaultTargetLanguage = defaultTargetLanguage
        self.sourceLanguageHint = sourceLanguageHint
        self.defaultSubtitleMode = defaultSubtitleMode
        self.saveTranscriptHistory = saveTranscriptHistory
        self.saveTranslatedSubtitleHistory = saveTranslatedSubtitleHistory
        self.senseVoiceCommandTemplate = Self.normalizedCommandTemplate(senseVoiceCommandTemplate)
        self.funASRCommandTemplate = Self.normalizedCommandTemplate(funASRCommandTemplate)
        self.qwen3ASRCommandTemplate = Self.normalizedCommandTemplate(qwen3ASRCommandTemplate)
        self.vibeVoiceASRCommandTemplate = Self.normalizedCommandTemplate(vibeVoiceASRCommandTemplate)
        self.whisperCommandTemplate = Self.normalizedCommandTemplate(whisperCommandTemplate)
        self.genericASRCommandTemplate = Self.normalizedCommandTemplate(genericASRCommandTemplate)
        self.liveAudioSource = liveAudioSource
        self.liveWindowOpacity = Self.normalizedOpacity(liveWindowOpacity)
        self.liveTextColorHex = Self.normalizedLiveTextColorHex(liveTextColorHex)
        self.liveWindowWidth = Self.normalizedLiveWindowWidth(liveWindowWidth)
        self.liveWindowHeight = Self.normalizedLiveWindowHeight(liveWindowHeight)
        self.liveASRPartialMillisecondsByModelID = Self.normalizedLiveASRPartialMillisecondsByModelID(liveASRPartialMillisecondsByModelID)
        self.exportDirectoryBookmark = exportDirectoryBookmark
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case realtimeASRModelID
        case fileASRModelID
        case defaultTargetLanguage
        case sourceLanguageHint
        case defaultSubtitleMode
        case saveTranscriptHistory
        case saveTranslatedSubtitleHistory
        case senseVoiceCommandTemplate
        case funASRCommandTemplate
        case qwen3ASRCommandTemplate
        case vibeVoiceASRCommandTemplate
        case whisperCommandTemplate
        case genericASRCommandTemplate
        case liveAudioSource
        case liveWindowOpacity
        case liveTextColorHex
        case liveWindowWidth
        case liveWindowHeight
        case liveASRPartialMillisecondsByModelID
        case exportDirectoryBookmark
    }

    public init(from decoder: Decoder) throws {
        let defaults = MediaSubtitlePreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        realtimeASRModelID = try container.decodeIfPresent(UUID.self, forKey: .realtimeASRModelID)
        fileASRModelID = try container.decodeIfPresent(UUID.self, forKey: .fileASRModelID)
        defaultTargetLanguage = try container.decodeIfPresent(String.self, forKey: .defaultTargetLanguage) ?? defaults.defaultTargetLanguage
        sourceLanguageHint = try container.decodeIfPresent(ASRSourceLanguageHint.self, forKey: .sourceLanguageHint) ?? defaults.sourceLanguageHint
        defaultSubtitleMode = try container.decodeIfPresent(SubtitleDisplayMode.self, forKey: .defaultSubtitleMode) ?? defaults.defaultSubtitleMode
        saveTranscriptHistory = try container.decodeIfPresent(Bool.self, forKey: .saveTranscriptHistory) ?? defaults.saveTranscriptHistory
        saveTranslatedSubtitleHistory = try container.decodeIfPresent(Bool.self, forKey: .saveTranslatedSubtitleHistory) ?? defaults.saveTranslatedSubtitleHistory
        senseVoiceCommandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .senseVoiceCommandTemplate) ?? defaults.senseVoiceCommandTemplate
        )
        funASRCommandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .funASRCommandTemplate) ?? defaults.funASRCommandTemplate
        )
        qwen3ASRCommandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .qwen3ASRCommandTemplate) ?? defaults.qwen3ASRCommandTemplate
        )
        vibeVoiceASRCommandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .vibeVoiceASRCommandTemplate) ?? defaults.vibeVoiceASRCommandTemplate
        )
        whisperCommandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .whisperCommandTemplate) ?? defaults.whisperCommandTemplate
        )
        genericASRCommandTemplate = Self.normalizedCommandTemplate(
            try container.decodeIfPresent(String.self, forKey: .genericASRCommandTemplate) ?? defaults.genericASRCommandTemplate
        )
        liveAudioSource = try container.decodeIfPresent(LiveSubtitleAudioSource.self, forKey: .liveAudioSource) ?? defaults.liveAudioSource
        liveWindowOpacity = Self.normalizedOpacity(
            try container.decodeIfPresent(Double.self, forKey: .liveWindowOpacity) ?? defaults.liveWindowOpacity
        )
        liveTextColorHex = Self.normalizedLiveTextColorHex(
            try container.decodeIfPresent(String.self, forKey: .liveTextColorHex) ?? defaults.liveTextColorHex
        )
        liveWindowWidth = Self.normalizedLiveWindowWidth(
            try container.decodeIfPresent(Double.self, forKey: .liveWindowWidth) ?? defaults.liveWindowWidth
        )
        liveWindowHeight = Self.normalizedLiveWindowHeight(
            try container.decodeIfPresent(Double.self, forKey: .liveWindowHeight) ?? defaults.liveWindowHeight
        )
        liveASRPartialMillisecondsByModelID = Self.normalizedLiveASRPartialMillisecondsByModelID(
            try container.decodeIfPresent([String: Int].self, forKey: .liveASRPartialMillisecondsByModelID) ?? defaults.liveASRPartialMillisecondsByModelID
        )
        exportDirectoryBookmark = try container.decodeIfPresent(Data.self, forKey: .exportDirectoryBookmark)
    }

    public static func normalizedLiveWindowWidth(_ width: Double) -> Double {
        guard width.isFinite else {
            return defaultLiveWindowWidth
        }
        return max(minimumLiveWindowWidth, width)
    }

    public static func normalizedLiveWindowHeight(_ height: Double) -> Double {
        guard height.isFinite else {
            return defaultLiveWindowHeight
        }
        return max(minimumLiveWindowHeight, height)
    }

    public static func normalizedLiveASRPartialMilliseconds(_ milliseconds: Int) -> Int {
        let clamped = min(max(milliseconds, minimumLiveASRPartialMilliseconds), maximumLiveASRPartialMilliseconds)
        let step = max(liveASRPartialStepMilliseconds, 1)
        return max(minimumLiveASRPartialMilliseconds, ((clamped + step / 2) / step) * step)
    }

    public static func normalizedLiveASRPartialMillisecondsByModelID(_ values: [String: Int]) -> [String: Int] {
        values.reduce(into: [:]) { result, element in
            guard UUID(uuidString: element.key) != nil else {
                return
            }
            result[element.key.uppercased()] = normalizedLiveASRPartialMilliseconds(element.value)
        }
    }

    public func liveASRPartialMillisecondsOverride(for modelID: UUID) -> Int? {
        liveASRPartialMillisecondsByModelID[modelID.uuidString.uppercased()]
    }

    public mutating func setLiveASRPartialMillisecondsOverride(_ milliseconds: Int?, for modelID: UUID) {
        let key = modelID.uuidString.uppercased()
        if let milliseconds {
            liveASRPartialMillisecondsByModelID[key] = Self.normalizedLiveASRPartialMilliseconds(milliseconds)
        } else {
            liveASRPartialMillisecondsByModelID.removeValue(forKey: key)
        }
    }

    public func commandTemplate(for family: SpeechModelFamily) -> String? {
        switch family {
        case .funASRNano:
            if let command = Self.nonEmpty(funASRCommandTemplate) {
                return command
            }
        case .funASRMLTNano:
            if let command = Self.nonEmpty(funASRCommandTemplate) {
                return command
            }
        case .senseVoiceSmall:
            if let command = Self.nonEmpty(senseVoiceCommandTemplate) {
                return command
            }
        case .qwen3ASR06B:
            if let command = Self.nonEmpty(qwen3ASRCommandTemplate) {
                return command
            }
        case .qwen3ASRSherpaOnnx:
            break
        case .vibeVoiceASR:
            if let command = Self.nonEmpty(vibeVoiceASRCommandTemplate) {
                return command
            }
        case .whisperCppCoreML:
            if let command = Self.nonEmpty(whisperCommandTemplate) {
                return command
            }
        case .customLocal:
            break
        }
        return Self.nonEmpty(genericASRCommandTemplate)
    }

    private static func normalizedCommandTemplate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedOpacity(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    public static func normalizedLiveTextColorHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else {
            return defaultLiveTextColorHex
        }
        return "#\(hex.uppercased())"
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = normalizedCommandTemplate(value)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct SubtitleSegment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var index: Int
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var originalText: String
    public var translatedText: String?
    public var sourceLanguage: String?
    public var languageConfidence: Double?
    public var sourceLanguageDetectorModel: String?
    public var speakerID: String?
    public var speakerLabel: String?
    public var speakerConfidence: Double?
    public var isFinal: Bool
    public var asrModelID: String
    public var translationModelID: String?
    public var translationEngineID: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        originalText: String,
        translatedText: String? = nil,
        sourceLanguage: String? = nil,
        languageConfidence: Double? = nil,
        sourceLanguageDetectorModel: String? = nil,
        speakerID: String? = nil,
        speakerLabel: String? = nil,
        speakerConfidence: Double? = nil,
        isFinal: Bool = true,
        asrModelID: String,
        translationModelID: String? = nil,
        translationEngineID: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        let normalizedStart = max(0, startTime)
        self.startTime = normalizedStart
        self.endTime = endTime.map { max(normalizedStart, $0) }
        self.originalText = originalText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.languageConfidence = languageConfidence
        self.sourceLanguageDetectorModel = sourceLanguageDetectorModel
        self.speakerID = speakerID
        self.speakerLabel = speakerLabel
        self.speakerConfidence = speakerConfidence.map { min(max($0, 0), 1) }
        self.isFinal = isFinal
        self.asrModelID = asrModelID
        self.translationModelID = translationModelID
        self.translationEngineID = translationEngineID
    }
}

public struct MediaFileDescriptor: Codable, Hashable, Sendable {
    public var fileName: String
    public var fileExtension: String
    public var mediaKind: String
    public var duration: TimeInterval?
    public var sizeBytes: Int64?
    public var redactedPathHash: String

    public init(
        fileName: String,
        fileExtension: String,
        mediaKind: String,
        duration: TimeInterval? = nil,
        sizeBytes: Int64? = nil,
        redactedPathHash: String
    ) {
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.mediaKind = mediaKind
        self.duration = duration
        self.sizeBytes = sizeBytes
        self.redactedPathHash = redactedPathHash
    }
}

public struct ASRHealthReport: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable, Hashable {
        case ready
        case modelMissing
        case runtimeMissing
        case incompatibleModel
        case loadFailed
        case inferenceFailed
    }

    public var modelID: UUID?
    public var modelName: String
    public var family: SpeechModelFamily?
    public var status: Status
    public var isRealtimeCapable: Bool
    public var isFileCapable: Bool
    public var runtimeSource: ASRRuntimeSource
    public var message: String
    public var checkedAt: Date

    public init(
        modelID: UUID?,
        modelName: String,
        family: SpeechModelFamily?,
        status: Status,
        isRealtimeCapable: Bool,
        isFileCapable: Bool,
        runtimeSource: ASRRuntimeSource = .unavailable,
        message: String,
        checkedAt: Date = .now
    ) {
        self.modelID = modelID
        self.modelName = modelName
        self.family = family
        self.status = status
        self.isRealtimeCapable = isRealtimeCapable
        self.isFileCapable = isFileCapable
        self.runtimeSource = runtimeSource
        self.message = message
        self.checkedAt = checkedAt
    }
}

public struct MediaSubtitleDiagnostics: Codable, Hashable, Sendable {
    public var mediaKind: String
    public var fileType: String
    public var durationBucket: String
    public var sampleRate: Int?
    public var asrModelID: String
    public var targetLanguage: String
    public var elapsedMilliseconds: Int
    public var segmentCount: Int
    public var speakerCount: Int?
    public var diarizationModelID: String?
    public var diarizationErrorCode: String?
    public var diarizationErrorMessage: String?
    public var errorCode: String?
    public var urlHash: String?
    public var domainHash: String?

    public init(
        mediaKind: String,
        fileType: String,
        durationBucket: String,
        sampleRate: Int?,
        asrModelID: String,
        targetLanguage: String,
        elapsedMilliseconds: Int,
        segmentCount: Int,
        speakerCount: Int? = nil,
        diarizationModelID: String? = nil,
        diarizationErrorCode: String? = nil,
        diarizationErrorMessage: String? = nil,
        errorCode: String? = nil,
        urlHash: String? = nil,
        domainHash: String? = nil
    ) {
        self.mediaKind = mediaKind
        self.fileType = fileType
        self.durationBucket = durationBucket
        self.sampleRate = sampleRate
        self.asrModelID = asrModelID
        self.targetLanguage = targetLanguage
        self.elapsedMilliseconds = elapsedMilliseconds
        self.segmentCount = segmentCount
        self.speakerCount = speakerCount
        self.diarizationModelID = diarizationModelID
        self.diarizationErrorCode = diarizationErrorCode
        self.diarizationErrorMessage = diarizationErrorMessage
        self.errorCode = errorCode
        self.urlHash = urlHash
        self.domainHash = domainHash
    }
}
