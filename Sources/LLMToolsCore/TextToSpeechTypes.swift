import Foundation

public enum TTSProjectMode: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case singleNarrator
    case multiRole

    public var id: String { rawValue }
}

public enum TTSModelVariant: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case voxCPM2BF16
    case voxCPM2FourBit
    case voxCPM2EightBit

    public var id: String { rawValue }

    public var repositoryID: String {
        switch self {
        case .voxCPM2BF16: return "mlx-community/VoxCPM2-bf16"
        case .voxCPM2FourBit: return "mlx-community/VoxCPM2-4bit"
        case .voxCPM2EightBit: return "mlx-community/VoxCPM2-8bit"
        }
    }

    public var modelDirectoryName: String {
        String(repositoryID.split(separator: "/").last ?? "VoxCPM2-bf16")
    }

    public var displayName: String {
        switch self {
        case .voxCPM2BF16: return "VoxCPM2 bf16"
        case .voxCPM2FourBit: return "VoxCPM2 4bit"
        case .voxCPM2EightBit: return "VoxCPM2 8bit"
        }
    }

    public var downloadSizeDescription: String {
        switch self {
        case .voxCPM2BF16: return "4.96 GB"
        case .voxCPM2FourBit: return "2.30 GB"
        case .voxCPM2EightBit: return "3.23 GB"
        }
    }

    public var isPrimaryChoice: Bool {
        self == .voxCPM2BF16 || self == .voxCPM2FourBit
    }
}

public enum TTSVoiceOrigin: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case designed
    case cloned

    public var id: String { rawValue }
}

public enum TTSSegmentKind: String, Codable, Sendable, Hashable {
    case narration
    case dialogue
}

public enum TTSGenerationState: String, Codable, Sendable, Hashable {
    case pending
    case generating
    case completed
    case failed
    case stale
}

public struct TTSVoiceProfile: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var groupName: String?
    public var origin: TTSVoiceOrigin
    public var language: String
    public var instruction: String
    public var referenceAudioRelativePath: String?
    public var previewAudioRelativePath: String?
    public var referenceText: String
    public var usageRightsConfirmed: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        groupName: String? = nil,
        origin: TTSVoiceOrigin = .designed,
        language: String = "Chinese",
        instruction: String = "",
        referenceAudioRelativePath: String? = nil,
        previewAudioRelativePath: String? = nil,
        referenceText: String = "",
        usageRightsConfirmed: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.origin = origin
        self.language = language
        self.instruction = instruction
        self.referenceAudioRelativePath = referenceAudioRelativePath
        self.previewAudioRelativePath = previewAudioRelativePath
        self.referenceText = referenceText
        self.usageRightsConfirmed = usageRightsConfirmed
        self.createdAt = createdAt
    }
}

public struct TTSVoiceSection: Identifiable, Sendable, Hashable {
    public var groupName: String?
    public var voices: [TTSVoiceProfile]

    public var id: String {
        groupName.map { "group:\($0)" } ?? "ungrouped"
    }

    public init(groupName: String?, voices: [TTSVoiceProfile]) {
        self.groupName = groupName
        self.voices = voices
    }
}

public enum TTSVoiceCatalog {
    public static func normalizedGroupName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    public static func sections(for voices: [TTSVoiceProfile]) -> [TTSVoiceSection] {
        var orderedGroupNames: [String] = []
        var grouped: [String: [TTSVoiceProfile]] = [:]
        var ungrouped: [TTSVoiceProfile] = []

        // 分组顺序取首次出现位置，组内顺序始终沿用项目 voices 数组，避免另存一套排序状态。
        for voice in voices {
            guard let groupName = normalizedGroupName(voice.groupName) else {
                ungrouped.append(voice)
                continue
            }
            if grouped[groupName] == nil {
                orderedGroupNames.append(groupName)
                grouped[groupName] = []
            }
            grouped[groupName]?.append(voice)
        }

        var sections = orderedGroupNames.compactMap { groupName in
            grouped[groupName].map { TTSVoiceSection(groupName: groupName, voices: $0) }
        }
        if !ungrouped.isEmpty {
            sections.append(TTSVoiceSection(groupName: nil, voices: ungrouped))
        }
        return sections
    }

    public static func movingVoice(
        _ id: UUID,
        by offset: Int,
        in voices: [TTSVoiceProfile]
    ) -> [TTSVoiceProfile]? {
        guard offset == -1 || offset == 1,
              let voice = voices.first(where: { $0.id == id }) else { return nil }
        let groupName = normalizedGroupName(voice.groupName)
        let groupIndices = voices.indices.filter {
            normalizedGroupName(voices[$0].groupName) == groupName
        }
        guard let position = groupIndices.firstIndex(where: { voices[$0].id == id }) else { return nil }
        let targetPosition = position + offset
        guard groupIndices.indices.contains(targetPosition) else { return nil }
        var moved = voices
        moved.swapAt(groupIndices[position], groupIndices[targetPosition])
        return moved
    }
}

