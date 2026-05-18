import Foundation

/// Optional List-view columns the user can toggle via the column
/// menu. The mandatory columns (Name / Codec / Resolution / FPS /
/// Duration / Size) are always shown; everything here is opt-in.
enum ListColumn: String, CaseIterable, Identifiable {
    case rating
    case modified
    case title
    case description
    case reel
    case scene
    case shot
    case take
    case angle
    case camera

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rating:      return "Rating"
        case .modified:    return "Date Modified"
        case .title:       return "Title"
        case .description: return "Description"
        case .reel:        return "Reel"
        case .scene:       return "Scene"
        case .shot:        return "Shot"
        case .take:        return "Take"
        case .angle:       return "Angle"
        case .camera:      return "Camera"
        }
    }

    /// Default preferred width per column.
    var idealWidth: CGFloat {
        switch self {
        case .rating:                  return 70
        case .modified:                return 130
        case .title, .description:     return 180
        default:                       return 80
        }
    }
}
