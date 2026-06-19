import Foundation
import Security

/// Abstraction over secret storage so `SettingsStore` can keep credentials in
/// the macOS Keychain in production and an in-memory map in tests — unsigned
/// `swift test` binaries can't reach the real Keychain without prompts/failures.
protocol SecretStore {
    /// Upsert `value` for `account`. An empty value deletes the item (so callers
    /// can round-trip an empty password without a special case).
    func set(_ value: String, for account: String)
    func get(_ account: String) -> String?
    func delete(_ account: String)
}

/// macOS Keychain-backed secret store. Items are **device-only**
/// (`…AfterFirstUnlockThisDeviceOnly`) so credentials never sync to iCloud
/// Keychain or travel in encrypted backups. Scoped to the
/// `com.phantomlives.Ircle` service, so removing that service clears them all.
final class KeychainSecretStore: SecretStore {
    static let service = "com.phantomlives.Ircle"

    func set(_ value: String, for account: String) {
        guard !value.isEmpty else { delete(account); return }
        delete(account)   // upsert: clear any existing item first
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)   // errSecItemNotFound is fine
    }
}

/// In-memory secret store for tests.
final class InMemorySecretStore: SecretStore {
    private var items: [String: String] = [:]
    func set(_ value: String, for account: String) {
        items[account] = value.isEmpty ? nil : value
    }
    func get(_ account: String) -> String? { items[account] }
    func delete(_ account: String) { items[account] = nil }
}
