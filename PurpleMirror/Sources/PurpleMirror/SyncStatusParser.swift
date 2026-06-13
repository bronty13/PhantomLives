import Foundation

/// Pure, side-effect-free parsing & formatting helpers for background-job state.
/// Kept separate from the controllers so the logic is unit-testable without
/// touching `launchctl`, the filesystem, or `Process`.
///
/// PurpleMirror manages an arbitrary set of launchd jobs (auto-discovered from
/// `~/Library/LaunchAgents`). Each job's log is parsed into a unified
/// ``LogSummary`` according to its ``LogKind`` — Obsidian's mirror log, a
/// PurpleAttic-style sync log, or a generic last-line fallback.
enum SyncStatusParser {

    // MARK: Log kinds

    /// How a job's log should be parsed for the status line.
    enum LogKind: String, Equatable, Codable {
        case obsidian          // "… Mirrored N markdown files → /path"
        case purpleAtticSync   // Rachel/PurpleAttic: "pull exit: N", "staged N NEW", "no new items"
        case generic           // unknown job: show the last meaningful line
    }

    /// A one-line, human-facing digest of a job's most recent activity.
    struct LogSummary: Equatable {
        var date: Date?
        var headline: String       // e.g. "Mirrored 442 files", "Staged 1 new item", "No new items"
        var ok: Bool?              // nil = unknown/neutral, true = last run fine, false = a failure
        var detail: String?        // optional secondary, e.g. "42,963 files · 241G"
    }

    /// Dispatch to the right parser for a job's `kind`. Returns nil if the log
    /// has nothing recognizable yet.
    static func summary(_ log: String, kind: LogKind) -> LogSummary? {
        switch kind {
        case .obsidian:        return obsidianSummary(log)
        case .purpleAtticSync: return purpleAtticSyncSummary(log)
        case .generic:         return genericSummary(log)
        }
    }

    // MARK: Obsidian mirror log

    struct LogEntry: Equatable {
        var date: Date?
        var fileCount: Int?
        var destination: String?
    }

    /// Parse the last meaningful line of the Obsidian sync log. The script writes:
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
        entry.date = leadingTimestamp(line)

        // File count: the integer after "Mirrored ".
        if let r = line.range(of: "Mirrored ") {
            entry.fileCount = Int(line[r.upperBound...].prefix { $0.isNumber })
        }
        // Destination: text after the arrow.
        if let r = line.range(of: "→") {
            entry.destination = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return entry
    }

    static func obsidianSummary(_ log: String) -> LogSummary? {
        guard let e = parseLastLogLine(log) else { return nil }
        let n = e.fileCount ?? 0
        let dest = e.destination.map { ($0 as NSString).lastPathComponent }
        return LogSummary(date: e.date,
                          headline: "Mirrored \(n) file\(n == 1 ? "" : "s")",
                          ok: true,
                          detail: dest)
    }

    // MARK: PurpleAttic sync log (Rachel et al.)

    /// Parse a PurpleAttic-style sync log. The orchestration script logs lines like:
    ///   `2026-06-13 17:25:16 pull exit: 0  — local files: 42966, size: 241G`
    ///   `2026-06-13 17:25:18 staged 2 NEW file(s) for review → …/20260613-172517`
    ///   `2026-06-13 16:32:09 no new items this run — nothing to stage for review`
    /// The most recent recognizable outcome line wins (later lines override earlier).
    static func purpleAtticSyncSummary(_ log: String) -> LogSummary? {
        var summary: LogSummary?
        var lastDetail: String?

        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let date = leadingTimestamp(line)

            // Carry the freshest "local files: N, size: S" as the detail line.
            if let r = line.range(of: "local files: ") {
                let rest = line[r.upperBound...]
                let count = Int(rest.prefix { $0.isNumber })
                var d = count.map { "\(grouped($0)) files" }
                if let sr = line.range(of: "size: ") {
                    let size = line[sr.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !size.isEmpty { d = (d.map { $0 + " · " } ?? "") + size }
                }
                if let d { lastDetail = d }
            }

            if line.contains("staged ") && line.contains(" NEW file") {
                let n = Int(line[line.range(of: "staged ")!.upperBound...].prefix { $0.isNumber }) ?? 0
                summary = LogSummary(date: date, headline: "Staged \(n) new item\(n == 1 ? "" : "s")", ok: true, detail: nil)
            } else if line.contains("no new items this run") {
                summary = LogSummary(date: date, headline: "No new items", ok: true, detail: nil)
            } else if line.contains("review staging is now ACTIVE") {
                summary = LogSummary(date: date, headline: "Caught up — staging active", ok: true, detail: nil)
            } else if line.contains("initial catch-up in progress") {
                summary = LogSummary(date: date, headline: "Catching up…", ok: true, detail: nil)
            } else if let r = line.range(of: "pull exit: ") {
                let code = Int(line[r.upperBound...].prefix { $0.isNumber || $0 == "-" })
                if let code, code != 0 {
                    summary = LogSummary(date: date, headline: "Pull failed (exit \(code))", ok: false, detail: nil)
                }
                // pull exit 0 is not itself the headline — the staged/no-new line that
                // follows in the same run is more informative — but keep its timestamp.
            } else if line.contains("unreachable") {
                summary = LogSummary(date: date, headline: "Mac unreachable — skipped", ok: nil, detail: nil)
            } else if line.contains("another sync is running") {
                summary = LogSummary(date: date, headline: "Skipped (already running)", ok: nil, detail: nil)
            }
        }

        if summary != nil { summary!.detail = summary!.detail ?? lastDetail }
        return summary
    }

    // MARK: Generic fallback

    /// For unknown jobs: surface the last non-empty log line (minus its leading
    /// timestamp) and that line's timestamp if present.
    static func genericSummary(_ log: String) -> LogSummary? {
        let lines = log.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let line = lines.last else { return nil }
        let date = leadingTimestamp(line)
        // Strip a leading "YYYY-MM-DD HH:MM:SS " if we parsed one.
        var headline = line
        if date != nil, line.count > 20 { headline = String(line.dropFirst(20)) }
        return LogSummary(date: date, headline: headline, ok: nil, detail: nil)
    }

    // MARK: Shared helpers

    /// Parse a leading `YYYY-MM-DD HH:MM:SS` timestamp from a log line.
    static func leadingTimestamp(_ line: String) -> Date? {
        guard line.count >= 19 else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.date(from: String(line.prefix(19)))
    }

    /// 42963 → "42,963" (thousands-grouped for the detail line).
    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
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
        case running        // a run is in progress
        case warning        // agent not installed / no recent run / a non-fatal hiccup
        case error          // last run failed

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
            case .running: return "Running…"
            case .warning: return "Attention"
            case .error:   return "Last run failed"
            }
        }

        /// Severity for picking the worst job's health to drive the menu-bar glyph.
        var severity: Int {
            switch self {
            case .healthy: return 0
            case .running: return 1
            case .warning: return 2
            case .error:   return 3
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
