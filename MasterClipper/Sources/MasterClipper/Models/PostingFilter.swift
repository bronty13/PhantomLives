import Foundation

/// Posting-completeness filter shared between the Dashboard (which sets it as
/// a navigation hint) and the Clips list (which reads + clears it on appear).
enum PostingFilter: String, Hashable, CaseIterable {
    case all
    case fullyPosted
    case partial
    case notPosted
    case noScope

    var label: String {
        switch self {
        case .all:         return "All"
        case .fullyPosted: return "Fully posted"
        case .partial:     return "Partial"
        case .notPosted:   return "Not posted"
        case .noScope:     return "No site scope"
        }
    }
}
