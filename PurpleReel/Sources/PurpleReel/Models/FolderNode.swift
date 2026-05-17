import Foundation

/// Recursive folder tree node. Built from the asset list's paths so
/// the sidebar reflects exactly the folders that actually contain
/// media — empty/non-media subdirectories don't pollute the tree.
final class FolderNode: Identifiable, Hashable {
    let id = UUID()
    let path: String         // absolute path
    let name: String         // last path component for display
    var children: [FolderNode] = []
    var directAssetCount: Int = 0   // files in this folder (not subfolders)

    init(path: String, name: String) {
        self.path = path
        self.name = name
    }

    /// Recursive total — used for the badge next to each folder name
    /// when drilldown is the default view mode.
    var recursiveAssetCount: Int {
        directAssetCount + children.reduce(0) { $0 + $1.recursiveAssetCount }
    }

    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

enum FolderTreeBuilder {

    /// Build a tree rooted at `rootPath` from a flat list of assets.
    /// Skips any asset whose path doesn't sit under `rootPath`.
    static func build(rootPath: String, assets: [Asset]) -> FolderNode? {
        guard !rootPath.isEmpty else { return nil }
        let normalizedRoot = (rootPath as NSString).standardizingPath
        let rootName = (normalizedRoot as NSString).lastPathComponent
        let root = FolderNode(path: normalizedRoot, name: rootName)

        // Insert each asset by walking down (creating nodes as needed).
        for asset in assets {
            let assetPath = (asset.path as NSString).standardizingPath
            guard assetPath.hasPrefix(normalizedRoot + "/") || assetPath == normalizedRoot else { continue }
            let parentDir = (assetPath as NSString).deletingLastPathComponent
            insert(parentDir: parentDir, under: root, rootPath: normalizedRoot)
        }

        // Now count direct-asset members per folder.
        let assetParents: [String: Int] = assets.reduce(into: [:]) { acc, a in
            let parent = ((a.path as NSString).standardizingPath as NSString)
                .deletingLastPathComponent
            acc[parent, default: 0] += 1
        }
        annotateCounts(root, counts: assetParents)

        sortAlphabetically(root)
        return root
    }

    // MARK: - Private

    private static func insert(parentDir: String, under root: FolderNode, rootPath: String) {
        // Walk from rootPath down to parentDir, creating missing
        // children along the way.
        guard parentDir.hasPrefix(rootPath) else { return }
        let suffix = String(parentDir.dropFirst(rootPath.count))
        let parts = suffix.split(separator: "/").map(String.init)
        var node = root
        var accumulated = rootPath
        for part in parts {
            accumulated += "/\(part)"
            if let existing = node.children.first(where: { $0.name == part }) {
                node = existing
            } else {
                let child = FolderNode(path: accumulated, name: part)
                node.children.append(child)
                node = child
            }
        }
    }

    private static func annotateCounts(_ node: FolderNode, counts: [String: Int]) {
        node.directAssetCount = counts[node.path] ?? 0
        for child in node.children { annotateCounts(child, counts: counts) }
    }

    private static func sortAlphabetically(_ node: FolderNode) {
        node.children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for c in node.children { sortAlphabetically(c) }
    }
}
