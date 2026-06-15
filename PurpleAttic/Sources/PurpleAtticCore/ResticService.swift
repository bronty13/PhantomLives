import Foundation

/// Drives `restic` non-interactively for the off-site, client-side-**E2EE** copy that replaces
/// the old Cryptomator/macFUSE vault. One `ResticService` call backs up the canonical archive
/// (ROG_WHITE) to one `CloudDestination` (a B2 repo today; an rclone-backed remote tomorrow,
/// config-only). It is built to be **unattended and laptop-friendly**:
///
///   - Secrets are never embedded. The repo passphrase is supplied via `RESTIC_PASSWORD_COMMAND`
///     so *restic* shells out to `/usr/bin/security` itself — the passphrase never enters this
///     process. Backend creds (B2 key id/key) are read from the Keychain into the **child's**
///     environment only.
///   - Network/repo unavailable is a clean **`.skipped`**, never a failure — an undocked or
///     offline laptop run is a no-op that catches up next time (same contract as the rsync mirror).
///   - `init` is idempotent (auto-creates the repo on first backup); `backup`, `check`, and
///     `restoreSample` round out the lifecycle.
///
/// Backend-specific behavior is isolated by `CloudDestination.Kind`, so adding a new backend is a
/// small `switch` arm — not a rearchitecture.
public enum ResticService {

    // MARK: - Keychain account names

    /// Fixed Keychain *account* names looked up under each destination's `keychainService`.
    /// (Documented alongside `CloudDestination`.) The service name varies per destination; these
    /// account names are constant so the runbook + tests can reference them.
    public enum KeychainAccount {
        public static let resticPassword = "restic-password"
        public static let b2AccountId    = "b2-account-id"
        public static let b2AccountKey   = "b2-account-key"
        public static let rcloneConfigPath = "rclone-config-path"
        public static let rcloneConfigPass = "rclone-config-pass"
    }

    // MARK: - Result type

    /// The outcome of a restic operation. Only `.failed` is a hard failure; `.skipped` (offline /
    /// repo unreachable) is expected and non-fatal, mapping to a successful `StepResult` exactly
    /// like the old "vault not mounted" skip.
    public enum Outcome: Sendable, Equatable {
        case backedUp(detail: String)
        case checked(detail: String)
        case restored(detail: String)
        case skipped(reason: String)
        case failed(String)

        /// Whether this outcome should mark its run step as failed. Skips are NOT failures.
        public var isFailure: Bool { if case .failed = self { return true } else { return false } }

        /// Short human detail for logs / the run report / PurpleMirror.
        public var detail: String {
            switch self {
            case .backedUp(let d), .checked(let d), .restored(let d): return d
            case .skipped(let r): return "skipped — \(r)"
            case .failed(let d): return d
            }
        }
    }

    /// Backend secrets resolved from the Keychain, passed to the (pure) env builder. Kept as a
    /// value type so `makeEnvironment` is testable without touching the Keychain.
    public struct ResolvedSecrets: Sendable, Equatable {
        public var b2AccountId: String?
        public var b2AccountKey: String?
        public var rcloneConfigPath: String?
        public var rcloneConfigPass: String?
        public init(b2AccountId: String? = nil, b2AccountKey: String? = nil,
                    rcloneConfigPath: String? = nil, rcloneConfigPass: String? = nil) {
            self.b2AccountId = b2AccountId
            self.b2AccountKey = b2AccountKey
            self.rcloneConfigPath = rcloneConfigPath
            self.rcloneConfigPass = rcloneConfigPass
        }
    }

    /// Stable `--host` for every snapshot so a *replaced* Mac still groups under one history and
    /// `restic snapshots --host purpleattic` / restore-latest stays meaningful across machines.
    public static let snapshotHost = "purpleattic"
    /// Tag applied to every PurpleAttic snapshot (separates these from any manual snapshots).
    public static let snapshotTag = "purpleattic"

    // MARK: - Pure builders (unit-tested; no Keychain / network / process)

