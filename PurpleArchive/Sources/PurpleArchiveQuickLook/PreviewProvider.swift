import QuickLookUI
import ArchiveKit
import Foundation
import UniformTypeIdentifiers

/// Data-based Quick Look preview: hit space on an archive in Finder and see its
/// contents as a styled file listing — no extraction. Renders the entry tree
/// (via the shared ArchiveKit engine, so it covers everything the app does,
/// legacy Mac formats included) to HTML.
final class PreviewProvider: QLPreviewProvider {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let html = Self.html(for: url)
        let data = Data(html.utf8)
        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 720, height: 560)) { _ in data }
    }

    // MARK: - HTML rendering

    static func html(for url: URL) -> String {
        let name = url.lastPathComponent
        do {
            let info = try ArchiveService().info(url)
            let entries = try ArchiveService().list(url).sorted {
                $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
            }
            let rows = entries.prefix(2000).map { e -> String in
                let icon = e.isDirectory ? "📁" : (e.isSymlink ? "🔗" : "📄")
                let size = e.isDirectory ? "" : byteString(e.uncompressedSize)
                let lock = e.isEncrypted ? " 🔒" : ""
                return """
                <tr><td class="i">\(icon)</td><td class="n">\(escape(e.displayPath))\(lock)</td><td class="s">\(size)</td></tr>
                """
            }.joined()
            let more = entries.count > 2000 ? "<p class=\"more\">… and \(entries.count - 2000) more</p>" : ""
            let summary = "\(info.fileCount) files · \(byteString(info.totalUncompressedSize)) uncompressed"
                + (info.isEncrypted ? " · 🔒 encrypted" : "")
            return page(title: name, subtitle: summary, body: "<table>\(rows)</table>\(more)")
        } catch {
            return page(title: name, subtitle: "Couldn’t read archive",
                        body: "<p class=\"err\">\(escape(error.localizedDescription))</p>")
        }
    }

    private static func page(title: String, subtitle: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { font: 13px -apple-system, system-ui, sans-serif; margin: 0; padding: 16px;
               color: #1d1d1f; background: #fff; }
        @media (prefers-color-scheme: dark) { body { color: #f5f5f7; background: #1e1e1e; } }
        h1 { font-size: 17px; margin: 0 0 2px; }
        .sub { color: #8a8a8e; margin: 0 0 14px; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 3px 6px; border-bottom: 1px solid rgba(128,128,128,0.15); vertical-align: top; }
        td.i { width: 20px; } td.s { text-align: right; color: #8a8a8e; white-space: nowrap; font-variant-numeric: tabular-nums; }
        td.n { word-break: break-all; }
        .more, .err { color: #8a8a8e; margin-top: 10px; } .err { color: #d70015; }
        .badge { display:inline-block; background:#7b2ff7; color:#fff; border-radius:5px;
                 padding:1px 7px; font-size:11px; margin-left:8px; vertical-align:middle; }
        </style></head><body>
        <h1>\(escape(title)) <span class="badge">Purple Archive</span></h1>
        <p class="sub">\(escape(subtitle))</p>
        \(body)
        </body></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func byteString(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]; var v = Double(bytes); var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(bytes) B" : String(format: "%.1f %@", v, units[i])
    }
}
