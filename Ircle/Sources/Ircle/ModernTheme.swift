import SwiftUI
import AppKit

/// A **Modern mode** theme: the persisted, shareable form of a complete Ircle
/// look. Colours are hex strings (so it round-trips cleanly through JSON and a
/// `.ircletheme` file); `flatChrome` chooses flat panels vs Ircle's recoloured
/// 3D bevels; `fonts` carries optional per-`FontSlot` overrides.
///
/// `palette(baseFontSize:)` materialises a full `PlatinumPalette` — the single
/// value every view already reads — so a theme drives the entire UI without any
/// per-view changes. Built-ins live in `ModernTheme.all`; the user's own themes
/// live in `AppSettings.userThemes`. Classic (retro) mode never consults this
/// type; it keeps using `PlatinumPalette.forAppearance`.
struct ModernTheme: Codable, Identifiable, Hashable {
    var id: String                  // built-in slug OR a custom theme's UUID string
    var name: String
    var basedOn: String? = nil      // provenance: the theme it was duplicated from
    var isBuiltIn: Bool = false
    /// Flat panels (hairline borders) vs recoloured two-tone 3D bevels.
    var flatChrome: Bool = true

    // Chrome
    var windowBG: String
    var paneBG: String
    var textBG: String
    var bevelLight: String
    var bevelDark: String
    var hairline: String
    var chromeText: String
    var selection: String

    // Message colours
    var normalText: String
    var timestamp: String
    var serverText: String
    var topicText: String
    var joinText: String
    var partText: String
    var noticeText: String
    var actionText: String
    var errorText: String
    var ownNick: String
    var otherNick: String
    var mentionBG: String

    /// Optional per-element font overrides, keyed by `FontSlot.rawValue`. Empty =
    /// the classic Monaco (body) / Geneva (chrome) defaults.
    var fonts: [String: FontStyle] = [:]

    // MARK: Materialisation

    /// Build the runtime palette. `baseFontSize` seeds the message-body root
    /// (the global font-size slider); a slot's own size overrides it.
    func palette(baseFontSize: Double = 12) -> PlatinumPalette {
        func col(_ hex: String, _ fallback: Color) -> Color { Color(ircleHex: hex) ?? fallback }

        // Resolve fonts: messageBody + chrome are roots; the rest inherit body.
        let bodyRoot = (fonts[FontSlot.messageBody.rawValue] ?? .inherit)
            .resolvedRoot(classicFamily: "Monaco", classicSize: baseFontSize)
        let chromeRoot = (fonts[FontSlot.chrome.rawValue] ?? .inherit)
            .resolvedRoot(classicFamily: "Geneva", classicSize: 11)
        let nick = (fonts[FontSlot.nick.rawValue] ?? .inherit).resolved(parent: bodyRoot)
        let stamp = (fonts[FontSlot.timestamp.rawValue] ?? .inherit).resolved(parent: bodyRoot)
        let system = (fonts[FontSlot.systemLine.rawValue] ?? .inherit).resolved(parent: bodyRoot)
        let resolved: [FontSlot: ResolvedFont] = [
            .messageBody: bodyRoot, .chrome: chromeRoot,
            .nick: nick, .timestamp: stamp, .systemLine: system,
        ]

        let bg = col(textBG, .white)
        return PlatinumPalette(
            windowBG:   col(windowBG, Color(white: 0.13)),
            paneBG:     col(paneBG,   Color(white: 0.18)),
            textBG:     bg,
            bevelLight: col(bevelLight, col(paneBG, .gray)),
            bevelDark:  col(bevelDark,  col(hairline, .black)),
            hairline:   col(hairline,  .gray),
            chromeText: col(chromeText, .primary),
            normalText: col(normalText, .primary),
            timestamp:  col(timestamp, .secondary),
            serverText: col(serverText, .blue),
            topicText:  col(topicText, .purple),
            joinText:   col(joinText, .green),
            partText:   col(partText, .orange),
            noticeText: col(noticeText, .teal),
            actionText: col(actionText, .purple),
            errorText:  col(errorText, .red),
            ownNick:    col(ownNick, .blue),
            otherNick:  col(otherNick, .brown),
            mentionBG:  col(mentionBG, .yellow),
            selection:  col(selection, .blue),
            messageBackgroundLuminance: PlatinumPalette.luminance(of: bg),
            flatChrome: flatChrome,
            isModern: true,
            messageFontName: bodyRoot.family,
            chromeFontName: chromeRoot.family,
            resolvedFonts: resolved
        )
    }