    /// Shell-quote a value for safe interpolation into `RESTIC_PASSWORD_COMMAND` (restic runs it
    /// via `/bin/sh -c`). Single-quote wrap with the standard `'\''` escape.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The non-interactive password command restic runs to unlock the repo: it asks the macOS
    /// Keychain for the `restic-password` item under this destination's service. The passphrase
    /// is printed by `security` directly to restic — it never passes through PurpleAttic.
    public static func passwordCommand(service: String) -> String {
        "/usr/bin/security find-generic-password -s \(shellQuote(service)) -a \(KeychainAccount.resticPassword) -w"
    }

    /// Ensure the Homebrew tool dirs are on PATH (the launchd-bare-PATH lesson) so restic can find
    /// `rclone` for rclone-backed destinations. B2-only runs don't need it, but it's harmless.
    public static func ensureToolDirs(inPATH path: String) -> String {
        let wanted = ["/opt/homebrew/bin", "/usr/local/bin"]
        var parts = path.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        for dir in wanted.reversed() where !parts.contains(dir) {
            parts.insert(dir, at: 0)
        }
        return parts.joined(separator: ":")
    }

    /// Build the restic environment for a destination from already-resolved secrets. Pure and
    /// deterministic so it can be asserted in tests. Includes `PATH`/`HOME` because callers feed
    /// this to `ProcessRunner` which *replaces* the child environment wholesale.
    public static func makeEnvironment(for dest: CloudDestination, secrets: ResolvedSecrets,
                                       inheritedPATH: String, home: String) -> [String: String] {
        var env: [String: String] = [:]
        env["HOME"] = home
        env["PATH"] = ensureToolDirs(inPATH: inheritedPATH)
        env["RESTIC_REPOSITORY"] = dest.repo
        env["RESTIC_PASSWORD_COMMAND"] = passwordCommand(service: dest.keychainService)
        // Non-interactive: never prompt, and don't try to render a TTY progress bar to a pipe.
        env["RESTIC_PROGRESS_FPS"] = "0"
        switch dest.kind {
        case .resticB2:
            if let id = secrets.b2AccountId { env["B2_ACCOUNT_ID"] = id }
            if let key = secrets.b2AccountKey { env["B2_ACCOUNT_KEY"] = key }
        case .resticRclone:
            // restic shells out to rclone, which reads its remote config from RCLONE_CONFIG.
            if let cfg = secrets.rcloneConfigPath { env["RCLONE_CONFIG"] = cfg }
            if let pass = secrets.rcloneConfigPass { env["RCLONE_CONFIG_PASS"] = pass }
        }
        return env
    }

    /// Arguments for `restic backup`. Quiet, JSON-free human output we parse line-by-line.
    public static func backupArguments(sourcePath: String, tag: String = snapshotTag,
                                       host: String = snapshotHost) -> [String] {
        // --host pins snapshot identity across machines; --tag separates our snapshots;
        // --cleanup-cache trims stale cache dirs; --one-file-system keeps us on the archive volume.
        ["backup", sourcePath,
         "--tag", tag, "--host", host,
         "--one-file-system", "--cleanup-cache"]
    }

    /// Arguments for a structure `restic check`. `subset` (e.g. "1/20") adds a sampled data read.
    public static func checkArguments(readDataSubset subset: String? = nil) -> [String] {
        var args = ["check"]
        if let subset { args += ["--read-data-subset", subset] }
        return args
    }

    // MARK: - Keychain resolution (impure)

    /// Read one Keychain generic-password item, or nil if absent/locked.
    static func keychainValue(service: String, account: String) -> String? {
        guard let r = try? ProcessRunner.capture(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", service, "-a", account, "-w"]
        ), r.exitCode == 0 else { return nil }
        let v = String(data: r.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? nil : v
    }

    /// Resolve the backend secrets a destination needs from the Keychain (account names fixed,
    /// service per-destination). Missing items come back nil — `backup` then surfaces a clean
    /// skip/failure rather than prompting.
    public static func resolveSecrets(for dest: CloudDestination) -> ResolvedSecrets {
        switch dest.kind {
        case .resticB2:
            return ResolvedSecrets(
                b2AccountId: keychainValue(service: dest.keychainService, account: KeychainAccount.b2AccountId),
                b2AccountKey: keychainValue(service: dest.keychainService, account: KeychainAccount.b2AccountKey))
        case .resticRclone:
            return ResolvedSecrets(
                rcloneConfigPath: keychainValue(service: dest.keychainService, account: KeychainAccount.rcloneConfigPath),
                rcloneConfigPass: keychainValue(service: dest.keychainService, account: KeychainAccount.rcloneConfigPass))
        }
    }

    // MARK: - Runtime environment

    /// The full environment for a real restic invocation: the live process env (so the Keychain
    /// `security` child inherits a session) with our restic overrides applied on top.
    static func runtimeEnvironment(for dest: CloudDestination, secrets: ResolvedSecrets) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let overrides = makeEnvironment(for: dest, secrets: secrets,
                                        inheritedPATH: env["PATH"] ?? "/usr/bin:/bin",
                                        home: NSHomeDirectory())
        for (k, v) in overrides { env[k] = v }
        return env
    }

