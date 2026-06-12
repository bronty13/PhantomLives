import Foundation

/// Runs one **sender pass**: export this Mac's Photos to the staging SSD (reusing the core
/// `ExportEngine` with an export-only profile), then rsync the staged archive over SSH to the
/// remote receiver. Export-only + ship; it never mirrors locally, never touches a vault, and has
/// no purge path. Idempotent and incremental — a first run is the full backup, every run after
/// (e.g. hourly via launchd) catches only new photos/videos.
public enum SenderAgent {

    public struct Summary: Sendable {
        public let exported: ExportEngine.RunSummary
        public let shipAttempted: Bool
        public let shipSucceeded: Bool
        public let shipDetail: String
        public var ok: Bool { exported.allSucceeded && (!shipAttempted || shipSucceeded) }
    }

    public enum AgentError: Error, CustomStringConvertible {
        case invalidConfig([String])
        case rsyncNotFound
        public var description: String {
            switch self {
            case .invalidConfig(let i): return "Sender config has problems:\n  - " + i.joined(separator: "\n  - ")
            case .rsyncNotFound: return "rsync not found (expected at /usr/bin/rsync)."
            }
        }
    }

    /// Export to staging, then (if `remote.enabled`) ship to the receiver. `dryRun` plans the
    /// osxphotos pass and skips the ship.
    public static func run(config: SenderConfig, logger: AtticLogger, dryRun: Bool = false) throws -> Summary {
        let issues = config.validationIssues()
        if !issues.isEmpty { throw AgentError.invalidConfig(issues) }

        logger.info("=== PurpleAttic SENDER: \(config.name)\(dryRun ? " (DRY RUN)" : "") ===")
        logger.info("Staging (SSD): \(config.stagingArchiveRoot)")
        if config.remote.enabled {
            logger.info("Ship → \(config.remote.user)@\(config.remote.host):\(config.remote.remotePath) (port \(config.remote.port))")
        } else {
            logger.info("Ship: disabled (export to SSD only)")
        }

        // 1. Export to the SSD via the core engine (export-only: no mirror, no cloud, no purge).
        let exported = try ExportEngine(logger: logger).run(profile: config.exportProfile(), dryRun: dryRun)

        // 2. Ship the staged archive to the receiver over SSH.
        var shipAttempted = false, shipSucceeded = false, shipDetail = "not attempted"
        if !dryRun && config.remote.enabled {
            guard exported.allSucceeded else {
                shipDetail = "skipped — export had failures (won't ship a partial archive)"
                logger.warn("Ship skipped: \(shipDetail)")
                return Summary(exported: exported, shipAttempted: false, shipSucceeded: false, shipDetail: shipDetail)
            }
            guard let rsync = Tooling.rsync else { throw AgentError.rsyncNotFound }
            shipAttempted = true
            let args = rsyncArguments(config: config, rsyncVersionBanner: ExportEngine.rsyncVersionBanner(rsync))
            logger.info("→ Ship: \(rsync) \(args.map(ExportPlan.shellQuote).joined(separator: " "))")
            let t0 = Date()
            let result = try ProcessRunner.run(executable: rsync, arguments: args) { line in
                logger.debug("[rsync:ship] \(line)")
            }
            shipSucceeded = result.exitCode == 0
            shipDetail = "exit \(result.exitCode) in \(ExportEngine.fmt(Date().timeIntervalSince(t0)))"
            (shipSucceeded ? logger.info : logger.error)("← Ship \(shipDetail)")
        }

        let s = Summary(exported: exported, shipAttempted: shipAttempted,
                        shipSucceeded: shipSucceeded, shipDetail: shipDetail)
        logger.info("=== Sender finished — \(s.ok ? "ALL OK" : "WITH FAILURES") ===")
        return s
    }

    /// Build the rsync argv that ships the staging archive root to the receiver over SSH.
    /// Pure + testable (the part most worth locking down: a wrong `-e ssh` string or a dropped
    /// trailing slash silently changes what gets copied where).
    ///
    /// - `-a` archive, `--partial` resume interrupted transfers, `-h`/`-v` for the log.
    /// - Excludes `.DS_Store` + the osxphotos export DB (same as the core mirror).
    /// - `-e "ssh …"` with `BatchMode=yes` (never prompt — this runs unattended under launchd)
    ///   and `StrictHostKeyChecking=accept-new` (trust on first connect, then pin).
    /// - Source ends in `/` so the *contents* of the archive root land under the remote path
    ///   (not a nested extra folder). The remote path is single-quoted for the remote shell so
    ///   spaces survive.
    public static func rsyncArguments(config: SenderConfig, rsyncVersionBanner: String) -> [String] {
        var sshParts = ["ssh", "-p", String(config.remote.port),
                        "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]
        if let key = config.remote.identityFile?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            sshParts += ["-i", key]
        }

        var args = ExportEngine.rsyncCopyArgs(versionBanner: rsyncVersionBanner)  // -ahv / -ah --info=progress2
        args += ["--partial"]
        args += ["-e", sshParts.joined(separator: " ")]

        let srcRoot = config.stagingArchiveRoot
        let src = srcRoot.hasSuffix("/") ? srcRoot : srcRoot + "/"
        let remoteDir = config.remote.remotePath.hasSuffix("/") ? config.remote.remotePath : config.remote.remotePath + "/"
        let target = "\(config.remote.user)@\(config.remote.host):'\(remoteDir)'"
        args += [src, target]
        return args
    }

    /// Copy-pasteable shell rendering of the ship command, for `agent plan` and logs.
    public static func shipShellCommand(config: SenderConfig, rsync: String, rsyncVersionBanner: String = "") -> String {
        ([rsync] + rsyncArguments(config: config, rsyncVersionBanner: rsyncVersionBanner))
            .map(ExportPlan.shellQuote).joined(separator: " ")
    }
}
