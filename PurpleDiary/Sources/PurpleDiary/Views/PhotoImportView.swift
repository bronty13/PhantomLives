import SwiftUI
import Photos
import AppKit

/// The editor's Photos section: a strip of the entry's attached photo
/// thumbnails (each removable) plus an "Add photos from this day" button that
/// opens the suggestion sheet. Loads thumbnails (not full images) for the strip.
struct EntryPhotosSection: View {
    @EnvironmentObject private var appState: AppState
    let entry: Entry

    @State private var thumbs: [AttachmentThumb] = []
    @State private var showingSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Photos")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingSuggestions = true
                } label: {
                    Label("Add photos from this day", systemImage: "photo.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if thumbs.isEmpty {
                Text("No photos yet. Pull in the ones you took on \(dayString) to set the scene.")
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
    }

    private var dayString: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: entry.dateValue)
    }

    private func thumbView(_ thumb: AttachmentThumb) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = thumb.thumbnailData, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

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
            .help("Remove this photo from the entry")
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

    enum Phase { case loading, denied, empty, ready }

    @State private var phase: Phase = .loading
    @State private var suggestions: [PhotosImportService.Suggestion] = []
    @State private var assetsById: [String: PHAsset] = [:]
    @State private var selected: Set<String> = []
    @State private var importing = false
    @State private var importedCount = 0

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            footer
        }
        .padding(18)
        .frame(width: 620, height: 540)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Photos from \(dayString)")
                .font(.title2.weight(.semibold))
            Text("Pick the photos to add to this entry. They're copied into your encrypted journal — nothing is uploaded.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    Text("No photos from \(dayString).").font(.headline)
                    Text("PurpleDiary looks for photos taken on the same day as this entry.")
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
        return f.string(from: date)
    }

    // MARK: - Load + import

    private func load() async {
        guard await PhotosImportService.requestAccess() else { phase = .denied; return }
        let assets = PhotosImportService.assets(on: date)
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
        // Load previews lazily, updating cells as they arrive.
        for a in assets {
            let img = await PhotosImportService.preview(for: a)
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
