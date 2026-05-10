import SwiftUI
import PurpleDedupCore

/// Sources control at the top of the cluster column. Compact when there
/// are sources (one chip per source); promotes the empty state with a
/// dashed-rectangle drop target + Add… menu when there aren't any.
///
/// Drag-and-drop hits the same surface the user is looking at — the
/// `.onDrop` lives on both the empty-state rectangle AND the populated
/// list view. Putting it on the parent NavigationSplitView wasn't
/// reliable because each split-view column intercepts events before the
/// parent sees them.
///
/// Embeds `PhotosLibraryHint` beneath the source list whenever at least
/// one Photos library is among the sources.
struct SourcesStrip: View {
    @Binding var sources: [ScanSource]
    @Binding var isDropTargeted: Bool
    @Binding var photoFilterSheetItem: PhotoFilterSheetItem?

    @ObservedObject var settingsStore: SettingsStore

    let photosAuthStatus: PhotoKitDeletionService.Authorization

    let onPickFolder: () -> Void
    let onPickPhotosLibrary: () -> Void
    let onToggleLookupOnly: (URL) -> Void
    let onHandleDrop: ([NSItemProvider]) -> Bool
    let onRequestPhotosAccess: () async -> Void
    let onResetPhotosPermission: () async -> Void
    let onOpenPhotosPrivacySettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if sources.isEmpty {
                emptyDropTarget
            } else {
                populatedList
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            // Wrapping the populated state too so the user can drop more
            // folders on the strip after the first add.
            onHandleDrop(providers)
        }
    }

    // MARK: - sections

    private var header: some View {
        HStack {
            Text("Sources").font(.subheadline.bold())
            if isDropTargeted {
                Text("· drop to add")
                    .font(.caption).foregroundStyle(.blue)
            }
            Spacer()
            Menu {
                Button {
                    onPickFolder()
                } label: {
                    Label("Add folder…", systemImage: "folder")
                }
                Button {
                    onPickPhotosLibrary()
                } label: {
                    Label("Add Photos library…", systemImage: "photo.on.rectangle.angled")
                }
            } label: {
                Label("Add…", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add a regular folder or your Apple Photos library (.photoslibrary)")
        }
    }

    private var emptyDropTarget: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isDropTargeted ? "Release to add" : "Drag folders or a Photos library here")
                .font(.callout)
                .foregroundStyle(isDropTargeted ? .blue : .secondary)
            Text("…or click Add… above. Photos libraries (.photoslibrary) live in ~/Pictures by default.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTargeted ? Color.blue : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [4]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            onHandleDrop(providers)
        }
    }

    @ViewBuilder
    private var populatedList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sources, id: \.url) { src in
                sourceRow(for: src)
            }
        }
        if sources.contains(where: \.isPhotosLibrary) {
            PhotosLibraryHint(
                anyUnlocked: sources.contains { $0.isPhotosLibrary && !$0.isLocked },
                authStatus: photosAuthStatus,
                onRequestAccess: onRequestPhotosAccess,
                onResetPermission: onResetPhotosPermission,
                onOpenPrivacySettings: onOpenPhotosPrivacySettings
            )
        }
        // Filter editor lives at the cluster column level — when open it
        // replaces the sources strip + cluster list so its sticky footer is
        // always reachable. See `clusterListColumn` for the conditional swap.
    }

    private func sourceRow(for src: ScanSource) -> some View {
        HStack(spacing: 6) {
            Image(systemName: src.isPhotosLibrary
                  ? "photo.on.rectangle.angled"
                  : (src.isLocked ? "lock.fill" : "folder"))
                .foregroundStyle(src.isPhotosLibrary
                                 ? .purple
                                 : (src.isLocked ? .orange : .primary))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(src.url.path)
                        .font(.caption.monospaced())
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    if src.isLookupOnly {
                        Text("(lookup only)")
                            .font(.caption2.bold())
                            .foregroundStyle(.purple)
                    }
                }
                if src.isPhotosLibrary,
                   let f = settingsStore.settings.photoLibraryFilters[src.url.path],
                   f.isActive {
                    Text(f.summary)
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer()
            // Lookup-only mode toggle for Photos libraries.
            if src.isPhotosLibrary {
                Button {
                    onToggleLookupOnly(src.url)
                } label: {
                    Image(systemName: src.isLookupOnly
                          ? "magnifyingglass.circle.fill"
                          : "magnifyingglass.circle")
                        .foregroundStyle(src.isLookupOnly ? .purple : .secondary)
                }
                .buttonStyle(.borderless)
                .help(src.isLookupOnly
                      ? "Lookup-only mode: this library tags folder duplicates that already live in Photos. Click to make it a regular scan source."
                      : "Treat this library as a lookup reference: scan folders for duplicates and tag any that already live in Photos.")
            }
            // Filter funnel for Photos libraries — opens the sheet.
            if src.isPhotosLibrary {
                let active = settingsStore.settings.photoLibraryFilters[src.url.path]?.isActive == true
                Button {
                    if photoFilterSheetItem?.url == src.url {
                        photoFilterSheetItem = nil
                    } else {
                        photoFilterSheetItem = PhotoFilterSheetItem(url: src.url)
                    }
                } label: {
                    Image(systemName: active
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(active ? .purple : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Filter this Photos library by album, subtype, favorites, or hidden state")
            }
            Button {
                sources.removeAll { $0.url == src.url }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help("Remove this source")
        }
    }
}
