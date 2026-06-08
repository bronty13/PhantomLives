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
    //
    // These protocol requirements are `nonisolated`, so a `@MainActor` type
    // can't satisfy them with isolated methods. `QLPreviewPanel` only ever
    // calls its data source on the main thread, so we declare them
    // `nonisolated` and reach the main-actor state via `assumeIsolated`.

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { items[index] as NSURL }
    }
}
