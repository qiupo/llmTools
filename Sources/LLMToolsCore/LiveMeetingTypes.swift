import Foundation

public enum LiveMeetingAudioSource: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case microphone
    case systemAudio
    case localFile

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .localFile: return "Local File"
        }
    }

    public var isLiveCapture: Bool {
        self == .microphone || self == .systemAudio
    }

    public var liveSubtitleCaptureSource: LiveSubtitleAudioSource? {
        switch self {
        case .microphone: return .microphone
        case .systemAudio: return .systemAudio
        case .localFile: return nil
        }
    }
}

public enum LiveMeetingSourceMediaKind: String, Codable, Sendable, Hashable {
    case audio
    case video
}

public enum LiveMeetingRunState: String, Codable, Sendable, Hashable {
    case idle
    case starting
    case running
    case stopping
    case stopped
    case failed
    case restored
}

public enum LiveMeetingSegmentState: String, Codable, Sendable, Hashable {
    case partial
    case final
    case lowConfidence
}

public enum LiveMeetingRecognitionStrategy: String, Codable, Sendable, Hashable {
    case nativeSpeakerASR
    case delayedSpeakerLabels
    case diarizationFirst
    case transcriptOnly

    public var displayName: String {
        switch self {
        case .nativeSpeakerASR: return "Native speaker ASR"
        case .delayedSpeakerLabels: return "Transcript first, delayed speaker labels"
        case .diarizationFirst: return "Diarization first"
        case .transcriptOnly: return "Transcript only"
        }
    }

    public var requiresFullSessionAudioBuffer: Bool {
        self == .delayedSpeakerLabels || self == .diarizationFirst
    }
}

public enum LiveMeetingFinalizationState: String, Codable, Sendable, Hashable {
    case idle
    case running
    case completed
    case cancelled
    case failed
}

public enum LiveMeetingNoteGenerationState: String, Codable, Sendable, Hashable {
    case idle
    case running
    case completed
    case cancelled
    case failed
}

public enum LiveMeetingSpeakerCountHint: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case automatic
    case two
    case three
    case four
    case fiveOrMore

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Auto"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .fiveOrMore: return "5+"
        }
    }

    public var expectedSpeakerCount: Int? {
        switch self {
        case .automatic: return nil
        case .two: return 2
        case .three: return 3
        case .four: return 4
        case .fiveOrMore: return 5
        }
    }
}

