import Foundation

public enum ProviderCredentialError: Error, LocalizedError, Sendable {
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Provider API key is missing."
        }
    }
}

public enum ProviderCredentialStore {
    public static func account(for modelID: UUID) -> String {
        "model.\(modelID.uuidString)"
    }

    public static func saveAPIKey(_ apiKey: String, account: String) throws {
        _ = apiKey
        _ = account
    }

    public static func readAPIKey(account: String) throws -> String? {
        _ = account
        return nil
    }

    public static func deleteAPIKey(account: String) throws {
        _ = account
    }

    public static func resolvedAPIKey(for configuration: ProviderConfiguration) throws -> String {
        configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
