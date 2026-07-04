import AppKit
import Foundation
import LLMToolsCore

@MainActor
final class BrowserIntegrationService {
    static let shared = BrowserIntegrationService()

    let chromeExtensionDevelopmentID = "jednddlgkkohaebgoejcidfppddjegij"
    let chromeExtensionChannel = "development"
    private let nativeHostName = "com.llmtools.native_host"

    private init() {}

    func browserStates() -> [BrowserIntegrationState] {
        browserConfigurations.map(browserState(for:))
    }

    func chromeState() -> BrowserIntegrationState {
        browserState(id: "chrome")
    }

    func edgeState() -> BrowserIntegrationState {
        browserState(id: "edge")
    }

    func browserState(id: String) -> BrowserIntegrationState {
        guard let configuration = browserConfigurations.first(where: { $0.id == id }) else {
            return BrowserIntegrationState(
                id: id,
                name: id,
                bundleID: "",
                status: .failed,
                lastErrorCode: BrowserIntegrationStatus.failed.rawValue,
                lastErrorMessage: "未知浏览器配置：\(id)"
            )
        }
        return browserState(for: configuration)
    }

    func installOrRepairChromeDevelopmentHost() throws -> BrowserIntegrationState {
        try installOrRepairDevelopmentHost(browserID: "chrome")
    }

    func installOrRepairEdgeDevelopmentHost() throws -> BrowserIntegrationState {
        try installOrRepairDevelopmentHost(browserID: "edge")
    }

    func installOrRepairDevelopmentHost(browserID: String) throws -> BrowserIntegrationState {
        guard let configuration = browserConfigurations.first(where: { $0.id == browserID }) else {
            throw BrowserIntegrationError("未知浏览器配置：\(browserID)")
        }
        return try installOrRepairDevelopmentHost(for: configuration)
    }

    func openChromeExtensionsPage() {
        openExtensionsPage(browserID: "chrome")
    }

    func openEdgeExtensionsPage() {
        openExtensionsPage(browserID: "edge")
    }

