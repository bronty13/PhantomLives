import Foundation

/// Best-effort live counters scraped from slackdump's stdout. Slackdump
/// emits human-readable progress lines, not a documented marker format,
/// so the parser is intentionally lenient: every regex is wrapped in a
/// success/no-op pair, and any missing match leaves the previous value
/// untouched. The user still gets a complete run if every regex misses
/// — the progress strip just degrades to indeterminate.
struct RunStats: Equatable {
    var channelCount: Int?
    var messageCount: Int?
    var fileCount: Int?
    var phase: String?
    var spanStart: Date?
    var spanEnd: Date?
    /// Byte total of the per-run output folder once slackdump exits.
    var outputBytes: Int64?

    static let empty = RunStats()

    /// Update in place from one line of slackdump output. Returns true
    /// when something was matched (used by RunnerTests to assert parser
    /// coverage as the slackdump format evolves).
    @discardableResult
    mutating func absorb(_ line: String) -> Bool {
        var matched = false

        if let n = RunStats.matchInt(line, pattern: #"([0-9]+)\s+channels?"#) {
            channelCount = n
            matched = true
        }
        if let n = RunStats.matchInt(line, pattern: #"([0-9]+)\s+messages?"#) {
            messageCount = n
            matched = true
        }
        if let n = RunStats.matchInt(line, pattern: #"([0-9]+)\s+files?"#) {
            fileCount = n
            matched = true
        }
        if let p = RunStats.matchPhase(line) {
            phase = p
            matched = true
        }
        if let p = RunStats.matchTranscribePhase(line) {
            phase = p
            matched = true
        }
        return matched
    }

    /// Walk a folder and sum up regular-file byte sizes. Used after a
    /// run completes to populate `outputBytes`.
    static func computeOutputBytes(folder: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if rv?.isRegularFile == true {
                total += Int64(rv?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Pretty-printed span for the sidebar / history. Mirrors the format
    /// messages-exporter-gui uses ("16d", "—" for all-time).
    static func formatSpan(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "—" }
        let days = max(0, Int(end.timeIntervalSince(start) / 86400))
        return "\(days)d"
    }

    // MARK: - Regex helpers (visible for testing)

    static func matchInt(_ line: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: line, options: [], range: range),
              m.numberOfRanges >= 2 else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    /// Pull a phase string when the line looks like a phase announcement.
    /// Slackdump prints things like "Fetching channels", "Downloading
    /// files", "Saving database". This is a soft match — any line
    /// starting with one of those verbs triggers a phase update.
    static func matchPhase(_ line: String) -> String? {
        let verbs = ["Fetching", "Downloading", "Saving", "Indexing", "Resuming"]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for verb in verbs where trimmed.hasPrefix(verb) {
            return trimmed
        }
        return nil
    }

    /// Convert TranscriptionService's "[transcribe N/M] foo.mp4 →
    /// foo.txt (45 MB, model=turbo)" file-start lines into a compact
    /// phase string ("Transcribing 3/7: foo.mp4") for the RunStrip.
    /// Matches the "file is starting" shape specifically — per-line
    /// tqdm updates and ✓/✗ summary lines don't trigger this.
    static func matchTranscribePhase(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[transcribe (\d+)/(\d+)\] ([^ ]+) → [^ ]+\.txt"#
        ) else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: line, options: [], range: range),
              m.numberOfRanges == 4 else { return nil }
        let cur = ns.substring(with: m.range(at: 1))
        let total = ns.substring(with: m.range(at: 2))
        let name = ns.substring(with: m.range(at: 3))
        return "Transcribing \(cur)/\(total): \(name)"
    }
}
