import SwiftUI

/// A selectable appearance preset: an **accent color** paired with a **light or
/// dark color scheme**. PurpleDiary's whole UI already pulls its accent from
/// `AppState.effectiveAccentColor` (which reads `settings.accentColorHex`) and
/// its light/dark mode from `settings.colorScheme`, so a theme is simply a named
/// `(accentHex, scheme)` pair that gets written into those two existing settings
/// fields when chosen — no new persisted state, no per-view wiring.
///
/// Because "Purple Dark" and "Purple Light" differ *only* by scheme, a theme has
/// to carry the scheme; that's why selecting one also sets light/dark. The
/// currently-selected theme is **derived** by matching the persisted
/// `(accentHex, scheme)` back to this table (`Theme.matching`), so the free-form
/// custom color picker and the Mode control still work — they just produce a
/// "Custom" state (no match) rather than a stored flag that could drift.
///
/// All colors are plain settings (no journal content), so themes have zero
/// bearing on the security model — see `Docs/SECURITY.md` §1/§10.
struct Theme: Identifiable, Equatable, Hashable {
    /// Stable slug, e.g. `"purple-dark"`. Used for lookups and tests, not persisted.
    let id: String
    /// User-facing name shown in the picker, e.g. "Purple Dark".
    let name: String
    /// A one-line description for the picker subtitle / tooltip.
    let blurb: String
    /// Accent color as a `#RRGGBB` hex string (written into `accentColorHex`).
    let accentHex: String
    /// `"light"` or `"dark"` (written into `colorScheme`). Themes never use
    /// `"auto"` — that's the un-themed "match system" state, shown as Custom.
    let scheme: String

    /// The accent as a SwiftUI `Color`. Falls back to purple if the literal is
    /// ever malformed (it isn't — the table is asserted valid in `ThemeTests`).
    var accent: Color { Color(hex: accentHex) ?? .purple }

    var isDark: Bool { scheme == "dark" }

    /// A representative card background for the picker swatch, so a dark theme
    /// previews dark and a light theme previews light without spinning up a real
    /// rendering. Not used anywhere in the live UI (that uses the real scheme).
    var previewBackground: Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.12)
               : Color(red: 0.98, green: 0.98, blue: 0.99)
    }

    /// The text color that reads on `previewBackground`.
    var previewForeground: Color { isDark ? .white : .black }
}

extension Theme {
    /// The signature default — the purple-on-dark look PurpleDiary ships with.
    static let signatureId = "purple-dark"

    /// The 15 built-in themes. Order is the picker order: the two purple
    /// signatures first, then a spread of dark and light accents. Every
    /// `(accentHex, scheme)` pair is unique so selection-by-match is unambiguous
    /// (asserted in `ThemeTests`).
    static let all: [Theme] = [
        Theme(id: "purple-dark",  name: "Purple Dark",  blurb: "The signature — violet on deep charcoal.",      accentHex: "#7C5CFF", scheme: "dark"),
        Theme(id: "purple-light", name: "Purple Light", blurb: "The signature violet on a clean light page.",    accentHex: "#7C5CFF", scheme: "light"),
        Theme(id: "midnight",     name: "Midnight",     blurb: "Cool cornflower blue for late-night writing.",   accentHex: "#5B8DEF", scheme: "dark"),
        Theme(id: "indigo-night", name: "Indigo Night", blurb: "Soft electric indigo on dark.",                  accentHex: "#818CF8", scheme: "dark"),
        Theme(id: "ocean",        name: "Ocean",        blurb: "Bright teal, like sun on deep water.",           accentHex: "#22B8CF", scheme: "dark"),
        Theme(id: "crimson",      name: "Crimson",      blurb: "Warm rose-red against charcoal.",                accentHex: "#F0526D", scheme: "dark"),
        Theme(id: "graphite",     name: "Graphite",     blurb: "Quiet, near-monochrome grey.",                   accentHex: "#9AA0AA", scheme: "dark"),
        Theme(id: "slate",        name: "Slate",        blurb: "Muted blue-grey, understated and calm.",         accentHex: "#7C8AA0", scheme: "dark"),
        Theme(id: "rose",         name: "Rose Quartz",  blurb: "Gentle pink on a bright page.",                  accentHex: "#E0699A", scheme: "light"),
        Theme(id: "lavender",     name: "Lavender",     blurb: "Soft lilac, lighter than the signature.",        accentHex: "#9B7FD4", scheme: "light"),
        Theme(id: "forest",       name: "Forest",       blurb: "Calm pine green on white.",                      accentHex: "#2F9E5E", scheme: "light"),
        Theme(id: "mint",         name: "Mint",         blurb: "Fresh blue-green, cool and light.",              accentHex: "#1FBF8F", scheme: "light"),
        Theme(id: "sunset",       name: "Sunset",       blurb: "Warm tangerine for a bright mood.",              accentHex: "#FB7138", scheme: "light"),
        Theme(id: "gold",         name: "Goldenrod",    blurb: "Warm amber on a light page.",                    accentHex: "#D9A21B", scheme: "light"),
        Theme(id: "sepia",        name: "Sepia",        blurb: "Vintage warm brown, like aged paper.",           accentHex: "#B0814E", scheme: "light"),
    ]

    /// The signature theme (`purple-dark`). Force-unwrap is safe: it's a literal
    /// member of `all`, guarded by `ThemeTests.testSignatureExists`.
    static var signature: Theme { all.first { $0.id == signatureId }! }

    static func byId(_ id: String) -> Theme? { all.first { $0.id == id } }

    /// The theme matching a persisted `(accentHex, scheme)` pair, or `nil` for a
    /// custom accent / "match system" mode. Hex comparison is case-insensitive so
    /// a `#7c5cff` saved by the system color picker still matches `#7C5CFF`.
    static func matching(accentHex: String, colorScheme: String) -> Theme? {
        let hex = accentHex.lowercased()
        return all.first { $0.accentHex.lowercased() == hex && $0.scheme == colorScheme }
    }
}
