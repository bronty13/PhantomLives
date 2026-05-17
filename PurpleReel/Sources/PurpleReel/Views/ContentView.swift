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
        List {
            Section("Library") {
                if let root = appState.rootFolder {
                    Label(root.lastPathComponent, systemImage: "folder")
                        .lineLimit(1)
                        .help(root.path)
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Stats") {
                LabeledContent("Items", value: "\(appState.assets.count)")
                LabeledContent("Status", value: appState.isScanning ? appState.scanProgress : "Idle")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}
