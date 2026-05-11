import SwiftUI
import AppKit

// MARK: - Appearance mode

/// Effective appearance preference. Orthogonal to the chosen theme:
/// `.system` follows the OS, `.light` / `.dark` override at the SwiftUI
/// root via `.preferredColorScheme`. Persisted in `AppSettings`.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case system, light, dark
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Auto (sync with system)"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Value to feed `.preferredColorScheme(_:)`. `nil` means "let the
    /// OS decide" — the auto case.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - PurpleTheme

/// Named visual palette. Each slot stores a `Slot(light:dark:)` pair so
/// the theme works in both appearance modes — the user picks
/// `AppearanceMode` separately. Built-ins are declared as static literals
/// below; user-built themes (slice 2) Codable-roundtrip via `UserTheme`.
struct PurpleTheme: Identifiable {
    let id: String
    let displayName: String

    /// Window background.
    let bg: Slot
    /// Sidebar surface (rendered behind `.regularMaterial` in chrome; the
    /// value here is the opaque fallback for inset footers).
    let sidebarOpaque: Slot
    /// Panel / list-row surface above `bg`.
    let card: Slot
    /// Primary text.
    let text: Slot
    /// Secondary text — captions, meta lines.
    let textDim: Slot
    /// Tertiary text — section headers, faint hints.
    let textFaint: Slot
    /// Subtle stroke on panels.
    let cardBorder: Slot
    /// In-list divider stroke (slightly stronger than cardBorder).
    let hairline: Slot
    /// Background for hovered selectable rows.
    let rowHover: Slot
    /// Primary brand accent.
    let accent: Slot
    /// Soft accent fill — selected sidebar row, accent button background.
    let accentSoft: Slot

    /// A (light, dark) color pair. `.color` resolves through the OS
    /// appearance at render time via the `Color(light:dark:)` helper.
    struct Slot {
        let light: Color
        let dark: Color
        var color: Color { Color(light: light, dark: dark) }
    }
}

extension PurpleTheme: Hashable {
    // Identity-only equality. Color values are dynamic providers; comparing
    // them is unreliable, and theme identity is what consumers actually
    // care about (e.g. "did the user pick a different theme?").
    static func == (lhs: PurpleTheme, rhs: PurpleTheme) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Built-in palettes

extension PurpleTheme {
    /// Flagship — the original oklch palette from the design handoff
    /// (`Design/purplelife/project/chrome.jsx`). Default theme on first run.
    static let royalPurple = PurpleTheme(
        id: "royalPurple",
        displayName: "Royal Purple",
        bg:            Slot(light: rgb(0.984, 0.980, 0.969), dark: rgb(0.110, 0.106, 0.118)),
        sidebarOpaque: Slot(light: rgb(0.945, 0.929, 0.898), dark: rgb(0.149, 0.141, 0.165)),
        card:          Slot(light: .white,                   dark: rgb(0.149, 0.141, 0.165)),
        text:          Slot(light: rgb(0.110, 0.102, 0.090), dark: rgb(0.925, 0.922, 0.910)),
        textDim:       Slot(light: rgb(0.478, 0.455, 0.408), dark: rgb(0.608, 0.584, 0.541)),
        textFaint:     Slot(light: rgb(0.659, 0.635, 0.580), dark: rgb(0.416, 0.392, 0.341)),
        cardBorder:    Slot(light: .black.opacity(0.06),     dark: .white.opacity(0.06)),
        hairline:      Slot(light: .black.opacity(0.07),     dark: .white.opacity(0.07)),
        rowHover:      Slot(light: .black.opacity(0.04),     dark: .white.opacity(0.05)),
        accent:        Slot(light: rgb(0.545, 0.396, 0.757), dark: rgb(0.659, 0.510, 0.871)),
        accentSoft:    Slot(light: rgb(0.945, 0.910, 0.965), dark: rgb(0.224, 0.180, 0.302))
    )

