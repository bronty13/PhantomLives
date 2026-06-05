import Foundation

/// A rendered-document theme. Raw values match the CSS body classes and the
/// JavaScript `PM.setTheme` ids in `Web/index.html`.
public enum RenderTheme: String, CaseIterable, Sendable {
    case `default` = "default"
    case nord      = "nord"
    case solarized = "solarized"
    case oneDark   = "one-dark"

    public var displayName: String {
        switch self {
        case .default:   return "Default"
        case .nord:      return "Nord"
        case .solarized: return "Solarized"
        case .oneDark:   return "One Dark"
        }
    }
}

/// Reading width for the Document view. Raw values match the CSS `width-*`
/// classes and `PM.setWidth` ids.
public enum ReadingWidth: String, CaseIterable, Sendable {
    case narrow  = "narrow"
    case `default` = "default"
    case wide    = "wide"
    case full    = "full"

    public var displayName: String {
        switch self {
        case .narrow:  return "Narrow"
        case .default: return "Default"
        case .wide:    return "Wide"
        case .full:    return "Full"
        }
    }
}

/// Locates the bundled web assets and builds self-contained HTML for export and
/// Quick Look. The live in-app preview (`MarkdownWebView`) loads the bundled
/// `index.html` directly and injects markdown via JavaScript for speed; this
/// type is the one-shot path that produces a single portable HTML document.
public enum RenderCore {
    /// The framework bundle that carries the `Web/` folder reference.
    public static let bundle = Bundle(for: BundleToken.self)

    /// URL of the `Web/` directory inside the framework bundle.
    public static var webURL: URL {
        bundle.resourceURL!.appendingPathComponent("Web", isDirectory: true)
    }

    /// URL of the live preview page.
    public static var indexURL: URL {
        webURL.appendingPathComponent("index.html")
    }

    /// JSON-encodes a markdown string so it can be safely embedded inside a
    /// `<script>` as a JS string literal (also used by `MarkdownWebView`).
    public static func jsStringLiteral(_ s: String) -> String {
        let data = try? JSONEncoder().encode(s)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    /// Builds a single self-contained HTML document with all CSS/JS/fonts
    /// inlined — no external references, safe to write to disk or hand to a
    /// Quick Look preview. Renders entirely offline.
    public static func standaloneHTML(markdown: String,
                                      theme: RenderTheme = .default,
                                      width: ReadingWidth = .default) -> String {
        let styles = readWeb("styles.css")
        let katexCSS = inlinedKatexCSS()
        let markdownIt = readWeb("vendor/markdown-it.min.js")
        let mermaid = readWeb("vendor/mermaid.min.js")
        let katexJS = readWeb("vendor/katex/katex.min.js")
        let autoRender = readWeb("vendor/katex/auto-render.min.js")
        let appJS = appScript()
        let mdLiteral = jsStringLiteral(markdown)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(katexCSS)</style>
        <style>\(styles)</style>
        </head>
        <body class="theme-\(theme.rawValue) width-\(width.rawValue)">
        <div id="content"></div>
        <script>\(markdownIt)</script>
        <script>\(mermaid)</script>
        <script>\(katexJS)</script>
        <script>\(autoRender)</script>
        <script>window.__PM_PENDING__ = \(mdLiteral);</script>
        <script>\(appJS)</script>
        </body>
        </html>
        """
    }

    // MARK: - Internals

    private static func readWeb(_ relativePath: String) -> String {
        let url = webURL.appendingPathComponent(relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Extracts just the inline `<script>` block from `index.html` so the
    /// standalone document and the live page share one render implementation.
    private static func appScript() -> String {
        let html = readWeb("index.html")
        // The render logic lives in the last `<script>...</script>` block.
        guard let openRange = html.range(of: "(function () {", options: .backwards),
              let closeRange = html.range(of: "})();", options: .backwards,
                                          range: openRange.lowerBound..<html.endIndex)
        else { return "" }
        return "(function () {" + html[openRange.upperBound..<closeRange.lowerBound] + "})();"
    }

    /// Reads katex.min.css and replaces `url(fonts/KaTeX_*.woff2)` references
    /// with base64 `data:` URLs so the math fonts travel inside the HTML.
    private static func inlinedKatexCSS() -> String {
        var css = readWeb("vendor/katex/katex.min.css")
        let fontsDir = webURL.appendingPathComponent("vendor/katex/fonts", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: fontsDir.path)
        else { return css }
        for name in names where name.hasSuffix(".woff2") {
            let fontURL = fontsDir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: fontURL) else { continue }
            let b64 = data.base64EncodedString()
            css = css.replacingOccurrences(
                of: "url(fonts/\(name))",
                with: "url(data:font/woff2;base64,\(b64))")
        }
        return css
    }
}

/// Anchor class used only to resolve the framework bundle.
private final class BundleToken {}
