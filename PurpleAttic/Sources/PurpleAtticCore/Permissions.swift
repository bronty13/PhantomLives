import Foundation

/// Full Disk Access probe shared by the GUI's permission preflight and the `pattic doctor`
/// command. We can't query TCC directly, so we probe a path that is **only** readable with
/// Full Disk Access: the Photos library bundle's internals (the `.photoslibrary` package is
/// TCC-protected — a plain Photos-library *authorization* grants PhotoKit API access, not raw
/// file access). If we can list the library's `database/` directory, FDA is effectively in
/// place for this process (and, because a spawned child inherits the responsible process's
/// TCC grants, for the osxphotos/exiftool subprocesses it launches).
public enum Permissions {

    /// Best-effort: is Full Disk Access granted to this process? Probes the configured
    /// library (or the System Photo Library) first, then falls back to the user TCC database.
    public static func fullDiskAccessLikely(libraryPath: String? = nil) -> Bool {
        let lib = LibraryInspector.resolveLibraryPath(libraryPath)
        let dbDir = (lib as NSString).appendingPathComponent("database")
        if (try? FileManager.default.contentsOfDirectory(atPath: dbDir)) != nil { return true }
        // Library absent (e.g. headless test box)? Fall back to the canonical FDA probe.
        let tcc = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        if FileManager.default.fileExists(atPath: tcc) {
            return FileManager.default.isReadableFile(atPath: tcc)
        }
        return false
    }
}
