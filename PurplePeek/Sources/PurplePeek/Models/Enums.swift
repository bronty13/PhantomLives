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

/// The toolbar "Date" lens: narrow Browse and Preview to items whose file-modified date falls
/// within a recent window. `.all` (default) applies no cutoff. Applied in
/// `AppState.recomputeDerived()` alongside the decision + tagged lenses, so it combines with
/// both and drives the grid and the Preview queue identically.
enum DateFilter: String, CaseIterable, Identifiable {
    case all, h1, h2, h4, h8, d1, d2, d3, d7, w2, m1

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Dates"
        case .h1:  return "Last Hour"
        case .h2:  return "Last 2 Hours"
        case .h4:  return "Last 4 Hours"
        case .h8:  return "Last 8 Hours"
        case .d1:  return "Last Day"
        case .d2:  return "Last 2 Days"
        case .d3:  return "Last 3 Days"
        case .d7:  return "Last 7 Days"
        case .w2:  return "Last 2 Weeks"
        case .m1:  return "Last Month"
        }
    }

    /// Window length in seconds; nil = no filtering. A month is 30 days (calendar-agnostic —
    /// this is a review lens, not an accounting period).
    var maxAge: TimeInterval? {
        switch self {
        case .all: return nil
        case .h1:  return 3_600
        case .h2:  return 2 * 3_600
        case .h4:  return 4 * 3_600
        case .h8:  return 8 * 3_600
        case .d1:  return 86_400
        case .d2:  return 2 * 86_400
        case .d3:  return 3 * 86_400
        case .d7:  return 7 * 86_400
        case .w2:  return 14 * 86_400
        case .m1:  return 30 * 86_400
        }
    }

    /// The earliest modified date that passes this filter, or nil for `.all`.
    func cutoff(now: Date = Date()) -> Date? {
        maxAge.map { now.addingTimeInterval(-$0) }
    }
}
