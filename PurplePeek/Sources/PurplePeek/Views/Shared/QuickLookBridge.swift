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
    /// If the file is already cached (pre-warmed on selection), show synchronously — QLPreviewPanel
    /// only reliably becomes key when opened inside the user-event turn, not a later async one.
    func toggle(file: MediaFile, provider: PeekMediaProvider?) {
        // If the original is reachable on disk (local mode, or the server's volume mounted over SMB),
        // Quick Look it directly — no whole-file HTTP download.
        if FileManager.default.fileExists(atPath: file.filePath) { toggle(file.fileURL); return }
        guard let provider else { toggle(file.fileURL); return }
        if isVisible { QLPreviewPanel.shared()?.orderOut(nil); return }
        let cached = Self.tempPath(id: file.id, fileName: file.fileName)
        if FileManager.default.fileExists(atPath: cached.path) {
            preview(cached)                     // synchronous → reliable
        } else {
            previewRemote(file: file, provider: provider)   // download then show (best-effort)
        }
    }

    /// Download `/full/<id>` to the temp cache ahead of a peek (called when the selection changes in
    /// remote mode) so the spacebar can show it synchronously. Cheap no-op if already cached.
    func prewarm(file: MediaFile, provider: PeekMediaProvider?) {
        guard let provider else { return }
        if FileManager.default.fileExists(atPath: Self.tempPath(id: file.id, fileName: file.fileName).path) { return }
        Task { _ = await Self.cachedFull(id: file.id, fileName: file.fileName, provider: provider) }
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

    /// Temp cache location for a peeked original — id-keyed, original extension preserved so Quick
    /// Look picks the right previewer.
    static func tempPath(id: String, fileName: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PurplePeekQL", isDirectory: true)
        let ext = (fileName as NSString).pathExtension
        return dir.appendingPathComponent(ext.isEmpty ? id : "\(id).\(ext)")
    }

    /// Download the original for `id` to a temp cache file (reused across peeks), returning its
    /// local URL.
    private static func cachedFull(id: String, fileName: String, provider: PeekMediaProvider) async -> URL? {
        let local = tempPath(id: id, fileName: fileName)
        try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
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
            NSApp.activate(ignoringOtherApps: true)   // helps the panel become key from an async turn
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
