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
        case purpleAtticSync   // PurpleAttic sync: "pull exit: N", "staged N NEW", "no new items"
        case purpleAttic       // local Photo Archive run (pattic): phase + per-destination + off-site
        case atwRepost         // ATW repost bot: "submitted N of M slot(s)" / "Nothing to repost"
        case brewAutoupdate    // brew-autoupdate: bracketed "[ts] [LEVEL] …" — finished / ERRORS (N)
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
        case .purpleAttic:     return purpleAtticArchiveSummary(log)
        case .atwRepost:       return atwRepostSummary(log)
        case .brewAutoupdate:  return brewAutoupdateSummary(log)
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
        // Prefer the per-run delta line ("Updated K of N …" / "No markdown changes …") for the
        // headline; fall back to the canonical "Mirrored N … → DEST" (older logs have only that).
        // Destination always comes from the freshest "Mirrored … → DEST" line.
        var deltaHeadline: String?, deltaDate: Date?
        var mirroredHeadline: String?, mirroredDate: Date?, dest: String?
        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let d = leadingTimestamp(line)
            if line.contains("Updated "), line.contains("markdown file"), let n = intBefore(" of ", in: line) {
                deltaHeadline = "Updated \(n) file\(n == 1 ? "" : "s")"; deltaDate = d
            } else if line.contains("No markdown changes") {
                deltaHeadline = "Up to date"; deltaDate = d
            } else if let r = line.range(of: "Mirrored ") {
                let n = Int(line[r.upperBound...].prefix { $0.isNumber }) ?? 0
                mirroredHeadline = "Mirrored \(n) file\(n == 1 ? "" : "s")"; mirroredDate = d
                if let arrow = line.range(of: "→") {
                    dest = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        guard let headline = deltaHeadline ?? mirroredHeadline else { return nil }
        return LogSummary(date: deltaDate ?? mirroredDate,
                          headline: headline,
                          ok: true,
                          detail: dest.map { ($0 as NSString).lastPathComponent })
    }

    // MARK: PurpleAttic sync log (external-source photo/messages archives)

    /// Parse a PurpleAttic-style sync log. Two flavors are handled:
    ///  • photo/messages: explicit outcome lines —
    ///      `staged 2 NEW file(s) …` / `no new items this run …` / `pull exit: N`.
    ///  • Tier-1 archivers (notes/reminders/safari/calls/calendar/mail/…): each run
    ///    prints a one-line summary with NO leading timestamp, e.g.
    ///      `Call history: +0 new call(s); 404 total.`
    ///      `Mail archive: +0 new message(s); 3633 total; 342 attachment(s); 0 unparseable.`
    ///    sandwiched between timestamped `… exit: 0` / `=== sync done ===` markers.
    /// The freshest candidate wins; the explicit photo/messages outcome is preferred
    /// over the generic printed summary on a tie.
    static func purpleAtticSyncSummary(_ log: String) -> LogSummary? {
        var specific: LogSummary?       // explicit photo/messages outcome (or a failure)
        var generic: LogSummary?        // a Tier-1 archiver's printed summary line
        var lastDetail: String?
        var lastDate: Date?
        var pendingHeadline: String?    // a timestamp-less summary line awaiting its run's commit

        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let date = leadingTimestamp(line)
            if let date { lastDate = date }

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
                specific = LogSummary(date: date, headline: "Staged \(n) new item\(n == 1 ? "" : "s")", ok: true, detail: nil)
                pendingHeadline = nil
            } else if line.contains("no new items this run") {
                specific = LogSummary(date: date, headline: "No new items", ok: true, detail: nil)
                pendingHeadline = nil
            } else if line.contains("review staging is now ACTIVE") {
                specific = LogSummary(date: date, headline: "Caught up — staging active", ok: true, detail: nil)
                pendingHeadline = nil
            } else if line.contains("initial catch-up in progress") {
                specific = LogSummary(date: date, headline: "Catching up…", ok: true, detail: nil)
                pendingHeadline = nil
            } else if line.contains("unreachable") {
                specific = LogSummary(date: date, headline: "Mac unreachable — skipped", ok: nil, detail: nil)
                pendingHeadline = nil
            } else if line.contains("another sync is running") {
                specific = LogSummary(date: date, headline: "Skipped (already running)", ok: nil, detail: nil)
                pendingHeadline = nil
            } else if let r = line.range(of: " exit: ") {
                // A run boundary: "<tool> exit: N" (also "pull exit: N").
                let code = Int(line[r.upperBound...].prefix { $0.isNumber || $0 == "-" })
                if let code, code != 0 {
                    let isPull = line.contains("pull exit:")
                    specific = LogSummary(date: date,
                                          headline: isPull ? "Pull failed (exit \(code))" : "Sync failed (exit \(code))",
                                          ok: false, detail: nil)
                    pendingHeadline = nil
                } else {
                    // Success: commit this run's printed summary (if any) as the headline.
                    if let h = pendingHeadline {
                        generic = LogSummary(date: date ?? lastDate, headline: h, ok: true, detail: nil)
                    }
                    pendingHeadline = nil
                }
            } else if line.contains("=== sync done ===") {
                if let h = pendingHeadline {
                    generic = LogSummary(date: date ?? lastDate, headline: h, ok: true, detail: nil)
                }
                pendingHeadline = nil
            } else if date != nil {
                // Some other timestamped line ("… pulled", "=== sync start ==="):
                // clear so we only capture the NEXT (this run's) printed summary.
                pendingHeadline = nil
            } else {
                // A non-timestamped, non-empty line = candidate printed-summary headline.
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { pendingHeadline = t }
            }
        }

        // Freshest wins; prefer the cleaner explicit outcome on a tie.
        var chosen: LogSummary?
        switch (specific, generic) {
        case (nil, nil): chosen = nil
        case (let s?, nil): chosen = s
        case (nil, let g?): chosen = g
        case (let s?, let g?):
            chosen = (g.date ?? .distantPast) > (s.date ?? .distantPast) ? g : s
        }
        if var c = chosen { c.detail = c.detail ?? lastDetail; return c }
        return nil
    }

    // MARK: PurpleAttic local Photo Archive run log (pattic)

    /// Parse the **local** archive run log (pattic → `~/Library/Logs/PurpleAttic/scheduler.out.log`,
    /// AtticLogger format `yyyy-MM-dd HH:mm:ss.SSS [LEVEL] message`). Surfaces, by recency:
    ///   • "Archive up to date" / "Archive run had failures"  (terminal `=== Run finished … ===`)
    ///   • "Waiting for drives"     (primary not attached — a clean no-op)
    ///   • "Skipped (already running)"  (single-writer lock held)
    ///   • the current phase ("Backing up off-site", …) when a run is mid-flight
    /// and carries the latest off-site tally ("Off-site 1 ok, 0 skipped, 0 failed") as the detail.
    static func purpleAtticArchiveSummary(_ log: String) -> LogSummary? {
        var chosen: LogSummary?          // freshest terminal/skip state (later lines overwrite)
        var offsiteDetail: String?       // latest "← Off-site: …" tally
        var lastStartDate: Date?         // latest "=== PurpleAttic run: …"
        var lastPhase: String?           // latest "→ <phase>" while a run is in flight

        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let date = leadingTimestamp(line)

            if line.contains("=== PurpleAttic run:") {
                lastStartDate = date
                lastPhase = nil
                continue
            }
            if let r = line.range(of: "← Off-site:") {
                offsiteDetail = "Off-site " + line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            }
            // Phase hints (the "→ <phase>" entry lines), used only if the run hasn't finished.
            if line.contains("→ Export") { lastPhase = "Exporting photos" }
            else if line.contains("→ Mirror:") { lastPhase = "Mirroring to 2nd drive" }
            else if line.contains("→ Verify:") { lastPhase = "Verifying copies" }
            else if line.contains("→ Off-site (") { lastPhase = "Backing up off-site" }

            if line.contains("Run finished") && line.contains("ALL OK") {
                chosen = LogSummary(date: date, headline: "Archive up to date", ok: true, detail: nil)
            } else if line.contains("Run finished") && line.contains("WITH FAILURES") {
                chosen = LogSummary(date: date, headline: "Archive run had failures", ok: false, detail: nil)
            } else if line.contains("Primary drive not attached") {
                chosen = LogSummary(date: date, headline: "Waiting for drives", ok: nil, detail: nil)
            } else if line.contains("lock held") {
                chosen = LogSummary(date: date, headline: "Skipped (already running)", ok: nil, detail: nil)
            }
        }

        // A run started after the last terminal line → it's still in flight; show the phase.
        if let start = lastStartDate,
           (chosen?.date ?? .distantPast) < start {
            return LogSummary(date: start, headline: lastPhase ?? "Running…", ok: nil, detail: offsiteDetail)
        }
        if var c = chosen { c.detail = c.detail ?? offsiteDetail; return c }
        return nil
    }

    // MARK: ATW repost bot log

    /// Parse the ATW repost bot's log (timestamped `yyyy-MM-dd HH:mm:ss msg` lines). Surfaces, by
    /// recency: a completed pass ("Run complete — submitted N of M slot(s)." → "Reposted N
    /// listing(s)"), "Nothing to repost — all listings already scheduled.", or a failed run.
    static func atwRepostSummary(_ log: String) -> LogSummary? {
        var chosen: LogSummary?
        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let date = leadingTimestamp(line)
            if line.contains(" slot"), let r = line.range(of: "submitted ") {
                let n = Int(line[r.upperBound...].prefix { $0.isNumber }) ?? 0
                chosen = LogSummary(date: date,
                                    headline: n == 0 ? "No reposts this run" : "Reposted \(n) listing\(n == 1 ? "" : "s")",
                                    ok: true, detail: nil)
            } else if line.contains("Nothing to repost") {
                chosen = LogSummary(date: date, headline: "Up to date — nothing to repost", ok: true, detail: nil)
            } else if line.contains("Run #") && line.contains("failed:") {
                let msg = line.range(of: "failed:").map { String(line[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
                chosen = LogSummary(date: date, headline: "Run failed", ok: false, detail: msg)
            }
        }
        return chosen
    }

    // MARK: brew-autoupdate log

    /// A `[yyyy-MM-dd HH:mm:ss]`-bracketed timestamp at the start of a line (brew-autoupdate's
    /// format, distinct from the bare-timestamp jobs).
    static func bracketTimestamp(_ line: String) -> Date? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let inner = String(line[line.index(after: line.startIndex)..<close])
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.date(from: inner)
    }

    /// Parse brew-autoupdate's stdout log. The script exits 0 even when `brew` reports errors, so
    /// health can't come from the exit code — we read the latest run's "[ERROR] ERRORS (N)" line.
    /// Surfaces the freshest run: "Running…", "Updated with N error(s)" (ok=false), "Updated
    /// packages", or "Up to date", with "finished in Ns" as the detail.
    static func brewAutoupdateSummary(_ log: String) -> LogSummary? {
        var date: Date?, finished = false, hadErrors = false, errorCount = 0, hadChanges = false
        var secs: String?
        for line in log.split(whereSeparator: \.isNewline).map(String.init) {
            let d = bracketTimestamp(line)
            if line.contains("Brew Auto-Update") && line.contains("starting") {
                finished = false; hadErrors = false; errorCount = 0; hadChanges = false; secs = nil
                if let d { date = d }
            } else if line.contains("Package changes:") {
                hadChanges = true
            } else if let r = line.range(of: "finished in ") {
                finished = true
                secs = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let d { date = d }
            } else if let r = line.range(of: "ERRORS (") {
                hadErrors = true
                errorCount = Int(line[r.upperBound...].prefix { $0.isNumber }) ?? 0
                if let d { date = d }
            }
        }
        guard date != nil else { return nil }
        if !finished { return LogSummary(date: date, headline: "Running…", ok: nil, detail: nil) }
        let detail = secs.map { "finished in \($0)" }
        if hadErrors {
            return LogSummary(date: date, headline: "Updated with \(errorCount) error\(errorCount == 1 ? "" : "s")",
                              ok: false, detail: detail)
        }
        return LogSummary(date: date, headline: hadChanges ? "Updated packages" : "Up to date",
                          ok: true, detail: detail)
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

    // MARK: 24-hour "new items" tally

    /// Total NEW items a job found/archived in the **last 24 hours**, summed across that window's
    /// runs — or `nil` when this job type has no per-run "new items" concept to total.
    ///
    /// Kind-aware on purpose: pull archives report *deltas* per run (`staged N NEW`, `+N new …`),
    /// which sum meaningfully; the Obsidian mirror reports the *full* file count every run
    /// ("Mirrored 456 files"), so summing it would be nonsense → `nil` (no badge). Returns `0`
    /// (not nil) when runs happened in the window but found nothing, so "0 in 24h" can show.
    static func itemsLast24h(_ log: String, kind: LogKind, now: Date = Date()) -> Int? {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        let lines = log.split(whereSeparator: \.isNewline).map(String.init)

        switch kind {
        case .generic, .brewAutoupdate:
            return nil

        case .obsidian:
            // Sum per-run "Updated K of N markdown file(s)" deltas ("No markdown changes" = 0).
            // Older logs (only "Mirrored N", a total) have no delta line → nil (not a false sum).
            var total = 0, saw = false
            for line in lines {
                guard let d = leadingTimestamp(line), d >= cutoff else { continue }
                if line.contains("Updated "), line.contains("markdown file"), let n = intBefore(" of ", in: line) {
                    total += n; saw = true
                } else if line.contains("No markdown changes") {
                    saw = true
                }
            }
            return saw ? total : nil

        case .purpleAttic:
            // Local photo archive: "N new item(s) …" lines (AtticLogger-timestamped).
            var total = 0, saw = false
            for line in lines {
                guard let d = leadingTimestamp(line), d >= cutoff else { continue }
                if let n = intBefore(" new item", in: line) { total += n; saw = true }
            }
            return saw ? total : nil

        case .atwRepost:
            // Sum reposts submitted per pass: "… submitted N of M slot(s)." ("Nothing to repost" = 0).
            var total = 0, saw = false
            for line in lines {
                guard let d = leadingTimestamp(line), d >= cutoff else { continue }
                if line.contains(" slot"), let r = line.range(of: "submitted ") {
                    total += Int(line[r.upperBound...].prefix { $0.isNumber }) ?? 0; saw = true
                } else if line.contains("Nothing to repost") {
                    saw = true
                }
            }
            return saw ? total : nil

        case .purpleAtticSync:
            // photo/messages: "staged N NEW file" / "no new items this run" (timestamped);
            // Tier-1 archivers: "…: +N new <noun>(s); …" (no timestamp → attributed to the
            // run's most recent timestamped marker).
            var total = 0, saw = false, lastDate: Date?
            for line in lines {
                if let d = leadingTimestamp(line) { lastDate = d }
                let within = (lastDate ?? .distantPast) >= cutoff
                if line.contains(" NEW file"), let r = line.range(of: "staged ") {
                    if within { total += Int(line[r.upperBound...].prefix { $0.isNumber }) ?? 0; saw = true }
                } else if line.contains("no new items this run") {
                    if within { saw = true }
                } else if let n = plusNewCount(line) {
                    if within { total += n; saw = true }
                }
            }
            return saw ? total : nil
        }
    }

    /// The contiguous integer immediately before `marker`, e.g. "… 137 new item(s)" with
    /// marker " new item" → 137.
    static func intBefore(_ marker: String, in line: String) -> Int? {
        guard let r = line.range(of: marker) else { return nil }
        let digits = String(line[..<r.lowerBound].reversed().prefix { $0.isNumber }.reversed())
        return digits.isEmpty ? nil : Int(digits)
    }

    /// A Tier-1 archiver's "+N new <noun>" delta, e.g. "Mail archive: +4 new message(s); …" → 4.
    /// Requires the digits to be immediately followed by " new" so unrelated "+" tokens don't match.
    static func plusNewCount(_ line: String) -> Int? {
        guard let r = line.range(of: "+") else { return nil }
        let after = line[r.upperBound...]
        let digits = after.prefix { $0.isNumber }
        guard !digits.isEmpty, after.dropFirst(digits.count).hasPrefix(" new") else { return nil }
        return Int(digits)
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
        case paused         // agent intentionally not loaded (auto-run off) — a deliberate state, not a problem
        case warning        // a non-fatal hiccup worth attention (e.g. a swallowed pull-exit error)
        case error          // last run failed

        /// SF Symbol shown in the menu bar (menu bar renders it as a template).
        var symbol: String {
            switch self {
            case .healthy: return "checkmark.icloud"
            case .running: return "arrow.triangle.2.circlepath"
            case .paused:  return "pause.circle"
            case .warning: return "exclamationmark.icloud"
            case .error:   return "xmark.icloud"
            }
        }

        var label: String {
            switch self {
            case .healthy: return "Up to date"
            case .running: return "Running…"
            case .paused:  return "Auto-run off"
            case .warning: return "Attention"
            case .error:   return "Last run failed"
            }
        }

        /// Severity for picking the worst job's health to drive the menu-bar glyph.
        /// `paused` ranks below `warning`/`error` so a deliberately-disabled job never
        /// drags the menu-bar glyph into an alarm state, but still above `healthy`/`running`
        /// so an all-paused set surfaces the pause glyph rather than a misleading checkmark.
        var severity: Int {
            switch self {
            case .healthy: return 0
            case .running: return 1
            case .paused:  return 2
            case .warning: return 3
            case .error:   return 4
            }
        }
    }

    /// An agent that isn't loaded is **paused** (auto-run off) — a state the user controls
    /// deliberately via enable/disable — not a `warning`. Genuine attention states come from a
    /// loaded agent whose last run failed (`error`) or whose log shows a swallowed failure
    /// (handled by the caller via the log summary).
    static func health(agentLoaded: Bool, lastExitCode: Int?, isSyncing: Bool) -> Health {
        if isSyncing { return .running }
        if let code = lastExitCode, code != 0 { return .error }
        if !agentLoaded { return .paused }
        return .healthy
    }
}
