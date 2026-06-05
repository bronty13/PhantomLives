import AppKit
import WebKit
import PurpleMarkRenderCore

/// Exports the current document to a self-contained HTML file or a PDF, both
/// rendered offline through `RenderCore` so Mermaid diagrams and KaTeX math are
/// preserved. Output defaults to `~/Downloads/PurpleMark/` (CLAUDE.md rule).
@MainActor
final class ExportService {
    static let shared = ExportService()

    /// Retains the offscreen web view + window while a PDF render is in flight.
    private var pdfWebView: WKWebView?
    private var pdfWindow: NSWindow?

    enum ExportError: Error { case write(Error), pdf(Error) }

    private func ensureDirectory(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func outputURL(baseName: String, ext: String, in dir: URL) -> URL {
        let safe = baseName.replacingOccurrences(of: "/", with: "-")
        let stem = (safe as NSString).deletingPathExtension
        return dir.appendingPathComponent("\(stem.isEmpty ? "Untitled" : stem).\(ext)")
    }

    /// Writes a portable `.html` file and returns its URL.
    @discardableResult
    func exportHTML(markdown: String, baseName: String,
                    theme: RenderTheme, width: ReadingWidth,
                    to directory: URL) throws -> URL {
        try ensureDirectory(directory)
        let html = RenderCore.standaloneHTML(markdown: markdown, theme: theme, width: width)
        let url = outputURL(baseName: baseName, ext: "html", in: directory)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.write(error)
        }
        return url
    }

    /// Renders the document in an offscreen web view and writes a PDF. The
    /// completion handler runs on the main actor.
    func exportPDF(markdown: String, baseName: String,
                   theme: RenderTheme, width: ReadingWidth,
                   to directory: URL,
                   completion: @escaping (Result<URL, Error>) -> Void) {
        do { try ensureDirectory(directory) }
        catch { completion(.failure(ExportError.write(error))); return }

        let html = RenderCore.standaloneHTML(markdown: markdown, theme: theme, width: width)
        let url = outputURL(baseName: baseName, ext: "pdf", in: directory)

        // An offscreen window gives the web view a real size so layout (and
        // thus pagination) matches the on-screen reading width.
        let frame = NSRect(x: 0, y: 0, width: 820, height: 1060)
        let webView = WKWebView(frame: frame)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = webView
        window.alphaValue = 0
        self.pdfWebView = webView
        self.pdfWindow = window

        let delegate = PDFLoadDelegate { [weak self] in
            // Give Mermaid/KaTeX async rendering a moment to settle, then snapshot.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let config = WKPDFConfiguration()
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url)
                            completion(.success(url))
                        } catch {
                            completion(.failure(ExportError.write(error)))
                        }
                    case .failure(let error):
                        completion(.failure(ExportError.pdf(error)))
                    }
                    self?.pdfWebView = nil
                    self?.pdfWindow = nil
                }
            }
        }
        webView.navigationDelegate = delegate
        objc_setAssociatedObject(webView, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private static var delegateKey: UInt8 = 0
}

/// Minimal navigation delegate that fires once the page finishes loading.
private final class PDFLoadDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