public struct LiveMeetingSession: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var source: LiveMeetingAudioSource
    public var sourceFileName: String?
    public var sourceMediaKind: LiveMeetingSourceMediaKind?
    public var startedAt: Date
    public var stoppedAt: Date?
    public var asrModelID: UUID
    public var asrModelName: String
    public var notesModelID: UUID?
    public var notesModelName: String?
    public var notesLanguage: String
    public var state: LiveMeetingRunState
    public var speakerCountHint: LiveMeetingSpeakerCountHint
    public var temporaryAudioDirectory: String?
    public var shouldDeleteTemporaryAudio: Bool
    public var finalizationState: LiveMeetingFinalizationState
    public var noteGenerationState: LiveMeetingNoteGenerationState
    public var longSessionReminderShownAt: Date?
    public var transcriptLagMilliseconds: Int
    public var speakerLagMilliseconds: Int
    public var diarizationRuntimeID: String?
    public var recognitionStrategy: LiveMeetingRecognitionStrategy?

    public init(
        id: UUID = UUID(),
        source: LiveMeetingAudioSource,
        sourceFileName: String? = nil,
        sourceMediaKind: LiveMeetingSourceMediaKind? = nil,
        startedAt: Date = .now,
        stoppedAt: Date? = nil,
        asrModelID: UUID,
        asrModelName: String,
        notesModelID: UUID? = nil,
        notesModelName: String? = nil,
        notesLanguage: String = "zh-Hans",
        state: LiveMeetingRunState = .idle,
        speakerCountHint: LiveMeetingSpeakerCountHint = .automatic,
        temporaryAudioDirectory: String? = nil,
        shouldDeleteTemporaryAudio: Bool = true,
        finalizationState: LiveMeetingFinalizationState = .idle,
        noteGenerationState: LiveMeetingNoteGenerationState = .idle,
        longSessionReminderShownAt: Date? = nil,
        transcriptLagMilliseconds: Int = 0,
        speakerLagMilliseconds: Int = 0,
        diarizationRuntimeID: String? = nil,
        recognitionStrategy: LiveMeetingRecognitionStrategy? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceFileName = Self.nonBlank(sourceFileName)
        self.sourceMediaKind = sourceMediaKind
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.asrModelID = asrModelID
        self.asrModelName = asrModelName
        self.notesModelID = notesModelID
        self.notesModelName = Self.nonBlank(notesModelName)
        self.notesLanguage = notesLanguage
        self.state = state
        self.speakerCountHint = speakerCountHint
        self.temporaryAudioDirectory = Self.nonBlank(temporaryAudioDirectory)
        self.shouldDeleteTemporaryAudio = shouldDeleteTemporaryAudio
        self.finalizationState = finalizationState
        self.noteGenerationState = noteGenerationState
        self.longSessionReminderShownAt = longSessionReminderShownAt
        self.transcriptLagMilliseconds = max(0, transcriptLagMilliseconds)
        self.speakerLagMilliseconds = max(0, speakerLagMilliseconds)
        self.diarizationRuntimeID = Self.nonBlank(diarizationRuntimeID)
        self.recognitionStrategy = recognitionStrategy
    }

    public var hasReachedLongSessionThreshold: Bool {
        guard source.isLiveCapture else { return false }
        return Date().timeIntervalSince(startedAt) >= 60 * 60
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct LiveMeetingSegment: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var index: Int
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var text: String
    public var originalText: String
    public var speakerID: String?
    public var speakerLabel: String?
    public var confidence: Double?
    public var state: LiveMeetingSegmentState
    public var userEditedSpeaker: Bool
    public var userEditedText: Bool
    public var textEditedAt: Date?
    public var includedInNotes: Bool

    public init(
        id: UUID = UUID(),
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        text: String,
        originalText: String? = nil,
        speakerID: String? = nil,
        speakerLabel: String? = nil,
        confidence: Double? = nil,
        state: LiveMeetingSegmentState = .final,
        userEditedSpeaker: Bool = false,
        userEditedText: Bool = false,
        textEditedAt: Date? = nil,
        includedInNotes: Bool = false
    ) {
        self.id = id
        self.index = max(0, index)
        let normalizedStartTime = max(0, startTime)
        self.startTime = normalizedStartTime
        self.endTime = endTime.map { max(normalizedStartTime, $0) }
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalText = (originalText ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        self.speakerID = Self.nonBlank(speakerID)
        self.speakerLabel = Self.nonBlank(speakerLabel)
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.state = state
        self.userEditedSpeaker = userEditedSpeaker
        self.userEditedText = userEditedText
        self.textEditedAt = textEditedAt
        self.includedInNotes = includedInNotes
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct LiveMeetingSpeaker: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var label: String
    public var displayName: String?
    public var colorKey: String
    public var mergedIntoSpeakerID: String?
    public var userEdited: Bool

    public init(
        id: String,
        label: String,
        displayName: String? = nil,
        colorKey: String = "blue",
        mergedIntoSpeakerID: String? = nil,
        userEdited: Bool = false
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = Self.nonBlank(displayName)
        self.colorKey = colorKey
        self.mergedIntoSpeakerID = Self.nonBlank(mergedIntoSpeakerID)
        self.userEdited = userEdited
    }

    public var renderedName: String { displayName ?? label }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct MeetingNoteState: Codable, Sendable, Hashable {
    public var summary: String
    public var decisions: [String]
    public var actionItems: [String]
    public var openQuestions: [String]
    public var topics: [String]
    public var language: String
    public var sourceSegmentCount: Int
    public var updatedAt: Date
    public var generationState: LiveMeetingNoteGenerationState
    public var isStale: Bool
    public var staleReason: String?
    public var chunkCount: Int

    public init(
        summary: String = "",
        decisions: [String] = [],
        actionItems: [String] = [],
        openQuestions: [String] = [],
        topics: [String] = [],
        language: String = "zh-Hans",
        sourceSegmentCount: Int = 0,
        updatedAt: Date = .now,
        generationState: LiveMeetingNoteGenerationState = .idle,
        isStale: Bool = false,
        staleReason: String? = nil,
        chunkCount: Int = 0
    ) {
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.decisions = decisions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.actionItems = actionItems.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.openQuestions = openQuestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.topics = topics.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.language = language
        self.sourceSegmentCount = max(0, sourceSegmentCount)
        self.updatedAt = updatedAt
        self.generationState = generationState
        self.isStale = isStale
        let staleReason = staleReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.staleReason = staleReason.isEmpty ? nil : staleReason
        self.chunkCount = max(0, chunkCount)
    }

    public var hasContent: Bool {
        !summary.isEmpty || !decisions.isEmpty || !actionItems.isEmpty || !openQuestions.isEmpty || !topics.isEmpty
    }
}

public struct LiveMeetingDiagnostics: Codable, Sendable, Hashable {
    public var sessionIDHash: String
    public var source: LiveMeetingAudioSource
    public var sourceMediaKind: LiveMeetingSourceMediaKind?
    public var asrModelID: String
    public var diarizationRuntime: String?
    public var notesModelID: String?
    public var durationBucket: String
    public var transcriptSegmentCount: Int
    public var speakerCount: Int
    public var transcriptLagBucket: String
    public var speakerLagBucket: String
    public var recoveryDraftState: String
    public var errorCode: String?

    public init(
        session: LiveMeetingSession,
        transcriptSegmentCount: Int,
        speakerCount: Int,
        recoveryDraftState: String,
        errorCode: String? = nil
    ) {
        sessionIDHash = Self.redactedHash(session.id.uuidString)
        source = session.source
        sourceMediaKind = session.sourceMediaKind
        asrModelID = session.asrModelID.uuidString
        diarizationRuntime = session.diarizationRuntimeID
        notesModelID = session.notesModelID?.uuidString
        durationBucket = Self.durationBucket(session.stoppedAt?.timeIntervalSince(session.startedAt) ?? Date().timeIntervalSince(session.startedAt))
        self.transcriptSegmentCount = max(0, transcriptSegmentCount)
        self.speakerCount = max(0, speakerCount)
        transcriptLagBucket = Self.lagBucket(session.transcriptLagMilliseconds)
        speakerLagBucket = Self.lagBucket(session.speakerLagMilliseconds)
        self.recoveryDraftState = recoveryDraftState
        let errorCode = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.errorCode = errorCode.isEmpty ? nil : errorCode
    }

    private static func redactedHash(_ value: String) -> String {
        MediaIntakeService.redactedHash(value)
    }

    private static func durationBucket(_ duration: TimeInterval) -> String {
        switch duration {
        case ..<60: return "<1m"
        case ..<300: return "1-5m"
        case ..<1800: return "5-30m"
        case ..<3600: return "30-60m"
        default: return "60m+"
        }
    }

    private static func lagBucket(_ milliseconds: Int) -> String {
        switch milliseconds {
        case ..<5_000: return "<5s"
        case ..<20_000: return "5-20s"
        case ..<90_000: return "20-90s"
        default: return "90s+"
        }
    }
}

public struct LiveMeetingRecoveryDraft: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var session: LiveMeetingSession
    public var savedAt: Date
    public var segments: [LiveMeetingSegment]
    public var speakers: [LiveMeetingSpeaker]
    public var notes: MeetingNoteState?
    public var appVersion: String

    public init(
        id: UUID = UUID(),
        session: LiveMeetingSession,
        savedAt: Date = .now,
        segments: [LiveMeetingSegment],
        speakers: [LiveMeetingSpeaker],
        notes: MeetingNoteState?,
        appVersion: String = "1"
    ) {
        self.id = id
        self.session = session
        self.savedAt = savedAt
        self.segments = segments
        self.speakers = speakers
        self.notes = notes
        self.appVersion = appVersion
    }
}

public struct LiveMeetingFileTranscriptionResult: Sendable, Hashable {
    public var descriptor: MediaFileDescriptor
    public var segments: [LiveMeetingSegment]
    public var duration: TimeInterval?
    public var asrRuntimeSource: ASRRuntimeSource
    public var recognitionStrategy: LiveMeetingRecognitionStrategy
    public var diarizationModelID: String?

    public init(
        descriptor: MediaFileDescriptor,
        segments: [LiveMeetingSegment],
        duration: TimeInterval?,
        asrRuntimeSource: ASRRuntimeSource,
        recognitionStrategy: LiveMeetingRecognitionStrategy = .transcriptOnly,
        diarizationModelID: String? = nil
    ) {
        self.descriptor = descriptor
        self.segments = segments
        self.duration = duration
        self.asrRuntimeSource = asrRuntimeSource
        self.recognitionStrategy = recognitionStrategy
        self.diarizationModelID = diarizationModelID
    }
}

public struct LiveMeetingSpeakerAudioSlice: Sendable, Hashable {
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var speakerID: String?
    public var speakerLabel: String?
    public var confidence: Double?
    public var isLowConfidence: Bool

    public init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: String?,
        speakerLabel: String?,
        confidence: Double? = nil,
        isLowConfidence: Bool = false
    ) {
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime, endTime)
        let normalizedSpeakerID = speakerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSpeakerLabel = speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.speakerID = normalizedSpeakerID.isEmpty ? nil : normalizedSpeakerID
        self.speakerLabel = normalizedSpeakerLabel.isEmpty ? nil : normalizedSpeakerLabel
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.isLowConfidence = isLowConfidence
    }
}
