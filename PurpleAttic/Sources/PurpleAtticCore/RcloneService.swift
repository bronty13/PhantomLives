import Foundation

/// Drives `rclone` for the **ad-hoc, file-level** Backblaze B2 store (a second B2 account, separate
/// from the restic photo off-site). It is the file-management counterpart to `ResticService`:
///
///   - **Two env-defined remotes, no config file on disk.** rclone reads a remote entirely from
///     `RCLONE_CONFIG_<REMOTE>_<KEY>` environment variables, so we build a base `b2` remote and a
///     `crypt` remote that wraps it purely from Keychain secrets at call time — nothing secret ever
///     touches disk (the same "secrets into the child env only" contract as `ResticService`). We also
///     pin `RCLONE_CONFIG=/dev/null` so a user's personal `~/.config/rclone/rclone.conf` can neither
///     leak in nor trigger a config-password prompt mid-run.
///   - **Client-side encryption (crypt).** The app always talks to the *crypt* remote, so listing,
///     rename, and delete operate on **decrypted** names; only the raw B2 console shows scrambled
///     keys. A rename is a server-side copy + delete of the unchanged encrypted blob (no re-upload).
///   - **Permanent deletes.** The base remote sets `hard_delete=true`, so `deletefile` purges rather
///     than hides (the maintainer's "always-permanent" choice).
///
/// This file holds the **pure, unit-tested** building blocks (env + argv) plus Keychain resolution;
/// the impure operations (`backup`/`list`/`rename`/`delete`/`diff`) live in `RcloneServiceOps`.
public enum RcloneService {

    // MARK: - Remote names

    /// The env-defined base B2 remote and the crypt remote that wraps it. Lowercase in connection
    /// strings ("padhoc:"); rclone uppercases the name to find the matching `RCLONE_CONFIG_*` vars.
    public static let baseRemote = "padhocb2"
    public static let cryptRemote = "padhoc"

    // MARK: - Keychain account names

    /// Fixed Keychain *account* names looked up under the store's `keychainService` (the service name
    /// varies per store; these account names are constant for the runbook + tests). Same pattern as
    /// `ResticService.KeychainAccount`.
    public enum KeychainAccount {
        public static let b2AccountId   = "b2-account-id"
        public static let b2AccountKey  = "b2-account-key"
        /// rclone crypt passphrase, stored in rclone's *obscured* form (see `obscure`).
        public static let cryptPassword  = "crypt-password"
        /// Optional crypt salt ("password2"), also obscured. Absent → rclone uses its default salt.
        public static let cryptPassword2 = "crypt-password2"
    }

    // MARK: - Result type

    /// Outcome of an rclone operation. Only `.failed` is a hard failure; `.skipped` (offline / not
    /// configured / missing creds) is expected and non-fatal — same skip-not-fail contract as restic.
    ///
    /// Conforms to `Error` only so it can serve as the `Failure` type of the `Result` that
    /// `RcloneServiceOps.prepared(_:)` funnels precondition checks through — these values are always
    /// *returned*, never thrown.
    public enum Outcome: Sendable, Equatable, Error {
        case ok(detail: String)
        case skipped(reason: String)
        case failed(String)

        public var isFailure: Bool { if case .failed = self { return true } else { return false } }
        public var detail: String {
            switch self {
            case .ok(let d): return d
            case .skipped(let r): return "skipped — \(r)"
            case .failed(let d): return d
            }
        }
    }

    /// Backend secrets resolved from the Keychain, passed to the (pure) env builder so it stays
    /// testable without touching the Keychain. The crypt passphrase values are the **obscured** form.
    public struct ResolvedSecrets: Sendable, Equatable {
        public var b2AccountId: String?
        public var b2AccountKey: String?
        public var cryptPasswordObscured: String?
        public var cryptPassword2Obscured: String?
        public init(b2AccountId: String? = nil, b2AccountKey: String? = nil,
                    cryptPasswordObscured: String? = nil, cryptPassword2Obscured: String? = nil) {
            self.b2AccountId = b2AccountId
            self.b2AccountKey = b2AccountKey
            self.cryptPasswordObscured = cryptPasswordObscured
            self.cryptPassword2Obscured = cryptPassword2Obscured
        }
    }

