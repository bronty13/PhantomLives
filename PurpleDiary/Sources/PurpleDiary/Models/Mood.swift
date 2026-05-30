import Foundation
import SwiftUI

/// A 0–5 star mood rating attached to an entry. `unset` (0) renders as empty
/// stars and is excluded from mood statistics.
enum Mood: Int, Codable, CaseIterable, Hashable {
    case unset = 0
    case awful = 1
    case bad = 2
    case okay = 3
    case good = 4
    case great = 5

    var label: String {
        switch self {
        case .unset: return "No mood"
        case .awful: return "Awful"
        case .bad:   return "Bad"
        case .okay:  return "Okay"
        case .good:  return "Good"
        case .great: return "Great"
        }
    }

    /// SF Symbol for the single-glyph mood face used in compact rows.
    var systemImage: String {
        switch self {
        case .unset: return "circle.dashed"
        case .awful: return "cloud.bolt.rain.fill"
        case .bad:   return "cloud.rain.fill"
        case .okay:  return "cloud.fill"
        case .good:  return "sun.max.fill"
        case .great: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .unset: return .secondary
        case .awful: return .purple
        case .bad:   return .blue
        case .okay:  return .gray
        case .good:  return .orange
        case .great: return .yellow
        }
    }

    /// Number of filled stars (0...5) — drives the star row in the editor.
    var filledStars: Int { rawValue }
}
