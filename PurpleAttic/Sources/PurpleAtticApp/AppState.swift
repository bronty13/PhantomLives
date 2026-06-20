import Foundation
import Combine
import PurpleAtticCore

/// Which detail pane the sidebar is showing.
enum Pane: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case run = "Archive"
    case schedule = "Schedule"
    case profile = "Settings"
    case offsite = "Off-site"
    case backup = "Backup"
    case purge = "Purge"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .run: return "externaldrive.badge.timemachine"
        case .schedule: return "clock.arrow.2.circlepath"
        case .profile: return "slider.horizontal.3"
        case .offsite: return "lock.icloud"
        case .backup: return "arrow.clockwise.icloud"
        case .purge: return "trash"
        }
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let level: AtticLogger.Level
    let text: String
}

/// The app's view-model. Runs the (synchronous, blocking) `ExportEngine` off the main
/// thread and streams its log lines back to the UI via the logger sink. Mutates
/// `@Published` state only on the main queue.
final class AppState: ObservableObject {
    let store = SettingsStore()

    @Published var selectedPane: Pane = .dashboard
    @Published var isRunning = false
    @Published var logLines: [LogLine] = []
    @Published var lastSummaryText: String? = nil
    @Published var runError: String? = nil
    /// Live phase-by-phase progress for the run dashboard (nil when no run is active/recent).
    @Published var progress: RunProgress? = nil
    @Published var readiness: Tooling.Readiness = Tooling.readiness()
    @Published var libraryInspection: LibraryInspection? = nil
    @Published var isCheckingLibrary = false
    @Published var vaultStatus: VaultStatus = .notConfigured

    /// macOS privacy grants — all three must be present before a dry run or archive (the
    /// preflight gate). Refreshed on launch, when the Archive pane appears, and after a grant.
    @Published var permissions = PermissionsReport()
    /// Per-destination free-space estimate (a non-blocking warning aid).
    @Published var spaceChecks: [FreeSpaceCheck.DestinationSpace] = []

    // Purge (Phase C) — all read-only until the user both enables purge and clicks through
    // the in-app + macOS confirmations.
    @Published var purgePlan: PurgePlan? = nil
    @Published var isPlanningPurge = false
    @Published var isPurging = false
    @Published var isStaging = false
    @Published var purgeMessage: String? = nil
    /// 0…1 while a purge/stage runs (for a determinate bar); nil when idle.
    @Published var purgeFraction: Double? = nil

    /// Live cancel handle for the in-flight purge/stage; flipped by `cancelPurge()`.
    private var purgeCancellation: PurgeCancellation? = nil

    /// Album the staging path drops verified-deletable photos into for one-shot deletion in Photos.
    static let toDeleteAlbumName = "PurpleAttic — To Delete"

    // Scheduler (Phase D)
    @Published var schedulerLoaded = false
    @Published var schedulerMessage: String? = nil

    // Dashboard (monitoring) — loaded from the persistent stores; refreshed on launch, when the
    // Dashboard pane appears, and after any run/stage/delete.
    @Published var runHistory: [RunRecord] = []
    @Published var purgeAudits: [PurgeAuditRecord] = []
    @Published var latestManifest: PurgeManifest? = nil
    @Published var dashboardSummary = DashboardMetrics.Summary()

