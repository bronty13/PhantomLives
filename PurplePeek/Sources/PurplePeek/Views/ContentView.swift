import SwiftUI
import UniformTypeIdentifiers

/// Root layout: a fixed-width sidebar + main area in a manual `HStack` (the PhantomLives
/// pattern — NOT `NavigationSplitView`, which mis-restores divider widths on macOS 14+).
///
/// Phase 2 adds folder discovery: drag a folder onto the window or use Open Folder, and the
/// main area becomes the browse view (tree-filtered thumbnail grid / list).
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true
    @State private var isDropTargeted = false
    @State private var showKeywordManager = false

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: 240)
                    .background(theme.sidebarBackground)
                Divider()
            }
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.appMode == .folderBrowse && appState.selectedFileId != nil {
                Divider()
                MediaDetailPanel()
                    .frame(width: 320)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showKeywordManager) {
            KeywordManagerSheet().environmentObject(appState)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
            } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help("Toggle Sidebar")
        }
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $appState.appMode) {
                ForEach(AppMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showKeywordManager = true
            } label: { Label("Keywords", systemImage: "tag") }
                .help("Manage keywords")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                openFolderPanel()
            } label: { Label("Open Folder", systemImage: "folder.badge.plus") }
                .keyboardShortcut("o", modifiers: [.command])
                .help("Open a folder to scan")
        }
    }

    // MARK: - Main area

    @ViewBuilder
    private var mainArea: some View {
        ZStack {
            LinearGradient(
                colors: theme.backgroundGradient,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if appState.appMode == .preview {
                previewPlaceholder
            } else if appState.selectedRootPath == nil && !appState.isScanning {
                emptyState
            } else {
                FolderBrowseView()
            }

            if isDropTargeted { dropHighlight }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(theme.accentColor)
            Text("Drop a folder to begin")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text("PurplePeek will scan it for photos, videos, and audio so you can triage them before importing to Photos.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Open Folder…") { openFolderPanel() }
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(40)
    }

    private var previewPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.accentColor)
            Text("Preview mode arrives in Phase 4")
                .font(.title3.weight(.semibold))
            Text("It will walk undecided items one by one with a large viewer and full EXIF metadata.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding(40)
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(theme.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
            .padding(8)
            .allowsHitTesting(false)
    }

    // MARK: - Folder intake

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to scan for photos, videos, and audio."
        if panel.runModal() == .OK, let url = panel.url {
            appState.scanFolder(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in appState.scanFolder(url) }
        }
        return true
    }
}
