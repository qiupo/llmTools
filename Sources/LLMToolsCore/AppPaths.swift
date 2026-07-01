import Foundation

public enum AppPaths {
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
}
