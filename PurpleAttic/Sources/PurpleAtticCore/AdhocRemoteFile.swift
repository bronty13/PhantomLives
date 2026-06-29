import Foundation

/// One object in the ad-hoc B2 store as reported by `rclone lsjson` against the **crypt** remote —
/// so `path`/`name` are already *decrypted* (rclone transparently decrypts when listing through the
/// crypt overlay; only the raw B2 console shows scrambled names) and `size` is the plaintext size.
public struct AdhocRemoteFile: Sendable, Equatable {
    public var path: String          // decrypted path within the store, e.g. "Invoices/2026-Q2.pdf"
    public var name: String          // basename
    public var size: Int64           // plaintext bytes (-1 for directories per rclone)
    public var modTime: Date
    public var isDir: Bool
    public var mimeType: String?
    /// SHA-1 of the *encrypted* blob if present. Through crypt this is usually absent (rclone can't
    /// cheaply expose a plaintext checksum), which is why the diff feature compares size+modtime.
    public var sha1: String?
    public var id: String?           // underlying B2 file id
    public var tier: String?

    public init(path: String, name: String, size: Int64, modTime: Date, isDir: Bool,
                mimeType: String? = nil, sha1: String? = nil, id: String? = nil, tier: String? = nil) {
        self.path = path
        self.name = name
        self.size = size
        self.modTime = modTime
        self.isDir = isDir
        self.mimeType = mimeType
        self.sha1 = sha1
        self.id = id
        self.tier = tier
    }
}

/// One line of `rclone check --combined -` output: a change symbol plus a path. This is how the
/// "sync differences" feature detects what a one-way additive backup would upload.
public struct DiffEntry: Sendable, Equatable {
    public enum Change: String, Sendable, CaseIterable {
        case same        = "="   // identical on both sides
        case differ      = "*"   // present on both but different (would re-upload)
        case onlyLocal   = "+"   // in the local source, missing in B2 (would upload)
        case onlyRemote  = "-"   // only in B2 (suppressed by --one-way; here for completeness)
        case error       = "!"   // rclone could not compare this path
    }
    public var change: Change
    public var path: String

    public init(change: Change, path: String) {
        self.change = change
        self.path = path
    }

    /// Whether a one-way additive sync would act on this entry (upload new or changed files).
    public var needsUpload: Bool { change == .onlyLocal || change == .differ }
}

/// A point-in-time snapshot of an rclone transfer, parsed from a `--use-json-log --stats` line.
public struct RcloneProgress: Sendable, Equatable {
    public var bytes: Int64
    public var totalBytes: Int64
    public var transfers: Int
    public var totalTransfers: Int
    public var speed: Double          // bytes/sec
    public var eta: Double?           // seconds remaining, if rclone reported one

    public init(bytes: Int64, totalBytes: Int64, transfers: Int, totalTransfers: Int,
                speed: Double, eta: Double? = nil) {
        self.bytes = bytes
        self.totalBytes = totalBytes
        self.transfers = transfers
        self.totalTransfers = totalTransfers
        self.speed = speed
        self.eta = eta
    }

    /// 0…1 by bytes when a total is known (nil before rclone has scanned the size).
    public var fraction: Double? { totalBytes > 0 ? min(1.0, Double(bytes) / Double(totalBytes)) : nil }
}

/// Pure parsers for rclone output. Kept free of process/network so they can be unit-tested against
/// captured fixtures — the same discipline as `ResticService`'s argv/env builders.
public enum RcloneParse {

    /// Parse `rclone lsjson` output (a JSON array) into `AdhocRemoteFile`s. Tolerant: malformed
    /// input yields an empty array rather than throwing (a listing failure is surfaced by the op's
    /// exit code, not here).
    public static func lsjson(_ data: Data) -> [AdhocRemoteFile] {
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items.map { it in
            AdhocRemoteFile(
                path: it.Path,
                name: it.Name,
                size: it.Size ?? -1,
                modTime: rfc3339(it.ModTime) ?? Date(timeIntervalSince1970: 0),
                isDir: it.IsDir ?? false,
                mimeType: it.MimeType,
                sha1: it.Hashes?["SHA-1"],
                id: it.ID,
                tier: it.Tier)
        }
    }

    /// Parse `rclone check --combined -` output into `DiffEntry`s. Each line is "<symbol> <path>".
    public static func checkCombined(_ text: String) -> [DiffEntry] {
        var out: [DiffEntry] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            guard let first = line.first,
                  let change = DiffEntry.Change(rawValue: String(first)) else { continue }
            // Drop the symbol and the single separating space; the remainder is the path verbatim.
            var path = String(line.dropFirst())
            if path.hasPrefix(" ") { path.removeFirst() }
            guard !path.isEmpty else { continue }
            out.append(DiffEntry(change: change, path: path))
        }
        return out
    }

    /// Parse an RFC3339 timestamp as emitted by rclone, which includes up to **nanosecond**
    /// fractional seconds (e.g. "2026-06-28T21:00:00.123456789Z"). `ISO8601DateFormatter` only
    /// understands milliseconds, so we strip the fractional component (second precision is plenty
    /// for a browse cache; the diff feature relies on rclone's own live comparison, not this value).
    public static func rfc3339(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let dot = s.firstIndex(of: ".") else { return iso.date(from: s) }
        // Everything after the fractional digits is the timezone designator (Z or ±hh:mm).
        let afterDot = s[s.index(after: dot)...]
        if let tz = afterDot.firstIndex(where: { !$0.isNumber }) {
            return iso.date(from: String(s[..<dot]) + String(afterDot[tz...]))
        }
        return iso.date(from: String(s[..<dot]) + "Z")
    }

    /// Parse an rclone `--use-json-log` **stats** line into a `RcloneProgress`. Returns nil for any
    /// line that isn't a stats object (ordinary log entries, non-JSON), so a caller can fall back to
    /// `logMessage`.
    public static func progress(_ line: String) -> RcloneProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = obj["stats"] as? [String: Any] else { return nil }
        func i(_ k: String) -> Int64 { (stats[k] as? NSNumber)?.int64Value ?? 0 }
        func d(_ k: String) -> Double { (stats[k] as? NSNumber)?.doubleValue ?? 0 }
        return RcloneProgress(
            bytes: i("bytes"), totalBytes: i("totalBytes"),
            transfers: Int(i("transfers")), totalTransfers: Int(i("totalTransfers")),
            speed: d("speed"), eta: (stats["eta"] as? NSNumber)?.doubleValue)
    }

    /// Extract a human-readable message from an rclone log line for the UI log tail: the `msg` of a
    /// JSON log entry (skipping stats lines, which `progress` handles), or the raw line if it isn't
    /// JSON (e.g. an op's own "→ backing up …" header). nil for blank/stats-only lines.
    public static func logMessage(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed
        }
        if obj["stats"] != nil { return nil }
        return (obj["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Internal DTO mirroring rclone lsjson keys (capitalized to match the JSON exactly).
    private struct Item: Decodable {
        let Path: String
        let Name: String
        let Size: Int64?
        let ModTime: String
        let IsDir: Bool?
        let MimeType: String?
        let ID: String?
        let Tier: String?
        let Hashes: [String: String]?
    }
}
