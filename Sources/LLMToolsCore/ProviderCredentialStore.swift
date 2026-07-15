import Foundation

public enum ProviderCredentialStore {
    public static func resolvedAPIKey(for configuration: ProviderConfiguration) throws -> String {
        // Provider 密钥只使用注册表中的本地值；旧 Keychain 字段仅用于解码兼容，绝不访问系统钥匙串。
        configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
