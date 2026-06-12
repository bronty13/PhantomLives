import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves the live preview's world over the custom `pm-app://` scheme:
///
/// - `pm-app://app/<path>`        — bundled Web assets (index.html, vendor JS, fonts)
/// - `pm-app://app/manifest.json` — current document's chunk manifest
/// - `pm-app://app/chunk/<id>`    — one markdown chunk's text
/// - `pm-app://doc/<rel-path>`    — resources next to the open document
///                                  (images, linked files), confined to its folder
///
/// This replaces pushing the whole document through `evaluateJavaScript` as a
/// JSON literal — for a 100MB file that meant 200MB+ of escaped JS through
/// IPC; now the page pulls 64KB chunks on demand and re-renders only the
/// chunks whose hash changed.
///
/// WebKit calls `WKURLSchemeHandler` on the main thread, and all mutation goes
/// through `update`/`setDocumentFolder` (also main thread) — no locking needed.
public final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "pm-app"
    public static let indexURL = URL(string: "pm-app://app/index.html")!

    public struct Options: Equatable, Sendable {
        public var linkify: Bool
        public var typographer: Bool
        /// Skip DOMPurify sanitization of raw HTML in markdown. Off by default
        /// — a .md file is untrusted input.
        public var allowRawHTML: Bool
        public init(linkify: Bool = true, typographer: Bool = true, allowRawHTML: Bool = false) {
            self.linkify = linkify
            self.typographer = typographer
            self.allowRawHTML = allowRawHTML
        }
    }

    private var chunks: [MarkdownChunk] = []
    private var refDefsSuffix = ""
    private var version = 0
    private var options = Options()
    private var truncated = false
    private var totalBytes = 0
    private var documentFolder: URL?

    /// Publishes a new document state; the page is then told to
    /// `PM.refresh(version)` and pulls the diff.
    public func update(result: ChunkResult, version: Int, options: Options) {
        self.chunks = result.chunks
        self.refDefsSuffix = result.refDefsSuffix
        self.truncated = result.truncated
        self.totalBytes = result.totalBytes
        self.version = version
        self.options = options
    }

    public func setDocumentFolder(_ url: URL?) {
        documentFolder = url?.standardizedFileURL
    }

    // MARK: - WKURLSchemeHandler

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else {
            fail(task); return
        }
        switch host {
        case "app": serveApp(url, task: task)
        case "doc": serveDoc(url, task: task)
        default:    fail(task)
        }
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Responses are delivered synchronously in `start`; nothing to cancel.
    }

    // MARK: - Routes

    private func serveApp(_ url: URL, task: WKURLSchemeTask) {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if path == "manifest.json" {
            respond(task, url: url, data: manifestData(), mime: "application/json")
            return
        }
        if path.hasPrefix("chunk/") {
            guard let id = Int(path.dropFirst("chunk/".count)),
                  chunks.indices.contains(id) else { fail(task); return }
            var body = String(chunks[id].text)
            if !refDefsSuffix.isEmpty { body += "\n\n" + refDefsSuffix }
            respond(task, url: url, data: Data(body.utf8), mime: "text/plain")
            return
        }

        // Bundled web asset — confined to the framework's Web folder.
        let base = RenderCore.webURL.standardizedFileURL
        let file = base.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(base.path),
              let data = try? Data(contentsOf: file) else { fail(task); return }
        respond(task, url: url, data: data, mime: mimeType(for: file))
    }

    private func serveDoc(_ url: URL, task: WKURLSchemeTask) {
        guard let base = documentFolder else { fail(task); return }
        let rel = url.path.removingPercentEncoding ?? url.path
        let file = base.appendingPathComponent(rel).standardizedFileURL
        // Confine to the document's folder — a crafted ../ path can't escape.
        guard file.path.hasPrefix(base.path + "/") || file.path == base.path,
              let data = try? Data(contentsOf: file) else { fail(task); return }
        respond(task, url: url, data: data, mime: mimeType(for: file))
    }

    /// Resolves a `pm-app://doc/...` URL back to the real file, honoring the
    /// same confinement as `serveDoc` — used by the host to open clicked
    /// relative markdown links as documents.
    public func fileURL(forDocURL url: URL) -> URL? {
        guard url.scheme == Self.scheme, url.host == "doc",
              let base = documentFolder else { return nil }
        let rel = url.path.removingPercentEncoding ?? url.path
        let file = base.appendingPathComponent(rel).standardizedFileURL
        guard file.path.hasPrefix(base.path + "/") || file.path == base.path else { return nil }
        return file
    }

    // MARK: - Helpers

    private func manifestData() -> Data {
        struct ManifestChunk: Encodable { let id: Int; let hash: String }
        struct Manifest: Encodable {
            let version: Int
            let truncated: Bool
            let totalBytes: Int
            let linkify: Bool
            let typographer: Bool
            let allowRawHTML: Bool
            let chunks: [ManifestChunk]
        }
        let manifest = Manifest(
            version: version,
            truncated: truncated,
            totalBytes: totalBytes,
            linkify: options.linkify,
            typographer: options.typographer,
            allowRawHTML: options.allowRawHTML,
            chunks: chunks.map { ManifestChunk(id: $0.id, hash: String($0.hash, radix: 16)) })
        return (try? JSONEncoder().encode(manifest)) ?? Data("{}".utf8)
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: headers) else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(URLError(.fileDoesNotExist))
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        switch url.pathExtension.lowercased() {
        case "woff2": return "font/woff2"
        case "md", "markdown": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
