import Foundation

/// Optional List-view columns the user can toggle via the column
/// menu. The mandatory columns (Name / Codec / Resolution / FPS /
/// Duration / Size) are always shown; everything here is opt-in.
enum ListColumn: String, CaseIterable, Identifiable {
    case rating
    case modified
    case created
    case recorded
    case displaySize
    case aspectRatio
    case title
    case description
    case reel
    case scene
    case shot
    case take
    case angle
    case camera
    /// Kyno-parity row 68. Renders a downsampled per-clip audio
    /// waveform inline so the user can spot dialog vs music vs
    /// silent footage without opening each clip. Cached to disk
    /// per (path, modtime).
    case waveform

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rating:       return "Rating"
        case .modified:     return "Date Modified"
        case .created:      return "Date Created"
        case .recorded:     return "Date Recorded"
        case .displaySize:  return "Display Size"
        case .aspectRatio:  return "Aspect Ratio"
        case .title:        return "Title"
        case .description:  return "Description"
        case .reel:         return "Reel"
        case .scene:        return "Scene"
        case .shot:         return "Shot"
        case .take:         return "Take"
        case .angle:        return "Angle"
        case .camera:       return "Camera"
        case .waveform:     return "Waveform"
        }
    }

    /// Default preferred width per column.
    var idealWidth: CGFloat {
        switch self {
        case .rating:                                return 70
        case .modified, .created, .recorded:         return 130
        case .displaySize:                           return 100
        case .aspectRatio:                           return 80
        case .title, .description:                   return 180
        case .waveform:                              return 160
        default:                                     return 80
        }
    }
}
