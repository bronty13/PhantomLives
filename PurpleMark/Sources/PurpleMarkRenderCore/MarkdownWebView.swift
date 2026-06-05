import SwiftUI
import WebKit

/// Live rendered-document preview. Loads the bundled `index.html` once and then
/// pushes markdown/theme/width changes via JavaScript — so the heavy libraries
/// (markdown-it, mermaid, KaTeX) parse a single time and re-renders are cheap.
public struct MarkdownWebView: NSViewRepresentable {
    public var markdown: String
    public var theme: RenderTheme
    public var width: ReadingWidth
    /// Reports the vertical scroll fraction (0…1) as the user scrolls the
    /// rendered view — used to drive sync-scroll with the source editor.
    public var onScroll: ((Double) -> Void)?
    /// When set, scrolls the rendered view to this fraction (0…1).
    public var scrollTo: Double?

    public init(markdown: String,
                theme: RenderTheme,
                width: ReadingWidth,
                onScroll: ((Double) -> Void)? = nil,
                scrollTo: Double? = nil) {
        self.markdown = markdown
        self.theme = theme
        self.width = width
        self.onScroll = onScroll
        self.scrollTo = scrollTo
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "scroll")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // transparent until themed
        webView.loadFileURL(RenderCore.indexURL, allowingReadAccessTo: RenderCore.webURL)
        context.coordinator.webView = webView
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(markdown: markdown, theme: theme, width: width)
        if let scrollTo { context.coordinator.applyScroll(to: scrollTo) }
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        weak var webView: WKWebView?
        private var isLoaded = false
        private var pending: (markdown: String, theme: RenderTheme, width: ReadingWidth)?
        private var lastApplied: (markdown: String, theme: RenderTheme, width: ReadingWidth)?

        init(_ parent: MarkdownWebView) { self.parent = parent }

        func apply(markdown: String, theme: RenderTheme, width: ReadingWidth) {
            if let last = lastApplied,
               last.markdown == markdown, last.theme == theme, last.width == width {
                return
            }
            lastApplied = (markdown, theme, width)
            guard isLoaded, let webView else {
                pending = (markdown, theme, width)
                return
            }
            run(markdown: markdown, theme: theme, width: width, on: webView)
        }

        private var lastReported: Double = 0
        private var lastScrollApplied: Double?

        func applyScroll(to fraction: Double) {
            guard isLoaded, let webView else { return }
            // Avoid a feedback loop: skip if this is essentially the position
            // the page just reported, or one we already applied.
            if abs(fraction - lastReported) < 0.002 { return }
            if let lastScrollApplied, abs(fraction - lastScrollApplied) < 0.002 { return }
            lastScrollApplied = fraction
            let js = "window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * \(fraction));"
            webView.evaluateJavaScript(js)
        }

        private func run(markdown: String, theme: RenderTheme, width: ReadingWidth, on webView: WKWebView) {
            let lit = RenderCore.jsStringLiteral(markdown)
            let js = """
            if (window.PM) {
              window.PM.setTheme('\(theme.rawValue)');
              window.PM.setWidth('\(width.rawValue)');
              window.PM.render(\(lit));
            }
            """
            webView.evaluateJavaScript(js)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            // Install a scroll reporter.
            let scrollJS = """
            window.addEventListener('scroll', function () {
              var max = document.body.scrollHeight - window.innerHeight;
              var f = max > 0 ? window.scrollY / max : 0;
              window.webkit.messageHandlers.scroll.postMessage(f);
            }, { passive: true });
            """
            webView.evaluateJavaScript(scrollJS)
            let p = pending ?? lastApplied
            if let p { run(markdown: p.markdown, theme: p.theme, width: p.width, on: webView) }
            pending = nil
        }

        public func userContentController(_ controller: WKUserContentController,
                                          didReceive message: WKScriptMessage) {
            if message.name == "scroll", let f = message.body as? Double {
                lastReported = f
                parent.onScroll?(f)
            }
        }
    }
}
