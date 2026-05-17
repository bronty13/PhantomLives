import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case content, tracks, log
    var id: String { rawValue }
    var label: String {
        switch self {
        case .content: return "Content"
        case .tracks:  return "Tracks"
        case .log:     return "Log"
        }
    }
    var icon: String {
        switch self {
        case .content: return "rectangle.grid.2x2"
        case .tracks:  return "waveform.path.ecg"
        case .log:     return "list.bullet.rectangle"
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
            if appState.rootFolder == nil {
                emptyState
            } else {
                VSplitView {
                    assetTable
                        .frame(minHeight: 180)

                    if appState.selectedAsset != nil {
                        detailPane
                            .frame(minHeight: 320)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
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

                    Toggle(isOn: $appState.drilldownEnabled) {
                        Label("Drilldown", systemImage: "tray.full")
                            .labelStyle(.titleAndIcon)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Drilldown ON shows every file under the selected folder, including subfolders. OFF shows direct children only.")

                    Divider().frame(height: 14)

                    typeFilterChips

                    Spacer()

                    sortMenu

                    if appState.isScanning {
                        ProgressView().controlSize(.small)
                        Text(appState.scanProgress).foregroundStyle(.secondary).font(.caption)
                    } else {
                        Text("\(filteredAssets.count) of \(appState.assets.count)")
                            .foregroundStyle(.secondary).font(.caption)
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
            }
        }
        .onChange(of: appState.selectedAsset) { _, newValue in
            loadIntoPlayer(newValue)
        }
    }

    private var assetTable: some View {
        Table(filteredAssets, selection: $appState.selectedAssetPath) {
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
        }
    }

    private var detailPane: some View {
        HSplitView {
            PlayerView(
                controller: playerController,
                onAddMarker: addMarkerAtPlayhead,
                onSaveSubclip: saveSubclipFromInOut
            )
            .frame(minWidth: 480)

            VStack(spacing: 0) {
                tabSwitcher
                Divider()
                Group {
                    switch detailTab {
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
                    case .log:
                        VStack(spacing: 0) {
                            MarkersListView(
                                fps: playerController.fps,
                                onJumpTo: { playerController.seek(to: $0) }
                            )
                            Divider()
                            SubclipsListView(
                                fps: playerController.fps,
                                onJumpTo: { playerController.seek(to: $0) }
                            )
                            Divider()
                            TagsRatingView()
                        }
                    }
                }
            }
            .frame(minWidth: 360, idealWidth: 420)
        }
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

    @ViewBuilder
    private var typeFilterChips: some View {
        HStack(spacing: 4) {
            chipButton(title: "All",    icon: "circle.grid.2x2", value: "all")
            chipButton(title: "Video",  icon: "film",            value: "video")
            chipButton(title: "Audio",  icon: "waveform",        value: "audio")
            chipButton(title: "Images", icon: "photo",           value: "image")
        }
    }

    private func chipButton(title: String, icon: String, value: String) -> some View {
        let active = appState.typeFilter == value
        return Button {
            appState.typeFilter = value
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.15),
                              in: Capsule())
                .foregroundStyle(active ? .white : .primary)
                .font(.caption)
        }
        .buttonStyle(.plain)
    }

    private var sortMenu: some View {
        Menu {
            sortOption("Name",     value: "name")
            sortOption("Date",     value: "date")
            sortOption("Size",     value: "size")
            sortOption("Duration", value: "duration")
            sortOption("FPS",      value: "fps")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort: \(sortLabel(appState.sortKey))")
                    .font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(width: 160)
    }

    private func sortOption(_ label: String, value: String) -> some View {
        Button {
            appState.sortKey = value
        } label: {
            if appState.sortKey == value {
                Label(label, systemImage: "checkmark")
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