    /// Light vs dark, by the message background's luminance — used to group the
    /// gallery and order `all`.
    var isDark: Bool { (Color(ircleHex: textBG).map { PlatinumPalette.luminance(of: $0) } ?? 0) < 0.5 }
}

// MARK: - Lookup, duplication

extension ModernTheme {
    /// A built-in by id, or nil.
    static func named(_ id: String) -> ModernTheme? { all.first { $0.id == id } }

    /// Resolve a selected id to a concrete theme: built-ins win, then the user's
    /// library (by UUID string), else the default (`midnight`).
    static func resolve(id: String, userThemes: [ModernTheme]) -> ModernTheme {
        if let b = named(id) { return b }
        if let u = userThemes.first(where: { $0.id == id }) { return u }
        return named(defaultID) ?? all[0]
    }

    /// Snapshot a base theme into a fresh, editable user theme (new UUID id).
    static func duplicate(of base: ModernTheme, name: String) -> ModernTheme {
        var copy = base
        copy.id = UUID().uuidString
        copy.name = name
        copy.basedOn = base.id
        copy.isBuiltIn = false
        return copy
    }

    static let defaultID = "midnight"

    // Tolerate themes authored by a newer version: any missing field defaults,
    // so importing a `.ircletheme` never hard-fails on an unknown shape.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys, _ d: String) -> String { (try? c.decode(String.self, forKey: k)) ?? d }
        id         = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name       = s(.name, "Untitled")
        basedOn    = try? c.decode(String.self, forKey: .basedOn)
        isBuiltIn  = (try? c.decode(Bool.self, forKey: .isBuiltIn)) ?? false
        flatChrome = (try? c.decode(Bool.self, forKey: .flatChrome)) ?? true
        windowBG   = s(.windowBG, "#161616");  paneBG = s(.paneBG, "#202020")
        textBG     = s(.textBG, "#0E0E0E");     bevelLight = s(.bevelLight, "#383838")
        bevelDark  = s(.bevelDark, "#000000");  hairline = s(.hairline, "#333333")
        chromeText = s(.chromeText, "#E8E8E8"); selection = s(.selection, "#2A2A2A")
        normalText = s(.normalText, "#EDEDED"); timestamp = s(.timestamp, "#888888")
        serverText = s(.serverText, "#6CA0F6"); topicText = s(.topicText, "#C58AF0")
        joinText   = s(.joinText, "#6BD58E");   partText = s(.partText, "#E6A65C")
        noticeText = s(.noticeText, "#5FC9C7"); actionText = s(.actionText, "#C58AF0")
        errorText  = s(.errorText, "#FF6B6B");  ownNick = s(.ownNick, "#8FB6FF")
        otherNick  = s(.otherNick, "#E0C277");  mentionBG = s(.mentionBG, "#3A3A3D")
        fonts      = (try? c.decode([String: FontStyle].self, forKey: .fonts)) ?? [:]
    }
}

// MARK: - The 20 built-in themes

extension ModernTheme {
    /// Compact factory for a built-in. Bevel edges default to (paneBG, hairline);
    /// flat themes don't draw them, so only beveled themes pass explicit values.
    private static func mk(_ id: String, _ name: String, dark: Bool, flat: Bool = true,
                           body: String = "Menlo", ui: String = "system-proportional",
                           windowBG: String, paneBG: String, textBG: String, hairline: String,
                           bevelLight: String? = nil, bevelDark: String? = nil,
                           chromeText: String, selection: String,
                           normalText: String, timestamp: String, serverText: String,
                           topicText: String, joinText: String, partText: String,
                           noticeText: String, actionText: String, errorText: String,
                           ownNick: String, otherNick: String, mentionBG: String) -> ModernTheme {
        var fonts: [String: FontStyle] = [:]
        if body != "Monaco" { fonts[FontSlot.messageBody.rawValue] = FontStyle(family: body) }
        if ui != "Geneva" { fonts[FontSlot.chrome.rawValue] = FontStyle(family: ui) }
        return ModernTheme(
            id: id, name: name, isBuiltIn: true, flatChrome: flat,
            windowBG: windowBG, paneBG: paneBG, textBG: textBG,
            bevelLight: bevelLight ?? paneBG, bevelDark: bevelDark ?? hairline,
            hairline: hairline, chromeText: chromeText, selection: selection,
            normalText: normalText, timestamp: timestamp, serverText: serverText,
            topicText: topicText, joinText: joinText, partText: partText,
            noticeText: noticeText, actionText: actionText, errorText: errorText,
            ownNick: ownNick, otherNick: otherNick, mentionBG: mentionBG, fonts: fonts)
    }

