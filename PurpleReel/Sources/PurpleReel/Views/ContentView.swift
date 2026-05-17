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
        .sheet(isPresented: $appState.batchRenameSheetVisible) {
            BatchRenameView()
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
            if !appState.workspaceRoots.isEmpty {
                List(selection: Binding(
                    get: { appState.selectedFolderPath },
                    set: { appState.navigate(to: $0) }
                )) {
                    Section("Workspace") {
                        ForEach(appState.workspaceRoots, id: \.self) { root in
                            if let tree = appState.folderTree(forRoot: root) {
                                FolderNodeRow(node: tree, depth: 0)
                                    .contextMenu {
                                        Button("Remove from Workspace") {
                                            appState.removeWorkspaceRoot(root)
                                        }
                                        Button("Reveal in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([root])
                                        }
                                    }
                            }
                        }
                    }
                    Section("Stats") {
                        LabeledContent("Items",
                                        value: "\(appState.displayedAssets.count) / \(appState.assets.count)")
                        LabeledContent("Status",
                                        value: appState.isScanning ? appState.scanProgress : "Idle")
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Open a folder to start")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
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

/// Recursive disclosure-style folder tree row. Each node is selectable
/// via List's selection binding; tapping expands/collapses children
/// via the chevron at the leading edge.
private struct FolderNodeRow: View {
    let node: FolderNode
    let depth: Int

    @State private var expanded: Bool = true

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
                Image(systemName: node.children.isEmpty ? "folder" : "folder.fill")
                    .foregroundStyle(.tint)
                    .font(.callout)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if node.recursiveAssetCount > 0 {
                    Text("\(node.recursiveAssetCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, CGFloat(depth) * 10)
            .tag(node.path)

            if expanded {
                ForEach(node.children) { child in
                    FolderNodeRow(node: child, depth: depth + 1)
                }
            }
        }
    }
}