    /// Softer pastel purple. Lighter accents, cooler surfaces — easier
    /// on the eyes for long sessions, still distinctly purple.
    static let lavender = PurpleTheme(
        id: "lavender",
        displayName: "Lavender",
        bg:            Slot(light: rgb(0.969, 0.953, 0.984), dark: rgb(0.110, 0.102, 0.149)),
        sidebarOpaque: Slot(light: rgb(0.929, 0.906, 0.961), dark: rgb(0.149, 0.141, 0.227)),
        card:          Slot(light: .white,                   dark: rgb(0.165, 0.149, 0.251)),
        text:          Slot(light: rgb(0.106, 0.094, 0.149), dark: rgb(0.929, 0.922, 0.945)),
        textDim:       Slot(light: rgb(0.475, 0.443, 0.541), dark: rgb(0.612, 0.580, 0.667)),
        textFaint:     Slot(light: rgb(0.659, 0.624, 0.706), dark: rgb(0.443, 0.408, 0.502)),
        cardBorder:    Slot(light: .black.opacity(0.06),     dark: .white.opacity(0.06)),
        hairline:      Slot(light: .black.opacity(0.07),     dark: .white.opacity(0.07)),
        rowHover:      Slot(light: .black.opacity(0.04),     dark: .white.opacity(0.05)),
        accent:        Slot(light: rgb(0.698, 0.557, 0.890), dark: rgb(0.788, 0.690, 0.941)),
        accentSoft:    Slot(light: rgb(0.929, 0.882, 0.973), dark: rgb(0.275, 0.227, 0.380))
    )

    /// Deep, saturated plum. Higher chroma accents for users who want a
    /// bolder purple than the default — still readable in both modes.
    static let plum = PurpleTheme(
        id: "plum",
        displayName: "Plum",
        bg:            Slot(light: rgb(0.984, 0.965, 0.976), dark: rgb(0.102, 0.071, 0.118)),
        sidebarOpaque: Slot(light: rgb(0.953, 0.910, 0.929), dark: rgb(0.165, 0.114, 0.176)),
        card:          Slot(light: .white,                   dark: rgb(0.176, 0.122, 0.192)),
        text:          Slot(light: rgb(0.118, 0.075, 0.106), dark: rgb(0.949, 0.925, 0.937)),
        textDim:       Slot(light: rgb(0.486, 0.408, 0.451), dark: rgb(0.627, 0.561, 0.604)),
        textFaint:     Slot(light: rgb(0.667, 0.580, 0.624), dark: rgb(0.439, 0.376, 0.408)),
        cardBorder:    Slot(light: .black.opacity(0.07),     dark: .white.opacity(0.07)),
        hairline:      Slot(light: .black.opacity(0.08),     dark: .white.opacity(0.08)),
        rowHover:      Slot(light: .black.opacity(0.05),     dark: .white.opacity(0.06)),
        accent:        Slot(light: rgb(0.541, 0.196, 0.624), dark: rgb(0.808, 0.443, 0.890)),
        accentSoft:    Slot(light: rgb(0.945, 0.871, 0.918), dark: rgb(0.290, 0.149, 0.345))
    )

    /// Warm mauve. Pink-leaning purple with warm cream surfaces — for
    /// users who prefer warm over cool light themes.
    static let heather = PurpleTheme(
        id: "heather",
        displayName: "Heather",
        bg:            Slot(light: rgb(0.980, 0.965, 0.965), dark: rgb(0.122, 0.082, 0.094)),
        sidebarOpaque: Slot(light: rgb(0.941, 0.902, 0.910), dark: rgb(0.176, 0.125, 0.141)),
        card:          Slot(light: .white,                   dark: rgb(0.184, 0.133, 0.153)),
        text:          Slot(light: rgb(0.122, 0.082, 0.094), dark: rgb(0.945, 0.925, 0.929)),
        textDim:       Slot(light: rgb(0.498, 0.420, 0.443), dark: rgb(0.624, 0.557, 0.580)),
        textFaint:     Slot(light: rgb(0.671, 0.604, 0.624), dark: rgb(0.439, 0.376, 0.392)),
        cardBorder:    Slot(light: .black.opacity(0.06),     dark: .white.opacity(0.06)),
        hairline:      Slot(light: .black.opacity(0.07),     dark: .white.opacity(0.07)),
        rowHover:      Slot(light: .black.opacity(0.04),     dark: .white.opacity(0.05)),
        accent:        Slot(light: rgb(0.651, 0.318, 0.494), dark: rgb(0.847, 0.541, 0.682)),
        accentSoft:    Slot(light: rgb(0.961, 0.878, 0.910), dark: rgb(0.290, 0.165, 0.208))
    )

