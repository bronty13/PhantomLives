import Foundation
import Security

/// Tiny wrapper over the macOS login Keychain for the one secret PurplePeek stores: the
/// PeekServer Basic-auth password. Keyed by `account` (we use the connection's `user@host:port`)
/// under a fixed service. Passwords never touch UserDefaults/JSON — only the Keychain.
enum KeychainStore {
    private static let service = "com.phantomlives.PurplePeek.PeekServer"

    /// Store (or replace) the password for `account`. Overwrites any existing item.
    static func setPassword(_ password: String, account: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete-then-add is simpler and race-free enough for a single-user app.
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Fetch the password for `account`, or nil if none is stored.
    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
