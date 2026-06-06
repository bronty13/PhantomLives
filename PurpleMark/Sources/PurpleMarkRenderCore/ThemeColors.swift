import Foundation

/// The full set of colors that define a rendered-document theme. These map 1:1
/// to the CSS custom properties in `Web/styles.css` (plus the body background
/// and text color). Both the four built-in themes and user-created custom themes
/// produce a `ThemeColors`, which is applied as inline CSS variables — so the
/// rendering path is identical for built-in and custom.
///
/// Colors are stored as CSS color strings (e.g. `#1e1e1f`).
public struct ThemeColors: Codable, Equatable, Sendable {
    public var background: String   // body background
    public var foreground: String   // body text color
    public var muted: String        // --pm-muted
    public var link: String         // --pm-link
    public var rule: String         // --pm-rule
    public var ruleStrong: String   // --pm-rule-strong
    public var codeBackground: String // --pm-code-bg (inline code pill, th)
    public var preBackground: String  // --pm-pre-bg (fenced code blocks)
    public var stripe: String       // --pm-stripe (even table rows)
    /// Whether this is a dark theme — drives the Mermaid diagram theme and the
    /// editor swatch rendering.
    public var isDark: Bool

    public init(background: String, foreground: String, muted: String, link: String,
                rule: String, ruleStrong: String, codeBackground: String,
                preBackground: String, stripe: String, isDark: Bool) {
        self.background = background
        self.foreground = foreground
        self.muted = muted
        self.link = link
        self.rule = rule
        self.ruleStrong = ruleStrong
        self.codeBackground = codeBackground
        self.preBackground = preBackground
        self.stripe = stripe
        self.isDark = isDark
    }

    /// The colors for one of the four built-in themes (values mirror styles.css).
    public static func builtin(_ theme: RenderTheme) -> ThemeColors {
        switch theme {
        case .default:
            return ThemeColors(background: "#1e1e1f", foreground: "#e6e6e8", muted: "#9a9aa2",
                               link: "#6ea8fe", rule: "#3a3a3d", ruleStrong: "#56565b",
                               codeBackground: "#2c2c2e", preBackground: "#252527",
                               stripe: "#232325", isDark: true)
        case .nord:
            return ThemeColors(background: "#2e3440", foreground: "#d8dee9", muted: "#8a94a6",
                               link: "#88c0d0", rule: "#3b4252", ruleStrong: "#4c566a",
                               codeBackground: "#3b4252", preBackground: "#343b48",
                               stripe: "#333a47", isDark: true)
        case .solarized:
            return ThemeColors(background: "#002b36", foreground: "#b9c7c6", muted: "#6f8a8f",
                               link: "#268bd2", rule: "#0c3a45", ruleStrong: "#14505f",
                               codeBackground: "#073642", preBackground: "#063540",
                               stripe: "#042e38", isDark: true)
        case .oneDark:
            return ThemeColors(background: "#282c34", foreground: "#abb2bf", muted: "#828a99",
                               link: "#61afef", rule: "#3a3f4b", ruleStrong: "#4b5263",
                               codeBackground: "#2f343f", preBackground: "#2b303a",
                               stripe: "#2c313a", isDark: true)
        }
    }

    /// A neutral starting point for a new light custom theme.
    public static var light: ThemeColors {
        ThemeColors(background: "#ffffff", foreground: "#1d1d1f", muted: "#6e6e73",
                    link: "#0066cc", rule: "#e2e2e4", ruleStrong: "#c7c7cc",
                    codeBackground: "#f0f0f2", preBackground: "#f6f6f8",
                    stripe: "#fafafa", isDark: false)
    }

    /// The JSON object pushed to the web view / inlined into standalone HTML.
    /// Keys are consumed by `PM.setThemeVars` in `Web/index.html`.
    public func jsObjectLiteral() -> String {
        let dict: [String: String] = [
            "background": background, "color": foreground, "muted": muted, "link": link,
            "rule": rule, "ruleStrong": ruleStrong, "codeBg": codeBackground,
            "preBg": preBackground, "stripe": stripe, "mermaid": isDark ? "dark" : "default",
        ]
        let data = (try? JSONEncoder().encode(dict)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Inline `style="…"` declarations for the standalone export `<body>`.
    public func inlineBodyStyle() -> String {
        "background:\(background);color:\(foreground);"
        + "--pm-muted:\(muted);--pm-link:\(link);--pm-rule:\(rule);"
        + "--pm-rule-strong:\(ruleStrong);--pm-code-bg:\(codeBackground);"
        + "--pm-pre-bg:\(preBackground);--pm-stripe:\(stripe);"
    }
}
