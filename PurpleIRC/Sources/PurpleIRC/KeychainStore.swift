import Foundation
import Security
import LocalAuthentication

/// Thin wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`.
/// Two use cases:
///
///   1. **Credential storage** (#1) — SASL / NickServ / server / proxy passwords
///      stored per-profile so `settings.json` never holds cleartext passwords.
///   2. **DEK cache** — the data-encryption key, stashed in the keychain so
///      subsequent launches don't have to reprompt for the passphrase.
///
/// All items are scoped to `kSecAttrService = "com.purpleirc"` so an uninstall
/// or `security delete-generic-password -s com.purpleirc` clears everything.
enum KeychainStore {

    static let service = "com.purpleirc"

    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    // MARK: - String (credential) storage

    /// Upsert a UTF-8 value for `account`. Empty value deletes instead of
    /// storing, so the caller can round-trip an empty password without a
    /// special case. Returns silently on success.
    static func setString(_ value: String, for account: String) throws {
        guard !value.isEmpty else {
            try delete(account: account)
            return
        }
        let data = Data(value.utf8)
        try setData(data, for: account)
    }

    /// Fetch a UTF-8 string. Returns nil when the account doesn't exist.
    static func getString(for account: String) -> String? {
        guard let data = getData(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Raw data storage (used for the wrapped DEK cache)

    static func setData(_ data: Data, for account: String,
                        requireBiometry: Bool = false) throws {
        // Delete any existing item first — avoids the usual SecItemAdd "dup"
        // dance when the value has changed.
        try? delete(account: account)
        var attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        var aclApplied = false
        if requireBiometry {
            // Gate reads behind user presence (Touch ID, or device password
            // fallback). `kSecAttrAccessControl` is mutually exclusive with
            // `kSecAttrAccessible`, so it carries the device-only protection
            // class itself. If the ACL can't be built (ad-hoc build, no
            // biometry hardware), we fall through to plain device-only
            // storage so caching still works — never a lockout.
            var err: Unmanaged<CFError>?
            if let ac = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                &err) {
                attrs[kSecAttrAccessControl as String] = ac
                aclApplied = true
            }
        }
        if !aclApplied {
            // `…ThisDeviceOnly` is load-bearing security, not a nicety: it
            // keeps the wrapped DEK and the stored credentials OUT of iCloud
            // Keychain sync, Keychain migration, and encrypted backups. A
            // plain `WhenUnlocked` item travels to other devices, where the
            // DEK alone unwraps every encrypted file without the passphrase.
            // Device-only pins confidentiality to this Mac.
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    /// Fetch raw data. Pass a (possibly already-authenticated) `LAContext`
    /// for a biometry-gated item; reading such an item without a context
    /// triggers the system Touch ID prompt synchronously.
    static func getData(for account: String, context: LAContext? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Result of a non-interactive existence probe.
    enum CacheProbe { case absent, readable, requiresAuth }

    /// Check whether an item exists and whether reading it would require a
    /// user-presence prompt — WITHOUT prompting. Used at launch to decide
    /// between a silent unlock, a biometric unlock, or the passphrase, all
    /// before any sensitive data is decrypted.
    static func probe(account: String) -> CacheProbe {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: ctx
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:             return .readable
        case errSecInteractionNotAllowed: return .requiresAuth
        default:                        return .absent
        }
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
    /// tab's "Revoke device cache / reset" destructive flow.
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Credential references

/// A credential stored in the Keychain is represented in `settings.json` as
/// an opaque reference like "kc:UUID". The UUID is the Keychain account name.
/// In-memory we keep the cleartext (SwiftUI binds to String fields directly),
/// so the transform happens only at the I/O boundary.
enum CredentialRef {
    static let prefix = "kc:"

    /// True when `raw` is a Keychain reference (not cleartext).
    static func isReference(_ raw: String) -> Bool {
        raw.hasPrefix(prefix)
    }

    /// Extract the account name from a reference, or nil when the string is
    /// cleartext.
    static func account(in raw: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }

    /// Build a new reference from a Keychain account name.
    static func makeReference(for account: String) -> String {
        prefix + account
    }
}
