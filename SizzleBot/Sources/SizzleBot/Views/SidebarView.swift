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

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ollamaService.isConnected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(ollamaService.isConnected
                 ? "Ollama · \(ollamaService.selectedModel)"
                 : "Ollama offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
