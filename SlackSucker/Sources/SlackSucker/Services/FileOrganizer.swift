import Foundation
import AVFoundation
import ImageIO
import CoreGraphics

/// Post-process a completed slackdump archive folder by sorting
/// `__uploads/<FILE_ID>/<name>` attachments into media-category
/// subdirectories at the run-folder root.
///
/// Resulting layout:
///
///     <RunFolder>/
///     ├── slackdump.sqlite        (untouched)
///     ├── archive.log             (slackdump stdout)
///     ├── organize-log.txt        (this service's summary)
///     ├── Videos/<file>
///     ├── Photos/<file>
///     ├── Audio/<file>
///     └── Other/<file>
///
/// `__avatars/` (user profile thumbnails) is intentionally left in
/// place — those aren't user-shared content, just identicons, and
/// dropping them in `Photos/` would pollute the gallery view a user
/// of this feature is probably aiming for.
///
/// The service never deletes files — only moves them. On collision it
/// renames the incoming file with a `(<FILE_ID>)` suffix instead of
/// overwriting.
enum FileOrganizer {

    enum Category: String, CaseIterable {
        case videos = "Videos"
        case photos = "Photos"
        case audio  = "Audio"
        case other  = "Other"

        /// Conservative-by-design: only widely-recognised extensions
        /// land in the three media buckets; anything unknown (PDFs,
        /// docs, archives, snippets, transcripts) goes to `Other`.
        static let videoExts: Set<String> = [
            "mp4","mov","m4v","avi","mkv","webm","wmv","flv","mpg","mpeg","3gp","ts"
        ]
        static let photoExts: Set<String> = [
            "jpg","jpeg","png","gif","heic","heif","webp","bmp","tiff","tif","svg","avif"
        ]
        static let audioExts: Set<String> = [
            "mp3","m4a","wav","ogg","flac","aac","wma","aiff","aif","opus","amr"
        ]

        static func classify(extension ext: String) -> Category {
            let lower = ext.lowercased()
            if videoExts.contains(lower) { return .videos }
            if photoExts.contains(lower) { return .photos }
            if audioExts.contains(lower) { return .audio }
            return .other
        }
    }

    struct Result: Equatable {
        var moved: [String: Int] = [:]   // category name → count
        var collisions: Int = 0
        var prefixedCount: Int = 0       // count with NNNN_ prefix applied
        var errors: [String] = []

        var totalMoved: Int { moved.values.reduce(0, +) }
    }

