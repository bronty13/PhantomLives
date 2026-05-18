import SwiftUI
import AppKit
import WebKit

/// In-app Markdown viewer for PurpleReel's bundled help docs.
///
/// We don't render Markdown ourselves — the build pipeline already
/// converts each `.md` into a styled `.html` under the Apple Help
/// Book bundle. This viewer just loads that file in a `WKWebView`
/// inside a free-floating `NSWindow`, so the user doesn't bounce out
/// to whatever Markdown app they happen to have configured as their
/// system default (or, more often, doesn't have configured at all).
///
/// One window per doc — opening the same doc twice focuses the
/// existing window instead of stacking a duplicate.
enum MarkdownDocWindow {
    /// Singleton store of open windows keyed by doc type. Keeps weak
    /// references so user-closed windows clear themselves out.
    private final class Registry {
        static let shared = Registry()
        private var windows: [HelpDocs.Document: NSWindow] = [:]

        func existing(for doc: HelpDocs.Document) -> NSWindow? {
            let w = windows[doc]
            if w == nil { windows.removeValue(forKey: doc) }
            return w
        }

        func register(_ window: NSWindow, for doc: HelpDocs.Document) {
            windows[doc] = window
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.windows.removeValue(forKey: doc)
            }
        }
    }

    /// Open `doc` in a new (or focused-existing) in-app window. If we
    /// can't locate the bundled .html, fall back to the .md via the
    /// system handler — `HelpDocs.open(_:)` callers shouldn't have
    /// to know the difference.
    @MainActor
    static func open(_ doc: HelpDocs.Document) {
        if let w = Registry.shared.existing(for: doc) {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let htmlURL = locateHTML(doc) else {
            // Fall through to the legacy NSWorkspace path — opens
            // the .md in whichever app the user has registered.
            HelpDocs.openExternally(doc)
            return
        }
        let window = makeWindow(for: doc, htmlURL: htmlURL)
        Registry.shared.register(window, for: doc)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Window construction

    private static func makeWindow(for doc: HelpDocs.Document,
                                    htmlURL: URL) -> NSWindow {
        let content = MarkdownDocView(doc: doc, htmlURL: htmlURL)
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = doc.displayName
        window.setContentSize(NSSize(width: 820, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable,
                            .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.center()
        // Avoid auto-saved frame collisions when several docs open
        // back-to-back — distinct names per doc.
        window.setFrameAutosaveName("PurpleReel.HelpDoc.\(doc.resourceName)")
        return window
    }

    // MARK: - HTML lookup

    /// Locate the bundled `.html` rendition of the doc. Apple Help
    /// Book bundles live at `Contents/Resources/PurpleReel.help/
    /// Contents/Resources/en.lproj/<NAME>.html`. We also accept the
    /// fallback flat layout in case the help book ever moves.
    private static func locateHTML(_ doc: HelpDocs.Document) -> URL? {
        let name = doc.resourceName
        let candidates: [(String, String?)] = [
            (name, "PurpleReel.help/Contents/Resources/en.lproj"),
            (name, "Resources/en.lproj"),
            (name, "en.lproj"),
            (name, nil),
        ]
        for (file, subdir) in candidates {
            if let url = Bundle.main.url(forResource: file,
                                          withExtension: "html",
                                          subdirectory: subdir) {
                return url
            }
        }
        return nil
    }
}

/// SwiftUI shell holding the toolbar + WKWebView for one doc.
private struct MarkdownDocView: View {
    let doc: HelpDocs.Document
    let htmlURL: URL

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            Divider()
            HelpWebView(htmlURL: htmlURL)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(doc.displayName)
                .font(.headline)
            Spacer()
            Button {
                HelpDocs.openExternally(doc)
            } label: {
                Label("Open .md…", systemImage: "arrow.up.right.square")
            }
            .help("Open the Markdown source in your system's default Markdown app.")
            Button {
                if let mdURL = HelpDocs.locateMarkdown(doc) {
                    NSWorkspace.shared.activateFileViewerSelecting([mdURL])
                }
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .help("Show the Markdown source file in Finder.")
        }
    }
}

/// WKWebView wrapper. Loads the help HTML with `loadFileURL` so
/// embedded relative links (image references, sibling-doc links)
/// resolve inside the bundle. JavaScript stays disabled — these are
/// static documents.
private struct HelpWebView: NSViewRepresentable {
    let htmlURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Static docs only — no JS, no auto-play, no media.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        loadDoc(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Re-load if the URL changed (e.g., user toggled to a sibling
        // doc inside the window — currently not exposed, but the
        // plumbing is here for it).
        if webView.url?.path != htmlURL.path {
            loadDoc(into: webView)
        }
    }

    private func loadDoc(into webView: WKWebView) {
        // Allow read access to the help book root so relative links
        // between docs resolve. The help-book layout is:
        //   PurpleReel.help/Contents/Resources/en.lproj/<file>.html
        // Granting access at the .help bundle level covers any
        // intra-bundle sibling reference plus inline images stored
        // alongside the HTML.
        let allowRoot = htmlURL
            .deletingLastPathComponent()  // en.lproj
            .deletingLastPathComponent()  // Resources
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()  // PurpleReel.help
        webView.loadFileURL(htmlURL, allowingReadAccessTo: allowRoot)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Intercepts navigation so http(s) links open in the user's
    /// browser instead of leaking out of the in-app viewer.
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                      decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
