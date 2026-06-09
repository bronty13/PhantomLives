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
    /// Total assets from the library database, or nil if it couldn't be read.
    public let totalAssets: Int?
    /// False when the library bundle couldn't be read (missing, or Full Disk Access not granted).
    public let readable: Bool

    public init(libraryPath: String, exists: Bool, originalsOnDisk: Int, totalAssets: Int?, readable: Bool) {
        self.libraryPath = libraryPath
        self.exists = exists
        self.originalsOnDisk = originalsOnDisk
        self.totalAssets = totalAssets
        self.readable = readable
    }

    /// True when we have a reliable asset count AND most originals are absent.
    public var optimizeStorageLikely: Bool {
        guard let total = totalAssets, total > 0 else { return false }
        return LibraryInspector.isLikelyOptimized(originalsOnDisk: originalsOnDisk, totalAssets: total)
    }

    /// One-line human summary for the UI / log.
    public var summary: String {
        if !exists { return "Library not found at \(libraryPath)." }
        if !readable { return "Can't read the library (grant Full Disk Access to enable the completeness check)." }
        if let total = totalAssets {
            if optimizeStorageLikely {
                return "⚠︎ Optimize Storage likely — \(originalsOnDisk) of \(total) originals on disk. Archiving now would be INCOMPLETE."
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
                                     totalAssets: nil, readable: false)
        }
        let originalsDir = (lib as NSString).appendingPathComponent("originals")
        let (count, readable) = countOriginals(originalsDir)
        let total = readAssetCount((lib as NSString).appendingPathComponent("database/Photos.sqlite"))
        return LibraryInspection(libraryPath: lib, exists: true, originalsOnDisk: count,
                                 totalAssets: total, readable: readable)
    }

    // MARK: - Internals

    /// Count regular files under the originals tree. `readable` is false when the directory
    /// can't be listed (TCC / Full Disk Access not granted, or no such folder).
    static func countOriginals(_ dir: String) -> (count: Int, readable: Bool) {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: dir)) != nil else {
            return (0, false)
        }
        var count = 0
        let url = URL(fileURLWithPath: dir)
        if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                  options: [.skipsHiddenFiles]) {
            for case let f as URL in en {
                if (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    count += 1
                }
            }
        }
        return (count, true)
    }

    /// Best-effort `SELECT COUNT(*) FROM ZASSET` against the live Photos database, opened
    /// read-only + immutable (so an open Photos.app / WAL doesn't block us). Returns nil on
    /// any failure (missing file, permission, schema change).
    static func readAssetCount(_ dbPath: String) -> Int? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        var db: OpaquePointer?
        let uri = "file:\(dbPath)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZASSET", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : nil
    }
}