    /// Move every file in `__uploads/<ID>/<name>` to
    /// `<RunFolder>/<Category>/<name>`. Removes the now-empty
    /// `__uploads` tree. No-op when `__uploads` doesn't exist.
    ///
    /// `ordering` controls whether files get a per-category
    /// `0001_, 0002_, …` prefix, and what signal drives the ordering:
    ///
    ///   - `.messageTimestamp` — query slackdump.sqlite for the parent
    ///     message TS of every FILE_ID, sort uploads chronologically
    ///     (within-message ties on `FILE.IDX`). Files with no SQLite
    ///     row sort last in FILE_ID order — predictable across re-runs.
    ///   - `.fileCreated` — read each file's on-disk creation date
    ///     (`URLResourceKey.creationDateKey`, ms precision) and sort
    ///     by that. No SQLite dependency. Reflects when slackdump
    ///     wrote the file during download, not the original Slack
    ///     upload time.
    ///   - `.none` — no prefix; original filenames preserved.
    ///
    /// Idempotent: re-running on an already-organized folder is safe
    /// (the `__uploads` directory will have been deleted on the first
    /// pass, so the second pass returns an empty Result).
    @discardableResult
    static func organize(runFolder: URL, ordering: FileOrdering = .none) -> Result {
        var result = Result()
        let fm = FileManager.default
        let uploadsDir = runFolder.appendingPathComponent("__uploads", isDirectory: true)
        guard fm.fileExists(atPath: uploadsDir.path) else { return result }

        // Walk __uploads/<FILE_ID>/<name> into a flat work list. Each
        // entry knows its FILE_ID (the parent dir name) and its on-disk
        // URL — that's everything we need to classify + (optionally)
        // prefix during the move.
        struct Pending {
            var fileID: String
            var sourceURL: URL
            var originalName: String
            var category: Category
        }
        var pending: [Pending] = []
        let fileIDDirs = (try? fm.contentsOfDirectory(
            at: uploadsDir,
            includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for idDir in fileIDDirs {
            let isDir = (try? idDir.resourceValues(forKeys: [.isDirectoryKey])
                                   .isDirectory) ?? false
            guard isDir else { continue }
            let fileID = idDir.lastPathComponent
            let inner = (try? fm.contentsOfDirectory(
                at: idDir, includingPropertiesForKeys: nil)) ?? []
            for url in inner {
                let name = url.lastPathComponent
                pending.append(Pending(
                    fileID: fileID,
                    sourceURL: url,
                    originalName: name,
                    category: Category.classify(extension: url.pathExtension)
                ))
            }
        }

        // Build the ordering only when the caller asked for it. Each
        // strategy has different inputs:
        //   .messageTimestamp → one sqlite3 process spawn + JSON parse
        //   .captureDate      → EXIF / AVAsset read per file, with a
        //                       Slack-upload-TS fallback that rescues
        //                       files whose EXIF was stripped on upload
        //   .none             → skip entirely
        let prefixByOrder = (ordering != .none)
        if prefixByOrder {
            let keys: [String: OrderKey]
            switch ordering {
            case .messageTimestamp:
                keys = chronologicalOrdering(
                    sqliteURL: runFolder.appendingPathComponent("slackdump.sqlite"))
            case .captureDate:
                var merged = captureDateOrdering(pending.map { ($0.fileID, $0.sourceURL) })
                // Slack upload TS is always present in the SQLite — it
                // rescues files with no EXIF (iOS / Slack web strip on
                // upload) and gives them a sensible chronological slot.
                let uploads = slackUploadOrdering(
                    sqliteURL: runFolder.appendingPathComponent("slackdump.sqlite"))
                for (fileID, key) in uploads where merged[fileID] == nil {
                    merged[fileID] = key
                }
                keys = merged
            case .none:
                keys = [:]  // unreachable
            }
            // FILE_IDs missing from the lookup get a sentinel that sorts
            // them last but stably (by lexical FILE_ID), so canvas files
            // / unreadable creation dates / unjoined rows still land
            // predictably across re-runs.
            pending.sort { a, b in
                let ka = keys[a.fileID] ?? OrderKey(ts: .greatestFiniteMagnitude, idx: 0, fileID: a.fileID)
                let kb = keys[b.fileID] ?? OrderKey(ts: .greatestFiniteMagnitude, idx: 0, fileID: b.fileID)
                if ka.ts != kb.ts { return ka.ts < kb.ts }
                if ka.idx != kb.idx { return ka.idx < kb.idx }
                return ka.fileID < kb.fileID
            }
        }

        // Per-category running ordinal. Reset to 1 for each category so
        // a user browsing `Photos/` sees 0001…N regardless of how many
        // videos / audio files came in earlier.
        var perCategoryCounter: [Category: Int] = [:]
        // Width of the prefix. Default 4 ("0001"). If a single
        // category has more files than fits 4 digits, the format
        // accommodates: 5 digits at 10k, 6 at 100k, etc.
        let categoryTotals = Dictionary(grouping: pending, by: { $0.category })
            .mapValues { $0.count }
        let prefixWidth: (Category) -> Int = { cat in
            let n = categoryTotals[cat] ?? 0
            return max(4, String(n).count)
        }

        for p in pending {
            let categoryDir = runFolder.appendingPathComponent(p.category.rawValue, isDirectory: true)
            do {
                try fm.createDirectory(at: categoryDir, withIntermediateDirectories: true)
            } catch {
                result.errors.append("create \(p.category.rawValue)/: \(error.localizedDescription)")
                continue
            }

            // Compose destination filename. Prefix on, then collision
            // suffix as a final layer if even the prefix didn't make
            // the name unique (it should — counter is monotonic).
            var destName: String
            if prefixByOrder {
                let n = (perCategoryCounter[p.category] ?? 0) + 1
                perCategoryCounter[p.category] = n
                let width = prefixWidth(p.category)
                let prefix = String(format: "%0\(width)d", n)
                destName = "\(prefix)_\(p.originalName)"
                result.prefixedCount += 1
            } else {
                destName = p.originalName
            }

            var dest = categoryDir.appendingPathComponent(destName)
            if fm.fileExists(atPath: dest.path) {
                // Disambiguate with the Slack file-ID rather than a
                // running counter — IDs are globally unique inside a
                // workspace, so re-running won't double-suffix.
                let base = (destName as NSString).deletingPathExtension
                let extPart = (destName as NSString).pathExtension
                let disambiguated = extPart.isEmpty
                    ? "\(base) (\(p.fileID))"
                    : "\(base) (\(p.fileID)).\(extPart)"
                dest = categoryDir.appendingPathComponent(disambiguated)
                result.collisions += 1
            }

            do {
                try fm.moveItem(at: p.sourceURL, to: dest)
                result.moved[p.category.rawValue, default: 0] += 1
            } catch {
                result.errors.append("\(p.originalName): \(error.localizedDescription)")
            }
        }

        // Sweep the now-empty __uploads/<FILE_ID>/ dirs. Leave any dir
        // with stragglers in place so the user can rerun and see what
        // got stranded.
        for idDir in fileIDDirs {
            let isDir = (try? idDir.resourceValues(forKeys: [.isDirectoryKey])
                                   .isDirectory) ?? false
            guard isDir else { continue }
            let remaining = (try? fm.contentsOfDirectory(at: idDir,
                                                        includingPropertiesForKeys: nil))?.count ?? 0
            if remaining == 0 { try? fm.removeItem(at: idDir) }
        }
        let stragglers = (try? fm.contentsOfDirectory(at: uploadsDir,
                                                     includingPropertiesForKeys: nil))?.count ?? 0
        if stragglers == 0 { try? fm.removeItem(at: uploadsDir) }

        writeSummary(runFolder: runFolder, result: result, prefixByOrder: prefixByOrder, ordering: ordering)
        return result
    }

    // MARK: - Chronological ordering

    /// One FILE_ID's position in the channel timeline. `ts` is the
    /// parent message TS (seconds since epoch as a Double; SQLite's
    /// TS column is text but always numeric in practice). `.greatest`
    /// is the sentinel for "no parent message found" — those rows
    /// sort to the end.
    struct OrderKey {
        var ts: Double
        var idx: Int
        var fileID: String
    }

    /// Read the **capture date** baked into each file:
    ///   - Photos: EXIF `DateTimeOriginal` (+ `SubSecTimeOriginal` for
    ///     ms precision) via `CGImageSource`
    ///   - Videos: QuickTime `creationDate` common metadata via
    ///     `AVAsset.commonMetadata`
    ///   - Anything else: nil (audio + "Other" land in the fallback)
    ///
    /// Returns only files where a capture date was found. Files with
    /// no embedded date are intentionally absent — the caller fills
    /// the gap from the Slack upload TS (`slackUploadOrdering`).
    ///
    /// IMPORTANT: this is the **original capture time** (camera shutter
    /// click / recording start), NOT the on-disk creation time. The
    /// difference matters: every file in a single slackdump run has
    /// roughly the same on-disk birthtime, so ordering by birthtime
    /// is useless. EXIF/QuickTime metadata is what humans actually
    /// expect when they say "in the order I took these photos."
    nonisolated static func captureDateOrdering(_ items: [(fileID: String, url: URL)]) -> [String: OrderKey] {
        var out: [String: OrderKey] = [:]
        out.reserveCapacity(items.count)
        for (fileID, url) in items {
            if let date = captureDate(at: url) {
                out[fileID] = OrderKey(
                    ts: date.timeIntervalSince1970,
                    idx: 0,
                    fileID: fileID
                )
            }
        }
        return out
    }

    /// Type-switch on file extension and dispatch to the right reader.
    nonisolated static func captureDate(at url: URL) -> Date? {
        let ext = url.pathExtension.lowercased()
        if Category.photoExts.contains(ext) { return photoExifDate(at: url) }
        if Category.videoExts.contains(ext) { return videoCreationDate(at: url) }
        return nil
    }

    /// EXIF `DateTimeOriginal` + optional `SubSecTimeOriginal` for
    /// ms precision. Returns nil when either the file isn't decodable
    /// or the tag isn't present (screenshots, edited copies, and
    /// Slack-uploaded photos often have EXIF stripped).
    nonisolated private static func photoExifDate(at url: URL) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dt = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              let date = Self.exifFormatter.date(from: dt)
        else { return nil }
        if let subsec = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String,
           let frac = Double("0.\(subsec)") {
            return date.addingTimeInterval(frac)
        }
        return date
    }

    /// QuickTime `creationDate` common metadata. AVURLAsset's
    /// synchronous `commonMetadata` accessor is deprecated in
    /// macOS 12+ but still works on 14+/26+ and saves an async hop
    /// per file in the organize hot path. We deliberately keep this
    /// synchronous; if Apple removes the API we can switch to
    /// `await asset.load(.commonMetadata)`.
    nonisolated private static func videoCreationDate(at url: URL) -> Date? {
        let asset = AVURLAsset(url: url)
        // `commonMetadata` on macOS 14+ is still synchronous and the
        // QuickTime creation-date item carries a Date value directly.
        for item in asset.commonMetadata where item.commonKey == .commonKeyCreationDate {
            if let date = item.dateValue { return date }
            // Some encoders write the value as an ISO 8601 string
            // instead of a Date. Parse defensively.
            if let s = item.stringValue,
               let date = Self.iso8601Formatter.date(from: s) {
                return date
            }
        }
        return nil
    }

    /// EXIF `DateTimeOriginal` is `"YYYY:MM:DD HH:MM:SS"` in camera
    /// local time with no timezone field. We treat it as the system's
    /// current local time — best effort, since some cameras embed
    /// timezone offset separately in GPS metadata we don't read.
    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()

    /// Fallback for QuickTime metadata that stores creation date as
    /// an ISO 8601 string instead of a Date.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Slack-side upload timestamp from `FILE.DATA.created` for every
    /// distinct FILE row. Unlike message TS, this is *always* present
    /// in slackdump's archive — Slack assigns it server-side at
    /// upload time. Used as the fallback layer under capture-date
    /// ordering when a file has no embedded EXIF/QuickTime metadata.
    nonisolated static func slackUploadOrdering(sqliteURL: URL) -> [String: OrderKey] {
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else { return [:] }
        let query = """
        SELECT f.ID AS id,
               MIN(CAST(json_extract(CAST(f.DATA AS TEXT), '$.created') AS REAL)) AS ts
        FROM FILE f
        GROUP BY f.ID;
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-json", "-readonly", sqliteURL.path, query]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [:] }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [:] }
        struct Row: Decodable { let id: String; let ts: Double? }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [:] }
        var result: [String: OrderKey] = [:]
        result.reserveCapacity(rows.count)
        for row in rows {
            result[row.id] = OrderKey(
                ts: row.ts ?? .greatestFiniteMagnitude,
                idx: 0,
                fileID: row.id
            )
        }
        return result
    }

    /// Shells to `/usr/bin/sqlite3 -json` to grab `(FILE_ID, ts, idx)`
    /// for every distinct FILE row, joined to its parent MESSAGE for
    /// the TS. Returns `[:]` on any failure — caller falls back to
    /// "no prefix" behavior, never blocks the move pass.
    nonisolated static func chronologicalOrdering(sqliteURL: URL) -> [String: OrderKey] {
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else { return [:] }
        let query = """
        SELECT f.ID AS id, MIN(CAST(m.TS AS REAL)) AS ts, MIN(f.IDX) AS idx
        FROM FILE f
        LEFT JOIN MESSAGE m ON f.MESSAGE_ID = m.ID
        GROUP BY f.ID;
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-json", "-readonly", sqliteURL.path, query]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [:] }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [:] }

        struct Row: Decodable { let id: String; let ts: Double?; let idx: Int? }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [:] }
        var result: [String: OrderKey] = [:]
        result.reserveCapacity(rows.count)
        for row in rows {
            result[row.id] = OrderKey(
                ts: row.ts ?? .greatestFiniteMagnitude,
                idx: row.idx ?? 0,
                fileID: row.id
            )
        }
        return result
    }

    /// Write a human-readable summary of the reorg into
    /// `<RunFolder>/organize-log.txt`. Non-fatal on write failure.
    private static func writeSummary(runFolder: URL, result: Result, prefixByOrder: Bool, ordering: FileOrdering = .none) {
        var lines: [String] = []
        lines.append("SlackSucker file-organization summary")
        lines.append("Run folder: \(runFolder.lastPathComponent)")
        lines.append("Ordering: \(ordering.label)")
        lines.append("")
        for cat in Category.allCases {
            lines.append("\(cat.rawValue): \(result.moved[cat.rawValue] ?? 0)")
        }
        lines.append("")
        lines.append("Total files moved: \(result.totalMoved)")
        if prefixByOrder {
            lines.append("Files prefixed with sequence number: \(result.prefixedCount)")
        }
        if result.collisions > 0 {
            lines.append("Filename collisions auto-renamed with file-ID suffix: \(result.collisions)")
        }
        if !result.errors.isEmpty {
            lines.append("")
            lines.append("Errors:")
            for e in result.errors { lines.append("  - \(e)") }
        }
        let logURL = runFolder.appendingPathComponent("organize-log.txt")
        try? lines.joined(separator: "\n").appending("\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }
}
