import Foundation

/// Guards against the footgun where a destination drive isn't mounted: the archive base path
/// (e.g. `/Volumes/ROG_WHITE`) doesn't exist, so a naive `createDirectory(…, intermediates:
/// true)` would silently create it **on the boot disk** and rsync hundreds of GB there. We
/// require a destination base to already exist AND — for a `/Volumes/*` path — to be on a
/// genuinely separate mounted volume (not a leftover stub directory on the system disk).
public enum VolumeReadiness {

    /// Is `path` on a different filesystem device than the root volume `/`? A real mounted
    /// external drive is; a stub directory left under `/Volumes` on the boot disk is not.
    public static func isOnSeparateVolume(_ path: String) -> Bool {
        var here = stat(), root = stat()
        guard stat(path, &here) == 0, stat("/", &root) == 0 else { return false }
        return here.st_dev != root.st_dev
    }

    /// Whether a destination *base* (volume/folder the archive subfolder is nested under) is
    /// ready to receive a copy, with a human reason when it isn't. Empty → not ready. A path
    /// under `/Volumes/` must exist *and* be a separate mounted volume; anywhere else, simply
    /// existing as a directory is enough (the user deliberately chose a boot-disk folder).
    public static func destinationReady(_ base: String) -> (ready: Bool, reason: String?) {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (false, "no path set") }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) && isDir.boolValue

        if trimmed.hasPrefix("/Volumes/") {
            // The mount point is /Volumes/<name>; check that, not a deeper subpath.
            let comps = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            let mount = comps.count >= 2 ? "/Volumes/\(comps[1])" : trimmed
            var mIsDir: ObjCBool = false
            let mExists = FileManager.default.fileExists(atPath: mount, isDirectory: &mIsDir) && mIsDir.boolValue
            if !mExists || !isOnSeparateVolume(mount) {
                return (false, "drive not mounted at \(mount) — skipping to avoid writing to the boot disk")
            }
            return (true, nil)
        }

        return exists ? (true, nil) : (false, "does not exist: \(trimmed)")
    }
}
