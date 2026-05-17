import Foundation
import IOKit
import Security

/// Thin wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`.
/// The DEK (data-encryption key) cache lives here so subsequent launches
/// don't have to reprompt for the passphrase. All items are scoped to
/// `kSecAttrService = service` so an uninstall or
/// `security delete-generic-password -s com.purplelife` clears everything
/// the production app owns.
///
/// **Test isolation (2026-05-15).** Under XCTest, `service` resolves to
/// `"com.purplelife.tests-<pid>"` instead of `"com.purplelife"`. Without
/// this split, `deleteAll()` (called by `KeyStoreTests.test_resetAndWipe…`
/// and friends) queries SecItem by service name alone — so any test
/// that exercised the wipe path would also delete the user's real
/// production DEK and leave the on-disk SQLCipher DB permanently
/// unreadable. Today's data-loss incident #4 was exactly this. The
/// per-pid suffix also keeps parallel test invocations from interfering
/// with each other. See HANDOFF.md (2026-05-15) for the full account.
enum KeychainStore {

    /// Service name used on every SecItem call. Production value is the
    /// stable `"com.purplelife"`; under XCTest it's a per-process
    /// `"com.purplelife.tests-<pid>"` so test cleanup paths cannot
    /// reach production entries.
    static let service: String = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "com.purplelife.tests-\(ProcessInfo.processInfo.processIdentifier)"
        }
        return "com.purplelife"
    }()

    /// Tier 3 — gate for iCloud Keychain mirror writes. Production
    /// always mirrors; tests never do (the per-pid test service name
    /// is ephemeral and would pollute the developer's iCloud
    /// Keychain). Read at static-init time so tests run in a
    /// consistent state.
    static let iCloudMirrorEnabled: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }()

    /// Per-machine identifier — incorporated into iCloud-mirror account
    /// names so each Mac in a user's trust circle gets its own entry.
    /// Without this, two Macs writing the same (service, account)
    /// synchronizable item would collide in iCloud Keychain and
    /// last-writer-wins would clobber the other Mac's DEK. With it,
    /// each Mac's mirror is independent; the trust circle delivers
    /// every Mac's own entry back to it after a local Keychain wipe.
    ///
    /// Sourced from `IOPlatformUUID` via IOKit — the OS-stable Mac
    /// hardware UUID. Stable across reboots and OS reinstalls; rotates
    /// on hardware replacement (and that's the right behavior — the
    /// SQLCipher DB on disk doesn't migrate either; Tier 2 recovery
    /// key handles cross-hardware moves).
    static let machineIdentifier: String = {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(entry) }
        guard entry != 0 else { return "unknown-machine" }
        let raw = IORegistryEntryCreateCFProperty(
            entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return (raw as? String) ?? "unknown-machine"
    }()

    /// Build the iCloud-mirror account name for a given primary
    /// account. Salts in `machineIdentifier` so per-Mac entries
    /// don't collide in the iCloud Keychain trust circle.
    static func iCloudMirrorAccount(for primary: String) -> String {
        "icloud-mirror.\(machineIdentifier).\(primary)"
    }

    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    static func setData(_ data: Data, for account: String, synchronizable: Bool = false) throws {
        // Delete any existing item first — avoids the usual SecItemAdd "dup"
        // dance when the value has changed.
        try? delete(account: account, synchronizable: synchronizable)
        var attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        if synchronizable {
            // The synchronizable flag opts the item into iCloud Keychain
            // sync. The OS handles the actual sync; on Macs where the
            // user hasn't enabled iCloud Keychain (or isn't signed in),
            // the item is still stored locally — it just doesn't
            // propagate. Either way the local read path still finds it.
            attrs[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    static func getData(for account: String, synchronizable: Bool = false) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if synchronizable {
            // SecItem treats sync and non-sync items as distinct.
            // Querying without this flag would miss the iCloud mirror
            // entry even if it's present locally.
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String, synchronizable: Bool = false) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        let status = SecItemDelete(query as CFDictionary)
        // Not-found is fine — the caller is asking us to make sure it's gone.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unexpectedStatus(status)
        }
    }

    // MARK: - Tier 3: iCloud Keychain mirror

    /// Write `data` to both the local Keychain entry AND a per-Mac
    /// iCloud Keychain mirror entry. The local entry is the fast
    /// silent-unlock path on subsequent launches. The mirror is the
    /// recovery path when the local entry is destroyed (bug, OS
    /// account migration, manual `security delete-generic-password`):
    /// `iCloud Keychain trust circle` redelivers it on next refresh.
    ///
    /// Per-Mac account naming (`iCloudMirrorAccount(for:)`) keeps each
    /// Mac's mirror independent — Mac A and Mac B can both have
    /// distinct DEKs in iCloud Keychain at the same time without
    /// collision. Cross-Mac DEK sharing was rejected as an architecture
    /// choice in HANDOFF 2026-05-15 (per-Mac DEKs + encryptedValues
    /// for sync); Tier 3 is purely a same-Mac convenience.
    ///
    /// iCloud-side writes are best-effort. If the user has iCloud
    /// Keychain disabled / isn't signed in / is offline, the OS
    /// either no-ops the sync or fails the SecItemAdd; we swallow
    /// the error and the keystore still has its local copy.
    static func setDataWithICloudMirror(_ data: Data, for account: String) throws {
        try setData(data, for: account, synchronizable: false)
        guard iCloudMirrorEnabled else { return }
        let mirrorAccount = iCloudMirrorAccount(for: account)
        try? setData(data, for: mirrorAccount, synchronizable: true)
    }

    /// Return the DEK data from the local Keychain entry, falling back
    /// to the per-Mac iCloud Keychain mirror. Used by `KeyStore.refreshState`
    /// to deliver silent recovery: if local Keychain lost the entry
    /// but the iCloud trust circle still has it, the fallback fires
    /// and the keystore unlocks without user intervention.
    static func getDataIncludingICloudMirror(for account: String) -> Data? {
        if let local = getData(for: account, synchronizable: false) {
            return local
        }
        guard iCloudMirrorEnabled else { return nil }
        let mirrorAccount = iCloudMirrorAccount(for: account)
        return getData(for: mirrorAccount, synchronizable: true)
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
        // Use kSecAttrSynchronizableAny on the list query so we
        // enumerate BOTH local and iCloud-mirror entries in one pass.
        // Each match's actual sync flag is read from the result and
        // used to route the per-account delete to the right namespace.
        // Without this, the iCloud mirror entries created by
        // setDataWithICloudMirror would be left behind on Reset.
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
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
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            // The synchronizable attribute round-trips as either a Bool
            // or NSNumber depending on macOS version; coerce
            // defensively. Items without the attribute set are treated
            // as non-synchronizable (the OS default).
            let syncFlag = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
            try? delete(account: account, synchronizable: syncFlag)
        }
    }

    /// Metadata-only probe — does an entry exist at this account?
    /// Distinguishes "definitely not there" from "couldn't tell" so the
    /// keystore bootstrap doesn't silently overwrite a slot whose
    /// contents we transiently failed to read. `getData` collapses both
    /// cases to nil, which is the load-bearing bug behind the recurring
    /// data-loss trap.
    static func entryStatus(for account: String, synchronizable: Bool = false) -> EntryStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
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
