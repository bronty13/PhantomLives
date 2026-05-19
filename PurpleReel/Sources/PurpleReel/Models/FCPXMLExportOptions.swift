import Foundation

/// Options collected by `FCPXMLExportSheet` (Kyno-parity, Image #88).
/// Threaded through to `FCPXMLWriter.makeXML(...)` so the same writer
/// can honor different keyword/favorite filtering choices per export.
struct FCPXMLExportOptions: Equatable, Hashable {

    // MARK: - Library / event

    /// Custom event name; the dialog defaults this to the stock
    /// PurpleReel Library / asset-name string, the user can edit it.
    var eventName: String

    /// File-reference style:
    /// - `.copyToLibrary` writes the FCPXML and expects FCP to copy
    ///   the source files into the library on import.
    /// - `.leaveInPlace` references the source paths so FCP edits
    ///   the originals.
    var fileReference: FileReference = .copyToLibrary

    enum FileReference: String, Codable, CaseIterable {
        case copyToLibrary
        case leaveInPlace
        var displayName: String {
            switch self {
            case .copyToLibrary: return "Copy to library"
            case .leaveInPlace:  return "Leave files in place"
            }
        }
    }

    /// Emit `<media-rep>` URLs as paths relative to the FCPXML
    /// file's directory rather than absolute. Required when the
    /// FCPXML + media will be moved together (e.g. handing off a
    /// `.fcpxml` to a colleague along with the source folder).
    var useRelativePaths: Bool = false

    /// After writing the file, hand it to Final Cut Pro via
    /// `NSWorkspace.open`. Equivalent to the legacy `openInFCP`
    /// parameter on `AppState.exportFCPXML(scope:openInFCP:)`.
    var openExportedFile: Bool = true

    // MARK: - Metadata mapping

    /// Sources of FCP "keyword" annotations. Kyno style — the user
    /// picks which catalog inputs map onto FCP keywords. PurpleReel's
    /// tag system is the canonical match; subclip names + folder
    /// path components are optional secondary sources.
    var keywordsFromTags: Bool = true
    var keywordsFromSubclips: Bool = false
    var keywordsFromFolders: Bool = false

    /// When `keywordsFromFolders` is on, picks which path components
    /// become keywords. "Only containing folder" emits just the
    /// asset's parent dir name; "All parent folders" walks every
    /// ancestor up to the workspace root.
    var folderKeywordScope: FolderKeywordScope = .containingFolder

    enum FolderKeywordScope: String, Codable, CaseIterable {
        case containingFolder
        case allParents
        var displayName: String {
            switch self {
            case .containingFolder: return "Only containing folder"
            case .allParents:       return "All parent folders"
            }
        }
    }

    /// Sources of FCP "favorite" range annotations. Marks a clip's
    /// in/out range — or the whole clip — as Favorited in FCP's
    /// browser so the editor can filter to picks fast.
    var favoritesFromSubclips: Bool = false
    var favoritesFromInOutPoints: Bool = false
    var favoritesFromRating: Bool = true
    /// Minimum star count when `favoritesFromRating` is on. Kyno's
    /// "At least: ★…" picker maps onto this; default to 1 (any rated
    /// clip is a Favorite).
    var favoritesMinStars: Int = 1
    /// C38 — destination folder for the resulting `.fcpxml` file.
    /// nil = fall back to the legacy `~/Downloads/PurpleReel/exports/`
    /// path the writer used pre-C38. Non-nil records the user's
    /// chosen folder; AppState pushes it onto
    /// `RecentDestinations.Scope.fcpxml` after a successful write.
    var outputDir: URL? = nil
}

extension FCPXMLExportOptions {
    /// Sensible starting point — matches Kyno's defaults from
    /// Image #88: Copy to library, no relative paths, Open after
    /// export, Keywords from tags, Favorites from rating ≥ 1 star.
    static let defaults = FCPXMLExportOptions(eventName: "")
}