    // MARK: - Pure helpers (unit-tested; no Keychain / network / process)

    /// The `RCLONE_CONFIG_<REMOTE>_<KEY>` environment variable name rclone reads a remote setting
    /// from. rclone uppercases both the remote name and the key.
    public static func configEnvKey(_ remote: String, _ key: String) -> String {
        "RCLONE_CONFIG_\(remote.uppercased())_\(key.uppercased())"
    }

    /// The base remote path the crypt remote wraps, e.g. "padhocb2:my-bucket/files" (prefix omitted
    /// → "padhocb2:my-bucket"). Slashes around the prefix are trimmed.
    public static func baseRemotePath(config: AdhocBackupConfig) -> String {
        let bucket = config.bucket.trimmingCharacters(in: .whitespaces)
        let prefix = config.prefix.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        return prefix.isEmpty ? "\(baseRemote):\(bucket)" : "\(baseRemote):\(bucket)/\(prefix)"
    }

    /// A crypt-remote path for an object, e.g. cryptPath("Invoices/x.pdf") → "padhoc:Invoices/x.pdf".
    /// An empty sub-path yields the remote root ("padhoc:").
    public static func cryptPath(_ sub: String = "") -> String {
        sub.isEmpty ? "\(cryptRemote):" : "\(cryptRemote):\(sub)"
    }

    /// Build the rclone environment for a store from already-resolved secrets. Pure and
    /// deterministic so tests can assert the exact remote definition. Includes `PATH`/`HOME` because
    /// callers feed this to `ProcessRunner`, which *replaces* the child environment wholesale.
    public static func makeEnvironment(for config: AdhocBackupConfig, secrets: ResolvedSecrets,
                                       inheritedPATH: String, home: String) -> [String: String] {
        var env: [String: String] = [:]
        env["HOME"] = home
        // Reuse restic's PATH augmentation (the launchd-bare-PATH lesson) so rclone is found.
        env["PATH"] = ResticService.ensureToolDirs(inPATH: inheritedPATH)
        // Isolate from any personal rclone config and its potential config-password prompt.
        env["RCLONE_CONFIG"] = "/dev/null"

        // Base B2 remote.
        env[configEnvKey(baseRemote, "type")] = "b2"
        if let id = secrets.b2AccountId { env[configEnvKey(baseRemote, "account")] = id }
        if let key = secrets.b2AccountKey { env[configEnvKey(baseRemote, "key")] = key }
        env[configEnvKey(baseRemote, "hard_delete")] = config.hardDelete ? "true" : "false"

        // Crypt remote wrapping the base. Filename + directory-name encryption pinned for
        // determinism regardless of rclone's defaults.
        env[configEnvKey(cryptRemote, "type")] = "crypt"
        env[configEnvKey(cryptRemote, "remote")] = baseRemotePath(config: config)
        env[configEnvKey(cryptRemote, "filename_encryption")] = "standard"
        env[configEnvKey(cryptRemote, "directory_name_encryption")] = "true"
        if let p = secrets.cryptPasswordObscured { env[configEnvKey(cryptRemote, "password")] = p }
        if let p2 = secrets.cryptPassword2Obscured { env[configEnvKey(cryptRemote, "password2")] = p2 }
        return env
    }

    // MARK: - Argument builders (pure)

    /// Copy a **directory's contents** into a remote folder: `rclone copy <dir> padhoc:<dest>` lands
    /// files at `padhoc:<dest>/…`, so passing the source's basename as `dest` preserves the folder.
    ///
    /// `--size-only`: compare by size alone, never modtime. Through a **crypt** remote rclone can't
    /// match B2's hashes (they're hashes of the *encrypted* blob, not the plaintext), so it falls
    /// back to size+modtime — and modtime is fragile here: re-staging a source onto another drive
    /// (e.g. moving the Rachel archive to REDONE) rewrites mtimes, so rclone would re-upload every
    /// file as "replaced existing" and re-send the whole archive each run. These stores are additive
    /// and **immutable** (photo/message exports are never edited in place; new items are only added),
    /// so "same name + same size = already uploaded" is correct and makes the backup a true, fast
    /// incremental. (Wrong for an in-place-editable tree, right for an append-only archive.)
    public static func copyArguments(source: String, destRemotePath: String) -> [String] {
        ["copy", source, cryptPath(destRemotePath), "--size-only"]
    }