    static let all: [ModernTheme] = [
        // ── Darks (flat) ─────────────────────────────────────────────
        mk("midnight", "Midnight", dark: true,
           windowBG: "#0F1420", paneBG: "#161D2E", textBG: "#0B0F18", hairline: "#28324A",
           chromeText: "#C7D2E6", selection: "#243352",
           normalText: "#D6DEEC", timestamp: "#5C6B86", serverText: "#6AA0FF",
           topicText: "#C79BF0", joinText: "#5BD08A", partText: "#E0A35C",
           noticeText: "#5BD0CE", actionText: "#C79BF0", errorText: "#FF6B6B",
           ownNick: "#8FB6FF", otherNick: "#E6C77A", mentionBG: "#2A3556"),
        mk("dracula", "Dracula", dark: true,
           windowBG: "#21222C", paneBG: "#1B1C24", textBG: "#282A36", hairline: "#44475A",
           chromeText: "#F8F8F2", selection: "#44475A",
           normalText: "#F8F8F2", timestamp: "#6272A4", serverText: "#8BE9FD",
           topicText: "#BD93F9", joinText: "#50FA7B", partText: "#FFB86C",
           noticeText: "#8BE9FD", actionText: "#FF79C6", errorText: "#FF5555",
           ownNick: "#BD93F9", otherNick: "#F1FA8C", mentionBG: "#3C3F54"),
        mk("nord", "Nord", dark: true,
           windowBG: "#2B303B", paneBG: "#262B34", textBG: "#2E3440", hairline: "#434C5E",
           chromeText: "#D8DEE9", selection: "#3B4252",
           normalText: "#ECEFF4", timestamp: "#616E88", serverText: "#81A1C1",
           topicText: "#B48EAD", joinText: "#A3BE8C", partText: "#D08770",
           noticeText: "#88C0D0", actionText: "#B48EAD", errorText: "#BF616A",
           ownNick: "#88C0D0", otherNick: "#EBCB8B", mentionBG: "#3B4252"),
        mk("tokyoNight", "Tokyo Night", dark: true,
           windowBG: "#16161E", paneBG: "#13131A", textBG: "#1A1B26", hairline: "#2A2E42",
           chromeText: "#A9B1D6", selection: "#283457",
           normalText: "#C0CAF5", timestamp: "#565F89", serverText: "#7AA2F7",
           topicText: "#BB9AF7", joinText: "#9ECE6A", partText: "#E0AF68",
           noticeText: "#7DCFFF", actionText: "#BB9AF7", errorText: "#F7768E",
           ownNick: "#7AA2F7", otherNick: "#E0AF68", mentionBG: "#283457"),
        mk("graphitePro", "Graphite Pro", dark: true,
           windowBG: "#1C1C1E", paneBG: "#232325", textBG: "#161618", hairline: "#38383B",
           chromeText: "#D7D7DB", selection: "#2F2F33",
           normalText: "#E4E4E8", timestamp: "#8A8A90", serverText: "#6CA0F6",
           topicText: "#C58AF0", joinText: "#6BD58E", partText: "#E6A65C",
           noticeText: "#5FC9C7", actionText: "#C58AF0", errorText: "#FF6B6B",
           ownNick: "#8FB6FF", otherNick: "#E0C277", mentionBG: "#3A3A3D"),
        mk("solarizedDark", "Solarized Dark", dark: true,
           windowBG: "#073642", paneBG: "#062E38", textBG: "#002B36", hairline: "#0E4B59",
           chromeText: "#93A1A1", selection: "#073642",
           normalText: "#93A1A1", timestamp: "#586E75", serverText: "#268BD2",
           topicText: "#6C71C4", joinText: "#859900", partText: "#B58900",
           noticeText: "#2AA198", actionText: "#D33682", errorText: "#DC322F",
           ownNick: "#268BD2", otherNick: "#B58900", mentionBG: "#0E4B59"),
        mk("gruvboxDark", "Gruvbox Dark", dark: true,
           windowBG: "#32302F", paneBG: "#282828", textBG: "#1D2021", hairline: "#504945",
           chromeText: "#EBDBB2", selection: "#3C3836",
           normalText: "#EBDBB2", timestamp: "#928374", serverText: "#83A598",
           topicText: "#D3869B", joinText: "#B8BB26", partText: "#FE8019",
           noticeText: "#8EC07C", actionText: "#D3869B", errorText: "#FB4934",
           ownNick: "#83A598", otherNick: "#FABD2F", mentionBG: "#3C3836"),
        mk("twilight", "Twilight", dark: true,
           windowBG: "#1E1A2B", paneBG: "#251F38", textBG: "#1A1626", hairline: "#3A3155",
           chromeText: "#D6CCEC", selection: "#2C2543",
           normalText: "#E2D9F3", timestamp: "#7A6E9C", serverText: "#9D86E8",
           topicText: "#C79BF0", joinText: "#7BD0A0", partText: "#E0A35C",
           noticeText: "#6FC9D8", actionText: "#D58BE0", errorText: "#FF6B8A",
           ownNick: "#B9A0FF", otherNick: "#E6C77A", mentionBG: "#322A4D"),
        mk("carbon", "Carbon", dark: true,
           windowBG: "#000000", paneBG: "#0D0D0D", textBG: "#000000", hairline: "#2A2A2A",
           chromeText: "#F2F2F2", selection: "#1F1F1F",
           normalText: "#FFFFFF", timestamp: "#8A8A8A", serverText: "#4DA3FF",
           topicText: "#C98BFF", joinText: "#4DD37A", partText: "#FFB14D",
           noticeText: "#4DD3D0", actionText: "#FF7AD1", errorText: "#FF5151",
           ownNick: "#6FB4FF", otherNick: "#FFD24D", mentionBG: "#2E2E00"),
        // ── Lights (flat) ────────────────────────────────────────────
        mk("paper", "Paper", dark: false,
           windowBG: "#F4F1EA", paneBG: "#ECE8DE", textBG: "#FBF9F3", hairline: "#D8D2C4",
           chromeText: "#3A352C", selection: "#DCE6F5",
           normalText: "#2C2A24", timestamp: "#9A927F", serverText: "#1F6FB2",
           topicText: "#8A4FA0", joinText: "#3C8C3C", partText: "#B5722A",
           noticeText: "#2A8A8A", actionText: "#8A4FA0", errorText: "#C23B3B",
           ownNick: "#1F5FA8", otherNick: "#8A6A1F", mentionBG: "#FFF1B8"),
        mk("solarizedLight", "Solarized Light", dark: false,
           windowBG: "#EEE8D5", paneBG: "#E6DFC8", textBG: "#FDF6E3", hairline: "#DDD6C1",
           chromeText: "#586E75", selection: "#E6DFC8",
           normalText: "#657B83", timestamp: "#93A1A1", serverText: "#268BD2",
           topicText: "#6C71C4", joinText: "#859900", partText: "#B58900",
           noticeText: "#2AA198", actionText: "#D33682", errorText: "#DC322F",
           ownNick: "#268BD2", otherNick: "#B58900", mentionBG: "#EEE8D5"),
        mk("sepia", "Sepia", dark: false,
           windowBG: "#F1E7D6", paneBG: "#E8DBC4", textBG: "#F7EFE0", hairline: "#D2C2A4",
           chromeText: "#4A3F2E", selection: "#E6D5B8",
           normalText: "#3A3024", timestamp: "#9C8A68", serverText: "#8A5A2B",
           topicText: "#8A4A3A", joinText: "#5A7A3A", partText: "#A5642A",
           noticeText: "#4A7A6A", actionText: "#8A4A3A", errorText: "#B23A2A",
           ownNick: "#6A4A2A", otherNick: "#8A5A2B", mentionBG: "#F0DCA8"),
        mk("lavender", "Lavender", dark: false,
           windowBG: "#F5F0FA", paneBG: "#ECE3F5", textBG: "#FBF8FE", hairline: "#DCCDEC",
           chromeText: "#3D1D5C", selection: "#E6D8F5",
           normalText: "#3D1D5C", timestamp: "#8E7AA8", serverText: "#6A4FB0",
           topicText: "#9B4FBF", joinText: "#4F9B6A", partText: "#B5722A",
           noticeText: "#4F8F9B", actionText: "#9B4FBF", errorText: "#C23B5A",
           ownNick: "#7B2CBF", otherNick: "#8A6A1F", mentionBG: "#FFE49C"),
        mk("snow", "Snow", dark: false,
           windowBG: "#ECEFF4", paneBG: "#E5E9F0", textBG: "#F7F9FC", hairline: "#D8DEE9",
           chromeText: "#2E3440", selection: "#D8E0EF",
           normalText: "#2E3440", timestamp: "#7B88A1", serverText: "#5E81AC",
           topicText: "#9D6E97", joinText: "#6E8B4E", partText: "#BF7B4B",
           noticeText: "#4C8A95", actionText: "#9D6E97", errorText: "#BF616A",
           ownNick: "#5E81AC", otherNick: "#9A7D2E", mentionBG: "#E5D9A8"),
        mk("mint", "Mint", dark: false,
           windowBG: "#EAF6EF", paneBG: "#DEF0E6", textBG: "#F6FCF8", hairline: "#C5E2D2",
           chromeText: "#1F3A2E", selection: "#CFEADD",
           normalText: "#1E3A2E", timestamp: "#6E9A84", serverText: "#1F7FA0",
           topicText: "#5A8A4F", joinText: "#2E8B57", partText: "#B5722A",
           noticeText: "#2A8A8A", actionText: "#4F9B6A", errorText: "#C23B3B",
           ownNick: "#1F7A5A", otherNick: "#8A6A1F", mentionBG: "#FFF1B8"),
        mk("highContrast", "High Contrast", dark: false,
           windowBG: "#FFFFFF", paneBG: "#F0F0F0", textBG: "#FFFFFF", hairline: "#000000",
           chromeText: "#000000", selection: "#C0C0C0",
           normalText: "#000000", timestamp: "#444444", serverText: "#0000CC",
           topicText: "#8800AA", joinText: "#006600", partText: "#884400",
           noticeText: "#006688", actionText: "#8800AA", errorText: "#CC0000",
           ownNick: "#0000AA", otherNick: "#884400", mentionBG: "#FFFF00"),
        // ── Beveled (recoloured 3D chrome) ───────────────────────────
        mk("platinumPlus", "Platinum Plus", dark: false, flat: false, body: "Monaco", ui: "Geneva",
           windowBG: "#DDDDDD", paneBG: "#CCCCCC", textBG: "#FFFFFF", hairline: "#8C8C8C",
           bevelLight: "#FFFFFF", bevelDark: "#808080",
           chromeText: "#000000", selection: "#4D73D9",
           normalText: "#000000", timestamp: "#808080", serverText: "#0000B3",
           topicText: "#8C009E", joinText: "#007300", partText: "#8C4D00",
           noticeText: "#007380", actionText: "#8C009E", errorText: "#C70000",
           ownNick: "#00008C", otherNick: "#4D3300", mentionBG: "#FFFF99"),
        mk("aqua", "Aqua", dark: false, flat: false, body: "Monaco", ui: "Lucida Grande",
           windowBG: "#D6E2F0", paneBG: "#C2D4EA", textBG: "#FFFFFF", hairline: "#93A8C4",
           bevelLight: "#FFFFFF", bevelDark: "#7C92AE",
           chromeText: "#1A2A3A", selection: "#3E7AD0",
           normalText: "#102030", timestamp: "#6A7E96", serverText: "#1F5FB0",
           topicText: "#6A4FB0", joinText: "#2E8B3E", partText: "#B5722A",
           noticeText: "#2A7A8A", actionText: "#7A4FB0", errorText: "#C23B3B",
           ownNick: "#1F5FB0", otherNick: "#7A5A1F", mentionBG: "#FFF0A0"),
        mk("slate", "Slate", dark: true, flat: false,
           windowBG: "#3A3D42", paneBG: "#45494F", textBG: "#2C2E33", hairline: "#54585F",
           bevelLight: "#565B62", bevelDark: "#25272B",
           chromeText: "#DFE3E8", selection: "#3A3E45",
           normalText: "#E4E7EC", timestamp: "#8A9099", serverText: "#6CA0F6",
           topicText: "#C58AF0", joinText: "#6BD58E", partText: "#E6A65C",
           noticeText: "#5FC9C7", actionText: "#C58AF0", errorText: "#FF6B6B",
           ownNick: "#8FB6FF", otherNick: "#E0C277", mentionBG: "#4A4E55"),
        mk("noir", "Noir", dark: true, flat: false, body: "Monaco", ui: "Geneva",
           windowBG: "#1A1A1A", paneBG: "#242424", textBG: "#0E0E0E", hairline: "#3A3A3A",
           bevelLight: "#3A3A3A", bevelDark: "#000000",
           chromeText: "#E8E8E8", selection: "#2A2A2A",
           normalText: "#EDEDED", timestamp: "#888888", serverText: "#C0C0C0",
           topicText: "#B0B0B0", joinText: "#9AD09A", partText: "#D0A06A",
           noticeText: "#9AD0CE", actionText: "#D0A0D0", errorText: "#FF6B6B",
           ownNick: "#FFFFFF", otherNick: "#C8C8C8", mentionBG: "#333300"),
    ]
}
