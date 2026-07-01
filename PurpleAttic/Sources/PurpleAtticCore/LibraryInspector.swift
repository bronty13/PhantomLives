import Foundation
import SQLite3

/// The result of inspecting a Photos library for archival readiness — specifically whether
/// the **originals are actually on disk** or the library is in "Optimize Mac Storage" mode
/// (most originals live only in iCloud). Archiving an optimized library captures only the
/// local subset and silently produces an INCOMPLETE archive — the exact footgun of running
/// on the wrong Mac. This lets the UI warn loudly before a real run.
public struct LibraryInspection: Sendable {
    public let libraryPath: String
    public let exists: Bool
    /// Count of master files under `<library>/originals/`. 0 when unreadable.
    public let originalsOnDisk: Int
    /// Total bytes of the master files under `<library>/originals/`. 0 when unreadable.
    /// Used to estimate the archive's on-disk footprint for the free-space sanity check.
    public let originalsBytes: Int64
    /// Total assets from the library database, or nil if it couldn't be read.
    public let totalAssets: Int?
    /// False when the library bundle couldn't be read (missing, or Full Disk Access not granted).
    public let readable: Bool

    public init(libraryPath: String, exists: Bool, originalsOnDisk: Int, originalsBytes: Int64 = 0,
                totalAssets: Int?, readable: Bool) {
        self.libraryPath = libraryPath
        self.exists = exists
        self.originalsOnDisk = originalsOnDisk
        self.originalsBytes = originalsBytes
        self.totalAssets = totalAssets
        self.readable = readable
    }

    /// True when we have a reliable asset count AND notably fewer originals are on disk than
    /// assets. This is a **fact about local files**, NOT a claim about the Photos storage setting:
    /// it can't tell "Optimize Mac Storage" from "Download Originals, still downloading" — both
    /// look identical on disk. So it's surfaced as neutral info, never an alarm or a run blocker.
    public var originalsIncomplete: Bool {
        guard let total = totalAssets, total > 0 else { return false }
        return LibraryInspector.isLikelyOptimized(originalsOnDisk: originalsOnDisk, totalAssets: total)
    }

    /// One-line human summary for the UI / log.
    public var summary: String {
        if !exists { return "Library not found at \(libraryPath)." }
        if !readable { return "Can't read the library (grant Full Disk Access to enable the completeness check)." }
        if let total = totalAssets {
            if originalsIncomplete {
                return "\(originalsOnDisk) of \(total) originals on disk — the rest are in iCloud (still downloading, or Optimize Mac Storage). Archiving now captures the local ones; re-run after they finish for full coverage."
            }
            return "\(originalsOnDisk) originals on disk for \(total) assets — looks fully downloaded."
        }
        return "\(originalsOnDisk) originals on disk (asset count unavailable)."
    }
}

public enum LibraryInspector {

    /// Resolve an explicit path, or fall back to the default System Photo Library location.
    public static func resolveLibraryPath(_ explicit: String?) -> String {
        if let p = explicit, !p.trimmingCharacters(in: .whitespaces).isEmpty { return p }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Photos Library.photoslibrary").path
    }

    /// Pure threshold so the decision is unit-testable. "Most" originals missing = optimized.
    /// A fully-downloaded library has originalsOnDisk ≈ (often ≥) totalAssets; an optimized
    /// one has far fewer. The 0.9 line leaves margin for edited/duplicate resource layout.
    public static func isLikelyOptimized(originalsOnDisk: Int, totalAssets: Int) -> Bool {
        totalAssets > 0 && Double(originalsOnDisk) < Double(totalAssets) * 0.9
    }

    /// Inspect the library at `explicit` (or the System Photo Library when nil). Filesystem +
    /// SQLite reads are best-effort; on permission failure the result is marked unreadable
    /// rather than throwing.
    public static func inspect(libraryPath explicit: String?) -> LibraryInspection {
        let lib = resolveLibraryPath(explicit)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: lib, isDirectory: &isDir) && isDir.boolValue
        guard exists else {
            return LibraryInspection(libraryPath: lib, exists: false, originalsOnDisk: 0,
                                     originalsBytes: 0, totalAssets: nil, readable: false)
        }
        let originalsDir = (lib as NSString).appendingPathComponent("originals")
        let (count, bytes, readable) = countOriginals(originalsDir)
        let total = readAssetCount((lib as NSString).appendingPathComponent("database/Photos.sqlite"))
        return LibraryInspection(libraryPath: lib, exists: true, originalsOnDisk: count,
                                 originalsBytes: bytes, totalAssets: total, readable: readable)
    }

    // MARK: - Internals

    /// Count regular files (and sum their bytes) under the originals tree. `readable` is
    /// false when the directory can't be listed (TCC / Full Disk Access not granted, or no
    /// such folder).
    static func countOriginals(_ dir: String) -> (count: Int, bytes: Int64, readable: Bool) {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: dir)) != nil else {
            return (0, 0, false)
        }
        var count = 0
        var bytes: Int64 = 0
        let url = URL(fileURLWithPath: dir)
        if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                  options: [.skipsHiddenFiles]) {
            for case let f as URL in en {
                guard let vals = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      vals.isRegularFile == true else { continue }
                count += 1
                bytes += Int64(vals.fileSize ?? 0)
            }
        }
        return (count, bytes, true)
    }

    /// Count of the user's **own, archivable** library assets — the right denominator for the
    /// originals-on-disk completeness check. A plain `COUNT(*) FROM ZASSET` overcounts: it
    /// includes trashed rows and, crucially, **"Shared with You" / syndicated** assets
    /// (`ZVISIBILITYSTATE != 0`) that aren't your originals, are excluded from the archive
    /// (`excludeSharedAndSyndicated`), and legitimately have no local master because
    /// "Download Originals to this Mac" never fetches them. Counting those guaranteed a false
    /// "Optimize Storage likely — archiving would be INCOMPLETE" on any Mac with shared content.
    /// We therefore count only **visible, non-trashed** assets (`ZVISIBILITYSTATE = 0 AND
    /// ZTRASHEDSTATE = 0`), which matches osxphotos' `--not-shared` set within a row.
    ///
    /// Opened read-only + immutable (so an open Photos.app / WAL doesn't block us). Returns nil
    /// on any failure (missing file, permission). If the visibility/trashed columns are absent
    /// (older/newer schema), falls back to a plain `COUNT(*)` rather than giving up.
    static func readAssetCount(_ dbPath: String) -> Int? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        var db: OpaquePointer?
        let uri = "file:\(dbPath)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        // Preferred: the user's own visible, non-trashed library. Fall back to a raw count if
        // those columns don't exist on this Photos schema version.
        return scalarCount(db, "SELECT COUNT(*) FROM ZASSET WHERE ZVISIBILITYSTATE = 0 AND ZTRASHEDSTATE = 0")
            ?? scalarCount(db, "SELECT COUNT(*) FROM ZASSET")
    }

    /// Run a single `SELECT COUNT(...)` and return the integer, or nil if the statement won't
    /// prepare (e.g. a referenced column is missing on this schema).
    private static func scalarCount(_ db: OpaquePointer?, _ sql: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : nil
    }
}
