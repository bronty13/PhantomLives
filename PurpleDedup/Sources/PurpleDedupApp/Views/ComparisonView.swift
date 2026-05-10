import SwiftUI
import AppKit
import PurpleDedupCore

/// Right-hand pane of the three-column layout. Receives the user's currently-selected
/// cluster and renders a grid of large thumbnails plus a per-file metadata table with
/// differing rows highlighted. EXIF/codec data is loaded lazily on selection — most
/// files in a scan never get viewed, and pre-extracting metadata for thousands of
/// files is wasted work.
struct ComparisonView: View {
    let selection: ClusterSelection?

    /// Per-cluster decisions, keyed by cluster ID. When the selection changes,
    /// the engine re-runs against the new cluster but `decisionsByCluster`
    /// remembers earlier rulings — so a user can scan, mark a few clusters,
    /// and still come back to ones they already reviewed.
    @Binding var decisionsByCluster: [String: ClusterDecisions]

    /// Per-cluster MANUAL overrides (URL → Decision). The engine output is the
    /// recommendation; manual overrides win in the final tally. Stored
    /// separately so re-running rules doesn't lose the user's input.
    @Binding var manualOverrides: [String: [URL: Decision]]

    /// Closure the comparison pane invokes when the user presses "Approve &
    /// next" — keeps the actual nav logic in `ContentView` where the cluster
    /// list lives. Defaults to a no-op when not provided.
    var onApproveAndNext: () -> Void = {}

    /// Trash a specific subset of files immediately (per-file or per-cluster
    /// actions in this pane). The host view raises the preflight sheet pre-
    /// filled with this list so the user gets the same confirm + undo
    /// guarantees as the bulk Trash button.
    var onRequestTrash: ([DiscoveredFile]) -> Void = { _ in }

    /// Hashes of every file in the user's lookup-mode Photos library
    /// source(s). When a file in the current cluster has a matching content
    /// hash, render an "Also in Photos library" badge so the user can spot
    /// folder duplicates that already live in Photos. Empty when no
    /// lookup-mode source is configured.
    var photosLookupHashes: Set<String> = []

    @State private var metadata: [URL: FileMetadata] = [:]
    @State private var loadingMetadata: Bool = false
    @State private var thumbSize: CGFloat = 220
    /// URLs in the current selection whose content hash is in
    /// `photosLookupHashes`. Populated during `loadMetadata` via a per-
    /// file DB lookup (cheap when the cache already has the file).
    @State private var lookupHits: Set<URL> = []
    /// Reverse-geocoded place names per file URL. Populated async after
    /// `loadMetadata` for any file with a GPS coord; nil/missing entries
    /// fall back to raw lat/lon in the metadata table.
    @State private var placeNames: [URL: String] = [:]

