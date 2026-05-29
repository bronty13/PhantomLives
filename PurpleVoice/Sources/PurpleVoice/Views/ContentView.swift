import SwiftUI

/// Root container. Manual HStack rather than `NavigationSplitView` per
/// CLAUDE.md "Sidebar layout: avoid `NavigationSplitView`" — the
/// PurpleReel/MusicJournal pattern, lifted verbatim.
struct ContentView: View {
    @EnvironmentObject var queue: ProcessingQueue
    @EnvironmentObject var settings: SettingsStore
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true

    /// Fixed-width sidebar. Resizability is a nice-to-have that
    /// re-opens the persistence-corruption door — defer until asked.
    private let sidebarWidth: CGFloat = 240

    /// Cached at view-init so we don't probe the filesystem on every
    /// SwiftUI re-render. `nil` ⇒ ffmpeg missing ⇒ show the install
    /// banner instead of the normal UI.
    @State private var ffmpegURL: URL? = FFmpegLocator.find()

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: sidebarWidth, alignment: .leading)
                    .clipped()
                    .background(.ultraThinMaterial)
                Divider()
            }
            mainPane
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
                    pickFiles()
                } label: {
                    Label("Add Clips…", systemImage: "plus")
                }
                .help("Pick audio or video files to clean (⌘O)")
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pvAddClipsRequested)) { _ in
            pickFiles()
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        if ffmpegURL == nil {
            MissingFFmpegView(onRecheck: {
                ffmpegURL = FFmpegLocator.find()
            })
        } else if let selectedID = queue.selectedClipID,
                  let clip = queue.clips.first(where: { $0.id == selectedID }) {
            ClipDetailView(clip: clip)
        } else {
            DropZoneView()
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        panel.title = "Add clips to clean"
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            queue.ingest(urls: panel.urls, settings: settings)
        }
    }
}
