import SwiftUI

/// Left sidebar: scanned roots grouped into the default "Folders" group plus any user-defined
/// sections, with the active root's folder outline beneath it. Roots can be drag-reordered
/// within a group and moved between sections via the context menu; the footer totals the
/// library. Uses a `List` (not the top-level split) so `.onMove` reordering and `Section`
/// headers come for free — the monorepo's no-`NavigationSplitView` rule is about the split,
/// not an inner list.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    /// Expanded folder-tree nodes for the active root (manual outline, so we control state).
    @State private var expandedFolders: Set<String> = []

    // New-section sheet/alert state. `pendingAssignRoot` is set when "New Section…" is chosen
    // from a root's Move-to menu, so the root lands in the freshly created section.
    @State private var showNewSection = false
    @State private var newSectionName = ""
    @State private var pendingAssignRoot: String?

    // Rename-section alert state.
    @State private var showRenameSection = false
    @State private var renameSectionId: String?
    @State private var renameSectionText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)

            if appState.scanRoots.isEmpty {
                emptyRoots
                Spacer(minLength: 0)
            } else {
                list
            }

            if !appState.scanRoots.isEmpty {
                Divider().opacity(0.3)
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("New Section", isPresented: $showNewSection) {
            TextField("Section name", text: $newSectionName)
            Button("Create") { commitNewSection() }
            Button("Cancel", role: .cancel) { resetNewSection() }
        } message: { Text("Group your scanned folders under a custom heading.") }
        .alert("Rename Section", isPresented: $showRenameSection) {
            TextField("Section name", text: $renameSectionText)
            Button("Rename") {
                if let id = renameSectionId { appState.renameSection(id, name: renameSectionText) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(theme.accentColor)
                .font(.title3)
            Text("PurplePeek").font(.headline)
            Spacer()
            Button {
                pendingAssignRoot = nil
                newSectionName = ""
                showNewSection = true
            } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.plain)
                .help("New section")
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

    // MARK: - List

    private var list: some View {
        List {
            ForEach(appState.sidebarGroups) { group in
                groupContent(group)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func groupContent(_ group: SidebarGroup) -> some View {
        let showHeader = group.id != nil || !appState.sidebarSections.isEmpty
        if showHeader {
            Section {
                rootRows(group)
            } header: {
                sectionHeader(group)
            }
        } else {
            rootRows(group)
        }
    }

    private func rootRows(_ group: SidebarGroup) -> some View {
        ForEach(group.roots) { root in
            rootRow(root)
                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                .listRowSeparator(.hidden)
                // Drag the folder by its path; drop onto another row inserts before it (and
                // moves it into that row's group when dragged across sections).
                .draggable(root.path) {
                    Label(root.displayName, systemImage: "folder.fill")
                        .padding(6)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    appState.moveRoot(dragged, toSection: group.id, before: root.path)
                    return true
                }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ group: SidebarGroup) -> some View {
        HStack {
            Text(group.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let id = group.id {
                Menu {
                    Button("Rename…") { startRenameSection(id: id, current: group.name) }
                    Button("Delete Section", role: .destructive) { appState.deleteSection(id) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Manage section")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let id = group.id {
                Button("Rename…") { startRenameSection(id: id, current: group.name) }
                Button("Delete Section", role: .destructive) { appState.deleteSection(id) }
            }
        }
        // Drop a folder onto a section header to move it into that section (appended).
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            appState.moveRoot(dragged, toSection: group.id, before: nil)
            return true
        }
    }

    // MARK: - Root row (+ folder outline for the active root)

    @ViewBuilder
    private func rootRow(_ root: ScanRoot) -> some View {
        let isActiveRoot = appState.selectedRootPath == root.path

        VStack(alignment: .leading, spacing: 2) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background((isActiveRoot && appState.selectedFolderPath == nil) ? theme.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { rootMenu(root) }

            if isActiveRoot, let tree = appState.folderTree, !tree.children.isEmpty {
                folderOutline(tree.children, depth: 0)
            }
        }
    }

    @ViewBuilder
    private func rootMenu(_ root: ScanRoot) -> some View {
        // Flat, titled section rather than a nested `Menu` — submenu buttons inside a
        // `.contextMenu` don't reliably fire their actions on macOS.
        Section("Move to Section") {
            Button("Folders (default)") { appState.assignRoot(root.path, toSection: nil) }
                .disabled(root.sectionId == nil)
            ForEach(appState.sidebarSections) { section in
                Button(section.name) { appState.assignRoot(root.path, toSection: section.id) }
                    .disabled(root.sectionId == section.id)
            }
            Button("New Section…") {
                pendingAssignRoot = root.path
                newSectionName = ""
                showNewSection = true
            }
        }
        Button("Forget Folder", role: .destructive) { appState.deleteScanRoot(root.path) }
    }

    // MARK: - Folder outline (manual recursion so expansion state is ours)

    // Returns `AnyView` (not `some View`): the recursive call would otherwise make the opaque
    // return type self-referential, which the compiler rejects.
    private func folderOutline(_ nodes: [FolderTreeNode], depth: Int) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                folderRow(node, depth: depth)
                if expandedFolders.contains(node.path), let kids = node.childrenOrNil {
                    folderOutline(kids, depth: depth + 1)
                }
            }
        )
    }

    private func folderRow(_ node: FolderTreeNode, depth: Int) -> some View {
        let isSelected = appState.selectedFolderPath == node.path
        return HStack(spacing: 6) {
            if node.childrenOrNil != nil {
                Button {
                    if expandedFolders.contains(node.path) { expandedFolders.remove(node.path) }
                    else { expandedFolders.insert(node.path) }
                } label: {
                    Image(systemName: expandedFolders.contains(node.path) ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 12)
            }
            Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
            Text(node.name).font(.callout).lineLimit(1)
            Spacer()
            Text("\(node.fileCount)").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .padding(.leading, CGFloat(depth) * 12 + 14)
        .background(isSelected ? theme.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedFolderPath = node.path
            appState.selectedFileId = nil
        }
    }

    // MARK: - Footer (library totals)

    private var footer: some View {
        let items = appState.totalItemCount
        let folders = appState.scanRoots.count
        return HStack {
            Text("\(items.formatted()) item\(items == 1 ? "" : "s") · \(folders) folder\(folders == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Section alert helpers

    private func startRenameSection(id: String, current: String) {
        renameSectionId = id
        renameSectionText = current
        showRenameSection = true
    }

    private func commitNewSection() {
        let section = appState.createSection(name: newSectionName)
        if let path = pendingAssignRoot, let section { appState.assignRoot(path, toSection: section.id) }
        resetNewSection()
    }

    private func resetNewSection() {
        newSectionName = ""
        pendingAssignRoot = nil
    }
}
