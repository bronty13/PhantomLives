import Foundation

/// A node in the ad-hoc store's folder tree — a folder (with `children`) or a file (a leaf). The tree
/// is **derived** from the flat, decrypted file paths in the cache (the listing is `--files-only`),
/// so no extra remote calls are needed to show folders.
public struct AdhocNode: Identifiable, Equatable, Sendable {
    /// Full path within the store (e.g. "HOTW/2026/file.pdf"); unique, so it's the row id.
    public let id: String
    /// Last path component shown in the row.
    public let name: String
    public let isDir: Bool
    /// File size, or for a folder the recursive sum of its files' sizes.
    public let size: Int64
    /// 1 for a file; for a folder the recursive count of files beneath it.
    public let fileCount: Int
    public let modTime: Date?        // files only
    /// The underlying file (nil for folders) — what the rename/delete actions operate on.
    public let file: AdhocFile?
    /// Child nodes for a folder; **nil** for a file (so the outline shows no disclosure triangle).
    public let children: [AdhocNode]?

    public init(id: String, name: String, isDir: Bool, size: Int64, fileCount: Int,
                modTime: Date?, file: AdhocFile?, children: [AdhocNode]?) {
        self.id = id
        self.name = name
        self.isDir = isDir
        self.size = size
        self.fileCount = fileCount
        self.modTime = modTime
        self.file = file
        self.children = children
    }
}

public enum AdhocTree {

    /// Build a folder tree from a flat list of files. Folders are inferred from the "/"-separated
    /// paths; at every level folders come first (case-insensitive), then files. Folder `size` /
    /// `fileCount` are recursive aggregates. Pure — unit-tested without any I/O.
    public static func build(_ files: [AdhocFile]) -> [AdhocNode] {
        // Transient mutable tree (a reference type so nested inserts are cheap).
        final class Dir {
            var subdirs: [String: Dir] = [:]
            var files: [AdhocFile] = []
        }
        let root = Dir()
        for f in files where !f.isDir {
            let segs = f.path.split(separator: "/").map(String.init)
            guard !segs.isEmpty else { continue }
            var cur = root
            for seg in segs.dropLast() {
                if cur.subdirs[seg] == nil { cur.subdirs[seg] = Dir() }
                cur = cur.subdirs[seg]!
            }
            cur.files.append(f)
        }

        func convert(_ dir: Dir, prefix: String) -> [AdhocNode] {
            var nodes: [AdhocNode] = []
            for name in dir.subdirs.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
                let path = prefix.isEmpty ? name : prefix + "/" + name
                let kids = convert(dir.subdirs[name]!, prefix: path)
                let size = kids.reduce(Int64(0)) { $0 + $1.size }
                let count = kids.reduce(0) { $0 + $1.fileCount }
                nodes.append(AdhocNode(id: path, name: name, isDir: true, size: size,
                                       fileCount: count, modTime: nil, file: nil, children: kids))
            }
            for f in dir.files.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                nodes.append(AdhocNode(id: f.path, name: f.name, isDir: false, size: max(0, f.size),
                                       fileCount: 1, modTime: f.modTime, file: f, children: nil))
            }
            return nodes
        }
        return convert(root, prefix: "")
    }
}
