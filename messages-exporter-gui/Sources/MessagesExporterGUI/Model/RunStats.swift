import Foundation

/// Numeric summary of an export run, displayed by the four stat tiles in
/// Mission Control. Populated piecewise as the CLI emits markers and
/// finalised after the run by reading the run folder's metadata.json and
/// `du`-equivalent walk.
///
/// `nil` means "unknown / not yet measured" — tiles render an em-dash for
/// nil values rather than zero, since zero is a valid result of a real
/// export (e.g. no attachments).
struct RunStats: Equatable {
    var messageCount: Int?
    var attachmentCount: Int?
    var photoCount: Int?
    var videoCount: Int?
    var voiceCount: Int?
    var outputBytes: Int64?
    var spanStart: Date?
    var spanEnd:   Date?

    static let empty = RunStats()

    /// Parse the message count out of the CLI's stage-3 line:
    /// `"[3/5] 18 messages in range"`. Returns nil for any other line so
    /// the caller can drop it into a `flatMap`.
    static func messageCount(in line: String) -> Int? {
        // Look for "[3/5] " prefix then a leading integer.
        guard let prefixRange = line.range(of: "[3/5] ") else { return nil }
        let tail = line[prefixRange.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Read `metadata.json` written by the CLI at the root of the run
    /// folder. Returns nil if the file is missing or malformed — the
    /// caller falls back to whatever it parsed mid-stream.
    ///
    /// The CLI writes (see `export_messages.py`):
    ///   {
    ///     "messages": [...],   // count via .count
    ///     "summary": { "messages": N, "photos": N, "videos": N, "voice": N }
    ///   }
    /// Older runs may not have a `summary` block — try the array length
    /// for a message count, then bail.
    static func decodeMetadata(at url: URL) -> RunStats? {
        guard let data = try? Data(contentsOf: url),
              let any  = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any]
        else { return nil }

        var stats = RunStats()
        if let summary = dict["summary"] as? [String: Any] {
            stats.messageCount    = summary["messages"]    as? Int
            stats.photoCount      = summary["photos"]      as? Int
            stats.videoCount      = summary["videos"]      as? Int
            stats.voiceCount      = summary["voice"]       as? Int
        }
        if stats.messageCount == nil, let messages = dict["messages"] as? [Any] {
            stats.messageCount = messages.count
        }
        // Attachments aren't a top-level summary field; sum the per-message
        // arrays. Cheap because metadata.json is small.
        if let messages = dict["messages"] as? [[String: Any]] {
            stats.attachmentCount = messages.reduce(0) { acc, m in
                acc + ((m["attachments"] as? [Any])?.count ?? 0)
            }
        }
        return stats
    }

    /// Walk every regular file under `folder`, summing byte sizes. Cheap
    /// for a typical run (a few thousand files) and avoids spawning `du`.
    static func computeOutputBytes(folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true,
               let size = values?.totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Format `outputBytes` as e.g. "2.4 GB" / "317 MB" / "—".
    static func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    /// Format the configured span as "16d" / "3h" / "—".
    static func formatSpan(start: Date?, end: Date?) -> String {
        guard let start, let end, end > start else { return "—" }
        let interval = end.timeIntervalSince(start)
        let days = Int((interval / 86400).rounded())
        if days >= 1 { return "\(days)d" }
        let hours = Int((interval / 3600).rounded())
        if hours >= 1 { return "\(hours)h" }
        let minutes = max(1, Int((interval / 60).rounded()))
        return "\(minutes)m"
    }

    /// Format `start → end` as "Apr 26 → May 8" / "—".
    static func formatSpanCaption(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: start)) → \(f.string(from: end))"
    }

    /// Format an integer with grouping separators ("4,812"). Returns "—"
    /// for nil so we never render a 0 placeholder where the real value is
    /// just unknown.
    static func formatInt(_ n: Int?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