    // MARK: - Reachability / init

    /// Result of probing a repo before a backup.
    enum RepoState: Equatable {
        case ready                  // repo exists + reachable (or just initialized)
        case unreachable(String)    // backend offline / creds wrong — skip, catch up later
    }

    /// Probe the repo, auto-initializing it the first time (idempotent). `restic cat config`
    /// succeeds iff the repo exists *and* the backend is reachable; on failure we try `init`:
    /// a fresh repo initializes (→ ready), an "already initialized" error means the repo exists
    /// but we couldn't reach/unlock it (→ unreachable, skip), any other init failure is also a
    /// clean skip with the reason logged.
    static func ensureRepo(restic: String, env: [String: String],
                           onLine: (String) -> Void) -> RepoState {
        // 1. Fast path: config readable → ready.
        if let cat = try? ProcessRunner.run(executable: restic, arguments: ["cat", "config", "--no-lock"],
                                            environment: env, onLine: { _ in }),
           cat.exitCode == 0 {
            return .ready
        }
        // 2. Try to initialize (first-ever backup). Run through run() so it sees the repo/creds,
        //    capturing output to classify any failure.
        var initOutput = ""
        let initRun = try? ProcessRunner.run(executable: restic, arguments: ["init"],
                                             environment: env) { line in initOutput += line + "\n" }
        guard let initRun else { return .unreachable("could not launch restic") }
        if initRun.exitCode == 0 {
            onLine("restic: initialized new repository")
            return .ready
        }
        let lower = initOutput.lowercased()
        if lower.contains("already initialized") || lower.contains("already exists") {
            // Repo is there; cat config failed → transient/offline/locked. Skip, catch up next run.
            return .unreachable("repo reachable check failed (offline or locked)")
        }
        let reason = initOutput.split(separator: "\n").last.map(String.init) ?? "backend unreachable"
        return .unreachable(reason.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Operations

    /// Back up `sourcePath` to `dest`. Resolves creds, ensures the repo, runs `restic backup`,
    /// and (when `dest.checkAfterBackup`) a structure `restic check`. Returns `.skipped` when the
    /// backend is unreachable, `.failed` on a real backup error, `.backedUp` otherwise.
    public static func backup(destination dest: CloudDestination, sourcePath: String,
                              onLine: (String) -> Void) -> Outcome {
        guard let restic = Tooling.restic else {
            return .failed("restic not found — install with `brew install restic`")
        }
        guard dest.isConfigured else {
            return .skipped(reason: "destination not configured (no repo / Keychain service)")
        }
        let secrets = resolveSecrets(for: dest)
        // For B2 we need both creds present, else it's a misconfiguration we skip (not a crash).
        if dest.kind == .resticB2, secrets.b2AccountId == nil || secrets.b2AccountKey == nil {
            return .skipped(reason: "B2 credentials not in Keychain (service \(dest.keychainService))")
        }
        let env = runtimeEnvironment(for: dest, secrets: secrets)

        switch ensureRepo(restic: restic, env: env, onLine: onLine) {
        case .unreachable(let why):
            return .skipped(reason: why)
        case .ready:
            break
        }

        // Run the backup, scraping restic's human output for a compact detail string.
        var filesLine = "", addedLine = "", snapshotId = ""
        let result: ProcessRunner.Result
        do {
            result = try ProcessRunner.run(executable: restic,
                                           arguments: backupArguments(sourcePath: sourcePath),
                                           environment: env) { line in
                onLine(line)
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Files:") { filesLine = t }
                else if t.hasPrefix("Added to the repository:") { addedLine = t }
                else if t.hasPrefix("snapshot ") && t.contains("saved") {
                    // "snapshot 1a2b3c4d saved"
                    snapshotId = t.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                }
            }
        } catch {
            return .failed("couldn't launch restic backup: \(error.localizedDescription)")
        }
        guard result.exitCode == 0 else {
            return .failed("restic backup exit \(result.exitCode)")
        }

        var bits: [String] = []
        if !filesLine.isEmpty { bits.append(filesLine.replacingOccurrences(of: "Files:", with: "").trimmingCharacters(in: .whitespaces)) }
        if !addedLine.isEmpty {
            let added = addedLine.replacingOccurrences(of: "Added to the repository:", with: "").trimmingCharacters(in: .whitespaces)
            bits.append("+\(added)")
        }
        if !snapshotId.isEmpty { bits.append("snapshot \(snapshotId)") }
        let backupDetail = bits.isEmpty ? "backup complete" : bits.joined(separator: "; ")

        guard dest.checkAfterBackup else { return .backedUp(detail: backupDetail) }

        // Structure check right after backup (cheap; deep --read-data-subset is a separate job).
        let checkOutcome = check(destination: dest, env: env, restic: restic,
                                 readDataSubset: nil, onLine: onLine)
        switch checkOutcome {
        case .checked:
            return .backedUp(detail: "\(backupDetail); check OK")
        case .failed(let d):
            return .failed("backup OK but check failed: \(d)")
        default:
            return .backedUp(detail: backupDetail)
        }
    }

    /// Run `restic check` against an already-built env (internal fast path used post-backup).
    static func check(destination dest: CloudDestination, env: [String: String], restic: String,
                      readDataSubset subset: String?, onLine: (String) -> Void) -> Outcome {
        let result = try? ProcessRunner.run(executable: restic,
                                            arguments: checkArguments(readDataSubset: subset),
                                            environment: env, onLine: onLine)
        guard let result else { return .failed("couldn't launch restic check") }
        return result.exitCode == 0
            ? .checked(detail: subset == nil ? "structure OK" : "data subset \(subset!) OK")
            : .failed("restic check exit \(result.exitCode)")
    }

    /// Public `restic check` that resolves creds itself (for the scheduled deep-check job / CLI).
    public static func check(destination dest: CloudDestination, readDataSubset subset: String? = nil,
                             onLine: (String) -> Void) -> Outcome {
        guard let restic = Tooling.restic else { return .failed("restic not found") }
        guard dest.isConfigured else { return .skipped(reason: "destination not configured") }
        let secrets = resolveSecrets(for: dest)
        let env = runtimeEnvironment(for: dest, secrets: secrets)
        switch ensureRepo(restic: restic, env: env, onLine: onLine) {
        case .unreachable(let why): return .skipped(reason: why)
        case .ready: return check(destination: dest, env: env, restic: restic,
                                  readDataSubset: subset, onLine: onLine)
        }
    }

    /// Restore the latest snapshot (or a path within it) to `targetDir` — the restore smoke-test
    /// / disaster-recovery primitive. `pathFilter` (e.g. a single subfolder) keeps a sample small.
    public static func restoreSample(destination dest: CloudDestination, to targetDir: String,
                                     pathFilter: String? = nil, onLine: (String) -> Void) -> Outcome {
        guard let restic = Tooling.restic else { return .failed("restic not found") }
        guard dest.isConfigured else { return .skipped(reason: "destination not configured") }
        let secrets = resolveSecrets(for: dest)
        let env = runtimeEnvironment(for: dest, secrets: secrets)
        switch ensureRepo(restic: restic, env: env, onLine: onLine) {
        case .unreachable(let why): return .skipped(reason: why)
        case .ready: break
        }
        var args = ["restore", "latest", "--target", targetDir]
        if let pathFilter { args += ["--include", pathFilter] }
        let result = try? ProcessRunner.run(executable: restic, arguments: args,
                                            environment: env, onLine: onLine)
        guard let result else { return .failed("couldn't launch restic restore") }
        return result.exitCode == 0
            ? .restored(detail: "restored latest → \(targetDir)")
            : .failed("restic restore exit \(result.exitCode)")
    }
}
