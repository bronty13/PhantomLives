import SwiftUI
import WebKit

/// Live rendered-document preview. Loads the bundled page once over the
/// `pm-app://` scheme; the document travels as ~64KB chunks pulled on demand
/// (see `PreviewSchemeHandler`), so a render push is a single tiny
/// `PM.refresh(version)` call instead of a JSON literal the size of the file —
/// and an edit re-renders only the chunks whose hash changed.
public struct MarkdownWebView: NSViewRepresentable {
    public var markdown: String
    /// Identifies the content (document) and its edit generation. The
    /// coordinator re-renders only when one of these changes — never by
    /// comparing the markdown itself, which would be O(n) per SwiftUI render
    /// (and would retain a duplicate copy of a possibly-huge document).
    public var contentID: UUID
    public var contentVersion: Int
    public var colors: ThemeColors
    public var width: ReadingWidth
    /// Folder of the open document — relative images/links in the markdown are
    /// served from here (confined to it) via `pm-app://doc/`.
    public var docFolder: URL?
    /// markdown-it features (degraded for large files by the host's policy).
    public var options: PreviewSchemeHandler.Options
    /// When set, the preview renders only the leading `capBytes` and shows a
    /// "Render anyway" banner; nil renders everything.
    public var capBytes: Int?
    /// The user clicked "Render anyway" on the truncation banner.
    public var onRenderAnyway: (() -> Void)?
    /// Reports the vertical scroll fraction (0…1) as the user scrolls the
    /// rendered view — used to drive sync-scroll with the source editor.
    public var onScroll: ((Double) -> Void)?
    /// When set, scrolls the rendered view to this fraction (0…1).
    public var scrollTo: Double?
    /// Called when a local file should open as a document: a file dropped onto
    /// the rendered view, or a clicked link to a relative markdown file.
    public var onOpenFile: ((URL) -> Void)?

    public init(markdown: String,
                contentID: UUID,
                contentVersion: Int,
                colors: ThemeColors,
                width: ReadingWidth,
                docFolder: URL? = nil,
                options: PreviewSchemeHandler.Options = .init(),
                capBytes: Int? = nil,
                onRenderAnyway: (() -> Void)? = nil,
                onScroll: ((Double) -> Void)? = nil,
                scrollTo: Double? = nil,
                onOpenFile: ((URL) -> Void)? = nil) {
        self.markdown = markdown
        self.contentID = contentID
        self.contentVersion = contentVersion
        self.colors = colors
        self.width = width
        self.docFolder = docFolder
        self.options = options
        self.capBytes = capBytes
        self.onRenderAnyway = onRenderAnyway
        self.onScroll = onScroll
        self.scrollTo = scrollTo
        self.onOpenFile = onOpenFile
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "scroll")
        controller.add(context.coordinator, name: "pmAction")
        config.userContentController = controller
        config.setURLSchemeHandler(context.coordinator.schemeHandler,
                                   forURLScheme: PreviewSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // transparent until themed
        webView.load(URLRequest(url: PreviewSchemeHandler.indexURL))
        context.coordinator.webView = webView
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyIfNeeded()
        if let scrollTo { context.coordinator.applyScroll(to: scrollTo) }
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        weak var webView: WKWebView?
        let schemeHandler = PreviewSchemeHandler()
        private var isLoaded = false
        private var hasPending = false
        private var chunkTask: Task<Void, Never>?
        private var publishedVersion = 0

        /// What the page currently shows — versions and styling only, never a
        /// retained copy of the markdown.
        private struct RenderKey: Equatable {
            let id: UUID
            let version: Int
            let colors: ThemeColors
            let width: ReadingWidth
            let options: PreviewSchemeHandler.Options
            let capBytes: Int?
        }
        private var lastApplied: RenderKey?

        init(_ parent: MarkdownWebView) { self.parent = parent }

        private var currentKey: RenderKey {
            RenderKey(id: parent.contentID, version: parent.contentVersion,
                      colors: parent.colors, width: parent.width,
                      options: parent.options, capBytes: parent.capBytes)
        }

        func applyIfNeeded() {
            let key = currentKey
            guard lastApplied != key else { return }
            lastApplied = key
            guard isLoaded, let webView else {
                hasPending = true
                return
            }
            run(on: webView)
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

        private func run(on webView: WKWebView) {
            // Theme + width apply immediately; chunking may take a moment.
            let styleJS = """
            if (window.PM) {
              window.PM.setThemeVars(\(parent.colors.jsObjectLiteral()));
              window.PM.setWidth('\(parent.width.rawValue)');
            }
            """
            webView.evaluateJavaScript(styleJS)

            schemeHandler.setDocumentFolder(parent.docFolder)
            publishedVersion += 1
            let version = publishedVersion
            let markdown = parent.markdown
            let options = parent.options
            let cap = parent.capBytes
            chunkTask?.cancel()

            if markdown.utf8.count < 512_000 {
                // Small document: chunk synchronously, no flicker window.
                schemeHandler.update(result: MarkdownChunker.split(markdown, maxTotalBytes: cap),
                                     version: version, options: options)
                webView.evaluateJavaScript("if (window.PM) window.PM.refresh(\(version));")
            } else {
                chunkTask = Task { [weak self] in
                    let result = await Task.detached(priority: .userInitiated) {
                        MarkdownChunker.split(markdown, maxTotalBytes: cap)
                    }.value
                    guard !Task.isCancelled, let self, let webView = self.webView else { return }
                    self.schemeHandler.update(result: result, version: version, options: options)
                    webView.evaluateJavaScript("if (window.PM) window.PM.refresh(\(version));",
                                               completionHandler: nil)
                }
            }
        }

        public func webView(_ webView: WKWebView,
                            decidePolicyFor navigationAction: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // A file drop navigates the view to the dropped file — hand it to
            // the host to open as a document instead.
            if url.isFileURL {
                decisionHandler(.cancel)
                parent.onOpenFile?(url)
                return
            }
            if url.scheme == PreviewSchemeHandler.scheme {
                // Clicked link to a sibling markdown file → open as a tab.
                if url.host == "doc", let file = schemeHandler.fileURL(forDocURL: url) {
                    decisionHandler(.cancel)
                    parent.onOpenFile?(file)
                    return
                }
                decisionHandler(.allow)   // our own page loads
                return
            }
            // External links open in the default browser — never navigate the
            // preview away from the rendered document.
            if navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto"].contains(scheme) {
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
                return
            }
            decisionHandler(.cancel)
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
            if hasPending || lastApplied != nil {
                run(on: webView)
            }
            hasPending = false
        }

        /// A 100MB DOM can get the web content process jettisoned — reload the
        /// page and replay the current state instead of going blank forever.
        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isLoaded = false
            hasPending = true
            webView.load(URLRequest(url: PreviewSchemeHandler.indexURL))
        }

        public func userContentController(_ controller: WKUserContentController,
                                          didReceive message: WKScriptMessage) {
            switch message.name {
            case "scroll":
                if let f = message.body as? Double {
                    lastReported = f
                    parent.onScroll?(f)
                }
            case "pmAction":
                if let action = message.body as? String, action == "renderAll" {
                    parent.onRenderAnyway?()
                }
            default:
                break
            }
        }
    }
}
