import Foundation

/// The impure operations of the ad-hoc B2 store: they resolve creds, build the runtime env, and
/// drive `rclone` via `ProcessRunner`. Kept separate from `RcloneService`'s pure builders so the
/// builders stay trivially testable. Each op is **skip-if-unavailable** (offline / missing creds is
/// a clean `.skipped`, never a crash), matching the restic contract.
extension RcloneService {

    /// Flags appended to long-running transfer/compare ops so progress is logged line-by-line
    /// (parsed for a progress bar in a later phase) rather than buffered until exit.
    static let runtimeProgressFlags = ["--use-json-log", "--stats", "1s",
                                       "--stats-log-level", "NOTICE", "--log-level", "INFO"]

    /// Resolve the tool + a ready runtime env, or a `.skipped`/`.failed` outcome explaining why not.
    /// All ops funnel through this so the preconditions are checked in exactly one place.
    private static func prepared(_ config: AdhocBackupConfig) -> Result<(rclone: String, env: [String: String]), Outcome> {
        guard let rclone = Tooling.rclone else {
            return .failure(.failed("rclone not found — install with `brew install rclone`"))
        }
        guard config.isConfigured else {
            return .failure(.skipped(reason: "ad-hoc B2 not configured (no bucket / Keychain service)"))
        }
        let secrets = resolveSecrets(for: config)
        guard secrets.b2AccountId != nil, secrets.b2AccountKey != nil else {
            return .failure(.skipped(reason: "B2 credentials not in Keychain (service \(config.keychainService))"))
        }
        guard secrets.cryptPasswordObscured != nil else {
            return .failure(.skipped(reason: "crypt passphrase not in Keychain (service \(config.keychainService))"))
        }
        return .success((rclone, runtimeEnvironment(for: config, secrets: secrets)))
    }

    /// Verify we can reach the bucket with the stored B2 credentials (a shallow listing). Note this
    /// proves *connectivity*, not crypt-password correctness — a wrong passphrase still "lists"
    /// (yielding garbage names), so Phase 1 adds a canary round-trip on top.
    public static func testConnection(config: AdhocBackupConfig, onLine: (String) -> Void = { _ in }) -> Outcome {
        let rclone: String, env: [String: String]
        switch prepared(config) {
        case .failure(let o): return o
        case .success(let p): (rclone, env) = p
        }
        let args = ["lsjson", cryptPath(), "--max-depth", "1"]
        guard let r = try? ProcessRunner.run(executable: rclone, arguments: args, environment: env, onLine: onLine) else {
            return .failed("could not launch rclone")
        }
        return r.exitCode == 0 ? .ok(detail: "connected to \(baseRemotePath(config: config))")
                               : .failed("rclone could not reach the bucket (exit \(r.exitCode))")
    }

    /// List the whole store, parsed into `AdhocRemoteFile`s for the cache. Uses `capture` because the
    /// JSON output *is* the payload. Returns the files plus an outcome (`.ok`/`.skipped`/`.failed`).
    public static func list(config: AdhocBackupConfig, hash: Bool = false) -> (files: [AdhocRemoteFile], outcome: Outcome) {
        let rclone: String, env: [String: String]
        switch prepared(config) {
        case .failure(let o): return ([], o)
        case .success(let p): (rclone, env) = p
        }
        let args = lsjsonArguments(recursive: true, filesOnly: true, hash: hash)
        guard let r = try? ProcessRunner.capture(executable: rclone, arguments: args, environment: env) else {
            return ([], .failed("could not launch rclone"))
        }
        guard r.exitCode == 0 else {
            let why = r.stderr.split(separator: "\n").last.map(String.init) ?? "rclone lsjson exit \(r.exitCode)"
            return ([], .failed(why.trimmingCharacters(in: .whitespaces)))
        }
        let files = RcloneParse.lsjson(r.stdout)
        return (files, .ok(detail: "\(files.count) item(s)"))
    }

