import SwiftUI
import PurpleMarkRenderCore

/// Root layout: a fixed-width sidebar (Outline | Files) + the single-pane editor
/// + a status bar, with the OpenMark-style toolbar. Uses a manual `HStack`
/// rather than `NavigationSplitView` per docs/sidebar-layout.md.
struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var find = FindController.shared

    private let sidebarWidth: CGFloat = 248

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if state.sidebarVisible && !settings.zenMode {
                    SidebarView()
                        .frame(width: sidebarWidth, alignment: .leading)
                        .clipped()
                        .background(.ultraThinMaterial)
                    Divider()
                }
                VStack(spacing: 0) {
                    if state.findVisible {
                        FindReplaceBar(find: find)
                        Divider()
                    }
                    EditorPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !settings.zenMode {
                Divider()
                StatusBar()
            }
        }
        .toolbar(settings.zenMode ? .hidden : .visible, for: .windowToolbar)
        .toolbar { toolbarContent }
        .navigationTitle(state.title)
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

            Picker("View", selection: $state.viewMode) {
                Image(systemName: "eye").tag(ViewMode.document)
                Image(systemName: "chevron.left.forwardslash.chevron.right").tag(ViewMode.markdown)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Document / Markdown")
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text(state.title).fontWeight(.semibold)
                if state.isDirty {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Inline formatting (B / I / S)
            Button { EditorAction.bold.post() } label: { Image(systemName: "bold") }
                .help("Bold (⌘B)")
            Button { EditorAction.italic.post() } label: { Image(systemName: "italic") }
                .help("Italic (⌘I)")
            Button { EditorAction.strikethrough.post() } label: { Image(systemName: "strikethrough") }
                .help("Strikethrough")

            // Text-size menu (AA)
            Menu {
                Button("Increase Text Size") { settings.fontSize = min(24, settings.fontSize + 1) }
                Button("Decrease Text Size") { settings.fontSize = max(12, settings.fontSize - 1) }
                Divider()
                Picker("Theme", selection: Binding(
                    get: { settings.theme }, set: { settings.theme = $0 })) {
                    ForEach(RenderTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Reading Width", selection: Binding(
                    get: { settings.readingWidth }, set: { settings.readingWidth = $0 })) {
                    ForEach(ReadingWidth.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("Text size, theme, and width")

            // Block formatting
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

            // Share / Export
            Menu {
                Button("Export to PDF…") { ExportCommands.exportPDF(state: state, settings: settings) }
                Button("Export to HTML…") { ExportCommands.exportHTML(state: state, settings: settings) }
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

/// The single editor pane — Document (rendered) or Markdown (source). Scroll
/// position is carried across the toggle when sync-scroll is enabled.
private struct EditorPane: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            switch state.viewMode {
            case .document:
                MarkdownWebView(
                    markdown: state.text,
                    theme: settings.theme,
                    width: settings.readingWidth,
                    onScroll: { f in if settings.syncScroll { state.scrollFraction = f } },
                    scrollTo: state.scrollFraction)
            case .markdown:
                SourceTextView(
                    text: $state.text,
                    settings: settings,
                    onScroll: { f in if settings.syncScroll { state.scrollFraction = f } },
                    scrollTo: state.scrollFraction)
            }
        }
    }
}
