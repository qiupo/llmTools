import AppKit
import Foundation
import LLMToolsCore

@MainActor
final class BrowserIntegrationService {
    static let shared = BrowserIntegrationService()

    let chromeExtensionDevelopmentID = "jednddlgkkohaebgoejcidfppddjegij"
    private let nativeHostName = "com.llmtools.native_host"

    private init() {}

    func chromeState() -> BrowserIntegrationState {
        let fm = FileManager.default
        let chromePath = "/Applications/Google Chrome.app"
        let hostPath = nativeHostExecutablePath()
        let manifestPath = chromeNativeHostManifestPath().path
        let chromeInstalled = fm.fileExists(atPath: chromePath)
        let hostExists = fm.isExecutableFile(atPath: hostPath)
        let manifestExists = fm.fileExists(atPath: manifestPath)

        let status: BrowserIntegrationStatus
        let errorMessage: String?
        if !chromeInstalled {
            status = .notInstalled
            errorMessage = "未找到 Google Chrome。"
        } else if !hostExists {
            status = .nativeHostInvalid
            errorMessage = "Native Host 可执行文件不存在，请先重新打包应用。"
        } else if !manifestExists {
            status = .nativeHostMissing
            errorMessage = "尚未安装 Chrome 本地桥接清单。"
        } else {
            status = .ready
            errorMessage = nil
        }

        return BrowserIntegrationState(
            id: "chrome",
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            appPath: chromeInstalled ? chromePath : nil,
            extensionID: chromeExtensionDevelopmentID,
            nativeHostManifestPath: manifestPath,
            status: status,
            lastErrorCode: errorMessage == nil ? nil : status.rawValue,
            lastErrorMessage: errorMessage
        )
    }

    func installOrRepairChromeDevelopmentHost() throws -> BrowserIntegrationState {
        let fm = FileManager.default
        let manifestURL = chromeNativeHostManifestPath()
        try fm.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let hostPath = nativeHostExecutablePath()
        guard fm.isExecutableFile(atPath: hostPath) else {
            throw BrowserIntegrationError("Native Host 不存在或不可执行：\(hostPath)")
        }

        let manifest = ChromeNativeHostManifest(
            name: nativeHostName,
            description: "llmTools native messaging host",
            path: hostPath,
            type: "stdio",
            allowed_origins: [
                "chrome-extension://\(chromeExtensionDevelopmentID)/"
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        return chromeState()
    }

    func openChromeExtensionsPage() {
        guard let url = URL(string: "chrome://extensions") else {
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/Google Chrome.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    func extensionFolderPath() -> String {
        let fm = FileManager.default
        if let resourcePath = Bundle.main.resourceURL?
            .appendingPathComponent("browser-extension/chromium", isDirectory: true)
            .path,
           fm.fileExists(atPath: resourcePath) {
            return resourcePath
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("browser-extension/chromium", isDirectory: true)
            .path
    }

    private func chromeNativeHostManifestPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent("\(nativeHostName).json", isDirectory: false)
    }

    private func nativeHostExecutablePath() -> String {
        if let bundlePath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("LLMToolsNativeHost")
            .path,
           FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/LLMToolsNativeHost")
            .path
    }
}

private struct ChromeNativeHostManifest: Codable {
    var name: String
    var description: String
    var path: String
    var type: String
    var allowed_origins: [String]
}

struct BrowserIntegrationError: LocalizedError {
    var errorDescription: String?

    init(_ message: String) {
        self.errorDescription = message
    }
}
