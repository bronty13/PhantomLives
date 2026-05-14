import Foundation
import Security

/// Thin wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`.
/// The DEK (data-encryption key) cache lives here so subsequent launches
/// don't have to reprompt for the passphrase. All items are scoped to
/// `kSecAttrService = "com.purplelife"` so an uninstall or
/// `security delete-generic-password -s com.purplelife` clears everything.
enum KeychainStore {

    static let service = "com.purplelife"

    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    static func setData(_ data: Data, for account: String) throws {
        // Delete any existing item first — avoids the usual SecItemAdd "dup"
        // dance when the value has changed.
        try? delete(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    static func getData(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // Not-found is fine — the caller is asking us to make sure it's gone.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unexpectedStatus(status)
        }
    }

    /// Wipe every item owned by this app's service. Called from the Security
    /// tab's destructive "Reset" flow and from `KeyStore.resetAndWipe`.
    ///
    /// Implementation note: `SecItemDelete` with a query that omits
    /// `kSecAttrAccount` is unreliable across macOS versions —
    /// historically it deleted all matches, but on macOS 15 it silently
    /// returns `errSecSuccess` without actually removing items (caught
    /// by `KeyStoreTests.test_resetAndWipeClearsEverything` failing
    /// deterministically even in isolation). The robust pattern is to
    /// enumerate items via `SecItemCopyMatching` with
    /// `kSecMatchLimitAll`, then delete each by its specific account
    /// using the account-scoped query — which IS reliable.
    static func deleteAll() {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(listQuery as CFDictionary, &result)
        // errSecItemNotFound is the happy path — there's nothing to delete.
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return
        }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String {
                try? delete(account: account)
            }
        }
    }

    /// Metadata-only probe — does an entry exist at this account?
    /// Distinguishes "definitely not there" from "couldn't tell" so the
    /// keystore bootstrap doesn't silently overwrite a slot whose
    /// contents we transiently failed to read. `getData` collapses both
    /// cases to nil, which is the load-bearing bug behind the recurring
    /// data-loss trap.
    static func entryStatus(for account: String) -> EntryStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:      return .present
        case errSecItemNotFound: return .absent
        default:                 return .unknown(status)
        }
    }

    enum EntryStatus: Equatable {
        case present
        case absent
        case unknown(OSStatus)
    }
}
