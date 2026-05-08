import SwiftUI

/// Color/typography/material tokens for the Mission Control redesign.
/// Hand-tuned sRGB approximations of the oklch tokens in the design
/// handoff (mission.jsx). We lean on SwiftUI materials for the frosted-
/// glass surfaces — Materials already adapt to light/dark and inherit
/// the desktop tint, which is the native Tahoe-glass behavior the design
/// is approximating.
struct MissionTheme {
    let isDark: Bool

    // Tinted gradient for the window background.
    let bg1: Color
    let bg2: Color

    // Foreground inks.
    let ink:     Color   // primary
    let inkDim:  Color   // secondary
    let inkMute: Color   // tertiary / labels

    // Hairlines + soft separators.
    let rule:     Color
    let ruleSoft: Color

    // Brand / accent (electric blue).
    let accent:       Color
    let accentSoft:   Color   // tinted background fill
    let accentBorder: Color

    // Run-strip gradient endpoints.
    let runGradStart: Color
    let runGradEnd:   Color

    // Status colors.
    let green: Color
    let amber: Color
    let red:   Color

    // Surfaces (used as fill colors atop materials when needed).
    let cardFill:       Color
    let cardFillStrong: Color   // opaque field background

    static func resolve(_ scheme: ColorScheme) -> MissionTheme {
        scheme == .dark ? .dark : .light
    }

    static let light = MissionTheme(
        isDark: false,
        bg1:          Color(red: 0.946, green: 0.951, blue: 0.965),
        bg2:          Color(red: 0.918, green: 0.918, blue: 0.949),
        ink:          Color(red: 0.149, green: 0.165, blue: 0.220),
        inkDim:       Color(red: 0.408, green: 0.420, blue: 0.475),
        inkMute:      Color(red: 0.580, green: 0.592, blue: 0.643),
        rule:         Color(red: 0.847, green: 0.851, blue: 0.882),
        ruleSoft:     Color.black.opacity(0.06),
        accent:       Color(red: 0.239, green: 0.435, blue: 1.000),
        accentSoft:   Color(red: 0.239, green: 0.435, blue: 1.000).opacity(0.10),
        accentBorder: Color(red: 0.239, green: 0.435, blue: 1.000).opacity(0.25),
        runGradStart: Color(red: 0.239, green: 0.435, blue: 1.000),
        runGradEnd:   Color(red: 0.310, green: 0.318, blue: 0.953),
        green:        Color(red: 0.204, green: 0.780, blue: 0.349),
        amber:        Color(red: 0.878, green: 0.659, blue: 0.184),
        red:          Color(red: 0.953, green: 0.314, blue: 0.231),
        cardFill:       Color.white.opacity(0.78),
        cardFillStrong: Color.white
    )

    static let dark = MissionTheme(
        isDark: true,
        bg1:          Color(red: 0.106, green: 0.118, blue: 0.157),
        bg2:          Color(red: 0.094, green: 0.090, blue: 0.157),
        ink:          Color(red: 0.929, green: 0.937, blue: 0.953),
        inkDim:       Color(red: 0.690, green: 0.702, blue: 0.741),
        inkMute:      Color(red: 0.518, green: 0.529, blue: 0.561),
        rule:         Color.white.opacity(0.10),
        ruleSoft:     Color.white.opacity(0.06),
        accent:       Color(red: 0.380, green: 0.533, blue: 1.000),
        accentSoft:   Color(red: 0.380, green: 0.533, blue: 1.000).opacity(0.16),
        accentBorder: Color(red: 0.380, green: 0.533, blue: 1.000).opacity(0.35),
        runGradStart: Color(red: 0.224, green: 0.404, blue: 0.965),
        runGradEnd:   Color(red: 0.278, green: 0.184, blue: 0.745),
        green:        Color(red: 0.306, green: 0.812, blue: 0.435),
        amber:        Color(red: 0.949, green: 0.769, blue: 0.361),
        red:          Color(red: 1.000, green: 0.420, blue: 0.376),
        cardFill:       Color.white.opacity(0.045),
        cardFillStrong: Color.white.opacity(0.05)
    )
}

/// User preference for window appearance, persisted in UserDefaults.
/// `.system` honors System Settings → Appearance; `.light` and `.dark`
/// force the chosen scheme regardless of system state.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Auto"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
    /// SwiftUI scheme override; nil means "follow system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    var next: ThemePreference {
        switch self {
        case .system: return .light
        case .light:  return .dark
        case .dark:   return .system
        }
    }
}

private struct MissionThemeKey: EnvironmentKey {
    static let defaultValue = MissionTheme.light
}

extension EnvironmentValues {
    var missionTheme: MissionTheme {
        get { self[MissionThemeKey.self] }
        set { self[MissionThemeKey.self] = newValue }
    }
}

/// Resolves the active theme from the system color scheme and injects it
/// into the environment. Wrap the root view in this so descendants can
/// `@Environment(\.missionTheme)` without re-deriving from `colorScheme`.
struct MissionThemeReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: (MissionTheme) -> Content

    var body: some View {
        let theme = MissionTheme.resolve(scheme)
        content(theme)
            .environment(\.missionTheme, theme)
    }
}

// MARK: - Typography

enum MissionFont {
    /// Display weight: bigger headings (h1, stat tiles).
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Body sans, default UI text.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Monospaced — log, kbd hints, numeric metadata in fields.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// All-caps kicker / section header label.
    static func kicker(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

// MARK: - Reusable surface

/// Frosted-glass card surface — a regular-material rounded rect with a
/// translucent fill on top so card edges read against any wallpaper. Used
/// for the form card, stat tiles, and live-output card.
struct GlassCard<Content: View>: View {
    @Environment(\.missionTheme) private var t
    var cornerRadius: CGFloat = 12
    var accent: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(accent ? t.accentSoft : t.cardFill)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accent ? t.accentBorder : t.ruleSoft, lineWidth: 1)
            }
    }
}
