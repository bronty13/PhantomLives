import Foundation
import SwiftUI

/// User-authored theme record. Each user theme is keyed by UUID so renames
/// don't break the active-theme lookup (we store the UUID string in
/// `AppSettings.themeName`).
struct UserTheme: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Name of the built-in theme this was cloned from. Empty for blank
    /// builds.
    var basedOn: String
    var gradientTopHex: String
    var gradientBottomHex: String
    var accentHex: String
    var cardBgHex: String
    var sidebarBgHex: String
    var trackColorHex: String
    var createdAt: Date
    var updatedAt: Date

    static func newDraft(basedOn base: Theme, name: String) -> UserTheme {
        UserTheme(
            id: UUID(),
            name: name,
            basedOn: base.name,
            gradientTopHex: base.gradientColors.first?.toHex() ?? "#0F1730",
            gradientBottomHex: base.gradientColors.last?.toHex() ?? "#1A253F",
            accentHex: base.accentColor.toHex() ?? "#3B82F6",
            cardBgHex: base.cardBackground.toHex() ?? "#1F2A44",
            sidebarBgHex: base.sidebarBackground.toHex() ?? "#0F1730",
            trackColorHex: base.timelineTrackColor.toHex() ?? "#94A3B8",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Materialize this user theme into a `Theme` for use throughout the
    /// rest of the UI. The `id` is `user:<uuid>` so it never collides with
    /// the built-in `id`s.
    func asTheme() -> Theme {
        Theme(
            id: "user:\(id.uuidString)",
            name: name,
            gradientColors: [
                Color(hex: gradientTopHex) ?? .black,
                Color(hex: gradientBottomHex) ?? .black,
            ],
            accentColor: Color(hex: accentHex) ?? .blue,
            cardBackground: Color(hex: cardBgHex) ?? .gray,
            sidebarBackground: Color(hex: sidebarBgHex) ?? .gray,
            timelineTrackColor: Color(hex: trackColorHex) ?? .gray
        )
    }
}
