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
        /// Filenames whose in-file metadata embed was skipped (damaged EXIF). The image + its
        /// `.xmp` sidecar were still archived — informational, NOT failures.
        public let metadataEmbedSkips: [String]
        public var allSucceeded: Bool { steps.allSatisfy { $0.success } }
        public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

        public init(profileName: String, startedAt: Date, finishedAt: Date, steps: [StepResult],
                    logFile: String?, metadataEmbedSkips: [String] = []) {
            self.profileName = profileName
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.steps = steps
            self.logFile = logFile
            self.metadataEmbedSkips = metadataEmbedSkips
        }
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
    private let onProgress: ((RunProgress) -> Void)?
    /// Filenames (deduped by uuid) whose in-file metadata embed was skipped this run.
    private var embedSkipFiles: [String] = []

    public init(logger: AtticLogger, onProgress: ((RunProgress) -> Void)? = nil) {
        self.logger = logger
        self.onProgress = onProgress
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
        embedSkipFiles = []

        // Live progress: a phase stepper for the GUI (the run is hours long).
        var kinds: [RunProgress.PhaseKind] = profile.enabledPasses.map {
            $0 == .originals ? .exportHEIC : .exportJPEG
        }
        if !dryRun {
            if !profile.mirrorArchiveRoots.isEmpty { kinds += [.mirror, .verify] }
            if let v = profile.cloudVaultPath, !v.trimmingCharacters(in: .whitespaces).isEmpty { kinds.append(.cloud) }
        }
        let tracker = RunProgressTracker(kinds: kinds, onProgress: onProgress)

        // 1. Export passes.
        for pass in profile.enabledPasses {
            let phaseKind: RunProgress.PhaseKind = (pass == .originals) ? .exportHEIC : .exportJPEG
            tracker.startPhase(phaseKind, detail: "starting…")
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
            // osxphotos is quiet when piped (rich progress is TTY-only), so poll the
            // destination file count for live "where it's at" feedback during the long pass.
            let poll = dryRun ? nil : Self.startExportPoll(dest: dest, tracker: tracker)
            var passEmbedUUIDs = Set<String>()
            let result = try ProcessRunner.run(executable: osxphotos, arguments: args) { line in
                switch OsxphotosLine.classify(line) {
                case .metadataEmbedSkip(let uuid, let file):
                    // Benign: file + sidecar archived; in-file embed skipped. Count once, no spam.
                    if passEmbedUUIDs.insert(uuid).inserted {
                        tracker.addEmbedSkip()
                        self.embedSkipFiles.append(file)
                    }
                case .companionNoise, .progressBar:
                    break  // suppress the retry / exiftool-error / progress-redraw spam
                case .exportFailure(_, let file, let reason):
                    self.logger.error("[osxphotos:\(pass.rawValue)] export FAILED: \(file) — \(reason)")
                case .other:
                    self.logger.debug("[osxphotos:\(pass.rawValue)] \(line)")
                }
            }
            poll?.cancel()
            let ok = result.exitCode == 0
            let dur = Date().timeIntervalSince(t0)
            (ok ? logger.info : logger.error)("← Export (\(pass.label)) exit \(result.exitCode) in \(Self.fmt(dur))")
            steps.append(.init(name: "Export \(pass.label)", success: ok,
                               detail: "exit \(result.exitCode)", duration: dur))
            tracker.finishPhase(phaseKind, state: ok ? .done : .failed,
                                detail: ok ? "exit 0" : "exit \(result.exitCode)")
            if !ok {
                logger.error("Export failed — skipping mirror/verify/cloud to avoid propagating a partial archive.")
                return self.finishRun(profile: profile, started: started, steps: steps, tracker: tracker)
            }
        }

        if dryRun {
            logger.info("Dry run — skipping mirror, verify, and cloud sync.")
            return self.finishRun(profile: profile, started: started, steps: steps, tracker: tracker)
        }

        // 2 + 3. Mirror then verify, per mirror. The archive lives in `archiveSubfolder`
        // under each base, so we mirror primary-archive-root → mirror-archive-root.
        guard let rsync = Tooling.rsync else { throw EngineError.rsyncNotFound }
        let primaryRoot = profile.primaryArchiveRoot
        let src = primaryRoot.hasSuffix("/") ? primaryRoot : primaryRoot + "/"
        // Pick rsync flags that the available binary actually supports: macOS's default rsync
        // is openrsync, which rejects --info=progress2 (an rsync-3.x flag) and aborts instantly.
        let banner = Self.rsyncVersionBanner(rsync)
        let mirrorArgs = Self.rsyncCopyArgs(versionBanner: banner)

        let mirrors = Array(zip(profile.mirrorDestinations, profile.mirrorArchiveRoots))
        if !mirrors.isEmpty {
            logger.info("rsync: \(rsync) [\(mirrorArgs.joined(separator: " "))]")
            tracker.startPhase(.mirror, detail: "copying…")
            let mt0 = Date()
            var mirrorOK = 0, mirrorSkipped = 0, mirrorFailed = 0
            var verifiedRoots: [String] = []
            for (base, mirror) in mirrors {
                // Mount guard: never createDirectory + rsync into an unmounted /Volumes path
                // (that would silently write hundreds of GB to the BOOT disk).
                let readiness = VolumeReadiness.destinationReady(base)
                guard readiness.ready else {
                    mirrorSkipped += 1
                    logger.warn("Mirror skipped — \(readiness.reason ?? "destination not ready"): \(base)")
                    continue
                }
                try? FileManager.default.createDirectory(atPath: mirror, withIntermediateDirectories: true)
                logger.info("→ Mirror: \(src) ⇒ \(mirror)")
                let result = try ProcessRunner.run(executable: rsync,
                                                   arguments: mirrorArgs + [src, mirror]) { line in
                    self.logger.debug("[rsync] \(line)")
                    if Self.looksLikeRelativePath(line) { tracker.update(currentFile: line) }
                }
                if result.exitCode == 0 { mirrorOK += 1; verifiedRoots.append(mirror) }
                else { mirrorFailed += 1; logger.error("← Mirror FAILED (exit \(result.exitCode)): \(mirror)") }
                steps.append(.init(name: "Mirror → \(mirror)", success: result.exitCode == 0,
                                   detail: "exit \(result.exitCode)", duration: Date().timeIntervalSince(mt0)))
            }
            let mState: RunProgress.State = mirrorFailed > 0 ? .failed : (mirrorOK == 0 ? .skipped : .done)
            tracker.finishPhase(.mirror, state: mState,
                                detail: "\(mirrorOK) ok, \(mirrorSkipped) skipped, \(mirrorFailed) failed")
            logger.info("← Mirror: \(mirrorOK) copied, \(mirrorSkipped) skipped, \(mirrorFailed) failed in \(Self.fmt(Date().timeIntervalSince(mt0)))")

            // Verify each successfully-mirrored copy against the primary.
            tracker.startPhase(.verify, detail: "checking…")
            let vt0 = Date()
            var verifyDiscrepancies = 0, verifyMatched = 0
            for mirror in verifiedRoots {
                logger.info("→ Verify: \(mirror) against primary\(deepVerify ? " (deep SHA-256)" : "")")
                let report = VerifyService.compare(primary: primaryRoot, mirror: mirror, deep: deepVerify) { n in
                    tracker.update(detail: "\(n.formatted()) files checked")
                }
                if report.matches {
                    verifyMatched += 1
                    logger.info("← Verify OK: \(report.primaryFileCount) files match")
                } else {
                    verifyDiscrepancies += report.discrepancies.count
                    logger.error("← Verify FOUND \(report.discrepancies.count) discrepancy(ies) in \(mirror):")
                    for d in report.discrepancies.prefix(50) {
                        logger.error("    [\(d.kind.rawValue)] \(d.relativePath) — \(d.detail)")
                    }
                    if report.discrepancies.count > 50 {
                        logger.error("    …and \(report.discrepancies.count - 50) more (see full inventory).")
                    }
                }
                steps.append(.init(name: "Verify \(mirror)", success: report.matches,
                                   detail: "\(report.discrepancies.count) discrepancies", duration: Date().timeIntervalSince(vt0)))
            }
            tracker.finishPhase(.verify, state: verifyDiscrepancies > 0 ? .failed : .done,
                                detail: verifyDiscrepancies > 0 ? "\(verifyDiscrepancies) discrepancies" : "\(verifyMatched) mirror(s) OK")
        }

        // 4. Cloud (Cryptomator vault). Never blocks the run.
        if let vault = profile.cloudVaultPath, !vault.trimmingCharacters(in: .whitespaces).isEmpty {
            tracker.startPhase(.cloud, detail: "copying…")
            var isDir: ObjCBool = false
            let mounted = FileManager.default.fileExists(atPath: vault, isDirectory: &isDir) && isDir.boolValue
                && FileManager.default.isWritableFile(atPath: vault)
            if mounted {
                // The vault is exempt from archiveSubfolder — copy the archive contents to
                // the vault root (it's already a dedicated encrypted container). It's also a
                // Cryptomator/macFUSE volume, so use the vault-safe flag set (--inplace, no
                // owner/group/perms — that filesystem doesn't implement chown/chmod/temp-rename).
                let cloudArgs = Self.rsyncCopyArgs(versionBanner: banner, forVault: true)
                logger.info("→ Cloud (Cryptomator): \(src) ⇒ \(vault) [\(cloudArgs.joined(separator: " "))]")
                let t0 = Date()
                let result = try ProcessRunner.run(executable: rsync,
                                                   arguments: cloudArgs + [src, vault]) { line in
                    self.logger.debug("[rsync:cloud] \(line)")
                    if Self.looksLikeRelativePath(line) { tracker.update(currentFile: line) }
                }
                let ok = result.exitCode == 0
                let dur = Date().timeIntervalSince(t0)
                (ok ? logger.info : logger.warn)("← Cloud exit \(result.exitCode) in \(Self.fmt(dur))")
                steps.append(.init(name: "Cloud → vault", success: ok,
                                   detail: "exit \(result.exitCode)", duration: dur))
                tracker.finishPhase(.cloud, state: ok ? .done : .failed, detail: ok ? "exit 0" : "exit \(result.exitCode)")
            } else {
                logger.warn("Cryptomator vault not mounted/writable at \(vault) — skipping cloud copy (will catch up next run).")
                steps.append(.init(name: "Cloud → vault", success: true,
                                   detail: "skipped (vault not mounted)", duration: 0))
                tracker.finishPhase(.cloud, state: .skipped, detail: "vault not mounted")
            }
        }

        return self.finishRun(profile: profile, started: started, steps: steps, tracker: tracker)
    }

    // MARK: - Helpers

    private func finishRun(profile: ArchiveProfile, started: Date,
                           steps: [StepResult], tracker: RunProgressTracker) -> RunSummary {
        if !embedSkipFiles.isEmpty {
            logger.info("ℹ️ \(embedSkipFiles.count) photo(s) archived with sidecar-only metadata "
                        + "(in-file embed skipped — damaged EXIF; the file + .xmp are fine). Listed in the report.")
        }
        let summary = RunSummary(profileName: profile.name, startedAt: started,
                                 finishedAt: Date(), steps: steps,
                                 logFile: logger.logFileURL?.path,
                                 metadataEmbedSkips: embedSkipFiles)
        logger.info("=== Run finished in \(Self.fmt(summary.duration)) — \(summary.allSucceeded ? "ALL OK" : "WITH FAILURES") ===")
        tracker.finishRun()
        return summary
    }

    /// A repeating background timer that counts files under the export destination so the GUI
    /// can show live progress while osxphotos runs quietly (its rich progress is TTY-only).
    static func startExportPoll(dest: String, tracker: RunProgressTracker) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "attic.exportpoll", qos: .utility))
        timer.schedule(deadline: .now() + 6, repeating: 8)
        timer.setEventHandler {
            let n = countFiles(dest)
            tracker.update(detail: "\(n.formatted()) files written")
        }
        timer.resume()
        return timer
    }

    /// Rough count of entries under `dir` (files + dirs); a cheap, format-independent progress
    /// proxy that doesn't depend on osxphotos output.
    static func countFiles(_ dir: String) -> Int {
        guard let en = FileManager.default.enumerator(atPath: dir) else { return 0 }
        var c = 0
        for _ in en { c += 1 }
        return c
    }

    /// Heuristic: is this rsync output line a copied file/dir path (vs a summary/error line)?
    /// Used to surface the current file in the progress UI.
    static func looksLikeRelativePath(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if t.contains(":") || t.hasPrefix("sent ") || t.hasPrefix("total ") || t.contains("speedup") { return false }
        if t.hasPrefix("rsync") || t.contains("error") || t.contains("warning") { return false }
        return t.contains("/") || t.hasSuffix(".jpeg") || t.hasSuffix(".HEIC") || t.hasSuffix(".JPG")
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
    static func rsyncCopyArgs(versionBanner: String, forVault: Bool = false) -> [String] {
        let v = versionBanner.lowercased()
        let isModern = !v.contains("openrsync")
            && v.range(of: #"version [3-9]\."#, options: .regularExpression) != nil
        var args = isModern ? ["-ah", "--info=progress2"] : ["-ahv"]
        // Exclude junk from the copies: Finder's `.DS_Store` and osxphotos' per-destination
        // export database. Both are dotfiles, so VerifyService / ArchiveIndex (which skip
        // hidden files) already ignore them — excluding them here can't create false verify
        // discrepancies. Critically, copying `.DS_Store` to a **Cryptomator/macFUSE** vault
        // makes openrsync's temp-then-rename fail ("renameat: No such file or directory") and
        // abort the ENTIRE cloud transfer.
        args += ["--exclude=.DS_Store", "--exclude=.osxphotos_export.db*"]
        // The Cryptomator/macFUSE vault is hostile to openrsync's defaults in three ways,
        // each of which aborted a real cloud copy until handled:
        //  • `--inplace` — write directly to the final file. openrsync's default
        //    copy-to-temp-then-rename fails on the vault ("mkstempat"/"renameat: No such file
        //    or directory") for some names; --inplace skips the temp file entirely.
        //  • `--no-owner --no-group --no-perms` — the volume doesn't implement chown/chmod
        //    ("fchownat: Function not implemented"); content + timestamps still transfer and
        //    perms are moot inside an encrypted container.
        if forVault {
            args += ["--inplace", "--no-owner", "--no-group", "--no-perms"]
        }
        return args
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
        if !metadataEmbedSkips.isEmpty {
            lines.append("Sidecar-only metadata (\(metadataEmbedSkips.count) photo(s)):")
            lines.append("  These images + their .xmp sidecars were archived, but osxphotos couldn't")
            lines.append("  re-embed metadata into the file (damaged EXIF). Not failures.")
            for f in metadataEmbedSkips.sorted() { lines.append("    \(f)") }
            lines.append("")
        }
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
