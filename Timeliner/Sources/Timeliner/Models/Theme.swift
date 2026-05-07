import SwiftUI

/// Visual theme: gradient stops + accent + card / sidebar / track colors.
/// Built-ins are static lets on this type; user-authored themes live in
/// `AppSettings.userThemes` as `UserTheme` records and resolve to a `Theme`
/// via `UserTheme.asTheme()`. `named(_:userThemes:)` accepts either the
/// canonical `"user:<uuid>"` form or a plain name (built-in or user theme).
struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    let gradientColors: [Color]
    let accentColor: Color
    let cardBackground: Color
    let sidebarBackground: Color
    let timelineTrackColor: Color

    static let all: [Theme] = [.default_, .midnight, .ocean, .forest, .sunset, .rose]

    static func named(_ name: String, userThemes: [UserTheme] = []) -> Theme {
        // 1. Built-ins by name (case-insensitive for forgiveness)
        if let builtIn = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return builtIn
        }
        // 2. User themes — accept either "user:<uuid>" (canonical) or just
        // the user theme's name (matches the picker label).
        if name.hasPrefix("user:") {
            let uuidStr = String(name.dropFirst("user:".count))
            if let uuid = UUID(uuidString: uuidStr),
               let u = userThemes.first(where: { $0.id == uuid }) {
                return u.asTheme()
            }
        }
        if let u = userThemes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return u.asTheme()
        }
        return .default_
    }

    static let `default_` = Theme(
        id: "default",
        name: "Default",
        gradientColors: [Color(.windowBackgroundColor), Color(.underPageBackgroundColor)],
        accentColor: Color(red: 0.23, green: 0.51, blue: 0.96),
        cardBackground: Color(.windowBackgroundColor),
        sidebarBackground: Color(.windowBackgroundColor),
        timelineTrackColor: Color(white: 0.5, opacity: 0.35)
    )

    static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        gradientColors: [Color(red: 0.06, green: 0.07, blue: 0.15), Color(red: 0.02, green: 0.03, blue: 0.08)],
        accentColor: Color(red: 0.40, green: 0.65, blue: 1.0),
        cardBackground: Color(white: 1.0, opacity: 0.07),
        sidebarBackground: Color(white: 0.0, opacity: 0.30),
        timelineTrackColor: Color(white: 1.0, opacity: 0.30)
    )

    static let ocean = Theme(
        id: "ocean",
        name: "Ocean",
        gradientColors: [Color(red: 0.04, green: 0.35, blue: 0.55), Color(red: 0.02, green: 0.18, blue: 0.32)],
        accentColor: Color(red: 0.10, green: 0.85, blue: 0.85),
        cardBackground: Color(white: 1.0, opacity: 0.10),
        sidebarBackground: Color(white: 0.0, opacity: 0.25),
        timelineTrackColor: Color(white: 1.0, opacity: 0.30)
    )

    static let forest = Theme(
        id: "forest",
        name: "Forest",
        gradientColors: [Color(red: 0.07, green: 0.22, blue: 0.11), Color(red: 0.03, green: 0.09, blue: 0.04)],
        accentColor: Color(red: 0.45, green: 0.85, blue: 0.35),
        cardBackground: Color(white: 1.0, opacity: 0.08),
        sidebarBackground: Color(white: 0.0, opacity: 0.25),
        timelineTrackColor: Color(white: 1.0, opacity: 0.30)
    )

    static let sunset = Theme(
        id: "sunset",
        name: "Sunset",
        gradientColors: [Color(red: 0.55, green: 0.18, blue: 0.05), Color(red: 0.22, green: 0.07, blue: 0.12)],
        accentColor: Color(red: 1.0, green: 0.65, blue: 0.15),
        cardBackground: Color(white: 1.0, opacity: 0.08),
        sidebarBackground: Color(white: 0.0, opacity: 0.25),
        timelineTrackColor: Color(white: 1.0, opacity: 0.30)
    )

    static let rose = Theme(
        id: "rose",
        name: "Rose",
        gradientColors: [Color(red: 0.55, green: 0.08, blue: 0.22), Color(red: 0.22, green: 0.04, blue: 0.10)],
        accentColor: Color(red: 1.0, green: 0.45, blue: 0.65),
        cardBackground: Color(white: 1.0, opacity: 0.08),
        sidebarBackground: Color(white: 0.0, opacity: 0.25),
        timelineTrackColor: Color(white: 1.0, opacity: 0.30)
    )
}
