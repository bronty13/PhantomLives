import SwiftUI

/// Popover for assigning the selected file to albums. Album names are stored locally and
/// realized in Photos during import. Shows current albums (removable), a field to add a new
/// one, and quick-add suggestions drawn from albums already used in PurplePeek **and the
/// albums in your Photos library** (a photo glyph marks the Photos ones).
struct AlbumPickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var newName = ""

    /// Merge PurplePeek-used album names with the Photos library's albums, de-duplicated
    /// (case-insensitively, Photos taking precedence for the source glyph) and minus the
    /// ones already on this file.
    private var suggestions: [(name: String, fromPhotos: Bool)] {
        let selected = Set(appState.selectedAlbums.map { $0.lowercased() })
        let photos = Set(appState.photosAlbumNames.map { $0.lowercased() })
        var seen = Set<String>()
        var result: [(String, Bool)] = []
        for name in appState.photosAlbumNames + appState.distinctAlbumNames() {
            let key = name.lowercased()
            guard !selected.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            result.append((name, photos.contains(key)))
        }
        return result.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
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

            HStack(spacing: 6) {
                Text("Add to an album").font(.caption).foregroundStyle(.secondary)
                if appState.isLoadingPhotosAlbums { ProgressView().controlSize(.mini) }
                Spacer()
            }
            .padding(.top, 2)

            if suggestions.isEmpty {
                Text(appState.isLoadingPhotosAlbums ? "Loading Photos albums…" : "No existing albums.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(suggestions, id: \.name) { item in
                            Button { appState.addAlbum(item.name) } label: {
                                HStack {
                                    Image(systemName: item.fromPhotos ? "photo.on.rectangle.angled" : "plus.circle")
                                        .foregroundStyle(theme.accentColor)
                                    Text(item.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .help(item.fromPhotos ? "From your Photos library" : "Used before in PurplePeek")
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { appState.loadPhotosAlbumsIfNeeded() }
    }

    private func addTyped() {
        appState.addAlbum(newName)
        newName = ""
    }
}
