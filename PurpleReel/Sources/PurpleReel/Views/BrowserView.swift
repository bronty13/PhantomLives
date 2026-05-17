import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var playerController = PlayerController()
    @State private var filterText: String = ""

    private var filteredAssets: [Asset] {
        let term = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return appState.assets }
        return appState.assets.filter { $0.filename.lowercased().contains(term) }
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
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by name…", text: $filterText)
                    .textFieldStyle(.plain)
                Spacer()
                if appState.isScanning {
                    ProgressView().controlSize(.small)
                    Text(appState.scanProgress).foregroundStyle(.secondary).font(.caption)
                } else {
                    Text("\(filteredAssets.count) of \(appState.assets.count)")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
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
            .frame(minWidth: 320, idealWidth: 360)
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
