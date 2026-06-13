import Foundation
import SwiftUI
import Combine

/// Observable state + actions for the Obsidian Markdown sync. A thin GUI over
/// `sync-md-to-obsidian.sh` and its launchd agent — the script remains the
/// single source of truth; this never reimplements the mirror logic.
@MainActor
final class SyncController: ObservableObject {

    // Discovered/derived state (drives the UI).
    @Published private(set) var agentLoaded = false
    @Published private(set) var runs: Int?
    @Published private(set) var lastExitCode: Int?
    @Published private(set) var lastLog = SyncStatusParser.LogEntry()
    @Published private(set) var intervalSeconds: Int = 3600
    @Published private(set) var isSyncing = false
    @Published private(set) var lastActionMessage: String?

    // User-configurable locations (persisted).
    @AppStorage("scriptPath") var scriptPath: String = SyncController.defaultScriptPath
    @AppStorage("vaultPathOverride") private var vaultPathOverride: String = ""

    private var timer: AnyCancellable?

    static var defaultScriptPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("dev/PhantomLives/sync-md-to-obsidian.sh")
    }
    private var logPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/phantomlives-obsidian-sync.log")
    }
    private var plistPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/\(SyncStatusParser.agentLabel).plist")
    }
    private var domainTarget: String { "gui/\(getuid())/\(SyncStatusParser.agentLabel)" }

    init() {
        Task { await refresh() }
        // Light periodic refresh so the menu-bar glyph stays current.
        timer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.refresh() } }
    }

    // MARK: Derived

    var health: SyncStatusParser.Health {
        SyncStatusParser.health(agentLoaded: agentLoaded, lastExitCode: lastExitCode, isSyncing: isSyncing)
    }
    var menuBarSymbol: String { health.symbol }

    /// The vault the agent targets: read from the installed plist, else the
    /// persisted override.
    var vaultPath: String {
        if let v = plistEnvVault(), !v.isEmpty { return v }
        return vaultPathOverride
    }

    var lastSyncRelative: String { SyncStatusParser.relativeAge(of: lastLog.date) }
    var intervalHuman: String { SyncStatusParser.humanizeInterval(intervalSeconds) }

    // MARK: Refresh

    func refresh() async {
        // Agent state via launchctl.
        let (status, out) = await Self.run("/bin/launchctl", ["print", domainTarget])
        let agent = SyncStatusParser.parseAgentState(out, launchctlSucceeded: status == 0)
        // Plist-derived interval.
        let interval = plistInterval() ?? intervalSeconds
        // Log tail.
        let entry = (try? String(contentsOfFile: logPath, encoding: .utf8))
            .flatMap { SyncStatusParser.parseLastLogLine($0) } ?? lastLog

        agentLoaded = agent.loaded
        runs = agent.runs
        lastExitCode = agent.lastExitCode
        intervalSeconds = interval
        lastLog = entry
    }

    // MARK: Actions

    /// Run the mirror once. Uses the installed agent (so the baked-in vault is
    /// honored); falls back to invoking the script directly if not installed.
    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        lastActionMessage = "Syncing…"
        Task {
            let result: (Int32, String)
            if agentLoaded {
                result = await Self.run("/bin/launchctl", ["kickstart", "-k", domainTarget])
            } else {
                result = await runScript([])   // a bare run of the script
            }
            // Give the mirror a moment, then re-read state.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refresh()
            isSyncing = false
            lastActionMessage = result.0 == 0 ? "Synced \(lastSyncRelative)" : "Sync failed (see log)"
        }
    }

    /// Reinstall the agent with a new interval (seconds), keeping the vault.
    func setInterval(_ seconds: Int) {
        Task {
            lastActionMessage = "Updating schedule…"
            _ = await runScript(["--install-agent", String(seconds)])
            await refresh()
            lastActionMessage = "Schedule: every \(SyncStatusParser.humanizeInterval(seconds))"
        }
    }

    func enableAutoSync() {
        Task {
            lastActionMessage = "Enabling auto-sync…"
            _ = await runScript(["--install-agent", String(intervalSeconds)])
            await refresh()
            lastActionMessage = "Auto-sync enabled"
        }
    }

    func disableAutoSync() {
        Task {
            lastActionMessage = "Disabling auto-sync…"
            _ = await runScript(["--uninstall-agent"])
            await refresh()
            lastActionMessage = "Auto-sync disabled (manual only)"
        }
    }

    func readLog() -> String {
        (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "(no log yet at \(logPath))"
    }

    func revealLogInFinder() {
        NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
    }

    func openLogInConsole() {
        let url = URL(fileURLWithPath: logPath)
        NSWorkspace.shared.open([url],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Plist reading

    private func plistDict() -> [String: Any]? {
        NSDictionary(contentsOfFile: plistPath) as? [String: Any]
    }
    private func plistInterval() -> Int? {
        plistDict()?["StartInterval"] as? Int
    }
    private func plistEnvVault() -> String? {
        (plistDict()?["EnvironmentVariables"] as? [String: Any])?["OBSIDIAN_VAULT"] as? String
    }

    // MARK: Process plumbing

    /// Run the sync script via /bin/bash, passing the configured vault through
    /// OBSIDIAN_VAULT so --install-agent bakes the right target.
    private func runScript(_ args: [String]) async -> (Int32, String) {
        var env = ProcessInfo.processInfo.environment
        let vault = vaultPath
        if !vault.isEmpty { env["OBSIDIAN_VAULT"] = vault }
        return await Self.run("/bin/bash", [scriptPath] + args, env: env)
    }

    /// Run a command off the main actor; capture merged stdout+stderr.
    nonisolated static func run(_ launchPath: String, _ args: [String],
                                env: [String: String]? = nil) async -> (Int32, String) {
        await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: launchPath)
            proc.arguments = args
            if let env { proc.environment = env }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
            } catch {
                return (-1, "failed to launch \(launchPath): \(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
