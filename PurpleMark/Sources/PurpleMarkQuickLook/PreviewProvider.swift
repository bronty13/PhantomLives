import Cocoa
import Quartz
import WebKit
import PurpleMarkRenderCore

/// Finder Quick Look preview for `.md` files (spacebar / ⌘Y). Renders the
/// markdown through the shared `RenderCore` into a `WKWebView` so the Finder
/// preview looks identical to PurpleMark's Document view — Mermaid diagrams and
/// LaTeX math included, fully offline.
class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: WKWebView!
    private var loadDelegate: LoadDelegate?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: container.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        view = container
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let html = RenderCore.standaloneHTML(markdown: markdown, theme: .default, width: .default)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = LoadDelegate {
                // Give async Mermaid/KaTeX rendering a brief moment to settle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    continuation.resume()
                }
            }
            self.loadDelegate = delegate
            self.webView.navigationDelegate = delegate
            self.webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

private final class LoadDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish() }
}
