import Foundation

/// A node in the sidebar's folder tree, derived from the directory paths of a root's media
/// files. `fileCount` is recursive (all media anywhere beneath this folder).
struct FolderTreeNode: Identifiable, Hashable {
    let path: String
    let name: String
    var children: [FolderTreeNode]
    var fileCount: Int

    var id: String { path }

    /// `nil` for leaves so `OutlineGroup` doesn't draw a disclosure chevron on them.
    var childrenOrNil: [FolderTreeNode]? { children.isEmpty ? nil : children }
}

enum FolderTree {
    /// Build a tree rooted at `rootPath` from the given files. Every file contributes a
    /// recursive +1 to its directory and each ancestor up to the root. O(files × depth).
    static func build(rootPath: String, files: [MediaFile]) -> FolderTreeNode {
        let root = (rootPath as NSString).standardizingPath
        var childrenMap: [String: Set<String>] = [:]
        var recursiveCount: [String: Int] = [:]

        for file in files where file.deletedAt == nil {
            let dir = (file.filePath as NSString).deletingLastPathComponent
            var current = dir
            while true {
                recursiveCount[current, default: 0] += 1
                if current == root { break }
                let parent = (current as NSString).deletingLastPathComponent
                // Stop if we somehow walked above the root (defensive — files should all be
                // under it). Avoids an infinite loop at the filesystem root.
                guard parent != current else { break }
                childrenMap[parent, default: []].insert(current)
                current = parent
                if !(current == root || current.hasPrefix(root + "/")) { break }
            }
        }

        func makeNode(_ path: String) -> FolderTreeNode {
            let kids = (childrenMap[path] ?? [])
                .sorted { ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending }
                .map(makeNode)
            return FolderTreeNode(
                path: path,
                name: (path as NSString).lastPathComponent,
                children: kids,
                fileCount: recursiveCount[path] ?? 0
            )
        }
        return makeNode(root)
    }
}
