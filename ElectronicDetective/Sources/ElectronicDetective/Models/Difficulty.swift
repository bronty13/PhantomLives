import Foundation

/// The three skill settings. Raw value is the number of private questions
/// permitted per turn — 1 (hardest) → 3 (easiest).
enum Difficulty: Int, Codable, CaseIterable, Hashable, Sendable {
    case masterDetective = 1
    case sleuth          = 2
    case gumshoe         = 3

    var privateQuestionsPerTurn: Int { rawValue }

    var displayName: String {
        switch self {
        case .masterDetective: return "Master Detective"
        case .sleuth:          return "Sleuth"
        case .gumshoe:         return "Gumshoe"
        }
    }
}
