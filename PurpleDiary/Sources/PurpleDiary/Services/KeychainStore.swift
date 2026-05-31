import Foundation
import Security

/// Thin wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`.
/// The DEK (data-encryption key) cache lives here so subsequent launches don't
/// have to reprompt for the passphrase. All items are scoped to
/// `kSecAttrService = service` so an uninstall or
/// `security delete-generic-password -s com.bronty13.PurpleDiary` clears
/// everything the production app owns.
///
/// PurpleDiary is **local-first by design** — the DEK is stored only in the
/// login Keychain on this Mac (no iCloud Keychain mirror, no cloud backup).
/// Cross-machine / lost-Keychain recovery is the user-held BIP39 recovery key
/// (`RecoveryKey` + `recovery_envelope.json`), never the cloud.
///
/// **Test isolation.** Under XCTest, `service` resolves to
/// `"com.bronty13.PurpleDiary.tests-<pid>"` instead of the production
/// `"com.bronty13.PurpleDiary"`. Without this split, a test exercising the
/// wipe path (`deleteAll()`) would query SecItem by service name alone and
/// delete the user's real production DEK, leaving the on-disk SQLCipher DB
/// permanently unreadable. The per-pid suffix also keeps parallel test
/// invocations from interfering with each other.
enum KeychainStore {

    /// Service name used on every SecItem call. Production is the stable
    /// `"com.bronty13.PurpleDiary"`; under XCTest it's a per-process
    /// `"com.bronty13.PurpleDiary.tests-<pid>"` so test cleanup paths
    /// cannot reach production entries.
    static let service: String = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "com.bronty13.PurpleDiary.tests-\(ProcessInfo.processInfo.processIdentifier)"
        }
        return "com.bronty13.PurpleDiary"
    }()

    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    static func setData(_ data: Data, for account: String) throws {
        // Delete any existing item first — avoids the SecItemAdd "dup" dance
        // when the value has changed.
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
    /// `kSecAttrAccount` is unreliable across macOS versions — on macOS 15 it
    /// can silently return `errSecSuccess` without removing items. The robust
    /// pattern is to enumerate items via `SecItemCopyMatching` with
    /// `kSecMatchLimitAll`, then delete each by its specific account.
    static func deleteAll() {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(listQuery as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return
        }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            try? delete(account: account)
        }
    }

    /// Metadata-only probe — does an entry exist at this account?
    /// Distinguishes "definitely not there" from "couldn't tell" so the
    /// keystore bootstrap doesn't silently overwrite a slot whose contents we
    /// transiently failed to read. `getData` collapses both cases to nil,
    /// which is the load-bearing bug behind the recurring data-loss trap.
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
