import Foundation

public enum SpeakerDiarizationTokenStore {
    public static var tokenFileURL: URL {
        AppPaths.applicationSupportDirectory
            .appendingPathComponent("secrets", isDirectory: true)
            .appendingPathComponent("pyannote-hf-token", isDirectory: false)
    }

    public static func save(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            try delete()
            return
        }
        let directory = tokenFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try Data(normalized.utf8).write(to: tokenFileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: tokenFileURL.path
        )
    }

    public static func read() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenFileURL.path) else {
            return nil
        }
        let token = try String(contentsOf: tokenFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    public static func delete() throws {
        guard FileManager.default.fileExists(atPath: tokenFileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: tokenFileURL)
    }

    public static func tokenPresent() -> Bool {
        ((try? read()) ?? nil)?.isEmpty == false
    }
}
