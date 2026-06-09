import Foundation
import Combine
import PurpleAtticCore

/// Which detail pane the sidebar is showing.
enum Pane: String, CaseIterable, Identifiable {
    case run = "Archive"
    case schedule = "Schedule"
    case profile = "Settings"
    case backup = "Backup"
    case purge = "Purge"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .run: return "externaldrive.badge.timemachine"
        case .schedule: return "clock.arrow.2.circlepath"
        case .profile: return "slider.horizontal.3"
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

    @Published var selectedPane: Pane = .run
    @Published var isRunning = false
    @Published var logLines: [LogLine] = []
    @Published var lastSummaryText: String? = nil
    @Published var runError: String? = nil
    @Published var readiness: Tooling.Readiness = Tooling.readiness()
    @Published var libraryInspection: LibraryInspection? = nil
    @Published var isCheckingLibrary = false
    @Published var vaultStatus: VaultStatus = .notConfigured

    // Purge (Phase C) — all read-only until the user both enables purge and clicks through
    // the in-app + macOS confirmations.
    @Published var purgePlan: PurgePlan? = nil
    @Published var isPlanningPurge = false
    @Published var isPurging = false
    @Published var purgeMessage: String? = nil

    // Scheduler (Phase D)
    @Published var schedulerLoaded = false
    @Published var schedulerMessage: String? = nil

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
        schedulerLoaded = SchedulerService.isLoaded()
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = LibraryInspector.inspect(libraryPath: path)
            DispatchQueue.main.async {
                self?.libraryInspection = result
                self?.isCheckingLibrary = false
            }
        }
    }

    /// Kick off an archival run. `dryRun` plans only (osxphotos --dry-run; no mirror/verify).
    func runArchive(dryRun: Bool) {
        guard !isRunning else { return }
        // Persist any pending edits so the run uses what's on screen.
        store.save()
        let profile = store.profile

        isRunning = true
        runError = nil
        lastSummaryText = nil
        logLines = []

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
            let engine = ExportEngine(logger: logger)
            do {
                let summary = try engine.run(profile: profile, dryRun: dryRun)
                let reportURL = summary.writeReport()
                DispatchQueue.main.async {
                    self.isRunning = false
                    var text = summary.reportText()
                    if let reportURL { text += "\nReport saved to: \(reportURL.path)" }
                    self.lastSummaryText = text
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
        isPurging = true
        purgeMessage = nil
        PhotoKitPurger.deleteAssets(uuids: uuids) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPurging = false
                switch result {
                case .success(let outcome):
                    var msg = "Deleted \(outcome.deleted) photo(s) — now in Photos → Recently Deleted for 30 days."
                    if outcome.resolved < outcome.requested {
                        msg += " (\(outcome.requested - outcome.resolved) couldn't be matched in Photos and were left untouched.)"
                    }
                    self.purgeMessage = msg
                    self.purgePlan = nil
                case .failure(let error):
                    self.purgeMessage = error.localizedDescription
                }
            }
        }
    }
}
