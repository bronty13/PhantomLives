import AppKit
import Quartz

/// Bridge from a SwiftUI menu action to macOS's `QLPreviewPanel`. The panel is a
/// shared singleton; it requires a data-source object that survives across the view
/// updates that triggered it. We hold one per-process instance and keep it alive for
/// the panel's lifetime.
@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private var items: [URL] = []

    func preview(_ url: URL) {
        items = [url]
        showPanel()
    }

    func preview(many: [URL]) {
        items = many
        showPanel()
    }

    private func showPanel() {
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }
}
