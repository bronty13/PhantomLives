import Foundation

/// A free-space sanity check for the archive destinations. This is a **warning aid**, not a
/// gate — the estimate is deliberately rough (osxphotos derivatives, sidecars, and the JPEG
/// pass don't have an exact a-priori size), so the UI surfaces it as advice rather than
/// blocking a run on it. The required estimate is derived from the live library's originals
/// footprint; free space is read per destination volume.
public enum FreeSpaceCheck {

    /// Estimated bytes the archive will occupy on **one** physical destination, given the
    /// library's originals footprint and which passes are enabled:
    ///  - originals pass ≈ the originals themselves (1×),
    ///  - JPEG pass ≈ ~0.5× (derivatives are typically smaller than HEIC/RAW originals).
    /// Plus a 10% slack for XMP sidecars and filesystem overhead. A coarse upper-ish bound.
    public static func estimatedRequiredBytes(originalsBytes: Int64, keepHEIC: Bool, keepJPEG: Bool) -> Int64 {
        guard originalsBytes > 0 else { return 0 }
        var raw = 0.0
        if keepHEIC { raw += Double(originalsBytes) }
        if keepJPEG { raw += Double(originalsBytes) * 0.5 }
        return Int64(raw * 1.10)
    }

    /// Available bytes on the volume containing `path` (the importable-usage figure macOS
    /// reports, which accounts for purgeable space). nil when the path isn't reachable
    /// (drive not mounted) — which the caller treats as "can't confirm enough space".
    public static func freeBytes(atVolumePath path: String) -> Int64? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        // Walk up to the nearest existing ancestor (the archive subfolder may not exist yet).
        var probe = url
        let fm = FileManager.default
        while !fm.fileExists(atPath: probe.path) {
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path { return nil }
            probe = parent
        }
        // Don't cross a mount boundary: if the only existing ancestor is "/Volumes" (or "/")
        // while the requested base was deeper, the target drive simply isn't mounted — report
        // "unmeasured" (nil) rather than the system volume's free space.
        if probe.path != url.path && (probe.path == "/Volumes" || probe.path == "/") {
            return nil
        }
        // Use statfs (what `df` uses): the only figure that's reliable across APFS/HFS *and*
        // macFUSE volumes like a mounted Cryptomator vault, where the URL
        // volumeAvailableCapacity* resource keys come back 0/absent and falsely look full.
        var info = statfs()
        if statfs(probe.path, &info) == 0 {
            return Int64(info.f_bavail) * Int64(info.f_bsize)
        }
        // Last-resort fallback to the Foundation key (APFS/HFS only).
        if let vals = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let cap = vals.volumeAvailableCapacity {
            return Int64(cap)
        }
        return nil
    }

    /// Free space and sufficiency for one destination.
    public struct DestinationSpace: Sendable, Identifiable {
        public let label: String        // "Primary", "Mirror 1", "Cloud vault"
        public let base: String         // the chosen base path
        public let freeBytes: Int64?    // nil = couldn't measure (not mounted)
        public let requiredBytes: Int64
        public var id: String { label }
        /// True only when we measured free space AND it covers the estimate.
        public var sufficient: Bool {
            guard let free = freeBytes else { return false }
            return free >= requiredBytes
        }
        /// True when we couldn't even measure (drive not mounted / path unreachable).
        public var unmeasured: Bool { freeBytes == nil }
    }

    /// Evaluate every physical destination (primary + mirrors) plus the vault if configured.
    /// Mirrors/vault each need the same estimate as the primary (they hold a full copy).
    public static func evaluate(profile: ArchiveProfile, originalsBytes: Int64) -> [DestinationSpace] {
        let required = estimatedRequiredBytes(originalsBytes: originalsBytes,
                                              keepHEIC: profile.keepHEIC, keepJPEG: profile.keepJPEG)
        var out: [DestinationSpace] = []
        if !profile.primaryDestination.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(DestinationSpace(label: "Primary", base: profile.primaryDestination,
                                        freeBytes: freeBytes(atVolumePath: profile.primaryDestination),
                                        requiredBytes: required))
        }
        for (i, m) in profile.mirrorDestinations.enumerated()
        where !m.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(DestinationSpace(label: "Mirror \(i + 1)", base: m,
                                        freeBytes: freeBytes(atVolumePath: m),
                                        requiredBytes: required))
        }
        if let vault = profile.cloudVaultPath, !vault.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(DestinationSpace(label: "Cloud vault", base: vault,
                                        freeBytes: freeBytes(atVolumePath: vault),
                                        requiredBytes: required))
        }
        return out
    }

    /// Human-readable byte size (GB/TB), for the UI banner and reports.
    public static func humanBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
