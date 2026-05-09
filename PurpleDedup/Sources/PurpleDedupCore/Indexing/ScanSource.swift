import Foundation

/// One scan source: a folder the user wants us to look in. The `isLocked` flag mirrors
/// the requirement that some sources are scanned for comparison only — files inside a
/// locked source are eligible to participate in clusters but never marked for deletion.
public struct ScanSource: Sendable, Hashable {
    public let url: URL
    public let isLocked: Bool
    /// Optional whitelist of file basenames. When non-nil, the walker only
    /// emits files whose `lastPathComponent` is in this set. Used by the
    /// Photos library filter to cut the scan to a curated subset (specific
    /// albums, favorites, etc.). Nil means "no filter — walk everything."
    public let allowedBasenames: Set<String>?

    /// "Lookup only" mode: when true, this source contributes its content
    /// hashes to a reference index but DOES NOT participate in dedup
    /// clustering. Used so a `.photoslibrary` can serve as a "have I got
    /// this in Photos already?" oracle while the user dedups regular
    /// folders. Files in folder sources whose content hash matches a hash
    /// in the index get an "Also in your Photos library" badge in the
    /// comparison pane.
    ///
    /// Implication: a lookup source's files never appear in clusters, are
    /// never marked DELETE, and don't count toward the result's file
    /// total. The engine walks them and hashes them only.
    public let isLookupOnly: Bool

    public init(
        url: URL,
        isLocked: Bool? = nil,
        allowedBasenames: Set<String>? = nil,
        isLookupOnly: Bool = false
    ) {
        self.url = url
        // .photoslibrary bundles auto-lock by default. Photos.app owns the
        // file organisation inside; trashing files directly out of
        // `originals/` would leave Photos.app's database referencing missing
        // UUIDs and cause silent breakage. The dedup workflow surfaces the
        // duplicates in the UI; the user finalises in Photos.app's own
        // Duplicates view OR — when Phase 6.5 PhotoKit auth is granted —
        // the GUI un-locks them and routes deletions through the album
        // round-trip in `PhotoKitDeletionService`.
        if let isLocked = isLocked {
            self.isLocked = isLocked
        } else {
            self.isLocked = ScanSource.isPhotosLibrary(url: url)
        }
        self.allowedBasenames = allowedBasenames
        self.isLookupOnly = isLookupOnly
    }

    /// True when the source URL points at an Apple Photos library package
    /// (`.photoslibrary`). Used to drive the lock + Photos-aware walker path.
    public static func isPhotosLibrary(url: URL) -> Bool {
        url.pathExtension.lowercased() == "photoslibrary"
    }

    public var isPhotosLibrary: Bool { Self.isPhotosLibrary(url: url) }
}

/// File-type filtering. Phase 1 ships with the photo + video extension sets verbatim from
/// the requirements doc. The "all" case is for users who want to see everything (and is
/// handy for testing the engine on text fixtures).
public enum FileKind: String, Sendable, CaseIterable, Codable {
    case photo
    case video
    case all

    public static let photoExtensions: Set<String> = [
        // Standard
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp",
        // RAW
        "dng", "cr2", "cr3", "nef", "nrw", "arw", "orf", "raf", "rw2",
    ]

    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "wmv", "mpg", "mpeg", "webm", "3gp",
        "prores", "mxf",
    ]

    public func matches(extension ext: String) -> Bool {
        let lower = ext.lowercased()
        switch self {
        case .photo: return Self.photoExtensions.contains(lower)
        case .video: return Self.videoExtensions.contains(lower)
        case .all:   return true
        }
    }
}

/// All knobs that govern a scan. Bundled into one struct so `ScanEngine` has a single
/// argument and so we can persist scan sessions later.
public struct ScanOptions: Sendable {
    public var kinds: Set<FileKind>
    public var includeHidden: Bool
    public var minSizeBytes: Int64?
    public var maxSizeBytes: Int64?

    public init(
        kinds: Set<FileKind> = [.photo, .video],
        includeHidden: Bool = false,
        minSizeBytes: Int64? = nil,
        maxSizeBytes: Int64? = nil
    ) {
        self.kinds = kinds
        self.includeHidden = includeHidden
        self.minSizeBytes = minSizeBytes
        self.maxSizeBytes = maxSizeBytes
    }

    /// True if a file with the given extension and size should be considered. The
    /// `.all` kind short-circuits the extension check (used by tests).
    public func accepts(extension ext: String, sizeBytes: Int64) -> Bool {
        if let min = minSizeBytes, sizeBytes < min { return false }
        if let max = maxSizeBytes, sizeBytes > max { return false }
        if kinds.contains(.all) { return true }
        return kinds.contains { $0.matches(extension: ext) }
    }
}