    /// Copy a **single file** to an exact remote path: `rclone copyto <file> padhoc:<dest>`.
    /// `--size-only` for the same reason as `copyArguments` (crypt can't hash-match; modtime is
    /// fragile; the store is additive/immutable).
    public static func copytoArguments(source: String, destRemotePath: String) -> [String] {
        ["copyto", source, cryptPath(destRemotePath), "--size-only"]
    }

    /// List the store. `--files-only` keeps the cache to real files (dirs are implied by paths);
    /// `--hash` includes the (encrypted-blob) SHA-1 when available.
    public static func lsjsonArguments(remotePath: String = "", recursive: Bool = true,
                                       filesOnly: Bool = true, hash: Bool = false) -> [String] {
        var a = ["lsjson", cryptPath(remotePath)]
        if recursive { a.append("--recursive") }
        if filesOnly { a.append("--files-only") }
        if hash { a.append("--hash") }
        return a
    }

    /// Rename/move within the store. `moveto` is a server-side copy + delete on B2 (no re-upload of
    /// the unchanged encrypted blob).
    public static func moveArguments(fromRemotePath: String, toRemotePath: String) -> [String] {
        ["moveto", cryptPath(fromRemotePath), cryptPath(toRemotePath)]
    }

    /// Delete one object. With the base remote's `hard_delete=true` this is permanent; `--b2-hard-delete`
    /// is added belt-and-suspenders so a permanent delete never silently degrades to a hide.
    public static func deleteArguments(remotePath: String) -> [String] {
        ["deletefile", cryptPath(remotePath), "--b2-hard-delete"]
    }

    /// One-way additive diff of a local source against a remote sub-path: reports `+` (upload),
    /// `*` (changed), `=` (same); `--one-way` suppresses remote-only entries. `--combined -` writes
    /// the symbol/path lines to stdout for `RcloneParse.checkCombined`.
    public static func checkArguments(localSource: String, remotePath: String = "") -> [String] {
        ["check", localSource, cryptPath(remotePath), "--one-way", "--combined", "-"]
    }

    // MARK: - Keychain resolution (impure)

    /// Resolve the secrets this store needs from the Keychain (account names fixed, service per-store).
    /// Missing items come back nil — ops then surface a clean skip rather than prompting.
    public static func resolveSecrets(for config: AdhocBackupConfig) -> ResolvedSecrets {
        ResolvedSecrets(
            b2AccountId: KeychainStore.get(service: config.keychainService, account: KeychainAccount.b2AccountId),
            b2AccountKey: KeychainStore.get(service: config.keychainService, account: KeychainAccount.b2AccountKey),
            cryptPasswordObscured: KeychainStore.get(service: config.keychainService, account: KeychainAccount.cryptPassword),
            cryptPassword2Obscured: KeychainStore.get(service: config.keychainService, account: KeychainAccount.cryptPassword2))
    }

    /// The full environment for a real rclone invocation: the live process env (so any child inherits
    /// a session) with our rclone remote definitions applied on top.
    static func runtimeEnvironment(for config: AdhocBackupConfig, secrets: ResolvedSecrets) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let overrides = makeEnvironment(for: config, secrets: secrets,
                                        inheritedPATH: env["PATH"] ?? "/usr/bin:/bin",
                                        home: NSHomeDirectory())
        for (k, v) in overrides { env[k] = v }
        return env
    }

    /// Convert a plaintext passphrase to rclone's *obscured* form (`rclone obscure`). This is the
    /// form rclone's config (and thus our `RCLONE_CONFIG_*_PASSWORD` env) requires. Obscure is
    /// reversible — it's not encryption — so the result is stored in the Keychain, never on disk.
    /// (Caveat: the plaintext is briefly visible in `ps` argv, the same accepted trade-off as
    /// `KeychainStore.set`.) Returns nil if rclone is unavailable.
    public static func obscure(_ plaintext: String) -> String? {
        guard let rclone = Tooling.rclone else { return nil }
        guard let r = try? ProcessRunner.capture(executable: rclone, arguments: ["obscure", plaintext]),
              r.exitCode == 0 else { return nil }
        let v = String(data: r.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? nil : v
    }
}
