import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case metadata, content, tracks, subclips, log
    var id: String { rawValue }
    var label: String {
        switch self {
        case .metadata: return "Metadata"
        case .content:  return "Content"
        case .tracks:   return "Tracks"
        case .subclips: return "Subclips"
        case .log:      return "Log"
        }
    }
    var icon: String {
        switch self {
        case .metadata: return "tag.fill"
        case .content:  return "rectangle.grid.2x2"
        case .tracks:   return "waveform.path.ecg"
        case .subclips: return "scissors"
        case .log:      return "list.bullet.rectangle"
        }
    }
}

struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var playerController = PlayerController()
    @State private var filterText: String = ""
    @AppStorage("detailTab") private var detailTab: DetailTab = .content

    private var filteredAssets: [Asset] {
        let base = appState.displayedAssets
        let term = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return base }
        return base.filter { $0.filename.lowercased().contains(term) }
    }

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider()
            Group {
                if appState.rootFolder == nil {
                    emptyState
                } else {
                    switch appState.viewMode {
                    case "grid":   gridView
                    case "detail": detailView
                    default:       listView   // includes "list"
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.selectedAsset) { _, newValue in
            loadIntoPlayer(newValue)
        }
    }

    /// Browser toolbar (was previously a `.safeAreaInset` overlay).
    /// Moved into the VStack so ScrollView-backed grid mode doesn't
    /// render content under it.
    @ViewBuilder
    private var browserToolbar: some View {
        VStack(spacing: 0) {
            // Row 1: back/forward + drilldown + type filter chips + sort + scan status
            HStack(spacing: 10) {
                    Button { appState.goBack() } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!appState.canGoBack)
                    .keyboardShortcut("[", modifiers: [.command])
                    .help("Back (⌘[)")

                    Button { appState.goForward() } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!appState.canGoForward)
                    .keyboardShortcut("]", modifiers: [.command])
                    .help("Forward (⌘])")

                    Divider().frame(height: 14)

                    viewModeToggle

                    Divider().frame(height: 14)

                    // Toolbar "Drilldown" toggle — Kyno semantics: it
                    // acts on the currently-selected folder, NOT a
                    // hidden global flag.
                    drilldownToolbarButton

                    Divider().frame(height: 14)

                    typeFilterChips

                    Spacer()

                    filterMenu

                    columnsMenu

                    sortMenu

                    // Grid-mode-only tile-size slider. Tucked between
                    // sort and scan status so it doesn't compete for
                    // space in List or Detail mode.
                    if appState.viewMode == "grid" {
                        Divider().frame(height: 14)
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.grid.3x2")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Slider(value: $gridTileSize, in: 100...320)
                                .frame(width: 90)
                                .controlSize(.mini)
                        }
                        .help("Resize Grid view tiles")
                    }

                    if appState.isScanning {
                        ProgressView().controlSize(.small)
                        Text(appState.scanProgress)
                            .foregroundStyle(.secondary).font(.caption)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Text("\(filteredAssets.count) of \(appState.assets.count)")
                            .foregroundStyle(.secondary).font(.caption)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
                // Row 2: name filter
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by name…", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                // Row 3: active-filter pills. Only shown when at least
                // one criterion is pinned, so the toolbar doesn't grow
                // a third row for users who aren't using advanced
                // filtering.
                if !appState.activeFilters.isEmpty {
                    Divider()
                    activeFiltersBar
                }
            }
    }

    /// Active-filter pills bar — one capsule per `FilterCriterion`,
    /// each tappable to remove. Trailing "Clear all" removes
    /// everything.
    @ViewBuilder
    private var activeFiltersBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            // Match-mode toggle. Tap the chip to flip AND ↔ OR
            // without diving back into the Filter menu. Only shown
            // when there are 2+ criteria (single-criterion case
            // is degenerate).
            if appState.activeFilters.count >= 2 {
                Button {
                    appState.filterMatchMode = (appState.filterMatchMode == "all" ? "any" : "all")
                } label: {
                    Text(appState.filterMatchMode == "all" ? "AND" : "OR")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.35), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Tap to switch between match-all (AND) and match-any (OR).")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(appState.activeFilters) { criterion in
                        Button {
                            appState.removeFilter(criterion)
                        } label: {
                            HStack(spacing: 4) {
                                Text(criterion.displayLabel)
                                    .font(.caption)
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.20), in: Capsule())
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this filter")
                    }
                }
            }
            Spacer()
            Button("Clear All") { appState.clearFilters() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - List view (Kyno ⌘2)

    /// Full-width table, no detail pane, no right inspector. Pure
    /// browsing surface — exactly what the user wants for navigating
    /// hundreds of clips at a time. Double-click opens the Detail
    /// sheet (or switch the view mode to "detail" for inline).
    private var listView: some View {
        assetTable
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid view (Kyno ⌘1)

    /// User-settable thumbnail tile size for Grid view (⌘1). Drives
    /// the LazyVGrid's adaptive minimum so tiles flow with the
    /// window. Persisted as a Double via @AppStorage.
    @AppStorage("gridTileSize") private var gridTileSize: Double = 180

    private var gridColumns: [GridItem] {
        let m = CGFloat(gridTileSize)
        return [GridItem(.adaptive(minimum: m, maximum: m * 1.4), spacing: 12)]
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(filteredAssets) { asset in
                    gridCellWrapper(asset: asset)
                }
            }
            .padding(12)
        }
    }

    /// Pulled out so the type-checker has a tractable shape — chaining
    /// .contentShape / .overlay / .contextMenu on a parameterised
    /// GridCell exceeds the type-check budget on Swift 5.9.
    @ViewBuilder
    private func gridCellWrapper(asset: Asset) -> some View {
        let selected = appState.selectedAssetPaths.contains(asset.path)
                    || (appState.selectedAssetPaths.isEmpty
                        && appState.selectedAssetPath == asset.path)
        let primary = appState.selectedAssetPath == asset.path
        GridCell(asset: asset,
                 isSelected: selected,
                 isPrimary: primary,
                 transcodeQueue: appState.transcodeQueue)
            .contentShape(Rectangle())
            .overlay(
                ClickWithModifiers(
                    onClick: { mods in
                        appState.handleAssetClick(path: asset.path, modifiers: mods)
                    },
                    onDoubleClick: {
                        openInlineDetail(asset)
                    }
                )
            )
            .contextMenu {
                AssetContextMenu(asset: asset)
                    .environmentObject(appState)
            }
    }

    /// Set the selection and switch into the inline Detail view (⌘3),
    /// which renders the file preview + metadata panel as the main
    /// area of the window instead of as a floating sheet — matches
    /// Kyno's cohesive single-window layout. Pressing ⌘1 or ⌘2 (or
    /// the toolbar mode toggle) returns the user to Grid / List.
    private func openInlineDetail(_ asset: Asset) {
        appState.selectedAssetPath = asset.path
        appState.viewMode = "detail"
    }

    // MARK: - Detail view (Kyno ⌘3) — inline, full window

    /// Inline single-clip detail view. Same content as the Detail
    /// sheet, but rendered as the main area instead of in a separate
    /// sheet. Lets the user stay in Detail mode while paging through
    /// clips with the toolbar's prev/next arrows.
    @ViewBuilder
    private var detailView: some View {
        if appState.selectedAsset != nil {
            ClipDetailInline(playerController: playerController)
                .environmentObject(appState)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Select a clip to view in Detail mode.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Multi-select binding for the asset Table. Table natively
    /// supports `Set<SelectionValue>` for Cmd / Shift modifiers. We
    /// mirror the primary anchor (`selectedAssetPath`) on selection
    /// changes so single-clicking a row still updates the viewer
    /// focus. Pulled out as a computed property so the Table call
    /// site stays inside the type-checker's expression budget.
    private var tableSelection: Binding<Set<String>> {
        Binding(
            get: { appState.selectedAssetPaths },
            set: { newValue in
                appState.selectedAssetPaths = newValue
                if newValue.count == 1, let only = newValue.first {
                    appState.selectedAssetPath = only
                } else if newValue.isEmpty {
                    appState.selectedAssetPath = nil
                }
            }
        )
    }

    private var assetTable: some View {
        Table(filteredAssets, selection: tableSelection) {
            TableColumn("") { asset in
                ThumbnailCell(asset: asset)
            }
            .width(90)
            TableColumn("Name") { asset in
                Text(asset.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Codec") { asset in
                Text(asset.codec ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Resolution") { asset in
                if let w = asset.widthPx, let h = asset.heightPx {
                    Text("\(w)×\(h)")
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 110)
            TableColumn("FPS") { asset in
                if let r = asset.frameRate {
                    Text(String(format: "%.2f", r))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 50, ideal: 70)
            TableColumn("Duration") { asset in
                Text(formatDuration(asset.durationSeconds))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Size") { asset in
                Text(formatSize(asset.sizeBytes))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            // Optional columns — SwiftUI Table caps at 10 columns, so
            // we expose up to 3 user-selected ones in priority order
            // (toggle via the Columns menu in the toolbar). User can
            // rotate which 3 are visible by toggling off then on.
            if let col = optionalColumn(at: 0) {
                TableColumn(col.displayName) { asset in
                    optionalCell(asset, column: col)
                }
                .width(min: 50, ideal: col.idealWidth)
            }
            if let col = optionalColumn(at: 1) {
                TableColumn(col.displayName) { asset in
                    optionalCell(asset, column: col)
                }
                .width(min: 50, ideal: col.idealWidth)
            }
            if let col = optionalColumn(at: 2) {
                TableColumn(col.displayName) { asset in
                    optionalCell(asset, column: col)
                }
                .width(min: 50, ideal: col.idealWidth)
            }
        }
        // Row-level context menu + primary action wired through the
        // Table's selection model. This is the SwiftUI Table API for
        // "right-click any column in the row" and "double-click any
        // column in the row" — replaces the per-cell tap gestures we
        // used before (which only fired on the Name / thumbnail
        // columns).
        .contextMenu(forSelectionType: String.self) { selectedPaths in
            if let path = selectedPaths.first,
               let asset = filteredAssets.first(where: { $0.path == path }) {
                AssetContextMenu(asset: asset)
                    .environmentObject(appState)
            }
        } primaryAction: { selectedPaths in
            if let path = selectedPaths.first,
               let asset = filteredAssets.first(where: { $0.path == path }) {
                openInlineDetail(asset)
            }
        }
    }

    /// Ordered list of user-enabled optional columns. The order is
    /// stable (matches `ListColumn.allCases`) so toggling on/off
    /// doesn't shuffle the user's table layout.
    private var visibleOptionalColumns: [ListColumn] {
        let on = appState.listColumns
        return ListColumn.allCases.filter { on.contains($0) }
    }

    private func optionalColumn(at index: Int) -> ListColumn? {
        let cols = visibleOptionalColumns
        return cols.indices.contains(index) ? cols[index] : nil
    }

    /// Cell renderer for an optional column. Pulls values from
    /// `clipMetadataIndex` (cached) for the log fields, or from the
    /// asset itself for technical columns.
    @ViewBuilder
    private func optionalCell(_ asset: Asset, column: ListColumn) -> some View {
        let meta = asset.rowId.flatMap { appState.clipMetadataIndex[$0] }
        switch column {
        case .rating:
            ratingDots(asset)
        case .modified:
            Text(shortDate(asset.modifiedAt))
                .foregroundStyle(.secondary)
        case .created:
            if let d = asset.createdAt {
                Text(shortDate(d)).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        case .recorded:
            if let d = asset.recordedAt {
                Text(shortDate(d)).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        case .displaySize:
            logCell(displaySizeLabel(asset))
        case .aspectRatio:
            logCell(aspectRatioLabel(asset))
        case .title:
            Text(meta?.title ?? "—")
                .foregroundStyle((meta?.title ?? "").isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .description:
            Text(meta?.description ?? "—")
                .foregroundStyle((meta?.description ?? "").isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .reel:    logCell(meta?.reel)
        case .scene:   logCell(meta?.scene)
        case .shot:    logCell(meta?.shot)
        case .take:    logCell(meta?.take)
        case .angle:   logCell(meta?.angle)
        case .camera:  logCell(meta?.camera)
        case .waveform: WaveformInlineView(asset: asset)
        }
    }

    /// Derive a Kyno-style "display size" label from the asset's pixel
    /// dimensions: 4320p / 2160p / 1440p / 1080p / 720p / 576p / 480p /
    /// SD. The label keys off the SHORTER edge so portrait phone video
    /// (1080×1920) shows as 1080p, matching every NLE's convention.
    private func displaySizeLabel(_ asset: Asset) -> String? {
        guard let w = asset.widthPx, let h = asset.heightPx, w > 0, h > 0
        else { return nil }
        let short = min(w, h)
        switch short {
        case 4320...:        return "8K (\(short)p)"
        case 2160..<4320:    return "4K (\(short)p)"
        case 1440..<2160:    return "QHD (\(short)p)"
        case 1080..<1440:    return "1080p"
        case 720..<1080:     return "720p"
        case 576..<720:      return "576p"
        case 480..<576:      return "480p"
        default:             return "SD"
        }
    }

    /// Reduce W×H to the nearest common cinema/broadcast aspect, or
    /// fall back to the GCD-reduced ratio. Matches what most editors
    /// expect to see in a list column.
    private func aspectRatioLabel(_ asset: Asset) -> String? {
        guard let w = asset.widthPx, let h = asset.heightPx, w > 0, h > 0
        else { return nil }
        let ratio = Double(w) / Double(h)
        let canon: [(Double, String)] = [
            (16.0/9, "16:9"),
            (4.0/3, "4:3"),
            (1.85, "1.85:1"),
            (2.35, "2.35:1"),
            (2.39, "2.39:1"),
            (1.0, "1:1"),
            (9.0/16, "9:16"),
            (3.0/4, "3:4"),
        ]
        for (target, label) in canon where abs(ratio - target) < 0.02 {
            return label
        }
        return String(format: "%.2f:1", ratio)
    }

    @ViewBuilder
    private func logCell(_ value: String?) -> some View {
        if let v = value, !v.isEmpty {
            Text(v).lineLimit(1).truncationMode(.tail)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    /// Inline 5-dot rating display for the table's Rating column.
    /// Reads from the DB on demand — the cache is row-keyed by
    /// `clipMetadataIndex` for log fields; for ratings we just do a
    /// quick DB lookup since the row count is small.
    @ViewBuilder
    private func ratingDots(_ asset: Asset) -> some View {
        let stars = starsForRow(asset.rowId)
        HStack(spacing: 1) {
            ForEach(0..<5) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(i < stars ? .yellow : .secondary.opacity(0.4))
            }
        }
    }

    private func starsForRow(_ rowId: Int64?) -> Int {
        guard let id = rowId else { return 0 }
        let r = (try? appState.db.rating(assetId: id)) ?? nil
        return r?.stars ?? 0
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    /// Full-height right inspector: tab switcher at top, then the
    /// currently-selected tab's content. Renders only when an asset
    /// is selected (the parent HStack conditionally includes it).
    /// Content is top-pinned via `.frame(…, alignment: .top)` so the
    /// Log tab's sections don't vertically center in the available
    /// height.
    @ViewBuilder
    private var inspectorPane: some View {
        VStack(spacing: 0) {
            tabSwitcher
            Divider()
            Group {
                switch detailTab {
                case .metadata:
                    MetadataPaneView(
                        playerFps: playerController.fps,
                        onSeek: { playerController.seek(to: $0) }
                    )
                case .content:
                    if let asset = appState.selectedAsset {
                        ClipContentView(asset: asset,
                                         onSeek: { playerController.seek(to: $0) })
                    } else {
                        Color.clear
                    }
                case .tracks:
                    if let asset = appState.selectedAsset {
                        ClipTracksView(asset: asset)
                    } else {
                        Color.clear
                    }
                case .subclips:
                    ScrollView {
                        SubclipsListView(
                            fps: playerController.fps,
                            onJumpTo: { playerController.seek(to: $0) }
                        )
                    }
                case .log:
                    ScrollView {
                        VStack(spacing: 0) {
                            MarkersListView(
                                fps: playerController.fps,
                                onJumpTo: { playerController.seek(to: $0) }
                            )
                            Divider()
                            TagsRatingView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    private var tabSwitcher: some View {
        Picker("", selection: $detailTab) {
            ForEach(DetailTab.allCases) { tab in
                Label(tab.label, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var viewModeToggle: some View {
        let useKyno = UserDefaults.standard.bool(forKey: "useKynoTerminology")
        let gridLabel = useKyno ? "Thumbnail" : "Grid"
        return HStack(spacing: 2) {
            modeButton(icon: "square.grid.2x2", value: "grid",
                       help: "\(gridLabel) view (⌘1)")
            modeButton(icon: "list.bullet", value: "list",
                       help: "List view (⌘2)")
            modeButton(icon: "rectangle", value: "detail",
                       help: "Detail view (⌘3)")
        }
    }

    private var selectedFolderDrilldownOn: Bool {
        guard let p = appState.selectedFolderPath else { return false }
        return appState.isDrilldownEnabled(forPath: p)
    }

    @ViewBuilder
    private var drilldownToolbarButton: some View {
        let on = selectedFolderDrilldownOn
        Button {
            appState.toggleDrilldownForSelection()
        } label: {
            Label("Drilldown", systemImage: on
                  ? "arrow.down.right.and.arrow.up.left.square.fill"
                  : "arrow.down.right.and.arrow.up.left.square")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(on ? Color.orange : Color.secondary.opacity(0.15),
                             in: Capsule())
                .foregroundStyle(on ? Color.white : Color.primary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .disabled(appState.selectedFolderPath == nil)
        .help("Toggle drilldown for the selected folder. ON includes every file under it (subfolders too); OFF shows direct children only.")
    }

    private func modeButton(icon: String, value: String, help: String) -> some View {
        let active = appState.viewMode == value
        return Button {
            switchTo(viewMode: value)
        } label: {
            Image(systemName: icon)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.15),
                              in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Switching to Detail (⌘3) with no asset selected used to dump
    /// the user at the "Select a clip…" placeholder with no obvious
    /// next step. Auto-pick the first visible asset so Detail mode
    /// always shows *something*. Other modes (Grid / List) just flip
    /// the mode flag.
    private func switchTo(viewMode value: String) {
        appState.viewMode = value
        if value == "detail",
           appState.selectedAssetPath == nil,
           let first = filteredAssets.first {
            appState.selectedAssetPath = first.path
        }
    }

    @ViewBuilder
    private var typeFilterChips: some View {
        // `.fixedSize` (and Label's own `.lineLimit(1)`) is the only
        // thing keeping the chips from collapsing into vertical
        // letter-stacked "A / I / I" pills when the toolbar gets
        // squeezed by Filter / Columns / Sort menus on the right.
        HStack(spacing: 4) {
            chipButton(title: "All",    icon: "circle.grid.2x2", value: "all")
            chipButton(title: "Video",  icon: "film",            value: "video")
            chipButton(title: "Audio",  icon: "waveform",        value: "audio")
            chipButton(title: "Images", icon: "photo",           value: "image")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chipButton(title: String, icon: String, value: String) -> some View {
        let active = appState.typeFilter == value
        return Button {
            appState.typeFilter = value
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.15),
                              in: Capsule())
                .foregroundStyle(active ? .white : .primary)
                .font(.caption)
        }
        .buttonStyle(.plain)
    }

    /// Advanced Filter menu — categorized submenus for adding
    /// pinned criteria. Pinning is additive (AND); each pick lands
    /// in `appState.activeFilters` and surfaces as a removable pill.
    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Section("Combine criteria") {
                Picker("Match", selection: $appState.filterMatchMode) {
                    Text("Match all (AND)").tag("all")
                    Text("Match any (OR)").tag("any")
                }
                .pickerStyle(.inline)
            }
            Section("Rating") {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    Button("≥ \(String(repeating: "★", count: stars))") {
                        appState.addFilter(.ratingAtLeast(stars))
                    }
                }
            }
            Menu("Video Codec") {
                ForEach(["h264", "hevc", "prores", "dnxhr", "cineform"],
                         id: \.self) { codec in
                    Button(codec.uppercased()) {
                        appState.addFilter(.videoCodec(codec))
                    }
                }
            }
            Menu("Audio Codec") {
                ForEach(["aac", "pcm", "alac", "mp3", "ac3"],
                         id: \.self) { codec in
                    Button(codec.uppercased()) {
                        appState.addFilter(.audioCodec(codec))
                    }
                }
            }
            Menu("Resolution") {
                ForEach(ResolutionPreset.allCases) { p in
                    Button(p.displayName) {
                        appState.addFilter(.resolutionPreset(p))
                    }
                }
            }
            Menu("Frame Rate") {
                ForEach(FrameRatePreset.allCases) { p in
                    Button(p.displayName) {
                        appState.addFilter(.frameRatePreset(p))
                    }
                }
                Divider()
                Section("Constant vs variable") {
                    ForEach(FrameRateMode.allCases) { m in
                        Button(m.displayName) {
                            appState.addFilter(.frameRateMode(m))
                        }
                    }
                }
            }
            Menu("Volume / Online status") {
                ForEach(OnlineStatus.allCases) { s in
                    Button(s.displayName) {
                        appState.addFilter(.onlineStatus(s))
                    }
                }
            }
            Menu("Size") {
                Button("≥ 100 MB") { appState.addFilter(.sizeAtLeastMB(100)) }
                Button("≥ 500 MB") { appState.addFilter(.sizeAtLeastMB(500)) }
                Button("≥ 1 GB")   { appState.addFilter(.sizeAtLeastMB(1000)) }
                Button("≥ 5 GB")   { appState.addFilter(.sizeAtLeastMB(5000)) }
                Divider()
                Button("≤ 100 MB") { appState.addFilter(.sizeAtMostMB(100)) }
                Button("≤ 10 MB")  { appState.addFilter(.sizeAtMostMB(10)) }
            }
            Menu("Duration") {
                Button("≥ 1 minute")   { appState.addFilter(.durationAtLeastSeconds(60)) }
                Button("≥ 5 minutes")  { appState.addFilter(.durationAtLeastSeconds(300)) }
                Button("≥ 30 minutes") { appState.addFilter(.durationAtLeastSeconds(1800)) }
                Divider()
                Button("≤ 30 seconds") { appState.addFilter(.durationAtMostSeconds(30)) }
                Button("≤ 5 minutes")  { appState.addFilter(.durationAtMostSeconds(300)) }
            }
            Menu("Date Modified") {
                ForEach(DateBucket.allCases) { b in
                    Button(b.displayName) {
                        appState.addFilter(.modifiedSince(b))
                    }
                }
            }
            Menu("Date Recorded") {
                ForEach(DateBucket.allCases) { b in
                    Button(b.displayName) {
                        appState.addFilter(.recordedSince(b))
                    }
                }
            }
            folderScopeSubmenu
            tagFilterSubmenu
            if !appState.activeFilters.isEmpty {
                Divider()
                Button("Clear All Filters") {
                    appState.clearFilters()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.activeFilters.isEmpty
                       ? "line.3.horizontal.decrease.circle"
                       : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(appState.activeFilters.isEmpty
                                      ? Color.secondary : Color.orange)
                Text("Filter").font(.caption)
                if !appState.activeFilters.isEmpty {
                    Text("(\(appState.activeFilters.count))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 100)
        .help("Pin additional filter criteria (rating, tag, codec, resolution, …)")
    }

    @ViewBuilder
    private var tagFilterSubmenu: some View {
        let tags = appState.knownTagNames
        if !tags.isEmpty {
            Menu("Has Tag") {
                ForEach(tags, id: \.self) { tag in
                    Button(tag) {
                        appState.addFilter(.hasTag(tag))
                    }
                }
            }
        }
    }

    /// Folder-scope filter — narrows the result set to assets whose
    /// path is under the chosen folder. Complements the sidebar's
    /// drilldown: drilldown changes the *displayed* root; this filter
    /// adds a path-prefix predicate on top of the current view, so
    /// the user can e.g. drill into ProjectA but limit to a single
    /// shot subfolder.
    @ViewBuilder
    private var folderScopeSubmenu: some View {
        Menu("In Folder") {
            if let selected = appState.selectedFolderPath, !selected.isEmpty {
                Button("Current folder (\((selected as NSString).lastPathComponent))") {
                    appState.addFilter(.underFolder(selected))
                }
                Divider()
            }
            ForEach(appState.workspaceRoots, id: \.self) { root in
                Button(root.lastPathComponent) {
                    appState.addFilter(.underFolder(root.path))
                }
            }
            if appState.workspaceRoots.isEmpty
                && (appState.selectedFolderPath?.isEmpty ?? true) {
                Text("No folders to scope to")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var columnsMenu: some View {
        Menu {
            ForEach(ListColumn.allCases) { col in
                Button {
                    appState.toggleListColumn(col)
                } label: {
                    if appState.listColumns.contains(col) {
                        Label(col.displayName, systemImage: "checkmark")
                    } else {
                        Text(col.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tablecells")
                Text("Columns").font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 110)
        .help("Toggle visibility of optional List-view columns.")
    }

    private var sortMenu: some View {
        Menu {
            sortOption("Name",     value: "name")
            sortOption("Date",     value: "date")
            sortOption("Size",     value: "size")
            sortOption("Duration", value: "duration")
            sortOption("FPS",      value: "fps")
            Divider()
            Button {
                appState.sortAscending.toggle()
            } label: {
                Label(appState.sortAscending ? "Ascending ✓" : "Ascending",
                       systemImage: "arrow.up")
            }
            Button {
                appState.sortAscending = false
            } label: {
                Label(!appState.sortAscending ? "Descending ✓" : "Descending",
                       systemImage: "arrow.down")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.sortAscending
                       ? "arrow.up" : "arrow.down")
                Text("Sort: \(sortLabel(appState.sortKey))")
                    .font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 180)
    }

    private func sortOption(_ label: String, value: String) -> some View {
        Button {
            if appState.sortKey == value {
                appState.sortAscending.toggle()
            } else {
                appState.sortKey = value
            }
        } label: {
            if appState.sortKey == value {
                Label(label, systemImage: appState.sortAscending
                                            ? "chevron.up" : "chevron.down")
            } else {
                Text(label)
            }
        }
    }

    private func sortLabel(_ key: String) -> String {
        switch key {
        case "date":     return "Date"
        case "size":     return "Size"
        case "duration": return "Duration"
        case "fps":      return "FPS"
        default:         return "Name"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No folder selected").font(.title2)
            Text("Choose a folder of source media to begin.")
                .foregroundStyle(.secondary)
            Button("Open Folder…") { appState.chooseRootFolder() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadIntoPlayer(_ asset: Asset?) {
        guard let asset else { return }
        // Skip AVPlayer load for images — it would yield a black
        // surface and burn a waveform-extraction pass for no reason.
        guard MediaKind.of(asset: asset) != .image else { return }
        let url = URL(fileURLWithPath: asset.path)
        playerController.load(url: url, fps: asset.frameRate ?? 30)
    }

    private func addMarkerAtPlayhead() {
        appState.addMarker(timecodeIn: playerController.currentTime)
    }

    private func saveSubclipFromInOut() {
        guard let inT = playerController.inMarker,
              let outT = playerController.outMarker else { return }
        let base = appState.selectedAsset?.filename ?? "Subclip"
        let name = "\(base) [\(Timecode.format(seconds: min(inT, outT), fps: playerController.fps))]"
        appState.addSubclip(name: name, timecodeIn: inT, timecodeOut: outT)
        playerController.clearInOut()
    }

    private func formatDuration(_ s: Double?) -> String {
        guard let s, s.isFinite, s > 0 else { return "—" }
        let total = Int(s.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
