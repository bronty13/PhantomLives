import AppKit
import Quartz

/// Minimal Quick Look driver: show the shared `QLPreviewPanel` for a single file URL (the
/// spacebar action in Preview mode). Holds the URL and serves it as the sole preview item.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private var url: URL?
    private var downloadTask: Task<Void, Never>?

    // MARK: Media-file entry points (local file URL, or remote /full download)

    /// Toggle Quick Look for a media file. Local mode previews its file URL directly; remote mode
    /// downloads `/full/<id>` to a temp cache file first (QLPreviewPanel only handles local files).
    func toggle(file: MediaFile, provider: PeekMediaProvider?) {
        guard let provider else { toggle(file.fileURL); return }
        if isVisible { QLPreviewPanel.shared()?.orderOut(nil); return }
        previewRemote(file: file, provider: provider)
    }

    /// Keep an open peek in step with the selection (remote-aware). No-op when nothing is peeked.
    func refreshIfVisible(file: MediaFile, provider: PeekMediaProvider?) {
        guard isVisible else { return }
        guard let provider else { preview(file.fileURL); return }
        previewRemote(file: file, provider: provider)
    }

    private func previewRemote(file: MediaFile, provider: PeekMediaProvider) {
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            guard let local = await Self.cachedFull(id: file.id, fileName: file.fileName, provider: provider)
            else { return }
            await MainActor.run { self?.preview(local) }
        }
    }

    /// Download the original for `id` to a temp cache file (reused across peeks), returning its
    /// local URL. The correct extension is preserved so Quick Look picks the right previewer.
    private static func cachedFull(id: String, fileName: String, provider: PeekMediaProvider) async -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PurplePeekQL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = (fileName as NSString).pathExtension
        let local = dir.appendingPathComponent(ext.isEmpty ? id : "\(id).\(ext)")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        var req = URLRequest(url: provider.fullURL(id: id))
        for (k, v) in provider.httpHeaders { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? data.write(to: local)
        return local
    }

    /// Show (or refresh) Quick Look for `url`.
    func preview(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func toggle(_ url: URL) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            preview(url)
        }
    }

    /// True while the shared Quick Look panel is on screen.
    var isVisible: Bool { QLPreviewPanel.shared()?.isVisible ?? false }

    /// Update the peek to a new file only if the panel is already open — used to keep the
    /// peek in step as the grid selection changes (no-op when nothing is being previewed).
    func refreshIfVisible(_ url: URL) {
        guard isVisible else { return }
        preview(url)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}
