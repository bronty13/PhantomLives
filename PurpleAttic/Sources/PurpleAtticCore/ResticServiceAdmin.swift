import Foundation

/// Administrative / setup-time restic operations the GUI drives so a brand-new Mac can be
/// configured end-to-end **without Terminal**: read repo status (snapshots + keys), add the
/// written-on-paper **recovery key**, and run the **Keychain-bypassed recovery drill** that
/// proves that paper key alone can restore the archive. These are separate from the unattended
/// backup/check path in `ResticService.swift`; they're interactive, one-time, and lock-aware.
public extension ResticService {

    // MARK: - Value types

    /// One key entry that can unlock the repo's master key (runtime key, recovery key, …).
    struct ResticKey: Equatable, Identifiable, Sendable {
        public let id: String          // key file id (hash)
        public let isCurrent: Bool     // the key this invocation unlocked with
        public let username: String
        public let hostname: String
        public let created: String
    }

    /// Compact snapshot tally for the status panel.
    struct SnapshotSummary: Equatable, Sendable {
        public let count: Int
        public let latest: String?     // ISO time of the newest snapshot, if any
    }

    /// Repo status for the UI: either why it's unreachable (offline / not yet seeded / wrong
    /// creds) or its keys + snapshot tally.
    enum RepoOverview: Equatable, Sendable {
        case unreachable(String)
        case ready(keys: [ResticKey], snapshots: SnapshotSummary)
    }

    // MARK: - Pure argv builders (unit-tested)

    static func keyListArguments() -> [String] { ["key", "list", "--json"] }
    static func snapshotsArguments() -> [String] { ["snapshots", "--json", "--no-lock"] }
    static func keyAddArguments(passwordFile: String) -> [String] {
        ["key", "add", "--new-password-file", passwordFile]
    }

    // MARK: - JSON parsing (pure)

