import SwiftUI

/// Root container. Manual `HStack` sidebar (NOT `NavigationSplitView`) per
/// `docs/sidebar-layout.md` — a fixed-width sidebar AppKit can't mis-restore.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("sidebarVisible") private var sidebarVisible: Bool = true
    private let sidebarWidth: CGFloat = 250

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .frame(width: sidebarWidth, alignment: .leading)
                    .clipped()
                    .background(.ultraThinMaterial)
                Divider()
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
                } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
                .help("Toggle Sidebar (⌃⌘S)")
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
            ToolbarItem(placement: .primaryAction) {
                Button { appState.presentImportPanel() } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import documents or images (⌘O)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { appState.presentTranscribePanel() } label: {
                    Label("Transcribe", systemImage: "waveform.badge.mic")
                }
                .help("Transcribe an audio or video file (⇧⌘T)")
            }
        }
        // Pasted-text / web-article entry sheets.
        .sheet(isPresented: $appState.showPasteSheet) { PasteTextSheet().environmentObject(appState) }
        .sheet(isPresented: $appState.showWebSheet) { WebArticleSheet().environmentObject(appState) }
        // Busy HUD.
        .overlay {
            if appState.isBusy {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(appState.busyMessage).font(.callout).foregroundStyle(.secondary)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 20)
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { appState.errorMessage != nil },
                                    set: { if !$0 { appState.errorMessage = nil } })) {
            Button("OK") { appState.errorMessage = nil }
        } message: { Text(appState.errorMessage ?? "") }
        .alert("Done",
               isPresented: Binding(get: { appState.infoMessage != nil },
                                    set: { if !$0 { appState.infoMessage = nil } })) {
            Button("OK") { appState.infoMessage = nil }
        } message: { Text(appState.infoMessage ?? "") }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.mode {
        case .transcriber:
            TranscriberView()
        case .reader:
            if appState.selectedDocument != nil {
                ReaderView()
            } else {
                EmptyReaderView()
            }
        }
    }
}

/// Shown when no document is selected.
struct EmptyReaderView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.bubble")
                .font(.system(size: 54))
                .foregroundStyle(.purple.opacity(0.6))
            Text("Nothing to read yet")
                .font(.title2.weight(.semibold))
            Text("Import a PDF, EPUB, Word doc, or image — paste some text, or read a web article. PurpleSpeak reads it aloud and follows along word by word.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button { appState.presentImportPanel() } label: {
                    Label("Import File", systemImage: "square.and.arrow.down")
                }
                Button { appState.startPasteFlow() } label: {
                    Label("Paste Text", systemImage: "doc.on.clipboard")
                }
                Button { appState.startWebFlow() } label: {
                    Label("Web Article", systemImage: "globe")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
