import Foundation
import SwiftUI

/// Fixed priority lifecycle for Matters. The raw value is what gets stored
/// in `matter.priority`; surfaced prominently in the detail header and on
/// the list row. Not user-renamable — this is a deliberate fixed set so
/// reports across Matters stay comparable.
enum MatterPriority: String, CaseIterable, Identifiable {
    case p1Critical = "P1 Critical"
    case p2High     = "P2 High"
    case p3Medium   = "P3 Medium"
    case p4Low      = "P4 Low"
    case p5TechDebt = "P5 Tech Debt"

    var id: String { rawValue }

    /// Default priority for new Matters.
    static let defaultPriority: MatterPriority = .p3Medium

    /// Short tag (P1..P5) used on dense list rows.
    var shortTag: String {
        switch self {
        case .p1Critical: return "P1"
        case .p2High:     return "P2"
        case .p3Medium:   return "P3"
        case .p4Low:      return "P4"
        case .p5TechDebt: return "P5"
        }
    }

    /// Color shown for the priority pill / list badge.
    var colorHex: String {
        switch self {
        case .p1Critical: return "#EF4444"   // red
        case .p2High:     return "#F97316"   // orange
        case .p3Medium:   return "#F59E0B"   // amber
        case .p4Low:      return "#22C55E"   // green
        case .p5TechDebt: return "#6B7280"   // slate
        }
    }

    var color: Color { Color(hex: colorHex) ?? .gray }

    /// Tolerant parse — falls back to default if the stored string doesn't
    /// match (e.g. legacy data, or a future we'd rather not crash through).
    static func parse(_ raw: String) -> MatterPriority {
        MatterPriority(rawValue: raw) ?? .defaultPriority
    }
}
