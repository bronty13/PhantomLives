import SwiftUI

struct Theme: Identifiable {
    let id: String
    let name: String
    let gradientColors: [Color]
    let accentColor: Color
    let chartPalette: [Color]
    let cardBackground: Color
    let sidebarBackground: Color

    static let all: [Theme] = [default_, midnight, ocean, forest, sunset, rose]

    static func named(_ name: String) -> Theme {
        all.first { $0.name == name } ?? .default_
    }

    static let `default_` = Theme(
        id: "default",
        name: "Default",
        gradientColors: [Color(.windowBackgroundColor), Color(.underPageBackgroundColor)],
        accentColor: Color(red: 0.04, green: 0.52, blue: 1.0),
        chartPalette: [.blue, .teal, .indigo, .purple, .cyan],
        cardBackground: Color(.windowBackgroundColor),
        sidebarBackground: Color(.windowBackgroundColor)
    )

    static let midnight = Theme(
        id: "midnight",
        name: "Midnight",
        gradientColors: [Color(red: 0.06, green: 0.07, blue: 0.15), Color(red: 0.02, green: 0.03, blue: 0.08)],
        accentColor: Color(red: 0.40, green: 0.60, blue: 1.0),
        chartPalette: [Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.6, green: 0.8, blue: 1.0), .teal, .purple, .cyan],
        cardBackground: Color(white: 1.0, opacity: 0.07),
        sidebarBackground: Color(white: 0.0, opacity: 0.3)
    )

    static let ocean = Theme(
        id: "ocean",
        name: "Ocean",
        gradientColors: [Color(red: 0.04, green: 0.35, blue: 0.55), Color(red: 0.02, green: 0.18, blue: 0.32)],
        accentColor: Color(red: 0.10, green: 0.85, blue: 0.85),
        chartPalette: [.cyan, .teal, Color(red: 0.1, green: 0.8, blue: 0.8), .blue, .mint],
        cardBackground: Color(white: 1.0, opacity: 0.10),
        sidebarBackground: Color(white: 0.0, opacity: 0.25)
    )

    static let forest = Theme(
        id: "forest",
        name: "Forest",
        gradientColors: [Color(red: 0.07, green: 0.22, blue: 0.11), Color(red: 0.03, green: 0.09, blue: 0.04)],
        accentColor: Color(red: 0.45, green: 0.85, blue: 0.35),
        chartPalette: [.green, .mint, Color(red: 0.45, green: 0.85, blue: 0.35), .teal, .cyan],
        cardBackground: Color(white: 1.0, opacity: 0.08),
        sidebarBackground: Color(white: 0.0, opacity: 0.25)
    )

    static let sunset = Theme(
        id: "sunset",
        name: "Sunset",
        gradientColors: [Color(red: 0.55, green: 0.18, blue: 0.05), Color(red: 0.22, green: 0.07, blue: 0.12)],
        accentColor: Color(red: 1.0, green: 0.65, blue: 0.15),
        chartPalette: [.orange, .red, Color(red: 1.0, green: 0.65, blue: 0.15), .pink, .yellow],
        cardBackground: Color(white: 1.0, opacity: 0.08),
        sidebarBackground: Color(white: 0.0, opacity: 0.25)
    )

    static let rose = Theme(
        id: "rose",
        name: "Rose",
        gradientColors: [Color(red: 0.55, green: 0.08, blue: 0.22), Color(red: 0.22, green: 0.04, blue: 0.10)],
        accentColor: Color(red: 1.0, green: 0.45, blue: 0.65),
        chartPalette: [.pink, .red, Color(red: 1.0, green: 0.45, blue: 0.65), .purple, .orange],
        cardBackground: Color(white: 1.0, opacity: 0.08),
        sidebarBackground: Color(white: 0.0, opacity: 0.25)
    )
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
