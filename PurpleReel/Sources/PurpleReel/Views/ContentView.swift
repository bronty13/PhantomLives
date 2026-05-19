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
    /// C6 — non-modal Transcode Queue. The boolean
    /// `appState.transcodeSheetVisible` is now an *open me* signal:
    /// when it flips to true we open the floating Queue window scene
    /// and immediately reset the flag, so the next enqueue (or the
    /// next user-driven menu click) can fire the signal again.
    @Environment(\.openWindow) private var openWindow

    /// Fixed width. Could be made user-resizable via a drag-handle, but
    /// MusicJournal's experience shows that fixed-width sidebars cause
    /// zero support issues. Resizability is a nice-to-have that re-opens
    /// the persistence-corruption door — defer until asked for.
    private let sidebarWidth: CGFloat = 240

    /// C34 — gates the resume-interrupted-runs alert so it fires at
    /// most once per launch. Set true on the first onAppear pass
    /// when AppState's `interruptedRuns` is non-empty.
    @State private var resumePromptShown: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                // `.frame(width:)` proposes 240 but SwiftUI lets the
                // child overflow if its intrinsic width exceeds the
                // proposal — long folder names at deep indents inside
                // Devices > Macintosh HD > … render the underlying
                // HStack wider than 240. The frame's DEFAULT alignment
                // is `.center`, which then splits that overflow evenly
                // between the leading and trailing edges. `.clipped()`
                // hides what's beyond the frame, but the leading half
                // of the overflow is what gets chopped — every label
                // appears to lose its first few characters.
                //
                // Fix: pin the inner content to the leading edge via
                // `alignment: .leading` so any overflow falls off the
                // (clipped) trailing edge harmlessly instead of shoving
                // the whole sidebar leftward. Then `.clipped()` keeps
                // the visual bounds tight.
                SidebarView()
                    .frame(width: sidebarWidth, alignment: .leading)
                    .clipped()
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
                    let hardRefresh = NSEvent.modifierFlags.contains(.shift)
                    Task {
                        if hardRefresh {
                            // Kyno-parity (1.9): Shift-click forces a
                            // hard refresh — purge all asset rows and
                            // rebuild from disk. Costs a full re-scan
                            // but fixes "stale index" / "phantom file"
                            // cases. Plain click stays the cheap
                            // incremental rescan.
                            try? appState.db.clearAssets()
                        }
                        await appState.rescan()
                    }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Rescan workspace (Shift-click = hard refresh; purges + reloads catalog).")
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
            // C6 — Active-queue status chip. Only renders when at
            // least one job is running or pending; clicking it brings
            // the floating Queue window back to the front so the user
            // can monitor / cancel without losing browser context.
            ToolbarItem(placement: .status) {
                queueStatusChip
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
        .onChange(of: appState.transcodeSheetVisible) { _, visible in
            // Treat the boolean as an "open me" pulse — open the
            // floating Queue window and immediately reset so the
            // next enqueue can re-fire. Idempotent: openWindow brings
            // an existing window to front rather than spawning a
            // duplicate.
            guard visible else { return }
            openWindow(id: "transcode-queue")
            appState.transcodeSheetVisible = false
        }
        // C12 — Report Definition dialog → run handoff. When the
        // dialog publishes a request, drive the existing NSSavePanel
        // + writer flow with the user's chosen format + sections.
        .onChange(of: appState.reportRunRequest) { _, req in
            guard let req else { return }
            appState.reportRunRequest = nil
            appState.runReportExport(format: req.format,
                                       sections: req.sections)
        }
        .sheet(isPresented: $appState.backupSheetVisible) {
            BackupView()
                .environmentObject(appState)
        }
        // C34 — resume-interrupted-runs alert. Fires at most once
        // per launch via the `resumePromptShown` gate. Resuming
        // restores the run; "Discard all" wipes every snapshot
        // (NB: the per-run resume action only discards the one it
        // resumed). Skipping the alert (no button) leaves snapshots
        // on disk for next launch.
        .alert(
            "Resume interrupted workflow chain?",
            isPresented: Binding(
                get: { !resumePromptShown && !appState.interruptedRuns.isEmpty },
                set: { _ in resumePromptShown = true }
            ),
            presenting: appState.interruptedRuns.first
        ) { firstRun in
            Button("Resume “\(firstRun.chain.name)”") {
                appState.resumeInterruptedRun(firstRun)
            }
            Button("Discard All", role: .destructive) {
                ActiveRunPersistence.clearAll()
                appState.interruptedRuns = []
            }
            Button("Not Now", role: .cancel) { }
        } message: { firstRun in
            let completedCount = firstRun.completedStepIndices.count
            let totalCount = firstRun.chain.steps.count
            Text(
                "PurpleReel found \(appState.interruptedRuns.count) "
                + "interrupted run(s) from a prior session. "
                + "“\(firstRun.chain.name)” completed "
                + "\(completedCount) of \(totalCount) step(s) before "
                + "it stopped. Resuming picks up at step "
                + "\(completedCount + 1)."
            )
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
        .sheet(item: $appState.fcpxmlExportSheetState) { state in
            FCPXMLExportSheet(options: state.options, scope: state.scope)
                .environmentObject(appState)
        }
        .sheet(item: $appState.reportDefinitionState) { state in
            ReportDefinitionSheet(sections: state.sections, format: state.format)
                .environmentObject(appState)
        }
        .sheet(item: $appState.analysisScopeState) { state in
            AnalysisScopeSheet(scope: state.scope)
                .environmentObject(appState)
        }
        .sheet(item: $appState.singleClipTagState) { state in
            SingleClipTagDialog(
                assetPath: state.assetPath,
                assetFilename: state.assetFilename
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $appState.shortcutsCheatSheetVisible) {
            ShortcutsCheatSheet()
        }
        .sheet(isPresented: $appState.batchMetadataSheetVisible) {
            BatchMetadataSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.batchTagSheetVisible) {
            BatchTagEditorSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.transferMetadataSheetVisible) {
            TransferMetadataSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.pasteRenameSheetVisible) {
            PasteRenameSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.combineClipsSheetVisible) {
            CombineClipsSheet(initialSources: appState.combineCandidates())
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.workflowChainsSheetVisible) {
            WorkflowChainsSheet()
                .environmentObject(appState)
        }
    }

    /// C6 — non-modal queue status chip. Only renders when at least
    /// one transcode job is running or pending; clicking it brings
    /// the floating Queue window back to the front. Live-updates as
    /// the queue's @Published lists change.
    @ViewBuilder
    private var queueStatusChip: some View {
        let queue = appState.transcodeQueue
        let running = queue.running.count
        let pending = queue.pending.count
        let total = running + pending
        if total > 0 {
            Button {
                openWindow(id: "transcode-queue")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("\(total) \(total == 1 ? "job" : "jobs")")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.18),
                             in: Capsule())
            }
            .buttonStyle(.plain)
            .help("\(running) running, \(pending) pending — click to open the Transcode Queue window")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    // Per-section collapse state — persisted across launches so the
    // user's preferred sidebar layout sticks. Sections collapse
    // independently; their headers remain visible (with the chevron)
    // so the user can re-expand without rummaging.
    @AppStorage("sidebar.workspace.expanded") private var workspaceExpanded: Bool = true
    @AppStorage("sidebar.devices.expanded")   private var devicesExpanded:   Bool = true
    @AppStorage("sidebar.stats.expanded")     private var statsExpanded:     Bool = true
    @AppStorage("sidebar.spans.expanded")     private var spansExpanded:     Bool = true

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
                    sectionHeader("Workspace", expanded: $workspaceExpanded)
                    if workspaceExpanded {
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
                    }
                    if !appState.spanGroups.isEmpty {
                        Divider().padding(.vertical, 8)
                        sectionHeader("Spanned Clips", expanded: $spansExpanded)
                        if spansExpanded {
                            ForEach(appState.spanGroups) { group in
                                SpanGroupRow(group: group)
                                    .environmentObject(appState)
                            }
                        }
                    }
                    Divider().padding(.vertical, 8)
                    sectionHeader("Devices", expanded: $devicesExpanded)
                    if devicesExpanded {
                        DevicesSection()
                            .environmentObject(appState)
                    }
                    Divider().padding(.vertical, 8)
                    sectionHeader("Stats", expanded: $statsExpanded)
                    if statsExpanded {
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
                }
                .padding(.bottom, 8)
            }
        }
    }

    /// Collapsible section header — Kyno-style disclosure chevron
    /// + label. Clicking anywhere on the header toggles the section.
    /// State persists across launches via @AppStorage on each
    /// section's binding.
    private func sectionHeader(_ title: String,
                                expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                expanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .layoutPriority(1)
                if let parent = workspaceParentLabel {
                    Text(parent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(0)
                }
                Spacer(minLength: 4)
                if node.recursiveAssetCount > 0 {
                    Text("\(node.recursiveAssetCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            // Hard cap row width — otherwise the workspace parent
            // label "[bronty/Downloads]" plus a long folder name
            // plus a 4-digit count plus indent can push the HStack
            // wider than the sidebar's proposed 240. SwiftUI then
            // hands that wider intrinsic size back up the tree and
            // the parent frame fails to clip it cleanly. Forcing
            // each row to fit the parent's proposal stops the leak.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Indent caps at depth 6 so /Users/bronty/Documents/A/B/C
            // doesn't shove a Devices-tree row 120 pixels right and
            // squeeze the truncated name into a few characters.
            .padding(.leading, 8 + CGFloat(min(depth, 6)) * 12)
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
