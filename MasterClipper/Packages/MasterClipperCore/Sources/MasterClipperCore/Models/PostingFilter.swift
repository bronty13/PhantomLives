import Foundation

public enum PostingFilter: String, Hashable, CaseIterable {
    case all
    case fullyPosted
    case partial
    case notPosted
    case noScope

    public var label: String {
        switch self {
        case .all:         return "All"
        case .fullyPosted: return "Fully posted"
        case .partial:     return "Partial"
        case .notPosted:   return "Not posted"
        case .noScope:     return "No site scope"
        }
    }
}
