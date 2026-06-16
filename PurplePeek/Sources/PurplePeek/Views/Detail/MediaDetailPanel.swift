import SwiftUI

/// Right-hand panel for the selected file: a large preview, basic file facts, and every
/// decision control (keep/skip, favorite, title, caption, keywords, albums). Each control
/// persists immediately. Title/caption commit on focus-loss so the DB write never disturbs
/// the cursor (see AppState.patchLocal).
struct MediaDetailPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme

    @State private var preview: NSImage?
    @State private var title: String = ""
    @State private var caption: String = ""
    /// The file the title/caption text currently belongs to — so a commit triggered by a
    /// focus change always targets the right row even mid-selection-switch.
    @State private var editingFileId: String?
    @State private var showKeywordPicker = false
    @State private var showAlbumPicker = false

    @FocusState private var focus: Field?
    private enum Field { case title, caption }

    private let previewSize = CGSize(width: 520, height: 520)

    var body: some View {
        if let file = appState.selectedFile {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewImage(for: file)
                    fileFacts(for: file)
                    Divider()
                    keepSkip(for: file)
                    favoriteRow(for: file)
                    hiddenRow(for: file)
                    Divider()
                    titleField(for: file)
                    captionField(for: file)
                    Divider()
                    keywordsSection(for: file)
                    albumsSection(for: file)
                    Divider()
                    actionButton(for: file)
                }
                .padding(16)
            }
            .background(.ultraThinMaterial)
            .task(id: file.id) { await loadForSelection(file) }
            .onChange(of: focus) { _, _ in commitText() }
            .onDisappear { commitText() }
        } else {
            EmptyView()
        }
    }

    /// Persist the in-flight title/caption to the row they belong to (`editingFileId`),
    /// not necessarily the currently selected file.
    private func commitText() {
        guard let id = editingFileId else { return }
        appState.setTitle(id, title)
        appState.setCaption(id, caption)
    }

    // MARK: - Preview + facts

    private func previewImage(for file: MediaFile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(theme.cellBackground)
            if let preview {
                Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: file.mediaType == .video ? "film" : (file.mediaType == .audio ? "waveform" : "photo"))
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func fileFacts(for file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(file.fileName).font(.headline).lineLimit(2).truncationMode(.middle)
            Text(factsLine(for: file)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func factsLine(for file: MediaFile) -> String {
        var parts = [file.mediaType.label]
        if let size = file.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Decisions

    private func keepSkip(for file: MediaFile) -> some View {
        HStack(spacing: 10) {
            decisionButton(
                title: "Keep", systemImage: "checkmark.circle.fill", tint: .green,
                active: file.keepDecision == true
            ) { appState.setKeep(file.id, file.keepDecision == true ? nil : true) }

            decisionButton(
                title: "Skip", systemImage: "xmark.circle.fill", tint: .red,
                active: file.keepDecision == false
            ) { appState.setKeep(file.id, file.keepDecision == false ? nil : false) }
        }
    }

    private func decisionButton(title: String, systemImage: String, tint: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(active ? tint.opacity(0.9) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func favoriteRow(for file: MediaFile) -> some View {
        Button {
            appState.setFavorite(file.id, !file.isFavorite)
        } label: {
            HStack {
                Image(systemName: file.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(file.isFavorite ? .pink : .secondary)
                Text("Favorite")
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hiddenRow(for file: MediaFile) -> some View {
        Button {
            appState.setHidden(file.id, !file.isHidden)
        } label: {
            HStack {
                Image(systemName: file.isHidden ? "eye.slash.fill" : "eye.slash")
                    .foregroundStyle(file.isHidden ? theme.accentColor : .secondary)
                Text("Hidden")
                Spacer()
                if file.isHidden {
                    Text("hidden in Photos on import").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func titleField(for file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title").font(.caption).foregroundStyle(.secondary)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .title)
                .onSubmit { appState.setTitle(file.id, title) }
        }
    }

    private func captionField(for file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Caption").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $caption)
                .frame(height: 64)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                .focused($focus, equals: .caption)
        }
    }

    // MARK: - Keywords / albums

    private func keywordsSection(for file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Keywords").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showKeywordPicker = true } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showKeywordPicker, arrowEdge: .leading) {
                        KeywordPickerView().environmentObject(appState)
                    }
            }
            chips(selectedKeywordNames, empty: "No keywords")
        }
    }

    private func albumsSection(for file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Albums").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showAlbumPicker = true } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAlbumPicker, arrowEdge: .leading) {
                        AlbumPickerView().environmentObject(appState)
                    }
            }
            chips(appState.selectedAlbums, empty: "No albums")
        }
    }

    private var selectedKeywordNames: [String] {
        appState.keywords.filter { appState.selectedKeywordIds.contains($0.id) }.map(\.name).sorted()
    }

    @ViewBuilder
    private func chips(_ names: [String], empty: String) -> some View {
        if names.isEmpty {
            Text(empty).font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.accentColor.opacity(0.18), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(for file: MediaFile) -> some View {
        if file.mediaType == .audio {
            if file.exportedAt != nil {
                Label("Exported to Kept Audio", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else {
                Button {
                    appState.exportAudio(file.id)
                } label: {
                    Label("Copy to Kept Audio", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        } else {
            if file.isImported {
                Label("Imported to Photos", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else {
                Button {
                    appState.importSingle(file.id)
                } label: {
                    Label("Import to Photos", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }

    // MARK: - Selection sync

    private func loadForSelection(_ file: MediaFile) async {
        // Commit any pending edits from the previously-shown file before swapping text.
        commitText()
        editingFileId = file.id
        title = file.title ?? ""
        caption = file.caption ?? ""
        preview = nil
        preview = await ThumbnailService.shared.thumbnail(for: file.fileURL, size: previewSize)
    }
}
