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
