import Foundation
import SwiftUI

/// Per-element font customization. Stored as a dictionary keyed by
/// `FontSlot.rawValue` on `AppSettings.fontSlots`. Empty / missing entries
/// fall back to the slot's default in `AppState.font(for:)`.
struct FontStyle: Codable, Hashable {
    /// Either a built-in token (`"system"`, `"system-mono"`,
    /// `"system-serif"`) or a PostScript font name. Empty == system.
    var family: String
    var size: Double
    /// Stored as a string so adding new weights doesn't break old DBs.
    /// Accepted values: regular / medium / semibold / bold / heavy.
    var weight: String

    init(family: String = "system", size: Double = 13, weight: String = "regular") {
        self.family = family
        self.size = size
        self.weight = weight
    }

    var swiftUIWeight: Font.Weight {
        switch weight {
        case "medium":   return .medium
        case "semibold": return .semibold
        case "bold":     return .bold
        case "heavy":    return .heavy
        default:         return .regular
        }
    }

    /// Materialize as a SwiftUI `Font`. Falls back to system for unknown
    /// PostScript names rather than crashing.
    func swiftUIFont() -> Font {
        switch family {
        case "system", "":
            return .system(size: size, weight: swiftUIWeight)
        case "system-mono":
            return .system(size: size, weight: swiftUIWeight, design: .monospaced)
        case "system-serif":
            return .system(size: size, weight: swiftUIWeight, design: .serif)
        case "system-rounded":
            return .system(size: size, weight: swiftUIWeight, design: .rounded)
        default:
            return .custom(family, size: size).weight(swiftUIWeight)
        }
    }
}

/// Named font slots used throughout the timeline UI.
enum FontSlot: String, CaseIterable, Hashable {
    case eventTitle
    case eventBody
    case eventDate
    case sidebar

    var label: String {
        switch self {
        case .eventTitle: return "Event title"
        case .eventBody:  return "Event body"
        case .eventDate:  return "Date column"
        case .sidebar:    return "Sidebar"
        }
    }

    var defaultStyle: FontStyle {
        switch self {
        case .eventTitle: return FontStyle(family: "system",         size: 14, weight: "semibold")
        case .eventBody:  return FontStyle(family: "system",         size: 12, weight: "regular")
        case .eventDate:  return FontStyle(family: "system-rounded", size: 14, weight: "semibold")
        case .sidebar:    return FontStyle(family: "system",         size: 13, weight: "regular")
        }
    }
}
