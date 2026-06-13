import Foundation

/// Pure, side-effect-free parsing & formatting helpers for the sync state.
/// Kept separate from `SyncController` so the logic is unit-testable without
/// touching `launchctl`, the filesystem, or `Process`.
enum SyncStatusParser {

    /// The launchd label the `sync-md-to-obsidian.sh` agent installs under.
    static let agentLabel = "com.phantomlives.obsidian-sync"

    // MARK: Log line

    struct LogEntry: Equatable {
        var date: Date?
        var fileCount: Int?
        var destination: String?
    }

    /// Parse the last meaningful line of the sync log. The script writes:
    /// `2026-06-13 14:26:22  Mirrored 442 markdown files → /path/to/Vault/PhantomLives`
    static func parseLastLogLine(_ log: String) -> LogEntry? {
        let lines = log.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.contains("Mirrored") }
        guard let line = lines.last else { return nil }
        return parseLogLine(line)
    }

    static func parseLogLine(_ line: String) -> LogEntry {
        var entry = LogEntry()

        // Timestamp: leading "YYYY-MM-DD HH:MM:SS"
        if line.count >= 19 {
            let stamp = String(line.prefix(19))
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            entry.date = fmt.date(from: stamp)
        }

        // File count: the integer after "Mirrored ".
        if let r = line.range(of: "Mirrored ") {
            let rest = line[r.upperBound...]
            let digits = rest.prefix { $0.isNumber }
            entry.fileCount = Int(digits)
        }

        // Destination: text after the arrow.
        if let r = line.range(of: "→") {
            entry.destination = line[r.upperBound...]
                .trimmingCharacters(in: .whitespaces)
        }

        return entry
    }

    // MARK: launchctl print

    struct AgentState: Equatable {
        var loaded: Bool
        var runs: Int?
        var lastExitCode: Int?
    }

    /// Parse `launchctl print gui/<uid>/<label>` output for the fields we show.
    /// `launchctlSucceeded` is whether the command exited 0 (i.e. the job is
    /// bootstrapped at all).
    static func parseAgentState(_ output: String, launchctlSucceeded: Bool) -> AgentState {
        var state = AgentState(loaded: launchctlSucceeded, runs: nil, lastExitCode: nil)
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("runs = ") {
                state.runs = Int(line.dropFirst("runs = ".count).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("last exit code = ") {
                let v = line.dropFirst("last exit code = ".count).trimmingCharacters(in: .whitespaces)
                state.lastExitCode = Int(v)   // "(never exited)" → nil, which is fine
            }
        }
        return state
    }

    // MARK: Interval

    /// Humanize a launchd StartInterval (seconds) → "30 min", "1 hr", "2 hr 30 min".
    static func humanizeInterval(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        switch (h, m) {
        case (0, let m): return "\(m) min"
        case (let h, 0): return "\(h) hr"
        default:         return "\(h) hr \(m) min"
        }
    }

    /// "3 min ago", "just now", "2 hr ago", or "never".
    static func relativeAge(of date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let secs = Int(now.timeIntervalSince(date))
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs) sec ago" }
        let mins = secs / 60
        if mins < 60 { return "\(mins) min ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs) hr ago" }
        return "\(hrs / 24) days ago"
    }

    // MARK: Health

    enum Health {
        case healthy        // agent loaded, last run succeeded
        case running        // a sync is in progress
        case warning        // agent not installed / no recent run
        case error          // last run exited non-zero

        /// SF Symbol shown in the menu bar (menu bar renders it as a template).
        var symbol: String {
            switch self {
            case .healthy: return "checkmark.icloud"
            case .running: return "arrow.triangle.2.circlepath"
            case .warning: return "exclamationmark.icloud"
            case .error:   return "xmark.icloud"
            }
        }

        var label: String {
            switch self {
            case .healthy: return "Up to date"
            case .running: return "Syncing…"
            case .warning: return "Auto-sync off"
            case .error:   return "Last sync failed"
            }
        }
    }

    static func health(agentLoaded: Bool, lastExitCode: Int?, isSyncing: Bool) -> Health {
        if isSyncing { return .running }
        if let code = lastExitCode, code != 0 { return .error }
        if !agentLoaded { return .warning }
        return .healthy
    }
}
