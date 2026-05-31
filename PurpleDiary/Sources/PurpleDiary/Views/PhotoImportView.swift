import SwiftUI
import Photos
import AppKit
import UniformTypeIdentifiers

/// The editor's Photos & video section: a strip of the entry's attached media
/// thumbnails (each removable, each tappable to view) plus an "Add from Photos"
/// button (auto-assembled day / browse) and an "Add from Files…" button
/// (filesystem images + videos). Loads thumbnails (not full media) for the strip.
struct EntryPhotosSection: View {
    @EnvironmentObject private var appState: AppState
    let entry: Entry

    /// Wraps an attachment id so it can drive `.sheet(item:)` (String isn't Identifiable).
    private struct ViewerItem: Identifiable { let id: String }

    @State private var thumbs: [AttachmentThumb] = []
    @State private var showingSuggestions = false
    @State private var viewerItem: ViewerItem?
    @State private var importingFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Media")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingSuggestions = true
                } label: {
                    Label("Add from Photos", systemImage: "photo.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Button(action: chooseFiles) {
                    if importingFiles {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Add from Files…", systemImage: "folder.badge.plus")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(importingFiles)
            }

            if thumbs.isEmpty {
                Text("No media yet. Pull in the photos you took on \(dayString), browse another day, or add photos, video, or audio from your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(thumbs) { thumb in
                            thumbView(thumb)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showingSuggestions) {
            PhotoSuggestionSheet(entryId: entry.id, date: entry.dateValue, onClose: reload)
                .environmentObject(appState)
        }
        .sheet(item: $viewerItem) { item in
            AttachmentViewerSheet(attachmentId: item.id)
                .environmentObject(appState)
        }
    }

    private var dayString: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: entry.dateValue)
    }

    private func thumbView(_ thumb: AttachmentThumb) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                viewerItem = ViewerItem(id: thumb.id)
            } label: {
                ZStack {
                    if let data = thumb.thumbnailData, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().scaledToFill()
                    } else {
                        Image(systemName: placeholderGlyph(thumb))
                            .font(.title2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(thumb.isAudio ? Color.secondary.opacity(0.08) : .clear)
                    }
                    if thumb.isVideo || thumb.isAudio {
                        Image(systemName: "play.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .font(.title)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .help(thumb.isVideo ? "Play this video" : thumb.isAudio ? "Play this audio" : "View this photo")

            Button {
                remove(thumb)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(3)
            .help(removeHelp(thumb))
        }
    }

    private func placeholderGlyph(_ thumb: AttachmentThumb) -> String {
        if thumb.isVideo { return "video" }
        if thumb.isAudio { return "music.note" }
        return "photo"
    }

    private func removeHelp(_ thumb: AttachmentThumb) -> String {
        let noun = thumb.isVideo ? "video" : thumb.isAudio ? "audio clip" : "photo"
        return "Remove this \(noun) from the entry"
    }

    /// NSOpenPanel for filesystem images + videos; imports each chosen file into
    /// the encrypted DB, then refreshes the strip.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = FileImportService.allowedContentTypes
        panel.message = "Choose photos, videos, or audio to add to this entry"
        panel.prompt = "Add"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        importingFiles = true
        Task {
            defer { importingFiles = false }
            var skipped = 0
            for url in urls {
                if let attachment = await FileImportService.makeAttachment(from: url, entryId: entry.id) {
                    do { try appState.addAttachment(attachment) }
                    catch { appState.errorMessage = error.localizedDescription }
                } else {
                    skipped += 1
                }
            }
            if skipped > 0 {
                appState.errorMessage = "Couldn’t import \(skipped) file\(skipped == 1 ? "" : "s") (unsupported or unreadable)."
            }
            reload()
        }
    }

    private func reload() {
        thumbs = (try? DatabaseService.shared.attachmentThumbs(forEntry: entry.id)) ?? []
    }

    private func remove(_ thumb: AttachmentThumb) {
        do {
            try appState.deleteAttachment(id: thumb.id)
            reload()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

/// Sheet that shows the photos taken on the entry's date and lets the user pick
/// which to attach. Requests Photos access on appear; explains + offers Settings
/// if denied. Already-attached photos are skipped on import (deduped by asset id).
struct PhotoSuggestionSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let entryId: String
    let date: Date
    let onClose: () -> Void

    init(entryId: String, date: Date, onClose: @escaping () -> Void) {
        self.entryId = entryId
        self.date = date
        self.onClose = onClose
        _browseDate = State(initialValue: date)
    }

    enum Phase { case loading, denied, empty, ready }

    @State private var phase: Phase = .loading
    @State private var suggestions: [PhotosImportService.Suggestion] = []
    @State private var assetsById: [String: PHAsset] = [:]
    @State private var selected: Set<String> = []
    @State private var importing = false
    @State private var importedCount = 0

    /// Which day to browse (defaults to the entry's date). Ignored when
    /// `showAllRecent` is on.
    @State private var browseDate: Date
    /// When on, browse the most recent photos across the whole library instead
    /// of a single day.
    @State private var showAllRecent = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            footer
        }
        .padding(18)
        .frame(width: 620, height: 560)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(showAllRecent ? "Recent photos" : "Photos from \(dayString)")
                .font(.title2.weight(.semibold))
            Text("Pick the photos to add to this entry. They're copied into your encrypted journal — nothing is uploaded.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if phase != .denied {
                HStack(spacing: 12) {
                    DatePicker("Day", selection: $browseDate, displayedComponents: .date)
                        .labelsHidden()
                        .disabled(showAllRecent)
                        .opacity(showAllRecent ? 0.4 : 1)
                        .onChange(of: browseDate) { _, _ in Task { await load() } }
                    Toggle("Show all recent", isOn: $showAllRecent)
                        .toggleStyle(.checkbox)
                        .onChange(of: showAllRecent) { _, _ in Task { await load() } }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            centered { ProgressView("Looking for photos…") }
        case .denied:
            centered {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("PurpleDiary doesn't have access to your photos.").font(.headline)
                    Text("Grant access in System Settings → Privacy & Security → Photos, then try again.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .frame(maxWidth: 360)
            }
        case .empty:
            centered {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(showAllRecent ? "No photos in your library." : "No photos from \(dayString).").font(.headline)
                    Text(showAllRecent
                         ? "Add photos to Apple Photos, or import from Files instead."
                         : "Try a different day, flip on “Show all recent,” or import from Files.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 360)
            }
        case .ready:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(suggestions) { s in cell(s) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func cell(_ s: PhotosImportService.Suggestion) -> some View {
        let isOn = selected.contains(s.localIdentifier)
        return Button {
            if isOn { selected.remove(s.localIdentifier) } else { selected.insert(s.localIdentifier) }
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = s.preview {
                        Image(nsImage: img).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Color.secondary.opacity(0.12))
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? appState.effectiveAccentColor : Color.secondary.opacity(0.2),
                                lineWidth: isOn ? 3 : 1)
                )

                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, appState.effectiveAccentColor)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            if importedCount > 0 {
                Label("Added \(importedCount)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button("Done") { onClose(); dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await importSelected() }
            } label: {
                if importing { ProgressView().controlSize(.small) }
                else { Text(selected.isEmpty ? "Add" : "Add \(selected.count)") }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(importing || selected.isEmpty || phase != .ready)
        }
    }

    private func centered<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        VStack { Spacer(); v(); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dayString: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: browseDate)
    }

    // MARK: - Load + import

    private func load() async {
        phase = .loading
        selected.removeAll()
        guard await PhotosImportService.requestAccess() else { phase = .denied; return }
        let assets = showAllRecent
            ? PhotosImportService.recentAssets()
            : PhotosImportService.assets(on: browseDate)
        if assets.isEmpty { phase = .empty; return }
        var byId: [String: PHAsset] = [:]
        var seeds: [PhotosImportService.Suggestion] = []
        for a in assets {
            byId[a.localIdentifier] = a
            seeds.append(.init(localIdentifier: a.localIdentifier, creationDate: a.creationDate, preview: nil))
        }
        assetsById = byId
        suggestions = seeds
        phase = .ready
        // Load previews lazily, updating cells as they arrive. Guard against a
        // newer load() having replaced the set out from under us.
        let token = assets.map(\.localIdentifier)
        for a in assets {
            let img = await PhotosImportService.preview(for: a)
            guard suggestions.map(\.localIdentifier) == token else { return }
            if let idx = suggestions.firstIndex(where: { $0.localIdentifier == a.localIdentifier }) {
                suggestions[idx].preview = img
            }
        }
    }

    private func importSelected() async {
        importing = true
        defer { importing = false }
        var added = 0
        for localId in selected {
            guard let asset = assetsById[localId] else { continue }
            if (try? DatabaseService.shared.attachmentExists(entryId: entryId, sourceAssetId: localId)) == true { continue }
            guard let result = await PhotosImportService.loadForImport(asset) else { continue }
            let thumb = ImageProcessing.thumbnailJPEG(from: result.image.data)
            let attachment = Attachment(
                id: UUID().uuidString,
                entryId: entryId,
                kind: "photo",
                filename: result.filename,
                mimeType: "image/jpeg",
                sizeBytes: Int64(result.image.data.count),
                width: result.image.width,
                height: result.image.height,
                data: result.image.data,
                thumbnailData: thumb,
                sourceAssetId: localId,
                createdAt: DatabaseService.isoNow()
            )
            do {
                try appState.addAttachment(attachment)
                added += 1
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
        importedCount += added
        selected.removeAll()
        onClose()   // refresh the editor strip behind the sheet
    }
}
