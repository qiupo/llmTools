import Foundation

public enum LiveMeetingDiarizationRuntimeSource: String, Codable, Sendable, Hashable {
    case fixtureJSON
    case sharedPyannoteRuntime
    case unavailable
}

public struct LiveMeetingDiarizationHealth: Codable, Sendable, Hashable {
    public var isReady: Bool
    public var source: LiveMeetingDiarizationRuntimeSource
    public var message: String
    public var checkedAt: Date

    public init(isReady: Bool, source: LiveMeetingDiarizationRuntimeSource, message: String, checkedAt: Date = .now) {
        self.isReady = isReady
        self.source = source
        self.message = message
        self.checkedAt = checkedAt
    }
}

public enum LiveMeetingDiarizationError: Error, LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

/// Meeting diarization deliberately shares the file-subtitle local runtime.
/// It never accepts a custom command and the underlying sidecar is forced offline.
public struct LiveMeetingDiarizationService: Sendable {
    private let sharedService: SpeakerDiarizationService

    public init(sharedService: SpeakerDiarizationService = SpeakerDiarizationService()) {
        self.sharedService = sharedService
    }

    public func health(
        preferences: SpeakerDiarizationPreferences = SpeakerDiarizationPreferences()
    ) async -> LiveMeetingDiarizationHealth {
        if (try? meetingFixtureResult()) != nil || (try? SpeakerDiarizationCommandRunner.fixtureResult()) != nil {
            return LiveMeetingDiarizationHealth(
                isReady: true,
                source: .fixtureJSON,
                message: "Fixture diarization is ready."
            )
        }
        guard !SpeakerDiarizationCommandRunner.hasCustomCommand(preferences: preferences) else {
            return LiveMeetingDiarizationHealth(
                isReady: false,
                source: .unavailable,
                message: "会议不使用自定义说话人分离命令。请使用已配置的本地 pyannote runtime。"
            )
        }

        let meetingPreferences = localMeetingPreferences(from: preferences)
        let report = await sharedService.health(preferences: meetingPreferences)
        guard report.status == .ready else {
            return LiveMeetingDiarizationHealth(
                isReady: false,
                source: .unavailable,
                message: report.message
            )
        }
        return LiveMeetingDiarizationHealth(
            isReady: true,
            source: .sharedPyannoteRuntime,
            message: "会议复用本地 pyannote 说话人分离运行时。"
        )
    }

    public func diarize(
        audioURL: URL,
        speakerCountHint: LiveMeetingSpeakerCountHint = .automatic,
        preferences: SpeakerDiarizationPreferences = SpeakerDiarizationPreferences()
    ) async throws -> SpeakerDiarizationResult {
        if let fixture = try meetingFixtureResult() {
            return fixture
        }
        guard !SpeakerDiarizationCommandRunner.hasCustomCommand(preferences: preferences) else {
            throw LiveMeetingDiarizationError.unavailable(
                "会议不使用自定义说话人分离命令。请使用已配置的本地 pyannote runtime。"
            )
        }
        let automaticMinimumSpeakerCount = speakerCountHint == .automatic ? 2 : nil
        return try await sharedService.diarize(
            audioURL: audioURL,
            preferences: localMeetingPreferences(from: preferences),
            expectedSpeakerCount: speakerCountHint.expectedSpeakerCount,
            minimumSpeakerCount: automaticMinimumSpeakerCount
        )
    }

    private func localMeetingPreferences(from preferences: SpeakerDiarizationPreferences) -> SpeakerDiarizationPreferences {
        SpeakerDiarizationPreferences(
            enabledForFileSubtitles: true,
            modelIdentifier: preferences.modelIdentifier,
            cacheDirectory: preferences.cacheDirectory,
            commandTemplate: "",
            persistSpeakerEmbeddings: false
        )
    }

    private func meetingFixtureResult() throws -> SpeakerDiarizationResult? {
        guard let value = ProcessInfo.processInfo.environment["LLMTOOLS_MEETING_DIARIZATION_FIXTURE_JSON"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        let data: Data
        if value.hasPrefix("{") || value.hasPrefix("[") {
            data = Data(value.utf8)
        } else {
            data = try Data(contentsOf: URL(fileURLWithPath: NSString(string: value).expandingTildeInPath))
        }
        var result = try JSONDecoder().decode(SpeakerDiarizationResult.self, from: data)
        result.runtimeSource = .fixtureJSON
        return result
    }
}
