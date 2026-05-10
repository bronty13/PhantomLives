import SwiftUI
import PurpleDedupCore

/// Right-hand pane of the three-column layout. Receives the current selection
/// and composes:
///   - `ClusterHeader` (title, kind capsule, thumb-size slider, action buttons)
///   - LazyVGrid of `FileCard`s (per-file thumbnails + decision controls)
///   - `MetadataDiffTable` (diff-highlighted EXIF table)
///
/// Most of the work lives in those components and `MetadataLoader`. This view
/// is the composition layer + the small "select a cluster" empty state.
struct ComparisonView: View {
    let selection: ClusterSelection?

    @Binding var decisionsByCluster: [String: ClusterDecisions]
    @Binding var manualOverrides: [String: [URL: Decision]]
    var onApproveAndNext: () -> Void = {}
    var onRequestTrash: ([DiscoveredFile]) -> Void = { _ in }
    var photosLookupHashes: Set<String> = []

    @StateObject private var loader = MetadataLoader()
    @State private var thumbSize: CGFloat = 220

    private var decisions: DecisionStore {
        DecisionStore(
            decisionsByCluster: $decisionsByCluster,
            manualOverrides: $manualOverrides
        )
    }

    var body: some View {
        if let s = selection {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ClusterHeader(
                        selection: s,
                        thumbSize: $thumbSize,
                        pendingDeletes: pendingDeletes(in: s),
                        onApproveAndNext: onApproveAndNext,
                        onRequestTrash: onRequestTrash
                    )
                    Divider()
                    fileGrid(s)
                    Divider()
                    MetadataDiffTable(selection: s, loader: loader)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: s.id) {
                await loader.load(for: s, photosLookupHashes: photosLookupHashes)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("Select a duplicate group to compare")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Adaptive thumbnail grid. Adaptive minimum follows `thumbSize` so the
    /// user's slider preference flows through to the layout without
    /// re-instantiating the view.
    private func fileGrid(_ s: ClusterSelection) -> some View {
        let columns = [GridItem(.adaptive(minimum: thumbSize), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(s.files, id: \.url) { f in
                FileCard(
                    file: f,
                    selection: s,
                    thumbSize: thumbSize,
                    inLookupHits: loader.lookupHits.contains(f.url),
                    isHiddenInPhotos: loader.metadata[f.url]?.photosIsHidden == true,
                    decisions: decisions,
                    onRequestTrashOne: { onRequestTrash([$0]) }
                )
            }
        }
        .padding(.vertical, 4)
    }

    /// Files in the currently-shown cluster that are marked DELETE (manual
    /// override or engine recommendation). Drives the per-cluster Trash
    /// button's count and the subset shipped to the preflight modal.
    private func pendingDeletes(in s: ClusterSelection) -> [DiscoveredFile] {
        s.files.filter {
            if case .delete = decisions.decision(for: $0.url, in: s) { return true }
            return false
        }
    }
}