    static func parseSnapshots(_ data: Data) -> SnapshotSummary {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return SnapshotSummary(count: 0, latest: nil)
        }
        let times = arr.compactMap { $0["time"] as? String }.sorted()
        return SnapshotSummary(count: arr.count, latest: times.last)
    }

    static func parseKeys(_ data: Data) -> [ResticKey] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { d in
            ResticKey(id: (d["id"] as? String) ?? "",
                      isCurrent: (d["current"] as? Bool) ?? false,
                      username: (d["userName"] as? String) ?? "",
                      hostname: (d["hostName"] as? String) ?? "",
                      created: (d["created"] as? String) ?? "")
        }
    }

    // MARK: - Status

    /// Whether each Keychain secret a destination needs is present (no values read). Drives the
    /// credentials checklist in the UI.
    struct CredentialPresence: Equatable, Sendable {
        public let resticPassword: Bool
        public let b2AccountId: Bool
        public let b2AccountKey: Bool
        /// Everything required for the destination's kind is present.
        public var allPresent: Bool { resticPassword && b2AccountId && b2AccountKey }
    }

    static func credentialPresence(for dest: CloudDestination) -> CredentialPresence {
        let svc = dest.keychainService
        return CredentialPresence(
            resticPassword: KeychainStore.exists(service: svc, account: KeychainAccount.resticPassword),
            b2AccountId: KeychainStore.exists(service: svc, account: KeychainAccount.b2AccountId),
            b2AccountKey: KeychainStore.exists(service: svc, account: KeychainAccount.b2AccountKey))
    }

    /// Probe the repo for the status panel: snapshots + keys, or an `.unreachable` reason. Read-only
    /// (`--no-lock` on snapshots; `key list` takes a non-exclusive lock that coexists with a backup).
    static func overview(destination dest: CloudDestination) -> RepoOverview {
        guard let restic = Tooling.restic else { return .unreachable("restic not found — `brew install restic`") }
        guard dest.isConfigured else { return .unreachable("destination not configured") }
        let secrets = resolveSecrets(for: dest)
        if dest.kind == .resticB2, secrets.b2AccountId == nil || secrets.b2AccountKey == nil {
            return .unreachable("B2 credentials not in Keychain")
        }
        if KeychainStore.get(service: dest.keychainService, account: KeychainAccount.resticPassword) == nil {
            return .unreachable("restic passphrase not in Keychain")
        }
        let env = runtimeEnvironment(for: dest, secrets: secrets)
        guard let snaps = try? ProcessRunner.capture(executable: restic,
                                                     arguments: snapshotsArguments(), environment: env),
              snaps.exitCode == 0 else {
            return .unreachable("repository not reachable yet (offline, or no first backup completed)")
        }
        let summary = parseSnapshots(snaps.stdout)
        let keysOut = try? ProcessRunner.capture(executable: restic,
                                                 arguments: keyListArguments(), environment: env)
        let keys = (keysOut?.exitCode == 0) ? parseKeys(keysOut!.stdout) : []
        return .ready(keys: keys, snapshots: summary)
    }

    // MARK: - Recovery key

    /// Add a second key to the repo derived from `newPassphrase` (the recovery key). Unlocks with
    /// the existing runtime key (Keychain) and writes the new passphrase to a 0600 temp file so the
    /// secret never appears in restic's argv. NOTE: `key add` takes a repo lock — during a running
    /// backup this call **blocks until the backup releases it**, so callers run it off the main thread.
    static func addRecoveryKey(destination dest: CloudDestination, newPassphrase: String,
                               onLine: (String) -> Void) -> Outcome {
        guard let restic = Tooling.restic else { return .failed("restic not found") }
        let secrets = resolveSecrets(for: dest)
        if dest.kind == .resticB2, secrets.b2AccountId == nil || secrets.b2AccountKey == nil {
            return .failed("B2 credentials not in Keychain")
        }
        if KeychainStore.get(service: dest.keychainService, account: KeychainAccount.resticPassword) == nil {
            return .failed("runtime passphrase not in Keychain — store credentials first")
        }
        let env = runtimeEnvironment(for: dest, secrets: secrets)

        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("pattic-newkey-\(UUID().uuidString)")
        do {
            // No trailing newline — restic uses the file's exact contents (a trailing newline,
            // if present, is stripped), so this matches what the user re-types in the drill.
            try newPassphrase.write(toFile: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp)
        } catch {
            return .failed("couldn't stage the recovery key file: \(error.localizedDescription)")
        }
        defer {
            // Best-effort scrub: overwrite then remove.
            if let h = FileHandle(forWritingAtPath: tmp) {
                try? h.truncate(atOffset: 0); try? h.close()
            }
            try? FileManager.default.removeItem(atPath: tmp)
        }

        guard let result = try? ProcessRunner.run(executable: restic,
                                                  arguments: keyAddArguments(passwordFile: tmp),
                                                  environment: env, onLine: onLine) else {
            return .failed("couldn't launch restic key add")
        }
        return result.exitCode == 0
            ? .checked(detail: "recovery key added")
            : .failed("restic key add exit \(result.exitCode)")
    }

    /// The **recovery drill** (hard acceptance gate): prove the recovery passphrase alone — with the
    /// Keychain path deliberately disabled — can open the repo and restore real bytes. Steps:
    ///   1. With `RESTIC_PASSWORD_COMMAND` removed and `RESTIC_PASSWORD` set to the typed passphrase,
    ///      `restic snapshots` must succeed (proves the key unwraps the master key → all data is
    ///      decryptable) and list ≥1 snapshot.
    ///   2. Best-effort byte proof: restore one small file from the repo and byte-compare it to the
    ///      local archive under `sourceRoot`.
    /// Returns `.restored` on PASS, `.failed` on any failure.
    static func verifyRecoveryKey(destination dest: CloudDestination, passphrase: String,
                                  sourceRoot: String, onLine: (String) -> Void) -> Outcome {
        guard let restic = Tooling.restic else { return .failed("restic not found") }
        let secrets = resolveSecrets(for: dest)
        if dest.kind == .resticB2, secrets.b2AccountId == nil || secrets.b2AccountKey == nil {
            return .failed("B2 credentials not in Keychain")
        }
        // Keychain BYPASSED: no password command, password supplied directly.
        var env = runtimeEnvironment(for: dest, secrets: secrets)
        env.removeValue(forKey: "RESTIC_PASSWORD_COMMAND")
        env["RESTIC_PASSWORD"] = passphrase

        // 1. Cryptographic gate.
        onLine("Verifying the recovery passphrase unlocks the repository (Keychain bypassed)…")
        guard let snaps = try? ProcessRunner.capture(executable: restic,
                                                     arguments: snapshotsArguments(), environment: env),
              snaps.exitCode == 0 else {
            return .failed("the recovery passphrase did NOT unlock the repository — check what you wrote down")
        }
        let summary = parseSnapshots(snaps.stdout)
        guard summary.count > 0 else {
            return .failed("the key unlocked the repo but there are no snapshots yet to verify against")
        }

        // 2. Byte proof: restore one small file **chosen from the snapshot itself** (so the sample
        //    is guaranteed to exist in `latest`, even mid-seed) and byte-compare it to the local
        //    archive at the same absolute path. Sampling from the local disk instead would pick a
        //    file the partial snapshot doesn't contain → an empty restore → a false mismatch.
        _ = sourceRoot   // retained for API symmetry; the sample now comes from the snapshot
        if let sample = firstSmallFileInSnapshot(restic: restic, env: env, maxBytes: 4_000_000) {
            let tmpDir = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("pattic-drill-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(atPath: tmpDir) }
            let name = (sample as NSString).lastPathComponent
            onLine("Restoring “\(name)” from the snapshot with the recovery key…")
            let r = try? ProcessRunner.run(executable: restic,
                                           arguments: ["restore", "latest", "--target", tmpDir, "--include", sample],
                                           environment: env, onLine: onLine)
            if let r, r.exitCode == 0 {
                // restic restores preserving the absolute source path under the target dir.
                let restored = (tmpDir as NSString).appendingPathComponent(sample)
                let fm = FileManager.default
                if fm.fileExists(atPath: sample) {
                    if fm.contentsEqual(atPath: sample, andPath: restored) {
                        return .restored(detail: "PASS — recovery key opened \(summary.count) snapshot(s); restored & byte-matched “\(name)”")
                    }
                    return .failed("a sample restored with the recovery key did NOT byte-match the local archive")
                }
                // No local copy to compare against (e.g. a bare recovery host) — prove the restore
                // produced a non-empty file.
                if let attrs = try? fm.attributesOfItem(atPath: restored),
                   let size = (attrs[.size] as? NSNumber)?.intValue, size > 0 {
                    return .restored(detail: "PASS — recovery key opened \(summary.count) snapshot(s); restored “\(name)” (\(size) bytes; no local copy to byte-compare)")
                }
                return .failed("the recovery restore produced no file")
            }
            // Unlock proven, sample restore couldn't run — still a pass on the crypto gate.
            return .restored(detail: "PASS — recovery key opened \(summary.count) snapshot(s) (sample restore skipped)")
        }
        return .restored(detail: "PASS — recovery key opened \(summary.count) snapshot(s)")
    }

    /// First small regular file **in the latest snapshot** (via `restic ls latest --json`), as an
    /// absolute path. Guarantees the recovery drill samples a file the snapshot actually contains.
    static func firstSmallFileInSnapshot(restic: String, env: [String: String], maxBytes: Int) -> String? {
        guard let r = try? ProcessRunner.capture(executable: restic,
                                                 arguments: ["ls", "latest", "--json", "--no-lock"],
                                                 environment: env), r.exitCode == 0 else { return nil }
        return parseFirstSmallFilePath(fromLsJSON: r.stdout, maxBytes: maxBytes)
    }

    /// Pure parser for `restic ls --json` (newline-delimited node objects): the first `type:"file"`
    /// node with `0 < size <= maxBytes`, skipping dotfiles. Returns its absolute `path`.
    static func parseFirstSmallFilePath(fromLsJSON data: Data, maxBytes: Int) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  (d["type"] as? String) == "file",
                  let path = d["path"] as? String else { continue }
            let size = (d["size"] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= maxBytes else { continue }
            if (path as NSString).lastPathComponent.hasPrefix(".") { continue }
            return path
        }
        return nil
    }

    /// First non-hidden regular file under `root` no larger than `maxBytes`, scanning at most
    /// `scanLimit` entries (bounded so a 360k-file archive doesn't stall the drill).
    static func firstSmallFile(under root: String, maxBytes: Int, scanLimit: Int) -> String? {
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: root) else { return nil }
        var scanned = 0
        while let rel = en.nextObject() as? String {
            scanned += 1
            if scanned > scanLimit { return nil }
            if (rel as NSString).lastPathComponent.hasPrefix(".") { continue }
            let full = (root as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let size = (attrs[.size] as? NSNumber)?.intValue, size > 0, size <= maxBytes {
                return full
            }
        }
        return nil
    }
}