    /// Accessibility-focused. Pure white/black surfaces with strong
    /// strokes and a bold saturated purple accent — designed for
    /// low-vision users and bright environments. Picks brand-consistent
    /// purple over the more common system blue/yellow high-contrast
    /// palettes.
    static let highContrast = PurpleTheme(
        id: "highContrast",
        displayName: "High Contrast",
        bg:            Slot(light: .white,                   dark: .black),
        sidebarOpaque: Slot(light: rgb(0.941, 0.941, 0.941), dark: rgb(0.039, 0.039, 0.039)),
        card:          Slot(light: .white,                   dark: rgb(0.078, 0.078, 0.078)),
        text:          Slot(light: .black,                   dark: .white),
        textDim:       Slot(light: rgb(0.149, 0.149, 0.149), dark: rgb(0.910, 0.910, 0.910)),
        textFaint:     Slot(light: rgb(0.310, 0.310, 0.310), dark: rgb(0.741, 0.741, 0.741)),
        cardBorder:    Slot(light: .black.opacity(0.32),     dark: .white.opacity(0.32)),
        hairline:      Slot(light: .black.opacity(0.26),     dark: .white.opacity(0.26)),
        rowHover:      Slot(light: .black.opacity(0.10),     dark: .white.opacity(0.12)),
        accent:        Slot(light: rgb(0.416, 0.106, 0.604), dark: rgb(0.780, 0.490, 1.000)),
        accentSoft:    Slot(light: rgb(0.910, 0.839, 0.961), dark: rgb(0.290, 0.157, 0.439))
    )

    /// Ordered for the picker. Royal Purple leads (default); High Contrast
    /// trails so accessibility users can find it by scanning down.
    static let allBuiltIns: [PurpleTheme] = [
        .royalPurple, .lavender, .plum, .heather, .highContrast
    ]

    /// Resolve a stored id against built-ins, then user themes. Built-ins
    /// win on collision so a hand-edited settings.json can't shadow the
    /// flagship by reusing its id. Falls back to `.royalPurple` when no
    /// match — keeps the app rendering even if settings.json is partially
    /// corrupt.
    static func resolve(id: String, userThemes: [UserTheme]) -> PurpleTheme {
        if let built = allBuiltIns.first(where: { $0.id == id }) { return built }
        if let custom = userThemes.first(where: { $0.id.uuidString == id }) {
            return custom.materialised
        }
        return .royalPurple
    }
}

// MARK: - UserTheme (Codable; full shape so slice 2's builder is purely UI)

/// Round-trippable custom theme stored in `settings.json`. Mirrors
/// `PurpleTheme`'s slot layout as `HexPair`s so SwiftUI `Color` doesn't
/// have to Codable itself. `materialised` produces the runtime
/// `PurpleTheme` value. The persistence shape lands in slice 1 so a
/// future settings.json carrying user themes already decodes; slice 2
/// adds the WYSIWYG builder UI on top.
struct UserTheme: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Built-in theme this was duplicated from, if any. Pure metadata —
    /// the renderer doesn't use it; it's surfaced in the builder so the
    /// user can see where their custom started.
    var basedOn: String?
    /// Wall-clock creation time. Surfaced in the builder list so the
    /// user can sort their library.
    var createdAt: Date = Date()

    var bg: HexPair
    var sidebarOpaque: HexPair
    var card: HexPair
    var text: HexPair
    var textDim: HexPair
    var textFaint: HexPair
    var cardBorder: HexPair
    var hairline: HexPair
    var rowHover: HexPair
    var accent: HexPair
    var accentSoft: HexPair

    /// `#RRGGBB` or `#AARRGGBB`. Two hex values per slot so the theme
    /// works in both appearance modes.
    struct HexPair: Codable, Hashable {
        var light: String
        var dark: String
    }

    /// Build a UserTheme by snapshotting an existing PurpleTheme's slots.
    /// The new theme gets a fresh UUID and a name derived from the base.
    static func duplicate(of base: PurpleTheme, name: String) -> UserTheme {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return UserTheme(
            name: trimmed.isEmpty ? "Custom from \(base.displayName)" : trimmed,
            basedOn: base.id,
            bg:            base.bg.hexPair,
            sidebarOpaque: base.sidebarOpaque.hexPair,
            card:          base.card.hexPair,
            text:          base.text.hexPair,
            textDim:       base.textDim.hexPair,
            textFaint:     base.textFaint.hexPair,
            cardBorder:    base.cardBorder.hexPair,
            hairline:      base.hairline.hexPair,
            rowHover:      base.rowHover.hexPair,
            accent:        base.accent.hexPair,
            accentSoft:    base.accentSoft.hexPair
        )
    }

