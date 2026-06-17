import AppKit
import Quartz

/// Minimal Quick Look driver: show the shared `QLPreviewPanel` for a single file URL (the
/// spacebar action in Preview mode). Holds the URL and serves it as the sole preview item.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private var url: URL?

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
