import SwiftUI
import SnRCore

@main
struct MacSearchReplaceApp: App {
    @StateObject private var viewModel = SearchReplaceViewModel()
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        WindowGroup("Search and Replace") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Search") { viewModel.reset() }
                    .keyboardShortcut("n")
                Button("Open Script…") { openScript() }
                    .keyboardShortcut("o")
                Menu("Open Recent Folder") {
                    if prefs.recentRoots.isEmpty {
                        Text("(none)")
                    } else {
                        ForEach(prefs.recentRoots, id: \.self) { p in
                            Button(URL(fileURLWithPath: p).lastPathComponent) {
                                viewModel.addRoot(path: p)
                            }
                        }
                        Divider()
                        Button("Clear Menu") { prefs.clearRecentRoots() }
                    }
                }
            }

            CommandMenu("Search") {
                Button("Find") { Task { await viewModel.runSearch() } }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("Stop") { viewModel.stopSearch() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!viewModel.isWorking)
                Divider()
                Button("Replace All") { Task { await viewModel.commit() } }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                Button("Replace with Prompt…") { viewModel.startAskEach() }
                Button("Multiple S/R Pairs…") {
                    if viewModel.stringPairs.isEmpty { viewModel.stringPairs = [StringPair()] }
                    viewModel.showStringPairsSheet = true
                }
                Divider()
                Button("Touch Files in Results") { viewModel.touchSelectedFiles() }
                Divider()
                Button("Open Backup Folder") { viewModel.openBackupsFolder() }
            }

            CommandMenu("Favorites") {
                Button("Save Current as Favorite…") {
                    viewModel.newFavoriteName = viewModel.pattern
                    viewModel.showSaveFavoriteSheet = true
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                if viewModel.favorites.isEmpty {
                    Text("No saved favorites")
                } else {
                    ForEach(viewModel.favorites) { fav in
                        Button(fav.name) { viewModel.loadFavorite(fav) }
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button("MacSearchReplace Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/")!)
                }
            }
        }

        Settings {
            PreferencesView()
        }
    }

    private func openScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let script = try SnRScript.load(from: url)
                if let firstStep = script.steps.first {
                    viewModel.pattern = firstStep.search
                    viewModel.replacement = firstStep.replace ?? ""
                    viewModel.isRegex = firstStep.type == "regex"
                    viewModel.caseInsensitive = firstStep.caseInsensitive
                    viewModel.multiline = firstStep.multiline
                }
                viewModel.includeGlobs = script.include.joined(separator: "; ")
                viewModel.excludeGlobs = script.exclude.joined(separator: "; ")
                viewModel.honorGitignore = script.honorGitignore
                viewModel.roots = script.roots.map { URL(fileURLWithPath: $0) }
                viewModel.statusText = "Loaded script: \(script.name)"
            } catch {
                viewModel.statusText = "Could not load script: \(error)"
            }
        }
    }
}
