import Foundation

public enum AppPaths {
    public static var applicationSupportDirectory: URL {
        let fm = FileManager.default
        let urls = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("llmTranslate", isDirectory: true)
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
}
