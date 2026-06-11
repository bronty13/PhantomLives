import Foundation

/// A filename → set-of-sizes index of an archive's `originals/` tree, used to verify that a
/// purge candidate's file is present in the archive. Indexed by **filename + the on-disk byte
/// sizes** seen for that name, independent of the osxphotos folder template (no need to
/// reconstruct the dated path).
///
/// IMPORTANT — what the size is for: it is **NOT** compared against the photo's pre-export size
/// from Photos. The export runs `osxphotos --exiftool`, which writes metadata *into* every
/// exported file, so an archived original is legitimately a few hundred bytes **larger** than
/// the `original_filesize` Photos reports. (Incident 2026-06-11: the first real purge preview
/// verified only 368 of 66,279 because it matched the Photos size; 67,122 archived files were
/// rejected purely for this metadata delta.) The size is instead used for **cross-copy
/// consistency**: a candidate is only verified when the primary and a mirror hold a byte-
/// identical copy (their size-sets for the name intersect) — proving two consistent copies
/// exist, which is the real point of the ≥2-copy gate.
public struct ArchiveIndex: Sendable {
    /// lowercased filename → set of byte sizes seen for that name
    private let map: [String: Set<Int>]
    public let fileCount: Int

    public init(map: [String: Set<Int>]) {
        self.map = map
        self.fileCount = map.values.reduce(0) { $0 + $1.count }
    }

    /// True when a file with this name exists and (when `size` is provided) a copy with that
    /// exact size is present. Without a size, a name match alone counts (weaker).
    public func contains(filename: String, size: Int?) -> Bool {
        guard let sizes = map[filename.lowercased()] else { return false }
        if let size { return sizes.contains(size) }
        return !sizes.isEmpty
    }

    /// The set of archived byte sizes seen for `filename` (empty if the name is absent). Used to
    /// check cross-copy consistency between primary and a mirror.
    public func sizes(forFilename filename: String) -> Set<Int> {
        map[filename.lowercased()] ?? []
    }

    public var isEmpty: Bool { map.isEmpty }

    /// Build an index by walking `<archiveRoot>/originals/`. Returns an empty index when the
    /// directory is absent or unreadable (→ nothing verifies → nothing is deletable; safe).
    public static func build(archiveRoot: String) -> ArchiveIndex {
        let originals = (archiveRoot as NSString).appendingPathComponent("originals")
        let fm = FileManager.default
        var map: [String: Set<Int>] = [:]
        let url = URL(fileURLWithPath: originals)
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else {
            return ArchiveIndex(map: [:])
        }
        for case let f as URL in en {
            guard let vals = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true else { continue }
            let name = f.lastPathComponent.lowercased()
            map[name, default: []].insert(vals.fileSize ?? 0)
        }
        return ArchiveIndex(map: map)
    }
}
