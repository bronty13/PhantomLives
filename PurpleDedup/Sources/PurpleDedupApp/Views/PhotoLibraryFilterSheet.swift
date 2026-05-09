import SwiftUI
import PurpleDedupCore

/// Sheet for configuring the per-source `PhotoLibraryFilter`. Loads the album
/// list from PhotoKit on appear (one fetch, cached for the life of the sheet)
/// so the user can pick from real album titles rather than typing them in.
///
/// Three sections (top to bottom):
///   1. Albums — multi-select checkbox list
///   2. Subtypes — Live Photo / HDR / Panorama / Screenshot / etc.
///   3. Toggles — favorites only, include hidden
///
/// Closes via Apply (commits filter back to the binding) or Cancel (discards).
/// The Reset button blanks the filter to "no constraint" — same as removing
/// the entry from `photoLibraryFilters`.
struct PhotoLibraryFilterSheet: View {

    let libraryURL: URL
    @Binding var filter: PhotoLibraryFilter
    let onClose: () -> Void

    /// Working copy — edits go here and only commit to `filter` on Apply.
    /// Otherwise hitting Cancel after toggling things would still leak state
    /// back through SwiftUI's two-way binding.
    @State private var working: PhotoLibraryFilter
    @State private var albumNames: [String] = []
    @State private var loadingAlbums = true

    init(libraryURL: URL, filter: Binding<PhotoLibraryFilter>, onClose: @escaping () -> Void) {
        self.libraryURL = libraryURL
        self._filter = filter
        self.onClose = onClose
        self._working = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        // Renders inline inside the sidebar's sources strip. The
        // middle sections (albums + subtypes + toggles) live inside a
        // bounded ScrollView so the editor's total footprint never
        // pushes the cluster list below it off the bottom of the
        // sidebar. The footer (Reset / Cancel / Apply) is OUTSIDE the
        // scroll so its buttons are always reachable, even on small
        // windows or libraries with hundreds of date-named albums.
        //
        // `minHeight` is required: without it, ScrollView in an
        // unbounded parent VStack collapses to 0 height because nothing
        // forces a non-zero size.
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    albumsSection
                    Divider()
                    subtypesSection
                    Divider()
                    togglesSection
                }
                .padding(12)
            }
            .frame(minHeight: 220, maxHeight: 360)
            Divider()
            footer
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .task { await loadAlbums() }
    }

    // MARK: - sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.purple)
                Text("Photos library filter").font(.headline)
                Spacer()
            }
            Text(libraryURL.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Text("Only assets matching every active constraint will be scanned. Empty sections mean \"no constraint.\"")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Albums").font(.subheadline.bold())
                Spacer()
                if let names = working.albumNames, !names.isEmpty {
                    Text("\(names.count) selected")
                        .font(.caption2).foregroundStyle(.purple)
                }
                Button("Clear") {
                    working.albumNames = nil
                }
                .buttonStyle(.borderless)
                .disabled(working.albumNames?.isEmpty ?? true)
                .font(.caption)
            }
            if loadingAlbums {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading albums from Photos…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if albumNames.isEmpty {
                Text("No user albums found, or Photos access was denied. Open System Settings → Privacy & Security → Photos to grant access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                // No nested ScrollView — the parent already wraps the
                // whole sections area in a bounded scroll, so adding
                // another here would conflict (and SwiftUI on Tahoe
                // collapses inner ScrollViews to 0 height inside an
                // outer ScrollView in this layout).
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                    ForEach(albumNames, id: \.self) { name in
                        Toggle(isOn: Binding(
                            get: { working.albumNames?.contains(name) ?? false },
                            set: { isOn in
                                var s = working.albumNames ?? []
                                if isOn { s.insert(name) } else { s.remove(name) }
                                working.albumNames = s.isEmpty ? nil : s
                            }
                        )) {
                            Text(name)
                                .font(.caption)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private var subtypesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Media subtypes").font(.subheadline.bold())
                Spacer()
                if let s = working.includedSubtypes, !s.isEmpty {
                    Text("\(s.count) selected")
                        .font(.caption2).foregroundStyle(.purple)
                }
                Button("Clear") {
                    working.includedSubtypes = nil
                }
                .buttonStyle(.borderless)
                .disabled(working.includedSubtypes?.isEmpty ?? true)
                .font(.caption)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(PhotoKitDeletionService.allSubtypeNames, id: \.self) { name in
                    Toggle(isOn: Binding(
                        get: { working.includedSubtypes?.contains(name) ?? false },
                        set: { isOn in
                            var s = working.includedSubtypes ?? []
                            if isOn { s.insert(name) } else { s.remove(name) }
                            working.includedSubtypes = s.isEmpty ? nil : s
                        }
                    )) {
                        Text(name).font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text("Tip: combine \"Live Photo\" + \"Screenshot\" to surface only those two kinds of duplicates.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Other").font(.subheadline.bold())
            Toggle(isOn: $working.requireFavorite) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Favorites only")
                    Text("Only scan assets marked with the heart in Photos.app.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: includeHiddenBinding) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Include hidden")
                    Text("By default hidden assets are excluded. Turn on to scan visible AND hidden assets together.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: onlyHiddenBinding) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Only hidden")
                    Text("Scan ONLY assets in the Hidden album — visible assets are skipped. Use this to dedup the Hidden album in isolation.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The two hidden toggles are mutually exclusive in their meaningful
    /// states ("only hidden" supersedes "include hidden"). These bindings
    /// enforce that — flipping one off the other when needed — so the
    /// user never lands in a contradictory configuration.
    private var includeHiddenBinding: Binding<Bool> {
        Binding(
            get: { working.includeHidden && !working.onlyHidden },
            set: { isOn in
                working.includeHidden = isOn
                if isOn { working.onlyHidden = false }
            }
        )
    }

    private var onlyHiddenBinding: Binding<Bool> {
        Binding(
            get: { working.onlyHidden },
            set: { isOn in
                working.onlyHidden = isOn
                if isOn { working.includeHidden = false }
            }
        )
    }

    private var footer: some View {
        HStack {
            Button("Reset filter") { working = PhotoLibraryFilter() }
                .disabled(!working.isActive)
            Spacer()
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)
            Button("Apply") {
                filter = working
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    // MARK: - helpers

    private func loadAlbums() async {
        loadingAlbums = true
        defer { loadingAlbums = false }
        let names = await PhotoKitDeletionService.shared.allUserAlbumNames()
        await MainActor.run { self.albumNames = names }
    }
}
