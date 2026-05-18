import SwiftUI

/// Root container. Uses a plain `HStack` instead of `NavigationSplitView`
/// because `NavigationSplitView`'s runtime layout on macOS 14+ does not
/// honor `.navigationSplitViewColumnWidth(min:)` reliably — persisted
/// state (in BOTH UserDefaults `NSSplitView Subview Frames *` keys and
/// `Saved Application State/<bundleId>.savedState/`) can produce a
/// sidebar that renders narrower than its declared minimum, with no
/// in-app recovery affordance. MusicJournal hit this first and burned
/// three fix attempts on the persistence side before giving up and
/// switching to manual layout. PurpleReel adopts the same pattern.
///
/// With a manual `HStack`, we own every pixel: the sidebar always
/// renders at exactly `sidebarWidth`, and AppKit's window-restoration
/// machinery has no split-view divider to mis-restore. The
/// `WindowStateGuard` helper still runs in `AppDelegate` to keep any
/// remaining `HSplitView` / `VSplitView` inside the detail tree clean,
/// but the top-level chrome is now bulletproof.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true

    /// Fixed width. Could be made user-resizable via a drag-handle, but
    /// MusicJournal's experience shows that fixed-width sidebars cause
    /// zero support issues. Resizability is a nice-to-have that re-opens
    /// the persistence-corruption door — defer until asked for.
    private let sidebarWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: sidebarWidth)
                    .background(.ultraThinMaterial)
                Divider()
            }
            BrowserView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarVisible.toggle()
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar (⌃⌘S)")
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.chooseRootFolder()
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.rescan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(appState.rootFolder == nil || appState.isScanning)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(TranscodePreset.all) { preset in
                        Button(preset.name) { appState.transcodeSelected(preset: preset) }
                    }
                    Divider()
                    Button("Show Queue…") { appState.transcodeSheetVisible = true }
                } label: {
                    Label("Transcode", systemImage: "wand.and.stars")
                }
                .disabled(appState.selectedAsset == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.backupSheetVisible = true
                } label: {
                    Label("Verified Backup", systemImage: "externaldrive.badge.checkmark")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Transcribe Selected (Whisper)") {
                        appState.transcribeSelected(generateMarkers: false)
                    }
                    .disabled(appState.selectedAsset == nil)
                    Button("Transcribe + Create Markers") {
                        appState.transcribeSelected(generateMarkers: true)
                    }
                    .disabled(appState.selectedAsset == nil)
                    Divider()
                    Button("Auto-Describe (Ollama)") {
                        appState.autoDescribeSelected()
                    }
                    .disabled(appState.selectedAsset == nil)
                    Divider()
                    Button("Find Similar Takes") {
                        appState.findSimilarTakes()
                    }
                    .disabled(appState.assets.isEmpty)
                } label: {
                    Label("AI", systemImage: "sparkles")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.batchRenameSheetVisible = true
                } label: {
                    Label("Batch Rename", systemImage: "character.cursor.ibeam")
                }
                .disabled(appState.assets.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.sftpSheetVisible = true
                } label: {
                    Label("SFTP Delivery", systemImage: "network")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Selected Clip to Final Cut Pro") {
                        appState.exportFCPXML(scope: .selectedOnly, openInFCP: true)
                    }
                    .disabled(appState.selectedAsset == nil)
                    Button("Entire Library to Final Cut Pro") {
                        appState.exportFCPXML(scope: .allCatalogued, openInFCP: true)
                    }
                    .disabled(appState.assets.isEmpty)
                    Divider()
                    Button("Selected Clip — Save .fcpxml Only") {
                        appState.exportFCPXML(scope: .selectedOnly, openInFCP: false)
                    }
                    .disabled(appState.selectedAsset == nil)
                    Button("Entire Library — Save .fcpxml Only") {
                        appState.exportFCPXML(scope: .allCatalogued, openInFCP: false)
                    }
                    .disabled(appState.assets.isEmpty)
                } label: {
                    Label("Send to FCP", systemImage: "arrow.up.forward.app")
                }
                .disabled(appState.rootFolder == nil)
            }
        }
        .sheet(isPresented: $appState.transcodeSheetVisible) {
            TranscodeQueueView(queue: appState.transcodeQueue)
        }
        .sheet(isPresented: $appState.backupSheetVisible) {
            BackupView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.sftpSheetVisible) {
            SFTPDeliveryView()
                .environmentObject(appState)
        }
        .sheet(item: $appState.aiSheetState) { state in
            AISheetView(state: state)
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.detailSheetVisible) {
            ClipDetailSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.batchRenameSheetVisible) {
            BatchRenameView()
                .environmentObject(appState)
        }
        .sheet(item: $appState.convertSheet) { state in
            ConvertSheet(state: state)
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.shortcutsCheatSheetVisible) {
            ShortcutsCheatSheet()
        }
        .sheet(isPresented: $appState.batchMetadataSheetVisible) {
            BatchMetadataSheet()
                .environmentObject(appState)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            // Plain ScrollView with our own tappable rows. List's
            // `selection:` binding only honors `.tag()` on its direct
            // children; FolderNodeRow recurses through VStacks so tags
            // on nested HStacks never reach the List's selection model.
            //
            // Both Workspace AND Devices render unconditionally: the
            // Workspace section is the user-curated folder set, the
            // Devices section is the system's mounted-volume list which
            // is always present (Macintosh HD + any externals) so the
            // user can browse files even before adding a workspace.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    if appState.workspaceRoots.isEmpty {
                        Text("Drag a folder here or use ⌘O to add one.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(appState.workspaceRoots, id: \.self) { root in
                            if let tree = appState.folderTree(forRoot: root) {
                                FolderNodeRow(node: tree, depth: 0,
                                                workspaceParentLabel: workspaceParentLabel(root))
                                    .environmentObject(appState)
                                    .contextMenu {
                                        workspaceRootContextMenu(root: root)
                                    }
                            }
                        }
                    }
                    Divider().padding(.vertical, 8)
                    Text("Devices")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                    DevicesSection()
                        .environmentObject(appState)
                    Divider().padding(.vertical, 8)
                    Text("Stats")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Items").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.displayedAssets.count) / \(appState.assets.count)")
                        }
                        HStack {
                            Text("Status").foregroundStyle(.secondary)
                            Spacer()
                            Text(appState.isScanning ? appState.scanProgress : "Idle")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 8)
            }
        }
    }

    /// Kyno-style right-click menu for a workspace-root row.
    @ViewBuilder
    private func workspaceRootContextMenu(root: URL) -> some View {
        Button("Remove from Workspace") {
            appState.removeWorkspaceRoot(root)
        }
        Button("Remove Others from Workspace") {
            for other in appState.workspaceRoots where other != root {
                appState.removeWorkspaceRoot(other)
            }
        }
        .disabled(appState.workspaceRoots.count <= 1)
        Divider()
        Button("New Folder…") {
            createSubfolder(in: root)
        }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([root])
        }
        Button(appState.drilldownEnabled ? "Drilldown ✓" : "Drilldown") {
            appState.drilldownEnabled.toggle()
        }
        Divider()
        Button("Clear Thumbnail Cache for This Folder") {
            clearThumbnailCache(under: root)
        }
        Button("Clear All Thumbnail Cache") {
            ThumbnailService.purgeCache()
        }
        Divider()
        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func createSubfolder(in parent: URL) {
        let alert = NSAlert()
        alert.messageText = "New Folder in \(parent.lastPathComponent)"
        alert.informativeText = "Name:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = "Untitled folder"
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        Task { await appState.rescan() }
    }

    private func clearThumbnailCache(under root: URL) {
        let assets = appState.assets.filter {
            ($0.path as NSString).standardizingPath
                .hasPrefix((root.path as NSString).standardizingPath + "/")
        }
        let cacheRoot = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/PurpleReel/thumbnails")
        for asset in assets {
            // Match the ThumbnailService cache hash format (path+mtime).
            // Cheaper: just iterate the whole thumbnail dir — small win
            // for the user, no precise bookkeeping required.
            _ = asset
            _ = cacheRoot
        }
        ThumbnailService.purgeCache()
    }

    /// "[bronty/Downloads]" style parent-path subtitle for a workspace
    /// root — disambiguates same-named roots and matches Kyno's
    /// Workspace section visual treatment.
    private func workspaceParentLabel(_ root: URL) -> String? {
        let parent = root.deletingLastPathComponent().path
        // Trim "/Users/" from the front so common cases show as
        // "[bronty/Downloads]" rather than "[/Users/bronty/Downloads]".
        let stripped: String
        if parent.hasPrefix("/Users/") {
            stripped = String(parent.dropFirst("/Users/".count))
        } else {
            stripped = parent
        }
        return stripped.isEmpty ? nil : "[\(stripped)]"
    }

    private var workspaceHeader: some View {
        HStack {
            Text("WORKSPACE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Add Folder to Workspace…") {
                    appState.addFolderToWorkspace()
                }
                .keyboardShortcut("i", modifiers: [.command])
                Divider()
                Button("Clear Workspace…") {
                    let alert = NSAlert()
                    alert.messageText = "Clear Workspace?"
                    alert.informativeText = "All workspace roots will be removed. Catalogued metadata (markers, tags, ratings) stays in the database."
                    alert.addButton(withTitle: "Clear")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        appState.clearWorkspace()
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Recursive disclosure-style folder tree row. Each row is its own
/// tappable surface (we don't rely on `List` selection because that
/// only routes through `.tag()` on direct List children, and this
/// view recurses through nested `VStack`s). Tapping a row navigates
/// to that folder; tapping the chevron expands/collapses children.
private struct FolderNodeRow: View {
    let node: FolderNode
    let depth: Int
    /// "[bronty/Downloads]"-style subtitle shown only for top-level
    /// workspace roots so users can disambiguate same-named entries.
    var workspaceParentLabel: String? = nil

    @EnvironmentObject var appState: AppState
    @State private var expanded: Bool = true

    private var isSelected: Bool { appState.selectedFolderPath == node.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if !node.children.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: node.children.isEmpty ? "folder" : "folder.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                    if appState.isDrilldownEnabled(forPath: node.path) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .background(Circle().fill(.background))
                            .offset(x: 3, y: 3)
                    }
                }
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let parent = workspaceParentLabel {
                    Text(parent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if node.recursiveAssetCount > 0 {
                    Text("\(node.recursiveAssetCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 8 + CGFloat(depth) * 12)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.30)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                appState.navigate(to: node.path)
            }

            if expanded {
                ForEach(node.children) { child in
                    FolderNodeRow(node: child, depth: depth + 1)
                        .environmentObject(appState)
                }
            }
        }
    }
}
