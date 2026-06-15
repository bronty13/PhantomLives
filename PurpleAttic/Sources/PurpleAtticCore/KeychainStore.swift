import Foundation

/// Reads and writes the small set of secrets the off-site (restic) layer needs, in the login
/// Keychain via `/usr/bin/security`. Centralizing it here lets the GUI store the Backblaze B2
/// credentials + the restic runtime passphrase **without the user ever opening Terminal**, while
/// `ResticService` reads them back the same way.
///
/// Why the `security` CLI and not the `SecItem*` framework API: an item created by the app via
/// `SecItemAdd` is ACL-bound to the app, so when restic's `/usr/bin/security find-generic-password`
/// child reads it a Keychain authorization prompt appears — fatal for an *unattended* backup.
/// Items created by the `security` CLI are read back by the same `security` CLI non-interactively
/// (the proven path our restore drills used). So we create them the way they're read.
///
/// The *service* name comes from each `CloudDestination.keychainService`; the *account* names are
/// the fixed `ResticService.KeychainAccount` constants.
///
/// Caveat: a secret passed to `security -w <value>` is briefly visible in the process argument
/// list (`ps`). On a single-user Mac that is an accepted trade-off for the non-interactive read
/// guarantee above; the alternative (interactive `-w` prompt) defeats unattended operation.
public enum KeychainStore {

    public enum KeychainError: Error, CustomStringConvertible {
        case commandFailed(String)
        public var description: String {
            switch self { case .commandFailed(let m): return m }
        }
    }

    // MARK: - Pure argv builders (unit-tested; the secret is appended by the caller's exec)

    /// `security add-generic-password -U …` upserts (creates or replaces) one item. The `-w`
    /// flag's value (the secret) is appended by `set(...)`, not here, so this argv is safe to test.
    public static func upsertArguments(service: String, account: String) -> [String] {
        ["add-generic-password", "-U", "-s", service, "-a", account, "-w"]
    }

    public static func readArguments(service: String, account: String) -> [String] {
        ["find-generic-password", "-s", service, "-a", account, "-w"]
    }

    public static func deleteArguments(service: String, account: String) -> [String] {
        ["delete-generic-password", "-s", service, "-a", account]
    }

    // MARK: - Operations

    /// Store (create or replace) a secret. Throws `KeychainError.commandFailed` on failure.
    public static func set(service: String, account: String, value: String) throws {
        let r = try ProcessRunner.capture(
            executable: "/usr/bin/security",
            arguments: upsertArguments(service: service, account: account) + [value])
        guard r.exitCode == 0 else {
            let why = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw KeychainError.commandFailed(why.isEmpty ? "security exit \(r.exitCode)" : why)
        }
    }

    /// Read a secret, or nil if absent / the Keychain is locked.
    public static func get(service: String, account: String) -> String? {
        guard let r = try? ProcessRunner.capture(
            executable: "/usr/bin/security",
            arguments: readArguments(service: service, account: account)),
              r.exitCode == 0 else { return nil }
        let v = String(data: r.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? nil : v
    }

    /// Whether an item exists, without returning (or prompting for) the secret value. Uses the
    /// no-`-w` form, which only needs the item's attributes — never the protected data — so it
    /// stays non-interactive even when the value itself would require authorization.
    public static func exists(service: String, account: String) -> Bool {
        ((try? ProcessRunner.capture(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", service, "-a", account]))?.exitCode == 0)
    }

    @discardableResult
    public static func delete(service: String, account: String) -> Bool {
        ((try? ProcessRunner.capture(
            executable: "/usr/bin/security",
            arguments: deleteArguments(service: service, account: account)))?.exitCode == 0)
    }
}
