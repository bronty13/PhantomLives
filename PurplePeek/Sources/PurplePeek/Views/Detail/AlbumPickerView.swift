import SwiftUI

/// Popover for assigning the selected file to albums. Album names are stored locally and
/// only realized in Photos during import (Phase 5). Shows current albums (removable), a
/// field to add a new one, and quick-add buttons for album names already in use.
struct AlbumPickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var newName = ""

    private var suggestions: [String] {
        appState.distinctAlbumNames().filter { !appState.selectedAlbums.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Albums").font(.headline)

            if appState.selectedAlbums.isEmpty {
                Text("Not in any album yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(appState.selectedAlbums, id: \.self) { name in
                    HStack {
                        Image(systemName: "rectangle.stack").foregroundStyle(theme.accentColor)
                        Text(name)
                        Spacer()
                        Button { appState.removeAlbum(name) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                TextField("New or existing album", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTyped)
                Button("Add", action: addTyped)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !suggestions.isEmpty {
                Text("Existing albums").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { appState.addAlbum(name) } label: {
                                HStack {
                                    Image(systemName: "plus.circle").foregroundStyle(theme.accentColor)
                                    Text(name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func addTyped() {
        appState.addAlbum(newName)
        newName = ""
    }
}
