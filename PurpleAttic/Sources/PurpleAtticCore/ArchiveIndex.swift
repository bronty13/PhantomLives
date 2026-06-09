import Foundation

/// A filename → set-of-sizes index of an archive's `originals/` tree, used to verify that a
/// purge candidate's file is actually present in the archive. Matching on **filename AND
/// exact byte size** makes false-positive verification effectively impossible while staying
/// independent of the osxphotos folder template (no need to reconstruct the dated path).
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
