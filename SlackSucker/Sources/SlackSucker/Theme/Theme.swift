import SwiftUI

/// Color / typography / material tokens. Ported from messages-exporter-gui's
/// MissionTheme with a Slack-flavored magenta accent so SlackSucker is
/// visually distinguishable from its sibling apps. The Materials substrate
/// auto-adapts to light/dark and the desktop tint.
struct AppTheme {
    let isDark: Bool

    let bg1: Color
    let bg2: Color

    let ink:     Color
    let inkDim:  Color
    let inkMute: Color

    let rule:     Color
    let ruleSoft: Color

    let accent:       Color
    let accentSoft:   Color
    let accentBorder: Color

    let runGradStart: Color
    let runGradEnd:   Color

    let green: Color
    let amber: Color
    let red:   Color

    let cardFill:       Color
    let cardFillStrong: Color

    static func resolve(_ scheme: ColorScheme) -> AppTheme {
        scheme == .dark ? .dark : .light
    }

    static let light = AppTheme(
        isDark: false,
        bg1:          Color(red: 0.957, green: 0.949, blue: 0.965),
        bg2:          Color(red: 0.937, green: 0.918, blue: 0.953),
        ink:          Color(red: 0.149, green: 0.165, blue: 0.220),
        inkDim:       Color(red: 0.408, green: 0.420, blue: 0.475),
        inkMute:      Color(red: 0.580, green: 0.592, blue: 0.643),
        rule:         Color(red: 0.847, green: 0.851, blue: 0.882),
        ruleSoft:     Color.black.opacity(0.06),
        accent:       Color(red: 0.612, green: 0.275, blue: 0.749),
        accentSoft:   Color(red: 0.612, green: 0.275, blue: 0.749).opacity(0.10),
        accentBorder: Color(red: 0.612, green: 0.275, blue: 0.749).opacity(0.25),
        runGradStart: Color(red: 0.612, green: 0.275, blue: 0.749),
        runGradEnd:   Color(red: 0.380, green: 0.227, blue: 0.835),
        green:        Color(red: 0.204, green: 0.780, blue: 0.349),
        amber:        Color(red: 0.878, green: 0.659, blue: 0.184),
        red:          Color(red: 0.953, green: 0.314, blue: 0.231),
        cardFill:       Color.white.opacity(0.78),
        cardFillStrong: Color.white
    )

    static let dark = AppTheme(
        isDark: true,
        bg1:          Color(red: 0.114, green: 0.106, blue: 0.149),
        bg2:          Color(red: 0.094, green: 0.078, blue: 0.149),
        ink:          Color(red: 0.929, green: 0.937, blue: 0.953),
        inkDim:       Color(red: 0.690, green: 0.702, blue: 0.741),
        inkMute:      Color(red: 0.518, green: 0.529, blue: 0.561),
        rule:         Color.white.opacity(0.10),
        ruleSoft:     Color.white.opacity(0.06),
        accent:       Color(red: 0.737, green: 0.388, blue: 0.871),
        accentSoft:   Color(red: 0.737, green: 0.388, blue: 0.871).opacity(0.16),
        accentBorder: Color(red: 0.737, green: 0.388, blue: 0.871).opacity(0.35),
        runGradStart: Color(red: 0.580, green: 0.235, blue: 0.741),
        runGradEnd:   Color(red: 0.302, green: 0.169, blue: 0.671),
        green:        Color(red: 0.306, green: 0.812, blue: 0.435),
        amber:        Color(red: 0.949, green: 0.769, blue: 0.361),
        red:          Color(red: 1.000, green: 0.420, blue: 0.376),
        cardFill:       Color.white.opacity(0.045),
        cardFillStrong: Color.white.opacity(0.05)
    )
}

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

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.light
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

struct AppThemeReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: (AppTheme) -> Content

    var body: some View {
        let theme = AppTheme.resolve(scheme)
        content(theme)
            .environment(\.appTheme, theme)
    }
}

enum AppFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func kicker(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.appTheme) private var t
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