    /// Cap the in-memory log so a long run can't balloon memory; the full log is on disk.
    private let maxLogLines = 5000

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-publish when the nested settings store changes so every pane stays fresh.
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        BackupService.runOnLaunchIfDue(settingsStore: store)
        refreshVaultStatus()
        refreshPermissions()
        schedulerLoaded = SchedulerService.isLoaded()
        refreshDashboard()
    }

    // MARK: - Dashboard (monitoring)

    /// Reload the persisted run history / purge audit / latest manifest off-main and republish the
    /// rolled-up summary. Cheap (a few hundred small records), but kept off the main queue so a long
    /// history can never hitch the UI.
    func refreshDashboard() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let runs = RunHistoryStore.load()
            let audits = PurgeAuditStore.load()
            let manifest = PurgeManifestStore.read()
            let summary = DashboardMetrics.summarize(runs: runs, audits: audits, manifest: manifest)
            DispatchQueue.main.async {
                guard let self else { return }
                self.runHistory = runs
                self.purgeAudits = audits
                self.latestManifest = manifest
                self.dashboardSummary = summary
            }
        }
    }

    // MARK: - Permissions preflight

    /// Re-read all three grants (no prompts).
    func refreshPermissions() {
        permissions = PermissionsService.current(libraryPath: store.profile.photosLibraryPath)
    }

    /// Trigger the system "control Photos" consent dialog, then refresh.
    func requestPhotosAutomation() {
        PermissionsService.requestPhotosAutomation { [weak self] state in
            self?.permissions.photosAutomation = state
            self?.refreshPermissions()
        }
    }

    /// Trigger the PhotoKit authorization prompt, then refresh.
    func requestPhotosLibrary() {
        PermissionsService.requestPhotosLibrary { [weak self] state in
            self?.permissions.photosLibrary = state
            self?.refreshPermissions()
        }
    }

    func openPermissionSettings(_ kind: PermissionKind) {
        PermissionsService.openSettings(for: kind)
    }

    // MARK: - Scheduler (Phase D)

    func refreshSchedulerStatus() {
        schedulerLoaded = SchedulerService.isLoaded()
    }

    /// Install or remove the launchd agent to match the current schedule setting.
    func applySchedule() {
        store.save()
        do {
            try SchedulerService.apply(store.settings.schedule,
                                       profilePath: ProfileStore.defaultProfileURL().path)
            refreshSchedulerStatus()
            schedulerMessage = store.settings.schedule.enabled
                ? "Schedule installed — \(store.settings.schedule.humanDescription.lowercased())."
                : "Schedule removed."
        } catch {
            schedulerMessage = error.localizedDescription
            refreshSchedulerStatus()
        }
    }

    /// Trigger the scheduled archive immediately (out of band).
    func runScheduledNow() {
        SchedulerService.runNow()
        refreshSchedulerStatus()
        schedulerMessage = "Triggered a run — output goes to the scheduler log."
    }

    func refreshReadiness() {
        readiness = Tooling.readiness()
    }

    /// Re-check whether the configured Cryptomator vault is currently unlocked.
    func refreshVaultStatus() {
        vaultStatus = VaultStatus.check(path: store.profile.cloudVaultPath)
    }

    /// Inspect the Photos library off-main (it walks the originals tree) and publish the
    /// result so the UI can warn about an optimized / previews-only library before a run.
    func checkLibrary() {
        guard !isCheckingLibrary else { return }
        isCheckingLibrary = true
        let path = store.profile.photosLibraryPath
        let profile = store.profile
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = LibraryInspector.inspect(libraryPath: path)
            let space = FreeSpaceCheck.evaluate(profile: profile, originalsBytes: result.originalsBytes)
            DispatchQueue.main.async {
                self?.libraryInspection = result
                self?.spaceChecks = space
                self?.isCheckingLibrary = false
            }
        }
    }

    /// Kick off an archival run. `dryRun` plans only (osxphotos --dry-run; no mirror/verify).
    func runArchive(dryRun: Bool) {
        guard !isRunning else { return }
        // Preflight gate: refuse until every required macOS grant is in place, so a run can
        // never degenerate into the AppleScript-denied restart loop again (defense in depth —
        // the UI also disables the buttons).
        refreshPermissions()
        guard permissions.allGranted else {
            runError = "Grant " + permissions.missing.map { $0.title }.joined(separator: ", ")
                + " before running (see the Permissions panel above)."
            return
        }
        // Persist any pending edits so the run uses what's on screen.
        store.save()
        let profile = store.profile

        isRunning = true
        runError = nil
        lastSummaryText = nil
        logLines = []
        progress = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let runName = profile.name.replacingOccurrences(of: " ", with: "_")
            let logger = AtticLogger(runName: runName, echo: false)
            logger.sink = { [weak self] level, message in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.logLines.append(LogLine(level: level, text: message))
                    if self.logLines.count > self.maxLogLines {
                        self.logLines.removeFirst(self.logLines.count - self.maxLogLines)
                    }
                }
            }
            let engine = ExportEngine(logger: logger, onProgress: { [weak self] prog in
                DispatchQueue.main.async { self?.progress = prog }
            })
            do {
                let summary = try engine.run(profile: profile, dryRun: dryRun)
                let reportURL = summary.writeReport()
                // Persist a structured run record for the dashboard (real runs only).
                if !dryRun { summary.writeRunRecord(trigger: "manual") }
                DispatchQueue.main.async {
                    self.isRunning = false
                    var text = summary.reportText()
                    if let reportURL { text += "\nReport saved to: \(reportURL.path)" }
                    self.lastSummaryText = text
                    self.refreshDashboard()
                }
            } catch {
                let message = (error as? ExportEngine.EngineError)?.description ?? error.localizedDescription
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.runError = message
                }
            }
        }
    }

    // MARK: - Purge (Phase C)

    /// Read-only: compute which photos are purge-eligible and which are verified-in-archive.
    /// Always safe to call; deletes nothing.
    func previewPurge() {
        guard !isPlanningPurge, !isPurging else { return }
        guard let osx = Tooling.osxphotos else { purgeMessage = "osxphotos not found."; return }
        store.save()
        let profile = store.profile
        isPlanningPurge = true
        purgeMessage = nil
        purgePlan = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let plan = try PurgePlanner.compute(osxphotos: osx, profile: profile, now: Date())
                DispatchQueue.main.async { self?.purgePlan = plan; self?.isPlanningPurge = false }
            } catch {
                let message = (error as? PhotoMetadataQuery.QueryError)?.description ?? error.localizedDescription
                DispatchQueue.main.async { self?.purgeMessage = message; self?.isPlanningPurge = false }
            }
        }
    }

    /// Delete the verified-in-≥2-copies subset via PhotoKit (which shows the macOS
    /// confirmation). Refuses unless purge is enabled in Settings.
    func executePurge() {
        guard store.profile.purgeEnabled else {
            purgeMessage = "Purge is disabled. Enable it in Settings → Purge first."
            return
        }
        guard let plan = purgePlan, !plan.verified.isEmpty, !isPurging else { return }
        let uuids = plan.verified.map { $0.uuid }
        let plannedBytes = Int64(plan.verifiedBytes)
        let plannedCount = plan.verified.count
        let token = PurgeCancellation()
        purgeCancellation = token
        isPurging = true
        purgeFraction = 0
        purgeMessage = "Deleting in batches… (macOS will confirm each batch)"
        PhotoKitPurger.deleteAssets(
            uuids: uuids,
            cancellation: token,
            progress: { [weak self] done, total in
                DispatchQueue.main.async {
                    self?.purgeFraction = total > 0 ? Double(done) / Double(total) : nil
                    self?.purgeMessage = "Deleting… \(done) / \(total)"
                }
            },
            status: { [weak self] message in
                DispatchQueue.main.async { self?.purgeMessage = message }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPurging = false
                self.purgeFraction = nil
                self.purgeCancellation = nil
                switch result {
                case .success(let outcome):
                    let bytes = plannedCount > 0
                        ? Int64(Double(plannedBytes) * Double(outcome.deleted) / Double(plannedCount)) : 0
                    PurgeAuditStore.append(PurgeAuditRecord(
                        timestamp: Date(), trigger: .manual, action: .delete,
                        requested: outcome.requested, resolved: outcome.resolved,
                        succeeded: outcome.deleted, failed: outcome.failed, bytes: bytes,
                        note: outcome.cancelled ? "cancelled by user" : nil))
                    self.refreshDashboard()
                    var msg = "Deleted \(outcome.deleted) photo(s) — now in Photos → Recently Deleted for 30 days."
                    if outcome.failed > 0 {
                        msg += " \(outcome.failed) couldn't be deleted this pass and were skipped — re-run the purge to retry them."
                        if let e = outcome.batchError { msg += " (First error: \(e))" }
                    }
                    if outcome.pausedOut {
                        msg += " Photos/iCloud stayed busy too long, so the run paused with photos still pending — re-run once sync settles and it’ll pick up the rest."
                    }
                    if outcome.resolved < outcome.requested {
                        msg += " (\(outcome.requested - outcome.resolved) couldn't be matched in Photos and were left untouched.)"
                    }
                    if outcome.cancelled { msg += " Stopped early — you cancelled." }
                    self.purgeMessage = msg
                    self.purgePlan = nil   // force a fresh preview before any further deletion
                case .failure(let error):
                    self.purgeMessage = error.localizedDescription
                }
            }
        }
    }

    /// Stop the in-flight purge/stage after the current batch (and during a back-off wait).
    func cancelPurge() {
        purgeCancellation?.cancel()
        purgeMessage = "Cancelling — stopping after the current batch…"
    }

    /// The scalable path: add the verified-deletable photos to a regular album (non-destructive,
    /// unattended, no confirmations), then the user deletes them in Photos.app with one click —
    /// where Apple's engine handles the bulk delete + iCloud pacing. Avoids the per-batch macOS
    /// confirmation and the 3300 choke that plague direct deletion at scale.
    func stageForDeletion() {
        guard let plan = purgePlan, !plan.verified.isEmpty, !isStaging, !isPurging else { return }
        let uuids = plan.verified.map { $0.uuid }
        let plannedBytes = Int64(plan.verifiedBytes)
        let plannedCount = plan.verified.count
        let album = Self.toDeleteAlbumName
        let token = PurgeCancellation()
        purgeCancellation = token
        isStaging = true
        purgeFraction = 0
        purgeMessage = "Staging to “\(album)”…"
        PhotoKitPurger.stageToAlbum(
            uuids: uuids,
            albumName: album,
            cancellation: token,
            progress: { [weak self] done, total in
                DispatchQueue.main.async {
                    self?.purgeFraction = total > 0 ? Double(done) / Double(total) : nil
                    self?.purgeMessage = "Staging… \(done) / \(total)"
                }
            },
            status: { [weak self] message in
                DispatchQueue.main.async { self?.purgeMessage = message }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isStaging = false
                self.purgeFraction = nil
                self.purgeCancellation = nil
                switch result {
                case .success(let o):
                    let bytes = plannedCount > 0
                        ? Int64(Double(plannedBytes) * Double(o.added) / Double(plannedCount)) : 0
                    PurgeAuditStore.append(PurgeAuditRecord(
                        timestamp: Date(), trigger: .manual, action: .stage,
                        requested: o.requested, resolved: o.resolved, succeeded: o.added,
                        failed: max(0, o.resolved - o.added), bytes: bytes, album: o.albumName,
                        note: o.cancelled ? "cancelled by user" : nil))
                    self.refreshDashboard()
                    var msg = "Staged \(o.added) photo(s) into the album “\(o.albumName)”. "
                    msg += "Now in Photos.app: open that album → Edit ▸ Select All → right-click ▸ "
                    msg += "“Delete \(o.added) Photos” (or the Image menu) — NOT the Delete key (that only removes them from the album). "
                    msg += "Confirm once; Photos handles the deletion + iCloud sync (it paces itself, no 3300)."
                    if o.pausedOut {
                        msg += " (Photos/iCloud stayed busy too long, so staging paused before adding everything — re-run once sync settles to stage the rest.)"
                    }
                    if o.cancelled { msg += " Stopped early — you cancelled." }
                    if o.resolved < o.requested {
                        msg += " (\(o.requested - o.resolved) couldn't be matched in Photos and weren't staged.)"
                    }
                    self.purgeMessage = msg
                case .failure(let error):
                    self.purgeMessage = error.localizedDescription
                }
            }
        }
    }
}