    var body: some View {
        if let selection = selection {
            // Outer vertical ScrollView so metadata isn't clipped when the
            // thumbnail grid eats the visible height. The grid below keeps its
            // own internal layout (LazyVGrid is fine to grow naturally inside
            // a ScrollView). Header is pinned at the top of the scroll
            // container's content so the Approve & next button stays
            // discoverable when the user is reviewing a long cluster.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    header(selection)
                    Divider()
                    thumbnailGrid(selection)
                    Divider()
                    metadataTable(selection)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: selection.id) { await loadMetadata(selection) }
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

    // MARK: - sections

    private func header(_ s: ClusterSelection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.title).font(.title3).bold()
                Spacer()
                Text(s.kindLabel)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(s.kindColor.opacity(0.2))
                    .foregroundStyle(s.kindColor)
                    .clipShape(Capsule())
            }
            Text(s.subtitle).font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Thumbnail size").font(.caption).foregroundStyle(.secondary)
                Slider(value: $thumbSize, in: 96...360, step: 16).frame(maxWidth: 220)
                Text("\(Int(thumbSize))px").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                let pending = pendingDeletesInCurrentCluster(s)
                if !pending.isEmpty {
                    Button(role: .destructive) {
                        onRequestTrash(pending)
                    } label: {
                        Label("Trash \(pending.count) duplicate\(pending.count == 1 ? "" : "s")", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Move just this cluster's marked files to Trash (skips the cross-cluster batch)")
                }
                Button {
                    onApproveAndNext()
                } label: {
                    Label("Approve & next", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .help("Accept the current recommendation and jump to the next undecided cluster (⌘⏎)")
            }
        }
    }

    /// Files in the currently-shown cluster that are marked DELETE (manual
    /// override or engine recommendation). Drives the per-cluster Trash
    /// button's count and the subset it ships to the preflight modal.
    private func pendingDeletesInCurrentCluster(_ s: ClusterSelection) -> [DiscoveredFile] {
        s.files.filter {
            if case .delete = decision(for: $0.url, in: s) { return true }
            return false
        }
    }

    /// Large adaptive thumbnail grid. Adaptive minimum follows `thumbSize` so the
    /// user's slider width preference flows through to the layout without
    /// re-instantiating the view.
    private func thumbnailGrid(_ s: ClusterSelection) -> some View {
        // No internal ScrollView — the parent ScrollView handles vertical
        // scrolling for the entire comparison pane. Wrapping a LazyVGrid in
        // its own ScrollView previously clipped the metadata table when the
        // thumbnails were tall.
        let columns = [GridItem(.adaptive(minimum: thumbSize), spacing: 12)]
        return Group {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(s.files, id: \.url) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            ThumbnailView(url: f.url, size: thumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(borderColor(for: f.url, in: s), lineWidth: 2)
                                )
                            decisionBadge(for: f.url, in: s)
                                .padding(6)
                            // "Also in Photos library" badge — shown when
                            // the user has a lookup-mode Photos source AND
                            // this file's content hash matches an asset in
                            // it. Bottom-leading so it doesn't fight the
                            // KEEP/DELETE chip on the top-right.
                            if lookupHits.contains(f.url) {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Label("In Photos", systemImage: "photo.on.rectangle.angled")
                                            .labelStyle(.titleAndIcon)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.purple.opacity(0.85))
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                }
                                .padding(6)
                            }
                            // "Hidden" badge — shown when the asset lives
                            // in Photos.app's Hidden album. Top-leading so
                            // it stays visible alongside the KEEP/DELETE
                            // decision chip (top-right) and the "In
                            // Photos" capsule (bottom-leading).
                            if metadata[f.url]?.photosIsHidden == true {
                                VStack {
                                    HStack {
                                        Label("Hidden", systemImage: "eye.slash.fill")
                                            .labelStyle(.titleAndIcon)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.orange.opacity(0.9))
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .padding(6)
                            }
                        }
                        .contextMenu {
                            Button("Mark KEEP")  { setManual(.keep(reason: "manual"), for: f.url, in: s) }
                            Button("Mark DELETE") { setManual(.delete(reason: "manual"), for: f.url, in: s) }
                            Button("Use recommendation") { clearManual(for: f.url, in: s) }
                            Divider()
                            Button("Trash this file now…", role: .destructive) {
                                onRequestTrash([f])
                            }
                            Divider()
                            Button("Quick Look") { QuickLookCoordinator.shared.preview(f.url) }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([f.url])
                            }
                            Button("Open in default app") { NSWorkspace.shared.open(f.url) }
                        }
                        .onTapGesture(count: 2) { QuickLookCoordinator.shared.preview(f.url) }
                        // Filename + tiny Reveal-in-Finder button. Path
                        // location matters when deciding which copy to keep
                        // (e.g. "the one in /Originals/ wins over the one in
                        // /Downloads/"); the parent-directory line below
                        // surfaces this without a context-menu trip.
                        HStack(spacing: 4) {
                            Text(f.url.lastPathComponent)
                                .font(.caption.bold()).lineLimit(1).truncationMode(.middle)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([f.url])
                            } label: {
                                Image(systemName: "arrow.right.square")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                        .frame(width: thumbSize, alignment: .leading)

                        Text(parentDirectoryDisplay(f.url))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: thumbSize, alignment: .leading)
                            .help(f.url.path)

