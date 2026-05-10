import SwiftUI

/// Visual tokens pulled from the design handoff (`Design/purplelife/project/chrome.jsx`,
/// `PE_LIGHT` / `PE_DARK`). SwiftUI's `Color` doesn't speak oklch, so the
/// oklch values from the prototype were converted to sRGB once at the
/// source.
///
/// Use these named tokens instead of `Color.secondary.opacity(...)` or
/// hardcoded hex literals so the look stays consistent across views.
enum Theme {

    // MARK: - Surfaces

    /// Window background — warm cream in light, warm near-black in dark.
    static let bg: Color = Color(
        light: Color(red: 0.984, green: 0.980, blue: 0.969),     // #fbfaf7
        dark:  Color(red: 0.110, green: 0.106, blue: 0.118)      // #1c1b1e
    )

    /// Sidebar background (rendered behind `.regularMaterial` in macOS
    /// chrome; the value here is the opaque fallback for places where
    /// the material would be inappropriate, e.g. inset footers).
    static let sidebarOpaque: Color = Color(
        light: Color(red: 0.945, green: 0.929, blue: 0.898),     // #f1ede5
        dark:  Color(red: 0.149, green: 0.141, blue: 0.165)      // #26242a
    )

    /// Card surface — what panels / list rows sit on top of `bg`.
    static let card: Color = Color(
        light: .white,
        dark:  Color(red: 0.149, green: 0.141, blue: 0.165)      // #26242a
    )

    // MARK: - Text

    static let text: Color = Color(
        light: Color(red: 0.110, green: 0.102, blue: 0.090),     // #1c1a17
        dark:  Color(red: 0.925, green: 0.922, blue: 0.910)      // #ecebe8
    )

    static let textDim: Color = Color(
        light: Color(red: 0.478, green: 0.455, blue: 0.408),     // #7a7468
        dark:  Color(red: 0.608, green: 0.584, blue: 0.541)      // #9b958a
    )

    static let textFaint: Color = Color(
        light: Color(red: 0.659, green: 0.635, blue: 0.580),     // #a8a294
        dark:  Color(red: 0.416, green: 0.392, blue: 0.341)      // #6a6457
    )

    // MARK: - Lines

    /// Card border — subtle 0.5 px stroke on panels and list cards.
    static let cardBorder: Color = Color(
        light: Color.black.opacity(0.06),
        dark:  Color.white.opacity(0.06)
    )

    /// Hairline divider — slightly stronger than cardBorder; used
    /// for in-list separators.
    static let hairline: Color = Color(
        light: Color.black.opacity(0.07),
        dark:  Color.white.opacity(0.07)
    )

    /// Hover background for selectable rows.
    static let rowHover: Color = Color(
        light: Color.black.opacity(0.04),
        dark:  Color.white.opacity(0.05)
    )

    // MARK: - Accent (PurpleLife brand)

    /// Primary accent — oklch(0.56 0.14 295) → roughly #8B65C1 in light.
    /// Slightly brighter in dark.
    static let accent: Color = Color(
        light: Color(red: 0.545, green: 0.396, blue: 0.757),
        dark:  Color(red: 0.659, green: 0.510, blue: 0.871)
    )

    /// Background tint behind a selected sidebar row / button.
    static let accentSoft: Color = Color(
        light: Color(red: 0.945, green: 0.910, blue: 0.965),
        dark:  Color(red: 0.224, green: 0.180, blue: 0.302)
    )

    // MARK: - Section header text style (uppercase + tracking)

    /// Section header foreground tone — picks textFaint up so it reads
    /// at small caps sizes.
    static let sectionHeader: Color = textFaint

    // MARK: - Convenience modifiers

    /// Card chrome shared by Today panels and schema editor field rows.
    static func card(_ content: some View, padding: CGFloat = 16, corner: CGFloat = 10) -> some View {
        content
            .padding(padding)
            .background(card)
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(cardBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

/// Light/dark variant of `Color`. SwiftUI's stock `Color(_:bundle:)` is
/// asset-catalog backed; this convenience wraps a `dynamicProvider`
/// resolver so we can declare per-mode pairs inline in `Theme`.
extension Color {
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(isDark ? dark : light)
        })
    }
}