public struct TTSSegment: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var index: Int
    public var kind: TTSSegmentKind
    public var roleID: UUID
    public var speakerName: String?
    public var sourceText: String
    public var spokenText: String
    public var sourceStart: Int?
    public var sourceEnd: Int?
    public var confidence: Double
    public var deliveryStyle: String?
    public var pauseAfterMilliseconds: Int
    public var generationState: TTSGenerationState
    public var audioRelativePath: String?
    public var duration: TimeInterval?
    public var errorMessage: String?
    public var generatedAt: Date?

    public init(
        id: UUID = UUID(),
        index: Int,
        kind: TTSSegmentKind,
        roleID: UUID,
        speakerName: String? = nil,
        sourceText: String,
        spokenText: String? = nil,
        sourceStart: Int? = nil,
        sourceEnd: Int? = nil,
        confidence: Double = 1,
        deliveryStyle: String? = nil,
        pauseAfterMilliseconds: Int = 250,
        generationState: TTSGenerationState = .pending,
        audioRelativePath: String? = nil,
        duration: TimeInterval? = nil,
        errorMessage: String? = nil,
        generatedAt: Date? = nil
    ) {
        self.id = id
        self.index = max(0, index)
        self.kind = kind
        self.roleID = roleID
        self.speakerName = speakerName
        self.sourceText = sourceText
        self.spokenText = spokenText ?? sourceText
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.confidence = min(max(confidence, 0), 1)
        self.deliveryStyle = deliveryStyle
        self.pauseAfterMilliseconds = min(max(pauseAfterMilliseconds, 0), 10_000)
        self.generationState = generationState
        self.audioRelativePath = audioRelativePath
        self.duration = duration
        self.errorMessage = errorMessage
        self.generatedAt = generatedAt
    }
}

public struct TTSProject: Codable, Identifiable, Sendable, Hashable {
    public static let defaultVoicePreviewText = "你好，这是当前音色的试听。愿你今天拥有清晰而愉快的声音体验。"

    public var id: UUID
    public var name: String
    public var mode: TTSProjectMode
    public var sourceText: String
    public var modelVariant: TTSModelVariant
    public var voices: [TTSVoiceProfile]
    public var selectedVoiceID: UUID?
    public var voicePreviewText: String?
    public var segments: [TTSSegment]
    public var createdAt: Date
    public var updatedAt: Date
    public var appVersion: String

    public init(
        id: UUID = UUID(),
        name: String = "未命名配音",
        mode: TTSProjectMode = .singleNarrator,
        sourceText: String = "",
        modelVariant: TTSModelVariant = .voxCPM2BF16,
        voices: [TTSVoiceProfile] = [],
        selectedVoiceID: UUID? = nil,
        voicePreviewText: String? = TTSProject.defaultVoicePreviewText,
        segments: [TTSSegment] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        appVersion: String = "1"
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.sourceText = sourceText
        self.modelVariant = modelVariant
        let resolvedVoices = voices.isEmpty ? [TTSVoiceProfile(name: "旁白")] : voices
        self.voices = resolvedVoices
        self.selectedVoiceID = selectedVoiceID ?? resolvedVoices.first?.id
        self.voicePreviewText = voicePreviewText
        self.segments = segments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appVersion = appVersion
    }
}

public enum TTSRuntimeStatus: String, Codable, Sendable, Hashable {
    case ready
    case runtimeMissing
    case modelMissing
    case failed
}

public struct TTSRuntimeHealth: Codable, Sendable, Hashable {
    public var status: TTSRuntimeStatus
    public var modelVariant: TTSModelVariant
    public var runtimePath: String
    public var modelPath: String
    public var message: String

    public init(
        status: TTSRuntimeStatus,
        modelVariant: TTSModelVariant,
        runtimePath: String,
        modelPath: String,
        message: String
    ) {
        self.status = status
        self.modelVariant = modelVariant
        self.runtimePath = runtimePath
        self.modelPath = modelPath
        self.message = message
    }
}

public struct TTSGenerationRequest: Sendable, Hashable {
    public var text: String
    public var instruction: String?
    public var referenceAudioURL: URL?
    public var referenceText: String?
    public var outputURL: URL
    public var inferenceTimesteps: Int
    public var guidance: Double
    public var seed: UInt64

    public init(
        text: String,
        instruction: String? = nil,
        referenceAudioURL: URL? = nil,
        referenceText: String? = nil,
        outputURL: URL,
        inferenceTimesteps: Int = 10,
        guidance: Double = 2,
        seed: UInt64 = 42
    ) {
        self.text = text
        self.instruction = instruction
        self.referenceAudioURL = referenceAudioURL
        self.referenceText = referenceText
        self.outputURL = outputURL
        self.inferenceTimesteps = min(max(inferenceTimesteps, 4), 30)
        self.guidance = min(max(guidance, 1), 5)
        self.seed = seed
    }
}

public struct TTSGenerationResult: Codable, Sendable, Hashable {
    public var outputPath: String
    public var duration: TimeInterval
    public var sampleRate: Int
    public var processingTime: TimeInterval
    public var peakMemoryGB: Double?
}

public struct TTSScriptAnalysis: Sendable, Hashable {
    public var voices: [TTSVoiceProfile]
    public var segments: [TTSSegment]

    public init(voices: [TTSVoiceProfile], segments: [TTSSegment]) {
        self.voices = voices
        self.segments = segments
    }
}

public struct TTSSourceUnit: Sendable, Hashable {
    public var index: Int
    public var text: String
    public var sourceStart: Int
    public var sourceEnd: Int

    public init(index: Int, text: String, sourceStart: Int, sourceEnd: Int) {
        self.index = index
        self.text = text
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
    }
}

public enum TTSExportFormat: String, Sendable, CaseIterable, Identifiable {
    case wav
    case m4a

    public var id: String { rawValue }
}
