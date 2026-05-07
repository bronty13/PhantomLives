import Foundation
import SwiftUI

enum CaseStatus: String, Codable, CaseIterable, Hashable {
    case active
    case cold
    case closed

    var label: String {
        switch self {
        case .active: return "Active"
        case .cold:   return "Cold"
        case .closed: return "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "flame.fill"
        case .cold:   return "snowflake"
        case .closed: return "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active: return .red
        case .cold:   return .blue
        case .closed: return .secondary
        }
    }
}

enum Importance: String, Codable, CaseIterable, Hashable {
    case low
    case medium
    case high
    case critical

    var label: String {
        switch self {
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }

    /// Pip count for the timeline list (4 dots maximum, filled by importance).
    var filledPips: Int {
        switch self {
        case .low:      return 1
        case .medium:   return 2
        case .high:     return 3
        case .critical: return 4
        }
    }

    var tint: Color {
        switch self {
        case .low:      return .secondary
        case .medium:   return .blue
        case .high:     return .orange
        case .critical: return .red
        }
    }

    var sortOrder: Int { filledPips }
}

enum PersonRole: String, Codable, CaseIterable, Hashable {
    case suspect
    case victim
    case witness
    case attorney
    case detective
    case other

    var label: String {
        switch self {
        case .suspect:   return "Suspect"
        case .victim:    return "Victim"
        case .witness:   return "Witness"
        case .attorney:  return "Attorney"
        case .detective: return "Detective"
        case .other:     return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .suspect:   return "person.fill.questionmark"
        case .victim:    return "heart.slash.fill"
        case .witness:   return "eye.fill"
        case .attorney:  return "scalemass.fill"
        case .detective: return "magnifyingglass"
        case .other:     return "person.fill"
        }
    }

    /// Default chip color (user can override per role in Settings → People Roles).
    var defaultColorHex: String {
        switch self {
        case .suspect:   return "#D14B5C"
        case .victim:    return "#9D4DCC"
        case .witness:   return "#3FA9F5"
        case .attorney:  return "#E8A93B"
        case .detective: return "#3FB950"
        case .other:     return "#888888"
        }
    }
}