    func openExtensionsPage(browserID: String) {
        guard let configuration = browserConfigurations.first(where: { $0.id == browserID }),
              let url = URL(string: configuration.extensionsPageURL) else {
            return
        }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: configuration.appPath),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func revealExtensionFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: extensionFolderPath())])
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

    func nativeHostExecutableDisplayPath() -> String {
        nativeHostExecutablePath()
    }

    private var browserConfigurations: [BrowserIntegrationConfiguration] {
        [
            BrowserIntegrationConfiguration(
                id: "chrome",
                name: "Google Chrome",
                bundleID: "com.google.Chrome",
                appPath: "/Applications/Google Chrome.app",
                nativeHostManifestDirectory: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true),
                extensionsPageURL: "chrome://extensions",
                extensionChannel: chromeExtensionChannel,
                extensionID: chromeExtensionDevelopmentID
            ),
            BrowserIntegrationConfiguration(
                id: "edge",
                name: "Microsoft Edge",
                bundleID: "com.microsoft.edgemac",
                appPath: "/Applications/Microsoft Edge.app",
                nativeHostManifestDirectory: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Microsoft Edge/NativeMessagingHosts", isDirectory: true),
                extensionsPageURL: "edge://extensions",
                extensionChannel: chromeExtensionChannel,
                extensionID: chromeExtensionDevelopmentID
            )
        ]
    }

    private func browserState(for configuration: BrowserIntegrationConfiguration) -> BrowserIntegrationState {
        let fm = FileManager.default
        let hostPath = nativeHostExecutablePath()
        let manifestPath = nativeHostManifestPath(for: configuration).path
        let extensionFolder = extensionFolderPath()
        let browserInstalled = fm.fileExists(atPath: configuration.appPath)
        let hostExists = fm.isExecutableFile(atPath: hostPath)
        let manifestExists = fm.fileExists(atPath: manifestPath)
        let extensionVersion = chromeExtensionVersion(extensionFolderPath: extensionFolder)
        let manifestDiagnosticCode = manifestExists
            ? validateNativeHostManifest(path: manifestPath, expectedHostPath: hostPath, configuration: configuration)
            : nil

        let diagnosticCode: BrowserIntegrationDiagnosticCode?
        if !browserInstalled {
            diagnosticCode = .browserNotInstalled
        } else if !hostExists {
            diagnosticCode = .nativeHostExecutableMissing
        } else if !manifestExists {
            diagnosticCode = .nativeHostManifestMissing
        } else if let manifestDiagnosticCode {
            diagnosticCode = manifestDiagnosticCode
        } else {
            diagnosticCode = nil
        }
        let status = browserIntegrationStatus(for: diagnosticCode)
        let errorMessage = diagnosticCode.map {
            browserIntegrationDiagnosticMessage(for: $0, configuration: configuration, hostPath: hostPath)
        }

        return BrowserIntegrationState(
            id: configuration.id,
            name: configuration.name,
            bundleID: configuration.bundleID,
            appPath: browserInstalled ? configuration.appPath : nil,
            extensionChannel: configuration.extensionChannel,
            extensionID: configuration.extensionID,
            extensionVersion: extensionVersion,
            nativeHostManifestPath: manifestPath,
            status: status,
            lastPingAt: diagnosticCode == nil ? Date() : nil,
            lastErrorCode: diagnosticCode?.rawValue,
            lastErrorMessage: errorMessage
        )
    }

    private func installOrRepairDevelopmentHost(for configuration: BrowserIntegrationConfiguration) throws -> BrowserIntegrationState {
        let fm = FileManager.default
        let manifestURL = nativeHostManifestPath(for: configuration)
        try fm.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let hostPath = nativeHostExecutablePath()
        guard fm.isExecutableFile(atPath: hostPath) else {
            throw BrowserIntegrationError("Native Host 不存在或不可执行：\(hostPath)")
        }

        let manifest = BrowserNativeMessagingManifest(
            name: nativeHostName,
            description: "llmTools native messaging host",
            path: hostPath,
            type: "stdio",
            allowedOrigins: [
                "chrome-extension://\(configuration.extensionID)/"
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        return browserState(for: configuration)
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

    private func chromeExtensionVersion(extensionFolderPath: String) -> String? {
        let manifestURL = URL(fileURLWithPath: extensionFolderPath)
            .appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ChromeExtensionManifest.self, from: data) else {
            return nil
        }
        return manifest.version
    }

    private func nativeHostManifestPath(for configuration: BrowserIntegrationConfiguration) -> URL {
        configuration.nativeHostManifestDirectory
            .appendingPathComponent("\(nativeHostName).json", isDirectory: false)
    }

    private func validateNativeHostManifest(path: String, expectedHostPath: String, configuration: BrowserIntegrationConfiguration) -> BrowserIntegrationDiagnosticCode? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .nativeHostManifestUnreadable
        }
        return BrowserNativeMessagingManifestValidator.diagnosticCode(
            data: data,
            expectedName: nativeHostName,
            expectedPath: expectedHostPath,
            expectedExtensionID: configuration.extensionID
        )
    }

    private func browserIntegrationStatus(for diagnosticCode: BrowserIntegrationDiagnosticCode?) -> BrowserIntegrationStatus {
        guard let diagnosticCode else {
            return .ready
        }
        switch diagnosticCode {
        case .browserNotInstalled:
            return .notInstalled
        case .nativeHostManifestMissing:
            return .nativeHostMissing
        case .appNotRunning:
            return .appNotRunning
        case .nativeHostExecutableMissing,
             .nativeHostManifestUnreadable,
             .nativeHostManifestNameMismatch,
             .nativeHostManifestTypeMismatch,
             .nativeHostManifestPathMismatch,
             .nativeHostManifestExtensionIDMismatch:
            return .nativeHostInvalid
        }
    }

    private func browserIntegrationDiagnosticMessage(
        for diagnosticCode: BrowserIntegrationDiagnosticCode,
        configuration: BrowserIntegrationConfiguration,
        hostPath: String
    ) -> String {
        switch diagnosticCode {
        case .browserNotInstalled:
            return "未找到 \(configuration.name)。"
        case .nativeHostExecutableMissing:
            return "Native Host 可执行文件不存在或不可执行：\(hostPath)。请先重新打包应用。"
        case .nativeHostManifestMissing:
            return "尚未安装 \(configuration.name) 本地桥接清单。"
        case .nativeHostManifestUnreadable:
            return "\(configuration.name) 本地桥接清单无法读取，请重新修复。"
        case .nativeHostManifestNameMismatch:
            return "\(configuration.name) 本地桥接清单名称不匹配，请重新修复。"
        case .nativeHostManifestTypeMismatch:
            return "\(configuration.name) 本地桥接清单 type 必须是 stdio，请重新修复。"
        case .nativeHostManifestPathMismatch:
            return "\(configuration.name) 本地桥接清单指向旧的 Native Host，请重新修复。"
        case .nativeHostManifestExtensionIDMismatch:
            return "\(configuration.name) 本地桥接清单缺少当前扩展 ID，请重新修复。"
        case .appNotRunning:
            return "llmTools 应用未运行，请先启动应用。"
        }
    }
}

private struct BrowserIntegrationConfiguration {
    var id: String
    var name: String
    var bundleID: String
    var appPath: String
    var nativeHostManifestDirectory: URL
    var extensionsPageURL: String
    var extensionChannel: String
    var extensionID: String
}

private struct ChromeExtensionManifest: Codable {
    var version: String?
}

struct BrowserIntegrationError: LocalizedError {
    var errorDescription: String?

    init(_ message: String) {
        self.errorDescription = message
    }
}
