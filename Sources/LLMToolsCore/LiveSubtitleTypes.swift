import Foundation

public enum LiveSubtitleAudioSource: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case systemAudio
    case microphone
    case systemAndMicrophone

    public var id: String { rawValue }

    public var includesSystemAudio: Bool {
        self == .systemAudio || self == .systemAndMicrophone
    }

    public var includesMicrophone: Bool {
        self == .microphone || self == .systemAndMicrophone
    }
}

public struct StartAppLiveSubtitlePayload: Codable, Sendable, Hashable {
    public var targetLanguage: String?
    public var displayMode: SubtitleDisplayMode?
    public var audioSource: LiveSubtitleAudioSource?

    public init(
        targetLanguage: String? = nil,
        displayMode: SubtitleDisplayMode? = nil,
        audioSource: LiveSubtitleAudioSource? = nil
    ) {
        self.targetLanguage = targetLanguage
        self.displayMode = displayMode
        self.audioSource = audioSource
    }
}

public struct StopAppLiveSubtitlePayload: Codable, Sendable, Hashable {
    public var reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct AppLiveSubtitleStatusPayload: Codable, Sendable, Hashable {
    public var isRunning: Bool
    public var sessionID: String?
    public var audioSource: LiveSubtitleAudioSource
    public var targetLanguage: String
    public var displayMode: SubtitleDisplayMode
    public var windowOpacity: Double
    public var modelName: String?
    public var originalText: String
    public var translatedText: String
    public var isPartial: Bool
    public var status: String
    public var message: String?
    public var audioLevel: Double
    public var bufferedMilliseconds: Int
    public var speechDetected: Bool
    public var asrInFlight: Bool

    public init(
        isRunning: Bool,
        sessionID: String? = nil,
        audioSource: LiveSubtitleAudioSource,
        targetLanguage: String,
        displayMode: SubtitleDisplayMode,
        windowOpacity: Double,
        modelName: String? = nil,
        originalText: String = "",
        translatedText: String = "",
        isPartial: Bool = false,
        status: String,
        message: String? = nil,
        audioLevel: Double = 0,
        bufferedMilliseconds: Int = 0,
        speechDetected: Bool = false,
        asrInFlight: Bool = false
    ) {
        self.isRunning = isRunning
        self.sessionID = sessionID
        self.audioSource = audioSource
        self.targetLanguage = targetLanguage
        self.displayMode = displayMode
        self.windowOpacity = windowOpacity
        self.modelName = modelName
        self.originalText = originalText
        self.translatedText = translatedText
        self.isPartial = isPartial
        self.status = status
        self.message = message
        self.audioLevel = audioLevel
        self.bufferedMilliseconds = bufferedMilliseconds
        self.speechDetected = speechDetected
        self.asrInFlight = asrInFlight
    }
}

public struct CreateLiveSubtitleSessionPayload: Codable, Sendable, Hashable {
    public var tabID: Int?
    public var urlHash: String?
    public var domainHash: String?
    public var targetLanguage: String
    public var displayMode: SubtitleDisplayMode
    public var sampleRate: Int
    public var channelCount: Int

    public init(
        tabID: Int? = nil,
        urlHash: String? = nil,
        domainHash: String? = nil,
        targetLanguage: String = "zh-Hans",
        displayMode: SubtitleDisplayMode = .bilingual,
        sampleRate: Int = 16_000,
        channelCount: Int = 1
    ) {
        self.tabID = tabID
        self.urlHash = urlHash
        self.domainHash = domainHash
        self.targetLanguage = targetLanguage
        self.displayMode = displayMode
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    private enum CodingKeys: String, CodingKey {
        case tabID
        case urlHash
        case domainHash
        case targetLanguage
        case displayMode
        case sampleRate
        case channelCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabID = try container.decodeIfPresent(Int.self, forKey: .tabID)
        urlHash = try container.decodeIfPresent(String.self, forKey: .urlHash)
        domainHash = try container.decodeIfPresent(String.self, forKey: .domainHash)
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        displayMode = try container.decodeIfPresent(SubtitleDisplayMode.self, forKey: .displayMode) ?? .bilingual
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 16_000
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 1
    }
}

public struct LiveSubtitleSessionResponse: Codable, Sendable, Hashable {
    public var sessionID: String
    public var sampleRate: Int
    public var chunkFormat: String
    public var asrModelName: String
    public var asrModelID: String
    public var targetLanguage: String
    public var displayMode: SubtitleDisplayMode
    public var privacyMode: String
    public var status: String

    public init(
        sessionID: String,
        sampleRate: Int,
        chunkFormat: String = "pcm_s16le_base64",
        asrModelName: String,
        asrModelID: String,
        targetLanguage: String,
        displayMode: SubtitleDisplayMode,
        privacyMode: String = "local_asr_no_audio_or_transcript_persistence",
        status: String = "running"
    ) {
        self.sessionID = sessionID
        self.sampleRate = sampleRate
        self.chunkFormat = chunkFormat
        self.asrModelName = asrModelName
        self.asrModelID = asrModelID
        self.targetLanguage = targetLanguage
        self.displayMode = displayMode
        self.privacyMode = privacyMode
        self.status = status
    }
}

public struct LiveAudioChunkPayload: Codable, Sendable, Hashable {
    public var sessionID: String
    public var sequence: Int
    public var sampleRate: Int
    public var channelCount: Int
    public var pcm16Base64: String
    public var capturedAt: Date?

    public init(
        sessionID: String,
        sequence: Int,
        sampleRate: Int,
        channelCount: Int = 1,
        pcm16Base64: String,
        capturedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.pcm16Base64 = pcm16Base64
        self.capturedAt = capturedAt
    }
}

public enum LiveSubtitleEventKind: String, Codable, Sendable, Hashable {
    case partialTranscript
    case finalTranscript
    case partialTranslation
    case finalTranslation
    case languageDetected
    case warning
    case error
    case stopped
}

public struct LiveSubtitleEvent: Codable, Sendable, Hashable {
    public var type: LiveSubtitleEventKind
    public var sessionID: String
    public var segment: SubtitleSegment?
    public var message: String?
    public var code: String?

    public init(
        type: LiveSubtitleEventKind,
        sessionID: String,
        segment: SubtitleSegment? = nil,
        message: String? = nil,
        code: String? = nil
    ) {
        self.type = type
        self.sessionID = sessionID
        self.segment = segment
        self.message = message
        self.code = code
    }
}

public struct LiveAudioChunkResponse: Codable, Sendable, Hashable {
    public var sessionID: String
    public var acceptedSequence: Int
    public var bufferedMilliseconds: Int
    public var speechDetected: Bool
    public var events: [LiveSubtitleEvent]

    public init(
        sessionID: String,
        acceptedSequence: Int,
        bufferedMilliseconds: Int,
        speechDetected: Bool,
        events: [LiveSubtitleEvent] = []
    ) {
        self.sessionID = sessionID
        self.acceptedSequence = acceptedSequence
        self.bufferedMilliseconds = bufferedMilliseconds
        self.speechDetected = speechDetected
        self.events = events
    }
}

public struct StopLiveSubtitleSessionPayload: Codable, Sendable, Hashable {
    public var sessionID: String
    public var reason: String?

    public init(sessionID: String, reason: String? = nil) {
        self.sessionID = sessionID
        self.reason = reason
    }
}
