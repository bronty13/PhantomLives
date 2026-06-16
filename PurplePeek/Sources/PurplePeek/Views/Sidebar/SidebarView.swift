import SwiftUI

/// Left sidebar: scanned roots, and — for the selected root — a recursive folder outline
/// derived from its media files. Selecting a folder narrows the grid to that subtree.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)

            if appState.scanRoots.isEmpty {
                emptyRoots
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.scanRoots) { root in
                            rootSection(root)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(theme.accentColor)
                .font(.title3)
            Text("PurplePeek").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyRoots: some View {
        Text("No folders scanned yet.\nDrop a folder or use Open Folder.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    // MARK: - Root section

    @ViewBuilder
    private func rootSection(_ root: ScanRoot) -> some View {
        let isActiveRoot = appState.selectedRootPath == root.path

        Button {
            appState.selectRoot(root.path)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(theme.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(root.displayName).lineLimit(1)
                    Text("\(root.totalFiles) items").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background((isActiveRoot && appState.selectedFolderPath == nil) ? theme.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        // Folder outline for the active root.
        if isActiveRoot, let tree = appState.folderTree, !tree.children.isEmpty {
            OutlineGroup(tree.children, children: \.childrenOrNil) { node in
                folderRow(node)
            }
            .padding(.leading, 8)
        }
    }

    private func folderRow(_ node: FolderTreeNode) -> some View {
        Button {
            appState.selectedFolderPath = node.path
            appState.selectedFileId = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
                Text(node.name).font(.callout).lineLimit(1)
                Spacer()
                Text("\(node.fileCount)").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(appState.selectedFolderPath == node.path ? theme.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
