import Foundation

/// Orchestrates one archival run (the safe, non-destructive half of PurpleAttic):
///   1. osxphotos export — once per enabled format pass (HEIC originals, JPEG set)
///   2. rsync mirror — replicate the primary to each configured mirror (no --delete)
///   3. verify — confirm each mirror matches the primary (inventory; deep optional)
///   4. cloud — rsync the primary into the mounted Cryptomator vault, if available
///
/// Every step logs in detail and contributes to a `RunSummary`, which the caller renders
/// into a human-readable report under ~/Downloads/PurpleAttic/. The engine never deletes
/// from the Photos library — purge is a separate, guarded stage shipped later.
public final class ExportEngine {

    public struct StepResult: Sendable {
        public let name: String
        public let success: Bool
        public let detail: String
        public let duration: TimeInterval
    }

    public struct RunSummary: Sendable {
        public let profileName: String
        public let startedAt: Date
        public let finishedAt: Date
        public let steps: [StepResult]
        public let logFile: String?
        public var allSucceeded: Bool { steps.allSatisfy { $0.success } }
        public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    }

    public enum EngineError: Error, CustomStringConvertible {
        case osxphotosNotFound
        case rsyncNotFound
        case invalidProfile([String])
        case destinationUnavailable(String)

        public var description: String {
            switch self {
            case .osxphotosNotFound:
                return "osxphotos not found. Install it with `pipx install osxphotos` (or `brew install osxphotos`)."
            case .rsyncNotFound:
                return "rsync not found (expected at /usr/bin/rsync)."
            case .invalidProfile(let issues):
                return "Profile has problems:\n  - " + issues.joined(separator: "\n  - ")
            case .destinationUnavailable(let path):
                return "Couldn't create the archive folder at \(path). Is the drive mounted and the path set correctly in Settings?"
            }
        }
    }

    private let logger: AtticLogger
    public init(logger: AtticLogger) {
        self.logger = logger
    }

