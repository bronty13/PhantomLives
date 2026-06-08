import SwiftUI
import PurpleMarkRenderCore

/// Root: an optional tab bar (when more than one document is open) above the
/// active document's window.
struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if state.documents.count > 1 {
                TabBar()
                Divider()
            }
            DocumentWindow(doc: state.active)
        }
        // Drag a markdown (or text) file from Finder onto the window to open it
        // in a tab. Mirrors the existing drop-on-app-icon behavior.
        .dropDestination(for: URL.self) { urls, _ in
            let opened = state.openDroppedFiles(urls)
            return opened
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The editor layout for one document: fixed-width sidebar (Outline | Files) +
/// the single-pane editor + status bar, with the OpenMark-style toolbar.
struct DocumentWindow: View {
    @ObservedObject var doc: Document
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var themes: ThemeStore
    @ObservedObject private var find = FindController.shared

    private let sidebarWidth: CGFloat = 248

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if state.sidebarVisible && !settings.zenMode {
                    SidebarView(doc: doc)
                        .frame(width: sidebarWidth, alignment: .leading)
                        .clipped()
                        .background(.ultraThinMaterial)
                    Divider()
                }
                VStack(spacing: 0) {
                    if state.findVisible {
                        FindReplaceBar(find: find, doc: doc)
                        Divider()
                    }
                    EditorPane(doc: doc)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !settings.zenMode {
                Divider()
                StatusBar(doc: doc)
            }
        }
        .toolbar(settings.zenMode ? .hidden : .visible, for: .windowToolbar)
        .toolbar { toolbarContent }
        .navigationTitle(doc.title)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { state.sidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar (⌃⌘S)")

            Picker("View", selection: $doc.viewMode) {
                Image(systemName: "eye").tag(ViewMode.document)
                Image(systemName: "chevron.left.forwardslash.chevron.right").tag(ViewMode.markdown)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Document / Markdown")
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text(doc.title).fontWeight(.semibold)
                if doc.isDirty {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { EditorAction.bold.post() } label: { Image(systemName: "bold") }
                .help("Bold (⌘B)")
            Button { EditorAction.italic.post() } label: { Image(systemName: "italic") }
                .help("Italic (⌘I)")
            Button { EditorAction.strikethrough.post() } label: { Image(systemName: "strikethrough") }
                .help("Strikethrough")

            Menu {
                Button("Increase Text Size") { settings.fontSize = min(24, settings.fontSize + 1) }
                Button("Decrease Text Size") { settings.fontSize = max(12, settings.fontSize - 1) }
                Divider()
                Picker("Theme", selection: Binding(
                    get: { settings.themeRaw }, set: { settings.themeRaw = $0 })) {
                    ForEach(themes.allOptions) { Text($0.name).tag($0.id) }
                }
                Picker("Reading Width", selection: Binding(
                    get: { settings.readingWidth }, set: { settings.readingWidth = $0 })) {
                    ForEach(ReadingWidth.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Text size, theme, and width")

            Button { EditorAction.unorderedList.post() } label: { Image(systemName: "list.bullet") }
                .help("Bulleted List")
            Button { EditorAction.orderedList.post() } label: { Image(systemName: "list.number") }
                .help("Numbered List")
            Button { EditorAction.quote.post() } label: { Image(systemName: "text.quote") }
                .help("Blockquote")
            Button { EditorAction.codeBlock.post() } label: { Image(systemName: "curlybraces") }
                .help("Code Block")
            Button { EditorAction.link.post() } label: { Image(systemName: "link") }
                .help("Link (⌘K)")

            Menu {
                Button("Export to PDF…") { ExportCommands.exportPDF(doc: doc, settings: settings) }
                Button("Export to HTML…") { ExportCommands.exportHTML(doc: doc, settings: settings) }
                Divider()
                Button("Open File…") { state.openDialog() }
                Button("Open Folder…") { state.openFolderDialog() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export and open")
        }
    }
}

/// The single editor pane for a document — Document (rendered) or Markdown
/// (source). Scroll position carries across the toggle.
private struct EditorPane: View {
    @ObservedObject var doc: Document
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var themes: ThemeStore

    var body: some View {
        Group {
            switch doc.viewMode {
            case .document:
                MarkdownWebView(
                    markdown: doc.text,
                    colors: themes.colors(forID: settings.themeRaw),
                    width: settings.readingWidth,
                    onScroll: { f in if settings.syncScroll { doc.scrollFraction = f } },
                    scrollTo: doc.scrollFraction)
            case .markdown:
                SourceTextView(
                    text: $doc.text,
                    settings: settings,
                    onScroll: { f in if settings.syncScroll { doc.scrollFraction = f } },
                    scrollTo: doc.scrollFraction)
            }
        }
    }
}
