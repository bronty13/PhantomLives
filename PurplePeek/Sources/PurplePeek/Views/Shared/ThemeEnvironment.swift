import SwiftUI

/// A color theme. Each theme defines a main-area background gradient, an accent color, and
/// sidebar/cell surface colors. Colors are built so they read acceptably under both Light
/// and Dark appearance (the gradient is a tint over the system surface, not an opaque slab).
struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let backgroundGradient: [Color]
    let accentColor: Color
    let sidebarBackground: Color
    let cellBackground: Color

    static let defaultThemeName = "Purple Dusk"

    static func named(_ name: String) -> AppTheme {
        all.first { $0.name == name } ?? purpleDusk
    }

    // MARK: - The ten themes

    static let purpleDusk = AppTheme(
        id: "purpleDusk", name: "Purple Dusk",
        backgroundGradient: [Color(red: 0.16, green: 0.09, blue: 0.30), Color(red: 0.30, green: 0.16, blue: 0.50)],
        accentColor: Color(red: 0.69, green: 0.45, blue: 1.0),
        sidebarBackground: Color(red: 0.12, green: 0.07, blue: 0.22).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let midnightBlue = AppTheme(
        id: "midnightBlue", name: "Midnight Blue",
        backgroundGradient: [Color(red: 0.06, green: 0.10, blue: 0.24), Color(red: 0.10, green: 0.20, blue: 0.42)],
        accentColor: Color(red: 0.40, green: 0.62, blue: 1.0),
        sidebarBackground: Color(red: 0.05, green: 0.08, blue: 0.18).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let forestGreen = AppTheme(
        id: "forestGreen", name: "Forest Green",
        backgroundGradient: [Color(red: 0.06, green: 0.18, blue: 0.12), Color(red: 0.11, green: 0.32, blue: 0.22)],
        accentColor: Color(red: 0.36, green: 0.80, blue: 0.55),
        sidebarBackground: Color(red: 0.05, green: 0.14, blue: 0.10).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let crimsonRed = AppTheme(
        id: "crimsonRed", name: "Crimson Red",
        backgroundGradient: [Color(red: 0.24, green: 0.06, blue: 0.10), Color(red: 0.42, green: 0.11, blue: 0.18)],
        accentColor: Color(red: 1.0, green: 0.42, blue: 0.50),
        sidebarBackground: Color(red: 0.18, green: 0.05, blue: 0.08).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let oceanTeal = AppTheme(
        id: "oceanTeal", name: "Ocean Teal",
        backgroundGradient: [Color(red: 0.04, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.32, blue: 0.38)],
        accentColor: Color(red: 0.30, green: 0.80, blue: 0.82),
        sidebarBackground: Color(red: 0.03, green: 0.14, blue: 0.17).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let warmAmber = AppTheme(
        id: "warmAmber", name: "Warm Amber",
        backgroundGradient: [Color(red: 0.26, green: 0.16, blue: 0.04), Color(red: 0.44, green: 0.28, blue: 0.08)],
        accentColor: Color(red: 1.0, green: 0.72, blue: 0.32),
        sidebarBackground: Color(red: 0.20, green: 0.12, blue: 0.03).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let roseGold = AppTheme(
        id: "roseGold", name: "Rose Gold",
        backgroundGradient: [Color(red: 0.28, green: 0.16, blue: 0.18), Color(red: 0.50, green: 0.30, blue: 0.32)],
        accentColor: Color(red: 0.95, green: 0.62, blue: 0.62),
        sidebarBackground: Color(red: 0.22, green: 0.12, blue: 0.14).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let slateGray = AppTheme(
        id: "slateGray", name: "Slate Gray",
        backgroundGradient: [Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.22, green: 0.24, blue: 0.27)],
        accentColor: Color(red: 0.62, green: 0.68, blue: 0.78),
        sidebarBackground: Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    static let sageGreen = AppTheme(
        id: "sageGreen", name: "Sage Green",
        backgroundGradient: [Color(red: 0.16, green: 0.20, blue: 0.14), Color(red: 0.28, green: 0.34, blue: 0.24)],
        accentColor: Color(red: 0.66, green: 0.78, blue: 0.54),
        sidebarBackground: Color(red: 0.13, green: 0.16, blue: 0.11).opacity(0.5),
        cellBackground: Color.white.opacity(0.06)
    )
    /// "System" defers to macOS — neutral window surfaces, system accent.
    static let system = AppTheme(
        id: "system", name: "System",
        backgroundGradient: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor)],
        accentColor: Color.accentColor,
        sidebarBackground: Color(nsColor: .windowBackgroundColor),
        cellBackground: Color(nsColor: .controlBackgroundColor)
    )

    static let all: [AppTheme] = [
        purpleDusk, midnightBlue, forestGreen, crimsonRed, oceanTeal,
        warmAmber, roseGold, slateGray, sageGreen, system
    ]
}

// MARK: - Environment plumbing

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .purpleDusk
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