    /// Run the archival pipeline. `dryRun` passes `--dry-run` to osxphotos and skips mirror,
    /// verify, and cloud (so a dry run touches nothing on disk).
    public func run(profile: ArchiveProfile, dryRun: Bool, deepVerify: Bool = false) throws -> RunSummary {
        let started = Date()
        let issues = profile.validationIssues()
        // A missing mirror only blocks purge, not archival; filter that one out for a run.
        let blocking = issues.filter { !$0.contains("Purge is enabled") }
        if !blocking.isEmpty { throw EngineError.invalidProfile(blocking) }

        guard let osxphotos = Tooling.osxphotos else { throw EngineError.osxphotosNotFound }
        logger.info("osxphotos: \(osxphotos)")
        if let exif = Tooling.exiftool {
            logger.info("exiftool: \(exif)")
        } else {
            logger.warn("exiftool not found — metadata embedding (--exiftool) will fail. Install with `brew install exiftool`.")
        }

        logger.info("=== PurpleAttic run: \(profile.name)\(dryRun ? " (DRY RUN)" : "") ===")
        logger.info("Primary archive: \(profile.primaryArchiveRoot)")
        logger.info("Formats: \(profile.enabledPasses.map { $0.label }.joined(separator: ", "))")

        // Completeness guard: warn loudly if the library looks optimized (originals only in
        // iCloud) and we're not downloading them — the archive would be incomplete.
        let inspection = LibraryInspector.inspect(libraryPath: profile.photosLibraryPath)
        logger.info("Library: \(inspection.summary)")
        if inspection.optimizeStorageLikely && !profile.downloadMissingFromICloud {
            logger.warn("INCOMPLETE-ARCHIVE RISK: most originals are not on disk. Run on the Mac set to \"Download Originals,\" or enable downloadMissingFromICloud. Continuing with the local subset only.")
        }

        var steps: [StepResult] = []

        // 1. Export passes.
        for pass in profile.enabledPasses {
            let dest = ExportPlan.destination(profile: profile, pass: pass)
            do {
                try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
            } catch {
                logger.error("Cannot create export folder \(dest): \(error.localizedDescription)")
                throw EngineError.destinationUnavailable(dest)
            }
            let args = ExportPlan.arguments(profile: profile, pass: pass, dryRun: dryRun)
            logger.info("→ Export (\(pass.label)): \(ExportPlan.shellCommand(osxphotos: osxphotos, profile: profile, pass: pass, dryRun: dryRun))")
            let t0 = Date()
            let result = try ProcessRunner.run(executable: osxphotos, arguments: args) { line in
                self.logger.debug("[osxphotos:\(pass.rawValue)] \(line)")
            }
            let ok = result.exitCode == 0
            let dur = Date().timeIntervalSince(t0)
            (ok ? logger.info : logger.error)("← Export (\(pass.label)) exit \(result.exitCode) in \(Self.fmt(dur))")
            steps.append(.init(name: "Export \(pass.label)", success: ok,
                               detail: "exit \(result.exitCode)", duration: dur))
            if !ok {
                logger.error("Export failed — skipping mirror/verify/cloud to avoid propagating a partial archive.")
                return Self.finish(profile: profile, started: started, steps: steps, logger: logger)
            }
        }

        if dryRun {
            logger.info("Dry run — skipping mirror, verify, and cloud sync.")
            return Self.finish(profile: profile, started: started, steps: steps, logger: logger)
        }

        // 2 + 3. Mirror then verify, per mirror. The archive lives in `archiveSubfolder`
        // under each base, so we mirror primary-archive-root → mirror-archive-root.
        guard let rsync = Tooling.rsync else { throw EngineError.rsyncNotFound }
        let primaryRoot = profile.primaryArchiveRoot
        // Pick rsync flags that the available binary actually supports: macOS's default rsync
        // is openrsync, which rejects --info=progress2 (an rsync-3.x flag) and aborts instantly.
        let copyArgs = Self.rsyncCopyArgs(versionBanner: Self.rsyncVersionBanner(rsync))
        logger.info("rsync: \(rsync) [\(copyArgs.joined(separator: " "))]")
        for mirror in profile.mirrorArchiveRoots {
            try? FileManager.default.createDirectory(atPath: mirror, withIntermediateDirectories: true)
            let src = primaryRoot.hasSuffix("/") ? primaryRoot : primaryRoot + "/"
            logger.info("→ Mirror: \(src) ⇒ \(mirror)")
            let t0 = Date()
            // No --delete: the mirror is never allowed to lose files just because the
            // primary did.
            let result = try ProcessRunner.run(executable: rsync,
                                               arguments: copyArgs + [src, mirror]) { line in
                self.logger.debug("[rsync] \(line)")
            }
            let ok = result.exitCode == 0
            let dur = Date().timeIntervalSince(t0)
            (ok ? logger.info : logger.error)("← Mirror exit \(result.exitCode) in \(Self.fmt(dur))")
            steps.append(.init(name: "Mirror → \(mirror)", success: ok,
                               detail: "exit \(result.exitCode)", duration: dur))

            // Verify this mirror against the primary.
            logger.info("→ Verify: \(mirror) against primary\(deepVerify ? " (deep SHA-256)" : "")")
            let vt0 = Date()
            let report = VerifyService.compare(primary: primaryRoot,
                                               mirror: mirror, deep: deepVerify) { n in
                self.logger.debug("[verify] checked \(n) files…")
            }
            let vdur = Date().timeIntervalSince(vt0)
            if report.matches {
                logger.info("← Verify OK: \(report.primaryFileCount) files match in \(Self.fmt(vdur))")
            } else {
                logger.error("← Verify FOUND \(report.discrepancies.count) discrepancy(ies):")
                for d in report.discrepancies.prefix(50) {
                    logger.error("    [\(d.kind.rawValue)] \(d.relativePath) — \(d.detail)")
                }
                if report.discrepancies.count > 50 {
                    logger.error("    …and \(report.discrepancies.count - 50) more (see full inventory).")
                }
            }
            steps.append(.init(name: "Verify \(mirror)", success: report.matches,
                               detail: "\(report.discrepancies.count) discrepancies", duration: vdur))
        }

        // 4. Cloud (Cryptomator vault). Never blocks the run.
        if let vault = profile.cloudVaultPath, !vault.isEmpty {
            var isDir: ObjCBool = false
            let mounted = FileManager.default.fileExists(atPath: vault, isDirectory: &isDir) && isDir.boolValue
                && FileManager.default.isWritableFile(atPath: vault)
            if mounted {
                // The vault is exempt from archiveSubfolder — copy the archive contents to
                // the vault root (it's already a dedicated encrypted container).
                let src = primaryRoot.hasSuffix("/") ? primaryRoot : primaryRoot + "/"
                logger.info("→ Cloud (Cryptomator): \(src) ⇒ \(vault)")
                let t0 = Date()
                let result = try ProcessRunner.run(executable: rsync,
                                                   arguments: copyArgs + [src, vault]) { line in
                    self.logger.debug("[rsync:cloud] \(line)")
                }
                let ok = result.exitCode == 0
                let dur = Date().timeIntervalSince(t0)
                (ok ? logger.info : logger.warn)("← Cloud exit \(result.exitCode) in \(Self.fmt(dur))")
                steps.append(.init(name: "Cloud → vault", success: ok,
                                   detail: "exit \(result.exitCode)", duration: dur))
            } else {
                logger.warn("Cryptomator vault not mounted/writable at \(vault) — skipping cloud copy (will catch up next run).")
                steps.append(.init(name: "Cloud → vault", success: true,
                                   detail: "skipped (vault not mounted)", duration: 0))
            }
        }

        return Self.finish(profile: profile, started: started, steps: steps, logger: logger)
    }

