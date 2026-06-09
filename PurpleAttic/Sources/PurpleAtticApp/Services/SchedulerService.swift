import Foundation
import PurpleAtticCore

/// Installs / removes the launchd LaunchAgent that runs the scheduled archive via the
/// bundled `pattic export` (which has no purge path — automated runs can never delete).
/// All launchctl calls target the per-user GUI domain (`gui/<uid>`).
enum SchedulerService {

    static let label = "com.bronty13.PurpleAttic.archive"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The pattic binary bundled inside the running app.
    static var patticPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pattic").path
    }

    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PurpleAttic", isDirectory: true)
    }
    static var stdoutPath: String { logDirectory.appendingPathComponent("scheduler.out.log").path }
    static var stderrPath: String { logDirectory.appendingPathComponent("scheduler.err.log").path }

    private static var domainTarget: String { "gui/\(getuid())" }
    private static var serviceTarget: String { "gui/\(getuid())/\(label)" }

    enum SchedulerError: LocalizedError {
        case bootstrapFailed(String)
        case missingPattic(String)
        var errorDescription: String? {
            switch self {
            case .bootstrapFailed(let m): return "Couldn't load the schedule into launchd: \(m)"
            case .missingPattic(let p): return "Bundled pattic not found at \(p). Reinstall the app with build-app.sh."
            }
        }
    }

    /// Install or remove the agent to match `schedule.enabled`.
    static func apply(_ schedule: ArchiveSchedule, profilePath: String?) throws {
        if schedule.enabled {
            try install(schedule, profilePath: profilePath)
        } else {
            try uninstall()
        }
    }

    static func install(_ schedule: ArchiveSchedule, profilePath: String?) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: patticPath) else {
            throw SchedulerError.missingPattic(patticPath)
        }
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        var args = [patticPath, "export"]
        if let p = profilePath, !p.isEmpty { args += ["--profile", p] }

        let xml = LaunchAgentPlist.build(label: label, programArguments: args, schedule: schedule,
                                         stdoutPath: stdoutPath, stderrPath: stderrPath)
        try xml.data(using: .utf8)?.write(to: plistURL, options: .atomic)

        // Reload: bootout (ignore "not loaded" errors) then bootstrap.
        _ = launchctl(["bootout", serviceTarget])
        let result = launchctl(["bootstrap", domainTarget, plistURL.path])
        if result.status != 0 {
            // bootstrap can report "already bootstrapped" if a stale copy lingered — retry once.
            _ = launchctl(["bootout", serviceTarget])
            let retry = launchctl(["bootstrap", domainTarget, plistURL.path])
            if retry.status != 0 {
                throw SchedulerError.bootstrapFailed(retry.output.isEmpty ? "launchctl exit \(retry.status)" : retry.output)
            }
        }
    }

    static func uninstall() throws {
        _ = launchctl(["bootout", serviceTarget])
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// True when launchd currently has the agent loaded.
    static func isLoaded() -> Bool {
        launchctl(["print", serviceTarget]).status == 0
    }

    /// Trigger a run immediately (out of schedule).
    static func runNow() {
        if !isLoaded() { _ = launchctl(["bootstrap", domainTarget, plistURL.path]) }
        _ = launchctl(["kickstart", "-k", serviceTarget])
    }

    /// Modification time of the scheduler stdout log — a proxy for "last run".
    static func lastRunDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: stdoutPath)
        return attrs?[.modificationDate] as? Date
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
