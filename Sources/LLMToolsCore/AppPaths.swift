import Foundation

public enum AppPaths {
    private static let privateDirectoryPermissions = 0o700
    private static let privateFilePermissions = 0o600

    public static var applicationSupportDirectory: URL {
        let fm = FileManager.default
        let urls = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let current = base.appendingPathComponent("llmTools", isDirectory: true)
        migrateLegacyApplicationSupportDirectoryIfNeeded(from: base.appendingPathComponent("llmTranslate", isDirectory: true), to: current)
        return current
    }

    public static var registryFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("model-registry.json", isDirectory: false)
    }

    public static var historyFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.json", isDirectory: false)
    }

    public static var webPageBridgeStateFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("web-page-bridge.json", isDirectory: false)
    }

    public static var liveMeetingRecoveryDraftFileURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("live-meeting", isDirectory: true)
            .appendingPathComponent("recovery-draft.json", isDirectory: false)
    }

    public static var liveMeetingTemporaryDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("live-meeting", isDirectory: true)
            .appendingPathComponent("temporary-audio", isDirectory: true)
    }

    public static var asrRuntimeDirectory: URL {
        runtimeDirectory(environmentKey: "LLMTOOLS_ASR_RUNTIME_ROOT", defaultName: "asr-runtime")
    }

    public static var funASRPipelineRuntimeDirectory: URL {
        if let value = environmentPath("LLMTOOLS_FUNASR_PIPELINE_ROOT") {
            return value
        }
        return asrRuntimeDirectory.appendingPathComponent("funasr-pipeline", isDirectory: true)
    }

    public static var diarizationRuntimeDirectory: URL {
        runtimeDirectory(environmentKey: "LLMTOOLS_DIARIZATION_RUNTIME_DIR", defaultName: "diarization-runtime")
    }

    public static var languageDetectionRuntimeDirectory: URL {
        runtimeDirectory(environmentKey: "LLMTOOLS_LID_RUNTIME_DIR", defaultName: "lid-runtime")
    }

    public static var fastTranslationRuntimeDirectory: URL {
        runtimeDirectory(environmentKey: "LLMTOOLS_FASTMT_RUNTIME_DIR", defaultName: "fastmt-runtime")
    }

    public static var ttsRuntimeDirectory: URL {
        runtimeDirectory(environmentKey: "LLMTOOLS_TTS_RUNTIME_ROOT", defaultName: "tts-runtime")
    }

    public static var ttsModelsDirectory: URL {
        ttsRuntimeDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public static var ttsProjectsDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("tts", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    public static func preparePrivateFileStorage(at fileURL: URL) throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: privateDirectoryPermissions]
        )
        // 注册表和历史可能包含密钥或用户文本，已有目录也必须主动修正旧权限。
        try fm.setAttributes(
            [.posixPermissions: privateDirectoryPermissions],
            ofItemAtPath: directory.path
        )
        if fm.fileExists(atPath: fileURL.path) {
            try hardenPrivateFile(at: fileURL)
        }
        if fileURL.lastPathComponent == "model-registry.json" {
            let backupPrefix = "\(fileURL.lastPathComponent).bak-"
            for candidate in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where candidate.lastPathComponent.hasPrefix(backupPrefix) {
                try hardenPrivateFile(at: candidate)
            }
        }
    }

    public static func hardenPrivateFile(at fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: privateFilePermissions],
            ofItemAtPath: fileURL.path
        )
    }

    private static func migrateLegacyApplicationSupportDirectoryIfNeeded(from legacy: URL, to current: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: current.path),
              fm.fileExists(atPath: legacy.path) else {
            return
        }
        try? fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: legacy, to: current)
        try? fm.removeItem(at: current.appendingPathComponent("web-page-bridge.json", isDirectory: false))
    }

    private static func runtimeDirectory(environmentKey: String, defaultName: String) -> URL {
        environmentPath(environmentKey)
            ?? applicationSupportDirectory.appendingPathComponent(defaultName, isDirectory: true)
    }

    private static func environmentPath(_ key: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath, isDirectory: true)
    }
}
