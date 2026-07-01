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
        /// Count of new items copied into "NEW PHOTOS TO REVIEW" this run (incremental only).
        public let reviewStagedCount: Int
        /// The dated review-batch folder, if anything was staged.
        public let reviewPath: String?
        /// Typed, machine-readable metrics for the monitoring dashboard (counts/bytes per phase).
        public let metrics: RunMetrics
        public var allSucceeded: Bool { steps.allSatisfy { $0.success } }
        public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

        public init(profileName: String, startedAt: Date, finishedAt: Date, steps: [StepResult],
                    logFile: String?, metadataEmbedSkips: [String] = [],
                    reviewStagedCount: Int = 0, reviewPath: String? = nil,
                    metrics: RunMetrics = RunMetrics()) {
            self.profileName = profileName
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.steps = steps
            self.logFile = logFile
            self.metadataEmbedSkips = metadataEmbedSkips
            self.reviewStagedCount = reviewStagedCount
            self.reviewPath = reviewPath
            self.metrics = metrics
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
    /// Running tally of items copied to "NEW PHOTOS TO REVIEW" this run + the batch folder.
    private var reviewStagedCount = 0
    private var reviewBatchPath: String?

    public init(logger: AtticLogger, onProgress: ((RunProgress) -> Void)? = nil) {
        self.logger = logger
        self.onProgress = onProgress
    }

    /// Run the archival pipeline. `dryRun` passes `--dry-run` to osxphotos and skips mirror,
    /// verify, and cloud (so a dry run touches nothing on disk).
    public func run(profile: ArchiveProfile, dryRun: Bool, deepVerify: Bool = false) throws -> RunSummary {
        let started = Date()

        // Single-writer lock (real runs only — a dry run touches nothing, so it needn't contend).
        // If another run already holds it, this run is a clean no-op rather than colliding (the
        // failure that wedged the old vault) or queuing behind a multi-hour seed. Held by an fd, so
        // a crashed run can never leave a stale lock. Released by `defer` (and `deinit`) on exit.
        var lock: RunLock?
        if !dryRun {
            lock = RunLock.tryAcquire()
            if lock == nil {
                logger.info("=== PurpleAttic run: \(profile.name) ===")
                logger.warn("Another archive run is already in progress (lock held) — skipping this run.")
                let now = Date()
                return RunSummary(
                    profileName: profile.name, startedAt: started, finishedAt: now,
                    steps: [StepResult(name: "Archive", success: true,
                                       detail: "skipped — another run in progress",
                                       duration: now.timeIntervalSince(started))],
                    logFile: logger.logFileURL?.path)
            }
        }
        defer { lock?.release() }

        // Resilience guard (runs FIRST): if the PRIMARY destination isn't a mounted
        // volume, do nothing this run — don't throw, and never createDirectory under an
        // unmounted /Volumes path (which would silently write to the boot disk). This is
        // what lets a scheduled (e.g. hourly) run be a clean no-op when the drives are
        // detached. The mirror + cloud copies already skip-and-catch-up on their own, so
        // a later run with the drive(s) attached brings every copy current.
        let primaryReady = VolumeReadiness.destinationReady(profile.primaryDestination)
        if !dryRun && !primaryReady.ready {
            logger.info("=== PurpleAttic run: \(profile.name) ===")
            logger.warn("Primary drive not attached — \(primaryReady.reason ?? "not ready"). "
                        + "Nothing to archive this run; will retry at the next scheduled time.")
            let now = Date()
            return RunSummary(
                profileName: profile.name, startedAt: started, finishedAt: now,
                steps: [StepResult(name: "Archive", success: true,
                                   detail: "skipped — primary drive not attached",
                                   duration: now.timeIntervalSince(started))],
                logFile: logger.logFileURL?.path)
        }

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

        // Completeness note (informational, never blocks): fewer originals on disk than assets
        // just means some are still in iCloud — could be Optimize Mac Storage OR a Download-
        // Originals pass still in progress; we can't tell which, so we don't alarm. The archive
        // is append-only, so a later run captures whatever finishes downloading.
        let inspection = LibraryInspector.inspect(libraryPath: profile.photosLibraryPath)
        logger.info("Library: \(inspection.summary)")
        if inspection.originalsIncomplete && !profile.downloadMissingFromICloud {
            logger.info("Note: \(inspection.originalsOnDisk) originals on disk; others are iCloud-only. Archiving the local set now; re-run after any download finishes for full coverage.")
        }

        var steps: [StepResult] = []
        var metrics = RunMetrics()
        embedSkipFiles = []
        reviewStagedCount = 0
        reviewBatchPath = nil

        // Live progress: a phase stepper for the GUI (the run is hours long).
        var kinds: [RunProgress.PhaseKind] = profile.enabledPasses.map {
            $0 == .originals ? .exportHEIC : .exportJPEG
        }
        if !dryRun {
            if !profile.mirrorArchiveRoots.isEmpty { kinds += [.mirror, .verify] }
            if profile.cloudDestinations.contains(where: { $0.enabled && $0.isConfigured }) { kinds.append(.cloud) }
        }
        let tracker = RunProgressTracker(kinds: kinds, onProgress: onProgress)

        // 0. Drive-replacement safeguard: if the primary disk was swapped for a blank one but a
        // populated mirror is attached, re-seed the primary from the mirror BEFORE osxphotos — so a
        // blank replacement triggers a fast local copy, not a needless full re-export. No-op on a
        // normal run (primary already full). Both-drives-lost is a manual `restic restore`.
        if !dryRun { maybeReseedPrimary(profile: profile, steps: &steps) }

        // 1. Export passes.
        for pass in profile.enabledPasses {
            let phaseKind: RunProgress.PhaseKind = (pass == .originals) ? .exportHEIC : .exportJPEG
            tracker.startPhase(phaseKind, detail: "starting…")
            let dest = ExportPlan.destination(profile: profile, pass: pass)
            // Snapshot the pass's files BEFORE export so we can stage only the newly-added
            // items for review afterwards. Empty on the baseline run → nothing staged.
            let stageReview = !dryRun && profile.reviewNewItems
            let beforeFiles: Set<String> = stageReview ? ReviewStaging.snapshot(dest) : []
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

            // Stage newly-added items for review (incremental runs only).
            var stagedThisPass = 0
            if ok && stageReview {
                let added = ReviewStaging.newPaths(before: beforeFiles, after: ReviewStaging.snapshot(dest))
                if beforeFiles.isEmpty {
                    logger.debug("Review staging skipped for \(pass.label) — baseline run (no prior items).")
                } else if !added.isEmpty {
                    let batch = self.reviewBatch(profile: profile, runStart: started)
                    tracker.update(detail: "staging \(added.count) new for review…")
                    let r = ReviewStaging.copyNew(relPaths: added, sourceDir: dest,
                                                  batchDir: batch, subfolder: profile.subdirectory(for: pass))
                    self.reviewStagedCount += r.copied
                    stagedThisPass = r.copied
                    logger.info("Staged \(r.copied) new \(pass.label) item(s) for review → \(batch)/\(profile.subdirectory(for: pass))"
                                + (r.failed > 0 ? " (\(r.failed) failed)" : ""))
                }
            }
            tracker.finishPhase(phaseKind, state: ok ? .done : .failed,
                                detail: ok ? "exit 0\(stagedThisPass > 0 ? " · \(stagedThisPass) staged" : "")" : "exit \(result.exitCode)")
            if !ok {
                logger.error("Export failed — skipping mirror/verify/cloud to avoid propagating a partial archive.")
                return self.finishRun(profile: profile, started: started, steps: steps, tracker: tracker, metrics: metrics)
            }
        }

        if dryRun {
            logger.info("Dry run — skipping mirror, verify, and cloud sync.")
            return self.finishRun(profile: profile, started: started, steps: steps, tracker: tracker, metrics: metrics)
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
            metrics.mirrorsCopied = mirrorOK
            metrics.mirrorsSkipped = mirrorSkipped
            metrics.mirrorsFailed = mirrorFailed
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
                metrics.primaryFileCount = max(metrics.primaryFileCount, report.primaryFileCount)
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
            metrics.mirrorsVerified = verifyMatched
            metrics.verifyDiscrepancies = verifyDiscrepancies
            tracker.finishPhase(.verify, state: verifyDiscrepancies > 0 ? .failed : .done,
                                detail: verifyDiscrepancies > 0 ? "\(verifyDiscrepancies) discrepancies" : "\(verifyMatched) mirror(s) OK")
        }

        // 4. Off-site (restic). A pluggable LIST of destinations (restic → B2 today; rclone-backed
        // Dropbox/Proton/S3/… later, config-only). Each is independent, client-side-E2EE,
        // resumable, and SKIP-IF-UNAVAILABLE — an offline/undocked laptop run is a clean no-op that
        // catches up next time. Replaces the old Cryptomator/macFUSE vault phase entirely. Never
        // blocks the run.
        let cloudDests = profile.cloudDestinations.filter { $0.enabled && $0.isConfigured }
        if !cloudDests.isEmpty {
            tracker.startPhase(.cloud, detail: "backing up off-site…")
            if Tooling.restic == nil {
                logger.warn("restic not found — skipping off-site backup. Install with `brew install restic`.")
                steps.append(.init(name: "Cloud (restic)", success: true,
                                   detail: "skipped (restic not installed)", duration: 0))
                tracker.finishPhase(.cloud, state: .skipped, detail: "restic not installed")
            } else {
                // restic backs up the canonical primary archive (ROG_WHITE/<subfolder>); its own
                // dedup/snapshots mean we always send the full tree and restic stores only deltas.
                let resticSource = profile.primaryArchiveRoot
                var okCount = 0, skipCount = 0, failCount = 0
                for dest in cloudDests {
                    logger.info("→ Off-site (\(dest.name)) [\(dest.kind.rawValue)]: \(resticSource) ⇒ \(dest.repo)")
                    let t0 = Date()
                    let outcome = ResticService.backup(destination: dest, sourcePath: resticSource) { line in
                        self.logger.debug("[restic:\(dest.name)] \(line)")
                        if Self.looksLikeRelativePath(line) { tracker.update(currentFile: line) }
                    }
                    let dur = Date().timeIntervalSince(t0)
                    switch outcome {
                    case .backedUp, .checked, .restored:
                        okCount += 1
                        metrics.applyCloudDetail(outcome.detail)
                        logger.info("← Off-site (\(dest.name)) OK: \(outcome.detail) in \(Self.fmt(dur))")
                    case .skipped:
                        skipCount += 1
                        logger.warn("← Off-site (\(dest.name)) \(outcome.detail) — will catch up next run")
                    case .failed:
                        failCount += 1
                        logger.error("← Off-site (\(dest.name)) FAILED: \(outcome.detail)")
                    }
                    // A skip is non-fatal (success = true), exactly like the old "vault not mounted".
                    steps.append(.init(name: "Cloud → \(dest.name)", success: !outcome.isFailure,
                                       detail: outcome.detail, duration: dur))
                }
                let cState: RunProgress.State = failCount > 0 ? .failed : (okCount == 0 ? .skipped : .done)
                tracker.finishPhase(.cloud, state: cState,
                                    detail: "\(okCount) ok, \(skipCount) skipped, \(failCount) failed")
                logger.info("← Off-site: \(okCount) ok, \(skipCount) skipped, \(failCount) failed")
            }
        }

        // 5. Purge PLANNING (no deletion — Core never touches Photos). When purge is enabled, after
        // the archive is verified we compute which aged, un-pinned photos are present in ≥2 copies and
        // write the manifest the GUI stage-agent consumes. The actual album-staging/deletion lives in
        // the app target; this step only records what *would* be purgeable, so it is safe to run
        // headless from the scheduler. Failures here are non-fatal — they never fail an archive run.
        if !dryRun && profile.purgeEnabled {
            planPurge(profile: profile, steps: &steps, metrics: &metrics)
        }

        return self.finishRun(profile: profile, started: started, steps: steps, tracker: tracker, metrics: metrics)
    }

    /// Compute the purge plan and persist the manifest (no deletion). Best-effort: any failure is
    /// logged and recorded as a non-failing step so it can never break the archive run.
    private func planPurge(profile: ArchiveProfile, steps: inout [StepResult], metrics: inout RunMetrics) {
        guard let osx = Tooling.osxphotos else {
            logger.warn("Purge plan skipped — osxphotos not found.")
            steps.append(.init(name: "Purge plan", success: true,
                               detail: "skipped (osxphotos not found)", duration: 0))
            return
        }
        let t0 = Date()
        logger.info("→ Purge plan: computing aged, un-pinned, ≥2-copy-verified photos…")
        do {
            let plan = try PurgePlanner.compute(osxphotos: osx, profile: profile, now: Date(), logger: logger)
            metrics.purgeEligible = plan.candidates.count
            metrics.purgeVerified = plan.verified.count
            metrics.purgeUnverified = plan.unverified.count
            metrics.purgeVerifiedBytes = Int64(plan.verifiedBytes)
            let manifest = PurgeManifest(from: plan, profileName: profile.name,
                                         keepWindowDays: profile.retention.keepWindowDays, computedAt: Date())
            let wrote = PurgeManifestStore.write(manifest)
            let dur = Date().timeIntervalSince(t0)
            logger.info("← Purge plan: \(plan.verified.count) verified-deletable of \(plan.candidates.count) eligible "
                        + "(\(plan.unverified.count) unverified)\(wrote ? "" : " — manifest write FAILED") in \(Self.fmt(dur))")
            steps.append(.init(name: "Purge plan", success: true,
                               detail: "\(plan.verified.count) deletable / \(plan.candidates.count) eligible / \(plan.unverified.count) unverified",
                               duration: dur))
        } catch {
            let dur = Date().timeIntervalSince(t0)
            let message = (error as? PhotoMetadataQuery.QueryError)?.description ?? error.localizedDescription
            logger.warn("← Purge plan skipped — \(message)")
            steps.append(.init(name: "Purge plan", success: true,
                               detail: "skipped — \(message)", duration: dur))
        }
    }

    // MARK: - Helpers

    private func finishRun(profile: ArchiveProfile, started: Date,
                           steps: [StepResult], tracker: RunProgressTracker,
                           metrics: RunMetrics = RunMetrics()) -> RunSummary {
        if !embedSkipFiles.isEmpty {
            logger.info("ℹ️ \(embedSkipFiles.count) photo(s) archived with sidecar-only metadata "
                        + "(in-file embed skipped — damaged EXIF; the file + .xmp are fine). Listed in the report.")
        }
        if reviewStagedCount > 0, let batch = reviewBatchPath {
            logger.info("ℹ️ \(reviewStagedCount) new item(s) copied to NEW PHOTOS TO REVIEW → \(batch)")
        }
        let summary = RunSummary(profileName: profile.name, startedAt: started,
                                 finishedAt: Date(), steps: steps,
                                 logFile: logger.logFileURL?.path,
                                 metadataEmbedSkips: embedSkipFiles,
                                 reviewStagedCount: reviewStagedCount, reviewPath: reviewBatchPath,
                                 metrics: metrics)
        logger.info("=== Run finished in \(Self.fmt(summary.duration)) — \(summary.allSucceeded ? "ALL OK" : "WITH FAILURES") ===")
        tracker.finishRun()
        return summary
    }

    /// The dated "NEW PHOTOS TO REVIEW" batch folder for this run (memoized).
    private func reviewBatch(profile: ArchiveProfile, runStart: Date) -> String {
        if let p = reviewBatchPath { return p }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let p = (profile.effectiveReviewRoot as NSString).appendingPathComponent(f.string(from: runStart))
        reviewBatchPath = p
        return p
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

    /// File threshold below which the primary archive is treated as "blank" (a freshly-swapped
    /// drive). A real archive has hundreds of thousands of files, so the bounded count below trips
    /// the limit instantly; only an essentially-empty volume falls under it.
    static let reseedThreshold = 50

    /// Count non-dotfile entries under `dir`, stopping at `limit` (so a populated archive returns
    /// `limit` in O(limit), not O(363k)). Dotfiles are skipped so a blank drive's `.Trashes` /
    /// `.Spotlight-V100` cruft doesn't read as "populated".
    static func countFilesBounded(_ dir: String, limit: Int) -> Int {
        guard let en = FileManager.default.enumerator(atPath: dir) else { return 0 }
        var c = 0
        for case let rel as String in en {
            if (rel as NSString).lastPathComponent.hasPrefix(".") { continue }
            c += 1
            if c >= limit { break }
        }
        return c
    }

    /// Drive-replacement safeguard (see call site). Fires only when the primary archive is
    /// essentially empty AND a mounted mirror is substantially populated — then rsyncs the mirror
    /// into the primary before export. Conservative by design: a partially-written primary (a run
    /// that died mid-export) is NOT re-seeded — osxphotos fills the gaps incrementally. Both drives
    /// lost is a documented manual `restic restore`, never automated here.
    private func maybeReseedPrimary(profile: ArchiveProfile, steps: inout [StepResult]) {
        let threshold = Self.reseedThreshold
        let primaryRoot = profile.primaryArchiveRoot
        guard Self.countFilesBounded(primaryRoot, limit: threshold) < threshold else { return }

        for (base, mirrorRoot) in zip(profile.mirrorDestinations, profile.mirrorArchiveRoots) {
            guard VolumeReadiness.destinationReady(base).ready else { continue }
            guard Self.countFilesBounded(mirrorRoot, limit: threshold) >= threshold else { continue }
            guard let rsync = Tooling.rsync else {
                logger.warn("Primary looks blank but rsync not found — skipping re-seed; osxphotos will rebuild it.")
                return
            }
            let banner = Self.rsyncVersionBanner(rsync)
            let args = Self.rsyncCopyArgs(versionBanner: banner)
            let s = mirrorRoot.hasSuffix("/") ? mirrorRoot : mirrorRoot + "/"
            try? FileManager.default.createDirectory(atPath: primaryRoot, withIntermediateDirectories: true)
            logger.warn("Primary archive looks blank but mirror \(mirrorRoot) is populated — "
                        + "re-seeding the primary from the mirror before export (replaced-drive safeguard).")
            let t0 = Date()
            let result = try? ProcessRunner.run(executable: rsync, arguments: args + [s, primaryRoot]) { line in
                self.logger.debug("[rsync:reseed] \(line)")
            }
            let code = result?.exitCode ?? -1
            let ok = code == 0
            let dur = Date().timeIntervalSince(t0)
            (ok ? logger.info : logger.error)("← Re-seed primary from \(mirrorRoot) exit \(code) in \(Self.fmt(dur))")
            steps.append(.init(name: "Re-seed primary ← \(mirrorRoot)", success: ok,
                               detail: ok ? "primary re-seeded from mirror" : "re-seed failed (exit \(code))",
                               duration: dur))
            return  // one populated mirror is enough
        }
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
        if reviewStagedCount > 0, let reviewPath {
            lines.append("New items staged for review: \(reviewStagedCount)")
            lines.append("  → \(reviewPath)")
            lines.append("  (originals + JPEG duplicates of this run's new photos — hand off or delete after review)")
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
