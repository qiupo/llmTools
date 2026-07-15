import Foundation

public struct RegistrySnapshot: Codable, Sendable {
    public var models: [ModelDescriptor]
    public var preferences: AppPreferences

    public init(models: [ModelDescriptor] = [], preferences: AppPreferences = .init()) {
        self.models = models
        self.preferences = preferences
    }
}

public actor RegistryStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = AppPaths.registryFileURL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> RegistrySnapshot {
        let fm = FileManager.default
        try AppPaths.preparePrivateFileStorage(at: fileURL)
        guard fm.fileExists(atPath: fileURL.path) else {
            return .init()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(RegistrySnapshot.self, from: data)
    }

    public func save(_ snapshot: RegistrySnapshot) throws {
        try AppPaths.preparePrivateFileStorage(at: fileURL)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        try AppPaths.hardenPrivateFile(at: fileURL)
    }
}