    /// Back up the store's `sources` one-way and additively (`copy`/`copyto`, never `sync --delete`),
    /// each source preserved under its basename. Local deletions never touch B2.
    public static func backup(config: AdhocBackupConfig, onLine: (String) -> Void) -> Outcome {
        let rclone: String, env: [String: String]
        switch prepared(config) {
        case .failure(let o): return o
        case .success(let p): (rclone, env) = p
        }
        guard !config.sources.isEmpty else { return .skipped(reason: "no sources selected") }

        var copied = 0
        for src in config.sources {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir) else {
                return .failed("source not found: \(src)")
            }
            let dest = (src as NSString).lastPathComponent
            let core = isDir.boolValue ? copyArguments(source: src, destRemotePath: dest)
                                       : copytoArguments(source: src, destRemotePath: dest)
            onLine("→ backing up \(src) → \(cryptPath(dest))")
            guard let r = try? ProcessRunner.run(executable: rclone, arguments: core + runtimeProgressFlags,
                                                 environment: env, onLine: onLine) else {
                return .failed("could not launch rclone copy for \(src)")
            }
            guard r.exitCode == 0 else { return .failed("rclone copy exit \(r.exitCode) for \(src)") }
            copied += 1
        }
        return .ok(detail: "backed up \(copied) source(s)")
    }

    /// Rename/move one object within the store (server-side copy + delete; no re-upload).
    public static func rename(config: AdhocBackupConfig, from: String, to: String,
                              onLine: (String) -> Void = { _ in }) -> Outcome {
        let rclone: String, env: [String: String]
        switch prepared(config) {
        case .failure(let o): return o
        case .success(let p): (rclone, env) = p
        }
        let from = from.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        let to = to.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !from.isEmpty, !to.isEmpty else { return .failed("rename needs both a source and a target path") }
        guard from != to else { return .ok(detail: "no change") }
        guard let r = try? ProcessRunner.run(executable: rclone,
                                             arguments: moveArguments(fromRemotePath: from, toRemotePath: to),
                                             environment: env, onLine: onLine) else {
            return .failed("could not launch rclone moveto")
        }
        return r.exitCode == 0 ? .ok(detail: "renamed \(from) → \(to)")
                               : .failed("rclone moveto exit \(r.exitCode)")
    }

    /// **Permanently** delete one object (hard delete). Destructive and unrecoverable — callers must
    /// gate this behind explicit confirmation (the UI uses a typed-filename confirm).
    public static func delete(config: AdhocBackupConfig, path: String,
                              onLine: (String) -> Void = { _ in }) -> Outcome {
        let rclone: String, env: [String: String]
        switch prepared(config) {
        case .failure(let o): return o
        case .success(let p): (rclone, env) = p
        }
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !path.isEmpty else { return .failed("delete needs a path") }
        guard let r = try? ProcessRunner.run(executable: rclone,
                                             arguments: deleteArguments(remotePath: path),
                                             environment: env, onLine: onLine) else {
            return .failed("could not launch rclone deletefile")
        }
        return r.exitCode == 0 ? .ok(detail: "permanently deleted \(path)")
                               : .failed("rclone deletefile exit \(r.exitCode)")
    }

    /// Compute the one-way additive differences between the local `sources` and the store: what a
    /// backup would upload (new) or re-upload (changed). Each source is compared under its basename,
    /// mirroring how `backup` lays them out.
    public static func diff(config: AdhocBackupConfig, onLine: (String) -> Void = { _ in }) -> (entries: [DiffEntry], outcome: Outcome) {
        let rclone: String, env: [String: String]
        switch prepared(config) {
        case .failure(let o): return ([], o)
        case .success(let p): (rclone, env) = p
        }
        guard !config.sources.isEmpty else { return ([], .skipped(reason: "no sources selected")) }

        var all: [DiffEntry] = []
        for src in config.sources {
            let base = (src as NSString).lastPathComponent
            // `rclone check` exits non-zero when differences exist, so a non-zero exit here is NOT a
            // failure — the combined output on stdout is the real signal. Capture and parse it.
            guard let r = try? ProcessRunner.capture(executable: rclone,
                                                     arguments: checkArguments(localSource: src, remotePath: base),
                                                     environment: env) else {
                return (all, .failed("could not launch rclone check for \(src)"))
            }
            let text = String(data: r.stdout, encoding: .utf8) ?? ""
            let entries = RcloneParse.checkCombined(text).map { e in
                // Re-root each path under its source basename so entries are unambiguous across sources.
                DiffEntry(change: e.change, path: base.isEmpty ? e.path : "\(base)/\(e.path)")
            }
            all.append(contentsOf: entries)
            onLine("checked \(src): \(entries.filter { $0.needsUpload }.count) change(s)")
        }
        let uploads = all.filter { $0.needsUpload }.count
        return (all, .ok(detail: "\(uploads) change(s) to upload across \(config.sources.count) source(s)"))
    }
}