    // MARK: - Helpers

    private static func finish(profile: ArchiveProfile, started: Date,
                               steps: [StepResult], logger: AtticLogger) -> RunSummary {
        let summary = RunSummary(profileName: profile.name, startedAt: started,
                                 finishedAt: Date(), steps: steps,
                                 logFile: logger.logFileURL?.path)
        logger.info("=== Run finished in \(fmt(summary.duration)) — \(summary.allSucceeded ? "ALL OK" : "WITH FAILURES") ===")
        return summary
    }

    static func fmt(_ t: TimeInterval) -> String {
        if t < 60 { return String(format: "%.1fs", t) }
        let m = Int(t) / 60, s = Int(t) % 60
        return "\(m)m \(s)s"
    }

    /// The `rsync --version` banner (stdout+stderr), used to pick compatible copy flags.
    static func rsyncVersionBanner(_ rsync: String) -> String {
        guard let r = try? ProcessRunner.capture(executable: rsync, arguments: ["--version"]) else {
            return ""
        }
        return (String(data: r.stdout, encoding: .utf8) ?? "") + r.stderr
    }

    /// rsync flags for the mirror/cloud copy, chosen for the *available* rsync. macOS's
    /// default is **openrsync** ("openrsync: protocol version …", self-reports "2.6.9
    /// compatible"), which rejects `--info=progress2` / `--progress` / `-P` and aborts
    /// instantly with a usage error — the bug that silently broke mirror + cloud + verify.
    /// Only a real rsync 3.x (e.g. Homebrew at /opt/homebrew/bin) supports progress2; for it
    /// we keep the nice overall progress, otherwise we fall back to plain verbose (`-ahv`),
    /// which every rsync understands. `-a` archive, `-h` human, `-v` per-file lines for the log.
    static func rsyncCopyArgs(versionBanner: String) -> [String] {
        let v = versionBanner.lowercased()
        let isModern = !v.contains("openrsync")
            && v.range(of: #"version [3-9]\."#, options: .regularExpression) != nil
        let base = isModern ? ["-ah", "--info=progress2"] : ["-ahv"]
        // Exclude junk from the copies: Finder's `.DS_Store` and osxphotos' per-destination
        // export database. Both are dotfiles, so VerifyService / ArchiveIndex (which skip
        // hidden files) already ignore them — excluding them here can't create false verify
        // discrepancies. Critically, copying `.DS_Store` to a **Cryptomator/macFUSE** vault
        // makes openrsync's temp-then-rename fail ("renameat: No such file or directory") and
        // abort the ENTIRE cloud transfer — so this is also the cloud-copy fix.
        return base + ["--exclude=.DS_Store", "--exclude=.osxphotos_export.db*"]
    }
}

// MARK: - Run report

public extension ExportEngine.RunSummary {
    /// Human-readable report body written to ~/Downloads/PurpleAttic/.
    func reportText() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        var lines: [String] = []
        lines.append("PurpleAttic — Archive Run Report")
        lines.append(String(repeating: "=", count: 40))
        lines.append("Profile:   \(profileName)")
        lines.append("Started:   \(df.string(from: startedAt))")
        lines.append("Finished:  \(df.string(from: finishedAt))")
        lines.append("Duration:  \(ExportEngine.fmt(duration))")
        lines.append("Result:    \(allSucceeded ? "ALL OK" : "WITH FAILURES")")
        if let logFile { lines.append("Log:       \(logFile)") }
        lines.append("")
        lines.append("Steps:")
        for s in steps {
            let mark = s.success ? "OK " : "FAIL"
            lines.append("  [\(mark)] \(s.name) — \(s.detail) (\(ExportEngine.fmt(s.duration)))")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Write the report to ~/Downloads/PurpleAttic/ and return its URL.
    @discardableResult
    func writeReport() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Downloads/PurpleAttic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let url = dir.appendingPathComponent("report-\(stamp.string(from: startedAt)).txt")
        try? reportText().data(using: .utf8)?.write(to: url)
        return url
    }
}
