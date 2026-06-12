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

    /// Quick Look renders at most this much markdown — inlining a 100MB file
    /// into the preview HTML would hang Finder's preview panel.
    private static let maxPreviewBytes = 2_000_000

    func preparePreviewOfFile(at url: URL) async throws {
        let markdown = Self.previewMarkdown(at: url)
        // Always sanitized: Quick Look renders whatever file the user taps
        // spacebar on — untrusted by definition.
        let html = RenderCore.standaloneHTML(markdown: markdown, colors: .builtin(.default),
                                             width: .default, allowRawHTML: false)

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

extension PreviewViewController {
    /// Reads the file with a UTF-8 → Latin-1 fallback, capped to
    /// `maxPreviewBytes` (cut at a line boundary, with a truncation note).
    static func previewMarkdown(at url: URL) -> String {
        guard var data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        var truncated = false
        if data.count > maxPreviewBytes {
            data = data.prefix(maxPreviewBytes)
            // Cut at the last newline so we don't split a UTF-8 sequence.
            if let lastNewline = data.lastIndex(of: 0x0A) {
                data = data.prefix(upTo: lastNewline)
            }
            truncated = true
        }
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        if truncated {
            text += "\n\n---\n\n*Preview truncated — open in PurpleMark to see the full document.*\n"
        }
        return text
    }
}

private final class LoadDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish() }
}
