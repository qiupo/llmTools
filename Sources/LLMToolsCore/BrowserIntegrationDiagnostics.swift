import Foundation

public enum BrowserIntegrationDiagnosticCode: String, Codable, Sendable, Hashable {
    case browserNotInstalled = "browser_not_installed"
    case nativeHostExecutableMissing = "native_host_executable_missing"
    case nativeHostManifestMissing = "native_host_manifest_missing"
    case nativeHostManifestUnreadable = "native_host_manifest_unreadable"
    case nativeHostManifestNameMismatch = "native_host_manifest_name_mismatch"
    case nativeHostManifestTypeMismatch = "native_host_manifest_type_mismatch"
    case nativeHostManifestPathMismatch = "native_host_manifest_path_mismatch"
    case nativeHostManifestExtensionIDMismatch = "native_host_manifest_extension_id_mismatch"
    case appNotRunning = "app_not_running"
}

public struct BrowserNativeMessagingManifest: Codable, Sendable, Hashable {
    public var name: String
    public var description: String
    public var path: String
    public var type: String
    public var allowedOrigins: [String]

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedOrigins = "allowed_origins"
    }

    public init(
        name: String,
        description: String,
        path: String,
        type: String = "stdio",
        allowedOrigins: [String]
    ) {
        self.name = name
        self.description = description
        self.path = path
        self.type = type
        self.allowedOrigins = allowedOrigins
    }
}

public enum BrowserNativeMessagingManifestValidator {
    public static func diagnosticCode(
        data: Data,
        expectedName: String,
        expectedPath: String,
        expectedExtensionID: String
    ) -> BrowserIntegrationDiagnosticCode? {
        guard let manifest = try? JSONDecoder().decode(BrowserNativeMessagingManifest.self, from: data) else {
            return .nativeHostManifestUnreadable
        }
        guard manifest.name == expectedName else {
            return .nativeHostManifestNameMismatch
        }
        guard manifest.type == "stdio" else {
            return .nativeHostManifestTypeMismatch
        }
        guard manifest.path == expectedPath else {
            return .nativeHostManifestPathMismatch
        }
        let expectedOrigin = "chrome-extension://\(expectedExtensionID)/"
        guard manifest.allowedOrigins.contains(expectedOrigin) else {
            return .nativeHostManifestExtensionIDMismatch
        }
        return nil
    }
}
