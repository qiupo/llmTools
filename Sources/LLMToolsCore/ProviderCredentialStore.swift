import Foundation
import Security

public enum ProviderCredentialError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidAccount
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Provider API key is missing."
        case .invalidAccount:
            return "Keychain account is missing."
        case .keychainFailure(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "Keychain operation failed with status \(status)."
        }
    }
}

public enum ProviderCredentialStore {
    private static let service = "llmTools.credentials"

    public static func account(for modelID: UUID) -> String {
        "model.\(modelID.uuidString)"
    }

    public static func saveAPIKey(_ apiKey: String, account: String) throws {
        let normalizedAccount = try normalizedAccount(account)
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            try deleteAPIKey(account: normalizedAccount)
            return
        }
        let data = Data(normalizedKey.utf8)
        let query = keychainQuery(account: normalizedAccount)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ProviderCredentialError.keychainFailure(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw ProviderCredentialError.keychainFailure(updateStatus)
        }
    }

    public static func readAPIKey(account: String) throws -> String? {
        let normalizedAccount = try normalizedAccount(account)
        var query = keychainQuery(account: normalizedAccount)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ProviderCredentialError.keychainFailure(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteAPIKey(account: String) throws {
        let normalizedAccount = try normalizedAccount(account)
        let status = SecItemDelete(keychainQuery(account: normalizedAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderCredentialError.keychainFailure(status)
        }
    }

    public static func resolvedAPIKey(for configuration: ProviderConfiguration) throws -> String {
        let inlineKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !inlineKey.isEmpty {
            return inlineKey
        }
        guard let account = configuration.apiKeyKeychainAccount?.trimmingCharacters(in: .whitespacesAndNewlines),
              !account.isEmpty else {
            return ""
        }
        return try readAPIKey(account: account)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedAccount(_ account: String) throws -> String {
        let normalized = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ProviderCredentialError.invalidAccount
        }
        return normalized
    }

    private static func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
