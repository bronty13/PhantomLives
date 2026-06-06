import SwiftUI

@main
struct PurpleMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .environmentObject(settings)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands { editorCommands }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(state)
        }
    }

    @CommandsBuilder
    private var editorCommands: some Commands {
        // App menu — Check for Updates…
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                UpdaterController.shared.checkForUpdates()
            }
            .disabled(!UpdaterController.shared.canCheckForUpdates)
        }
        // File
        CommandGroup(replacing: .newItem) {
            Button("New") { state.newDocument() }
                .keyboardShortcut("n")
            Button("Open…") { state.openDialog() }
                .keyboardShortcut("o")
            Button("Open Folder…") { state.openFolderDialog() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Menu("Open Recent") {
                ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) { state.open(url) }
                }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { _ = state.save() }
                .keyboardShortcut("s")
            Button("Save As…") { _ = state.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Export to PDF…") { ExportCommands.exportPDF(state: state, settings: settings) }
            Button("Export to HTML…") { ExportCommands.exportHTML(state: state, settings: settings) }
        }
        // View
        CommandGroup(after: .toolbar) {
            Button("Show Document") { state.viewMode = .document }
                .keyboardShortcut("1", modifiers: .command)
            Button("Show Markdown Source") { state.viewMode = .markdown }
                .keyboardShortcut("2", modifiers: .command)
            Button(state.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                state.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
        // Find
        CommandGroup(after: .textEditing) {
            Section {
                Button("Find…") { state.showFind(replace: false) }
                    .keyboardShortcut("f")
                Button("Find and Replace…") { state.showFind(replace: true) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { FindController.shared.next() }
                    .keyboardShortcut("g")
                Button("Find Previous") { FindController.shared.previous() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
        // Format
        CommandMenu("Format") {
            Button("Bold") { EditorAction.bold.post() }
                .keyboardShortcut("b")
            Button("Italic") { EditorAction.italic.post() }
                .keyboardShortcut("i")
            Button("Strikethrough") { EditorAction.strikethrough.post() }
                .keyboardShortcut("s", modifiers: [.command, .shift, .option])
            Button("Inline Code") { EditorAction.inlineCode.post() }
                .keyboardShortcut("e")
            Button("Link") { EditorAction.link.post() }
                .keyboardShortcut("k")
            Divider()
            Button("Bulleted List") { EditorAction.unorderedList.post() }
            Button("Numbered List") { EditorAction.orderedList.post() }
            Button("Blockquote") { EditorAction.quote.post() }
            Button("Code Block") { EditorAction.codeBlock.post() }
        }
    }
}
