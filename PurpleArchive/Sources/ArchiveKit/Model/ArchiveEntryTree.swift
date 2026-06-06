import Foundation

/// A directory-hierarchy view over a flat `[ArchiveEntry]` listing, for the
/// GUI's outline/table and breadcrumb navigation. Built purely in Swift — no
/// backend involvement — so it's cheap to rebuild when the user changes the
/// active filename encoding (Phase 2).
public final class ArchiveEntryNode: Identifiable, @unchecked Sendable {
    public let name: String
    public let isDirectory: Bool
    /// The backing entry, if this node corresponds to a real archive member.
    /// Synthetic intermediate directories (implied by a deep path) have `nil`.
    public let entry: ArchiveEntry?
    public internal(set) var children: [ArchiveEntryNode]
    public let id: String   // full path, stable for SwiftUI

    init(name: String, isDirectory: Bool, entry: ArchiveEntry?, id: String) {
        self.name = name
        self.isDirectory = isDirectory
        self.entry = entry
        self.children = []
        self.id = id
    }

    /// Total uncompressed bytes of this node and everything beneath it.
    public var totalSize: Int64 {
        let own = entry?.uncompressedSize ?? 0
        return own + children.reduce(0) { $0 + $1.totalSize }
    }

    /// Recursive file count (excludes directories).
    public var fileCount: Int {
        let own = (entry?.isDirectory == false) ? 1 : 0
        return own + children.reduce(0) { $0 + $1.fileCount }
    }

    func sortRecursively() {
        children.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        children.forEach { $0.sortRecursively() }
    }
}

public enum ArchiveEntryTree {
    /// Build a sorted directory tree from a flat listing. Intermediate
    /// directories implied by nested paths are synthesized when an archive
    /// lists files without their parent entries (common in zip/tar).
    public static func build(from entries: [ArchiveEntry]) -> ArchiveEntryNode {
        let root = ArchiveEntryNode(name: "", isDirectory: true, entry: nil, id: "")
        var index: [String: ArchiveEntryNode] = ["": root]

        for entry in entries {
            let components = entry.path
            guard !components.isEmpty else { continue }
            var parent = root
            var prefix = ""
            for (i, comp) in components.enumerated() {
                let isLast = i == components.count - 1
                prefix = prefix.isEmpty ? comp : prefix + "/" + comp
                if let existing = index[prefix] {
                    parent = existing
                    continue
                }
                let node = ArchiveEntryNode(
                    name: comp,
                    isDirectory: isLast ? entry.isDirectory : true,
                    entry: isLast ? entry : nil,
                    id: prefix)
                parent.children.append(node)
                index[prefix] = node
                parent = node
            }
        }
        root.sortRecursively()
        return root
    }
}