    /// Construct the runtime `PurpleTheme` from this UserTheme. Hex
    /// strings that fail to parse fall back to the corresponding
    /// Royal Purple slot — keeps the app rendering when a hand-edited
    /// settings.json has bad data.
    var materialised: PurpleTheme {
        func slot(_ pair: HexPair, fallback: PurpleTheme.Slot) -> PurpleTheme.Slot {
            PurpleTheme.Slot(
                light: Color(hex: pair.light) ?? fallback.light,
                dark:  Color(hex: pair.dark)  ?? fallback.dark
            )
        }
        let fb: PurpleTheme = .royalPurple
        return PurpleTheme(
            id: id.uuidString,
            displayName: name,
            bg:            slot(bg,            fallback: fb.bg),
            sidebarOpaque: slot(sidebarOpaque, fallback: fb.sidebarOpaque),
            card:          slot(card,          fallback: fb.card),
            text:          slot(text,          fallback: fb.text),
            textDim:       slot(textDim,       fallback: fb.textDim),
            textFaint:     slot(textFaint,     fallback: fb.textFaint),
            cardBorder:    slot(cardBorder,    fallback: fb.cardBorder),
            hairline:      slot(hairline,      fallback: fb.hairline),
            rowHover:      slot(rowHover,      fallback: fb.rowHover),
            accent:        slot(accent,        fallback: fb.accent),
            accentSoft:    slot(accentSoft,    fallback: fb.accentSoft)
        )
    }
}

extension PurpleTheme.Slot {
    /// Hex-pair representation for UserTheme persistence. Opacities are
    /// flattened to `#AARRGGBB`. Used by `UserTheme.duplicate(of:)`.
    var hexPair: UserTheme.HexPair {
        UserTheme.HexPair(light: light.hexARGB, dark: dark.hexARGB)
    }
}

// MARK: - Persistence helpers (used by ThemeBuilderView; pulled out so
// they're testable without instantiating SwiftUI views).

extension UserTheme {
    /// Insert or replace by id. Preserves position when updating so the
    /// theme picker's user-themes grid doesn't reorder after an edit.
    static func upsert(_ theme: UserTheme, in array: inout [UserTheme]) {
        if let idx = array.firstIndex(where: { $0.id == theme.id }) {
            array[idx] = theme
        } else {
            array.append(theme)
        }
    }
}

extension PurpleTheme {
    /// Compute the themeID to use after deleting a user theme. If the
    /// deleted theme is currently active, fall back to its `basedOn`
    /// built-in (when known); otherwise to `royalPurple`. If the deleted
    /// theme wasn't active, keep `currentID` unchanged. Pulled out as a
    /// pure function so the active-theme fallback can be tested without
    /// the builder UI.
    static func resolveAfterDelete(
        currentID: String,
        removedID: String,
        basedOn basedOnID: String?
    ) -> String {
        guard currentID == removedID else { return currentID }
        if let basedOnID, allBuiltIns.contains(where: { $0.id == basedOnID }) {
            return basedOnID
        }
        return royalPurple.id
    }
}

// MARK: - Color helpers

extension Color {
    /// Light/dark variant of `Color`. SwiftUI's stock `Color(_:bundle:)` is
    /// asset-catalog backed; this wrapper uses an NSColor dynamicProvider so
    /// per-mode pairs can be declared inline in `PurpleTheme`.
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark
            ]) != nil
            return NSColor(isDark ? dark : light)
        })
    }

    /// Parse `#RGB`, `#RRGGBB`, or `#AARRGGBB` (with or without a leading
    /// `#`). Returns `nil` for anything else.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 3:
            r = Double((v >> 8) & 0xF) / 15.0
            g = Double((v >> 4) & 0xF) / 15.0
            b = Double( v       & 0xF) / 15.0
            a = 1.0
        case 6:
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8)  & 0xFF) / 255.0
            b = Double( v        & 0xFF) / 255.0
            a = 1.0
        case 8:
            a = Double((v >> 24) & 0xFF) / 255.0
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8)  & 0xFF) / 255.0
            b = Double( v        & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// `#AARRGGBB` representation. Falls back to `#FF000000` if extraction
    /// fails (which only happens for dynamic-provider colors — the static
    /// values fed into `Slot(light:dark:)` always extract).
    var hexARGB: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        let a = Int(round(ns.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }
}

/// Inline shorthand for `Color(.sRGB, red:green:blue:opacity:1)` so the
/// built-in theme literals fit on one line each.
private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
}
