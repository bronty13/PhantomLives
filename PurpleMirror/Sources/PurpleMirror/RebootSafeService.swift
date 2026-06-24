import Foundation

/// The GUI equivalent of the `reboot-safe` CLI: unmount every external drive,
/// then restart. macOS Tahoe 26 hangs shutdown when `diskarbitrationd` tries to
/// unmount a *mounted* external volume (it wedges in-kernel in
/// `unmount()`→`vnode_iterate` while Spotlight/`revisiond` hold vnodes; SIGKILL
/// can't interrupt an in-kernel wait → hard power-off). Unmounting every external
/// volume first removes the thing it hangs on. See `docs/reboot-hangs.md`.
///
/// We only ever *graceful*-unmount (never force) so client media is never put at
/// risk — if a volume is busy we abort and report it rather than restart into a
/// hang or yank a drive mid-write.
enum RebootSafeService {

    struct EjectOutcome {
        /// True when no external volume remains mounted.
        var ok: Bool
        /// Names of external volumes that refused to unmount (something is using them).
        var stillMounted: [String]
    }

    // MARK: - Pure parsers (unit-tested; no process execution)

    /// Physical external disk identifiers from `diskutil list external physical`.
    /// Lines look like: `/dev/disk6 (external, physical):`
    static func parseExternalDisks(_ diskutilOutput: String) -> [String] {
        diskutilOutput.split(separator: "\n").compactMap { line in
            guard line.contains("(external, physical)"),
                  let dev = line.split(separator: " ").first,
                  dev.hasPrefix("/dev/") else { return nil }
            return String(dev.dropFirst("/dev/".count))
        }
    }

    /// External volume names (mounted under `/Volumes/`) from `mount` output.
    /// A line looks like: `/dev/disk7s1 on /Volumes/PRO-G40 (apfs, local, …)`
    /// Handles volume names containing spaces by reading up to the ` (` that
    /// precedes the mount-options list.
    static func parseMountedExternalVolumes(_ mountOutput: String) -> [String] {
        let marker = " on /Volumes/"
        return mountOutput.split(separator: "\n").compactMap { line -> String? in
            guard let r = line.range(of: marker) else { return nil }
            let after = line[r.upperBound...]
            guard let optsParen = after.range(of: " (") else { return String(after) }
            return String(after[..<optsParen.lowerBound])
        }
    }

    // MARK: - Live operations

    static func externalDisks() async -> [String] {
        let (_, out) = await JobController.run("/usr/sbin/diskutil", ["list", "external", "physical"])
        return parseExternalDisks(out)
    }

    static func mountedExternalVolumes() async -> [String] {
        let (_, out) = await JobController.run("/sbin/mount", [])
        return parseMountedExternalVolumes(out)
    }

    /// Graceful-unmount every external disk's volumes, then report whether any
    /// external volume is still mounted (busy).
    static func ejectAll() async -> EjectOutcome {
        for disk in await externalDisks() {
            _ = await JobController.run("/usr/sbin/diskutil", ["unmountDisk", "/dev/\(disk)"])
        }
        let remaining = await mountedExternalVolumes()
        return EjectOutcome(ok: remaining.isEmpty, stillMounted: remaining)
    }

    /// Begin a normal restart (same path as the Apple-menu Restart) via System
    /// Events. Returns false if the Apple event failed (e.g. Automation not yet
    /// granted), so the caller can fall back to telling the user to restart by hand.
    @discardableResult
    static func restart() async -> Bool {
        let (status, _) = await JobController.run(
            "/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"])
        return status == 0
    }
}
