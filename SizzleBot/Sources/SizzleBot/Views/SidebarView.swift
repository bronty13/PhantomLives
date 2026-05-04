import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var characterStore: CharacterStore
    @EnvironmentObject var ollamaService: OllamaService
    @State private var showingNewCharacter = false
    @State private var editTarget: Character?
    @State private var searchText = ""

    var filtered: [Character] {
        guard !searchText.isEmpty else { return characterStore.characters }
        return characterStore.characters.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tagline.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: Binding(
            get: { characterStore.selectedCharacter },
            set: { characterStore.selectedCharacter = $0 }
        )) {
            if !characterStore.builtInCharacters.isEmpty {
                Section("Featured") {
                    ForEach(filtered.filter { $0.isBuiltIn }) { char in
                        CharacterRow(character: char)
                            .tag(char)
                            .contextMenu {
                                Button("Edit") { editTarget = char }
                                if characterStore.canResetToDefault(char) {
                                    Divider()
                                    Button("Reset to Default") {
                                        characterStore.resetToDefault(char)
                                    }
                                }
                            }
                    }
                }
            }
            if !characterStore.userCharacters.isEmpty {
                Section("My Characters") {
                    ForEach(filtered.filter { !$0.isBuiltIn }) { char in
                        CharacterRow(character: char)
                            .tag(char)
                            .contextMenu {
                                Button("Edit") { editTarget = char }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    characterStore.deleteCharacter(char)
                                }
                            }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search characters")
        .navigationTitle("SizzleBot")
        .toolbar {
            ToolbarItem {
                Button { showingNewCharacter = true } label: {
                    Label("New Character", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            OllamaStatusBar()
                .padding(10)
        }
        .sheet(isPresented: $showingNewCharacter) {
            CharacterEditorView(mode: .create)
                .environmentObject(characterStore)
        }
        .sheet(item: $editTarget) { char in
            CharacterEditorView(mode: .edit(char))
                .environmentObject(characterStore)
        }
    }
}

struct CharacterRow: View {
    let character: Character

    var body: some View {
        HStack(spacing: 10) {
            Text(character.avatar)
                .font(.system(size: 26))
                .frame(width: 42, height: 42)
                .background(character.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(character.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

struct OllamaStatusBar: View {
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var ollamaSetup: OllamaSetup

    private var activeDisplayName: String {
        ollamaService.selectedModel.components(separatedBy: ":").first ?? ollamaService.selectedModel
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ollamaService.isConnected ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            if ollamaService.isConnected {
                Menu {
                    Section("Switch model") {
                        if ollamaService.availableModels.isEmpty {
                            Text("No models installed")
                        } else {
                            ForEach(ollamaService.availableModels) { model in
                                Button {
                                    ollamaService.setModel(model.name)
                                } label: {
                                    if model.name == ollamaService.selectedModel {
                                        Label(model.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(model.displayName)
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    SettingsLink {
                        Label("Open Settings…", systemImage: "gearshape")
                    }
                    Button {
                        Task { await ollamaService.checkConnection() }
                    } label: {
                        Label("Refresh model list", systemImage: "arrow.clockwise")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Ollama · \(activeDisplayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Text("Ollama offline")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer()

            if !ollamaService.isConnected {
                Button("Retry") { Task { await ollamaService.checkConnection() } }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