                        Text(formatBytes(f.sizeBytes))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        decisionControls(for: f.url, in: s)
                        if let reason = decisionReason(for: f.url, in: s) {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func decisionBadge(for url: URL, in s: ClusterSelection) -> some View {
        if let d = decision(for: url, in: s) {
            switch d {
            case .keep:
                Text("KEEP")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .overlay(manualMark(url: url, in: s))
            case .delete:
                Text("DELETE")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .overlay(manualMark(url: url, in: s))
            }
        }
    }

    /// Visible Keep / Delete pair under each thumbnail. Always present so the
    /// user never has to discover the right-click menu — clicking either button
    /// sets a manual override that wins over the engine's recommendation. The
    /// "↻" reset chip clears the override so the engine's pick is restored.
    @ViewBuilder
    private func decisionControls(for url: URL, in s: ClusterSelection) -> some View {
        let current = decision(for: url, in: s)
        let isManual = manualOverrides[s.id]?[url] != nil
        HStack(spacing: 4) {
            Button {
                setManual(.keep(reason: "manual"), for: url, in: s)
            } label: {
                Label("Keep", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.bold())
                    .foregroundStyle(isKeepActive(current) ? .white : .green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(isKeepActive(current) ? Color.green : Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Keep this file (overrides the engine's recommendation if needed)")

            Button {
                setManual(.delete(reason: "manual"), for: url, in: s)
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.bold())
                    .foregroundStyle(isDeleteActive(current) ? .white : .red)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(isDeleteActive(current) ? Color.red : Color.red.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Mark this file for trashing")

            if isManual {
                Button {
                    clearManual(for: url, in: s)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Reset to engine recommendation")
            }
        }
        .frame(width: thumbSize, alignment: .leading)
    }

    private func isKeepActive(_ d: Decision?) -> Bool {
        if case .keep = d { return true }
        return false
    }

    private func isDeleteActive(_ d: Decision?) -> Bool {
        if case .delete = d { return true }
        return false
    }

    @ViewBuilder
    private func manualMark(url: URL, in s: ClusterSelection) -> some View {
        if manualOverrides[s.id]?[url] != nil {
            // Tiny dot in the corner so the user can tell at a glance which
            // decisions they overrode versus which the engine made.
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .offset(x: 14, y: -8)
        }
    }

    private func borderColor(for url: URL, in s: ClusterSelection) -> Color {
        switch decision(for: url, in: s) {
        case .keep:   return .green.opacity(0.7)
        case .delete: return .red.opacity(0.7)
        case nil:     return .secondary.opacity(0.3)
        }
    }

    private func decision(for url: URL, in s: ClusterSelection) -> Decision? {
        if let manual = manualOverrides[s.id]?[url] { return manual }
        return decisionsByCluster[s.id]?.perFile[url]
    }

    private func decisionReason(for url: URL, in s: ClusterSelection) -> String? {
        switch decision(for: url, in: s) {
        case .keep(let r):   return r.isEmpty ? nil : "keeper · \(r)"
        case .delete(let r): return r.isEmpty ? nil : "delete · \(r)"
        case nil:            return nil
        }
    }

    private func setManual(_ d: Decision, for url: URL, in s: ClusterSelection) {
        var m = manualOverrides[s.id] ?? [:]
        m[url] = d
        manualOverrides[s.id] = m
    }

    private func clearManual(for url: URL, in s: ClusterSelection) {
        var m = manualOverrides[s.id] ?? [:]
        m[url] = nil
        if m.isEmpty {
            manualOverrides[s.id] = nil
        } else {
            manualOverrides[s.id] = m
        }
    }

    /// Side-by-side metadata table. Each row is one EXIF/codec attribute; cells with
    /// values that disagree across the cluster get a subtle background tint so the
    /// user's eye lands on the differences (FR-3.7 — visual diff indicators).
    private func metadataTable(_ s: ClusterSelection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Metadata").font(.headline)
                if loadingMetadata {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            let allRows = unifiedRowKeys(for: s)
            // Horizontal scroll lets the per-file columns extend wider than
            // the pane for clusters with many members; vertical scrolling
            // is handled by the outer pane ScrollView so the table can grow
            // naturally without clipping.
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    // Header — filename per column. Always present even when
                    // EXIF metadata isn't, because the path/size rows below
                    // are still useful on their own.
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(s.files, id: \.url) { f in
                            Text(f.url.lastPathComponent)
                                .font(.caption.bold())
                                .lineLimit(1).truncationMode(.middle)
                                .frame(minWidth: 200, alignment: .leading)
                        }
                    }
                    Divider().gridCellColumns(s.files.count + 1)

                    // PATH — always at the top of the table because directory
                    // location is one of the most common deciding factors
                    // ("keep the one in Originals, dump the one in Downloads").
                    // Paths always differ across cluster members (otherwise
                    // they'd be the same file), so the orange diff highlight
                    // is permanent on this row.
                    GridRow {
                        Text("Path").font(.callout).foregroundStyle(.secondary)
                        ForEach(s.files, id: \.url) { f in
                            Text(parentDirectoryDisplay(f.url))
                                .font(.callout.monospaced())
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .padding(.horizontal, 4)
                                .background(Color.orange.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .help(f.url.path)
                                .frame(minWidth: 200, alignment: .leading)
                        }
                    }

                    // SIZE — companion row for path. Always populated, often
                    // identical (exact dupes) but useful when comparing
                    // perceptual variants where one is a smaller re-encode.
                    GridRow {
                        Text("Size").font(.callout).foregroundStyle(.secondary)
                        ForEach(s.files, id: \.url) { f in
                            let allSizes = s.files.map(\.sizeBytes)
                            let sizesDiffer = !allSizes.allSatisfy { $0 == allSizes.first }
                            Text(formatBytes(f.sizeBytes))
                                .font(.callout.monospaced())
                                .padding(.horizontal, 4)
                                .background(sizesDiffer ? Color.orange.opacity(0.18) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    // EXIF / codec rows (loaded lazily) — present below the
                    // always-on path/size pair so the comparison view is
                    // immediately useful even before metadata extraction
                    // finishes for the selected cluster.
                    if allRows.isEmpty && !loadingMetadata {
                        GridRow {
                            Text("Metadata").font(.callout).foregroundStyle(.secondary)
                            Text("No EXIF or codec metadata available for these files.")
                                .font(.callout).foregroundStyle(.secondary)
                                .gridCellColumns(s.files.count)
                        }
                    } else {
                        ForEach(allRows, id: \.self) { rowKey in
                            let valuesByURL = valuesForRow(rowKey, in: s)
                            let differs = valuesDiffer(valuesByURL.map { $0.value })
                            GridRow {
                                Text(labelFor(rowKey))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                ForEach(s.files, id: \.url) { f in
                                    Text(valuesByURL[f.url] ?? "—")
                                        .font(.callout.monospaced())
                                        .padding(.horizontal, 4)
                                        .background(differs ? Color.orange.opacity(0.18) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - data plumbing

    private func loadMetadata(_ s: ClusterSelection) async {
        // Reset and load on selection change. We capture the URL set and bail early
        // if a faster selection beat us to the punch — `task(id:)` cancels and
        // re-launches so the result lands on whichever selection the user is now
        // looking at.
        //
        // Photos library paths get a SECOND fetch in parallel via
        // `PhotoKitDeletionService.fetchMetadata` so albums + subtypes +
        // favorite/hidden status surface alongside the EXIF data.
        loadingMetadata = true
        defer { loadingMetadata = false }
        let urls = s.files.map(\.url)
        let extractor = MetadataExtractor()
        var results: [URL: FileMetadata] = [:]

        await withTaskGroup(of: (URL, FileMetadata).self) { group in
            for url in urls {
                group.addTask {
                    var meta = await extractor.extract(url: url)
                    // Enrich with Photos-app metadata if this file lives in a
                    // `.photoslibrary`. The PhotoKit fetch is a no-op for
                    // non-library paths and for auth states < .limited.
                    if url.path.contains(".photoslibrary/") {
                        if let p = await PhotoKitDeletionService.shared.fetchMetadata(forPath: url) {
                            meta.photosAlbumNames = p.albumNames
                            meta.photosMediaSubtypes = p.mediaSubtypes
                            meta.photosIsFavorite = p.isFavorite
                            meta.photosIsHidden = p.isHidden
                            meta.photosCreationDate = p.creationDate
                            meta.photosHasAdjustments = p.hasAdjustments
                            meta.photosBurstIdentifier = p.burstIdentifier
                            meta.photosIsBurstRepresentative = p.isBurstRepresentative
                        }
                    }
                    return (url, meta)
                }
            }
            for await (url, m) in group {
                results[url] = m
            }
        }
        if Task.isCancelled { return }
        metadata = results

        // Reverse-geocode any GPS coords. Cache-coalesced through
        // `GeoCache` so the same neighborhood doesn't burn N requests on
        // a 12-photo burst. Best-effort: failures leave the row showing
        // raw lat/lon. Runs in the background so the metadata table
        // appears immediately and place names fill in as they resolve.
        Task { [urls, results] in
            for url in urls {
                if Task.isCancelled { return }
                guard let m = results[url],
                      let lat = m.gpsLatitude, let lon = m.gpsLongitude else { continue }
                if let name = await GeoCache.shared.placeName(latitude: lat, longitude: lon) {
                    await MainActor.run {
                        // Only commit if the user is still on this cluster.
                        // Otherwise placeNames pollutes future sessions.
                        if metadata[url] != nil {
                            placeNames[url] = name
                        }
                    }
                }
            }
        }

        // Lookup-mode badge population. For each file, read its content
        // hash from the cache and check against `photosLookupHashes`. Done
        // here so the per-thumbnail badge appears as soon as metadata
        // settles (no separate task chain needed).
        if !photosLookupHashes.isEmpty {
            var hits: Set<URL> = []
            if let db = try? Database.openDefault() {
                for url in urls {
                    if let f = try? db.file(at: url.path),
                       let blob = f.contentHash {
                        let hex = blob.map { String(format: "%02x", $0) }.joined()
                        if photosLookupHashes.contains(hex) {
                            hits.insert(url)
                        }
                    }
                }
            }
            if Task.isCancelled { return }
            lookupHits = hits
        } else {
            lookupHits = []
        }
    }

    /// All metadata row IDs that appear on any file in the cluster — preserves the
    /// natural display order from `FileMetadata.rows()` by interleaving the union.
    private func unifiedRowKeys(for s: ClusterSelection) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for f in s.files {
            guard let m = metadata[f.url] else { continue }
            for row in m.rows() where !seen.contains(row.id) {
                seen.insert(row.id)
                ordered.append(row.id)
            }
        }
        return ordered
    }

    private func valuesForRow(_ id: String, in s: ClusterSelection) -> [URL: String] {
        var out: [URL: String] = [:]
        for f in s.files {
            guard let m = metadata[f.url] else { continue }
            if let row = m.rows().first(where: { $0.id == id }) {
                if id == "gps", let place = placeNames[f.url] {
                    // Decorate with the reverse-geocoded place when available;
                    // raw coords stay visible for precision-sensitive use cases.
                    out[f.url] = "\(place)  ·  \(row.value)"
                } else {
                    out[f.url] = row.value
                }
            }
        }
        return out
    }

    private func valuesDiffer(_ values: [String]) -> Bool {
        guard let first = values.first else { return false }
        return values.contains { $0 != first }
    }

    private func labelFor(_ id: String) -> String {
        // Mirror the labels FileMetadata.Row uses; we look one up by walking any
        // metadata that contains this id.
        for m in metadata.values {
            if let row = m.rows().first(where: { $0.id == id }) { return row.label }
        }
        return id
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter(); bcf.allowedUnits = [.useAll]; bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }

    /// Compact parent-directory display. Replaces the user's home directory
    /// with `~` (so `/Users/bronty/Pictures/foo/` renders `~/Pictures/foo/`)
    /// and trims a leading `/Volumes/` for external drives so the meaningful
    /// folder hierarchy uses the full thumbnail width.
    private func parentDirectoryDisplay(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if dir == home || dir.hasPrefix(home + "/") {
            return "~" + dir.dropFirst(home.count) + "/"
        }
        return dir + "/"
    }
}

// MARK: - selection model

/// Type-erased cluster passed from the cluster list to the comparison pane. The
/// three cluster kinds (exact / similar_photo / similar_video) have different
/// underlying data shapes; this struct flattens them to the subset the comparison
/// view actually needs.
struct ClusterSelection: Identifiable, Hashable {
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let files: [DiscoveredFile]

    enum Kind: Hashable {
        case exact
        case similarPhoto
        case similarVideo
    }

    var kindLabel: String {
        switch kind {
        case .exact:        return "EXACT"
        case .similarPhoto: return "SIMILAR PHOTOS"
        case .similarVideo: return "SIMILAR VIDEOS"
        }
    }

    var kindColor: Color {
        switch kind {
        case .exact:        return .green
        case .similarPhoto: return .blue
        case .similarVideo: return .purple
        }
    }
}
