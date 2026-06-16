import Foundation

/// Top-level UI mode. Folder browse shows the tree + grid + detail panel; Preview walks
/// items one-by-one with a large viewer + EXIF panel.
enum AppMode: String, Codable, CaseIterable, Identifiable {
    case folderBrowse
    case preview

    var id: String { rawValue }
    var label: String {
        switch self {
        case .folderBrowse: return "Browse"
        case .preview:      return "Preview"
        }
    }
}

/// Window appearance preference. `.system` defers to macOS.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }
    var label: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
}

/// A lens over decision state, used to filter the grid and the Preview queue — including
/// reviewing items you've already decided.
enum DecisionFilter: String, CaseIterable, Identifiable {
    case all
    case undecided
    case decided
    case kept
    case skipped

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "All"
        case .undecided: return "Undecided"
        case .decided:   return "Decided"
        case .kept:      return "Kept"
        case .skipped:   return "Skipped"
        }
    }

    func matches(_ file: MediaFile) -> Bool {
        switch self {
        case .all:       return true
        case .undecided: return file.keep == nil
        case .decided:   return file.keep != nil
        case .kept:      return file.keepDecision == true
        case .skipped:   return file.keepDecision == false
        }
    }
}

/// The three media kinds PurplePeek discovers. Stored as the raw string in the
/// `media_files.file_type` column.
enum MediaType: String, Codable, CaseIterable, Identifiable {
    case photo
    case video
    case audio

    var id: String { rawValue }
    var label: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }

    /// Audio cannot enter the Photos library (Photos holds images + videos only); it is
    /// keep-exported to a folder instead. This flag gates every import code path.
    var isImportableToPhotos: Bool { self != .audio }
}
