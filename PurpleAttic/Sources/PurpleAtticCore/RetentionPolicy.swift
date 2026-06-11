import Foundation

/// A single photo/video as far as the retention decision is concerned. Deliberately
/// minimal and value-typed so the purge predicate is pure and exhaustively testable
/// without a live Photos library. The GUI/PhotoKit layer maps `PHAsset` → `PhotoAsset`;
/// osxphotos JSON maps its records → `PhotoAsset`.
public struct PhotoAsset: Sendable, Equatable {
    public let uuid: String
    public let created: Date
    public let isFavorite: Bool
    public let albums: [String]
    public let keywords: [String]

    public init(
        uuid: String,
        created: Date,
        isFavorite: Bool = false,
        albums: [String] = [],
        keywords: [String] = []
    ) {
        self.uuid = uuid
        self.created = created
        self.isFavorite = isFavorite
        self.albums = albums
        self.keywords = keywords
    }
}

/// Decides which photos may be removed from the live Photos library after they have been
/// safely archived. This is the single highest-stakes piece of logic in PurpleAttic — a
/// false "eligible" verdict can delete a photo that should have been kept — so it is kept
/// pure, defaulted conservatively, and covered by unit tests.
///
/// A photo is **purge-eligible** only when BOTH hold:
///   1. it is OLDER than `keepWindowDays` (default 365), AND
///   2. it is NOT flagged to keep — i.e. not in a "Save" album, not tagged a "save"
///      keyword, and (optionally) not a Favorite.
///
/// Anything else is kept. The default is intentionally additive: when in doubt, keep.
public struct RetentionPolicy: Codable, Sendable, Equatable {
    /// Photos created within this many days of "now" are always kept, regardless of tags.
    public var keepWindowDays: Int
    /// Album names whose membership pins a photo (case- and whitespace-insensitive match).
    public var keepAlbumNames: [String]
    /// Keywords that pin a photo (case- and whitespace-insensitive match).
    public var keepKeywords: [String]
    /// When true, a Favorite is also pinned. Off by default so "Favorite" isn't overloaded
    /// with "never archive-and-delete" unless the user opts in.
    public var keepFavorites: Bool

    public init(
        keepWindowDays: Int = 365,
        keepAlbumNames: [String] = ["Save"],
        keepKeywords: [String] = ["save"],
        keepFavorites: Bool = false
    ) {
        self.keepWindowDays = keepWindowDays
        self.keepAlbumNames = keepAlbumNames
        self.keepKeywords = keepKeywords
        self.keepFavorites = keepFavorites
    }

    /// Normalize a tag for matching so it is **case- and whitespace-insensitive**: "Save",
    /// "save", "SAVE", " SaVe " all compare equal. Applied to BOTH the keep-list and the asset's
    /// own album/keyword names, so a match never hinges on how either side was capitalized or on
    /// stray spaces (e.g. a hand-edited `profile.json` or a keyword typed with a leading space).
    static func normalizeTag(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when the asset is pinned by a Save album, Save keyword, or (if enabled) Favorite.
    public func isPinned(_ asset: PhotoAsset) -> Bool {
        if keepFavorites && asset.isFavorite { return true }
        let albumSet = Set(keepAlbumNames.map(Self.normalizeTag))
        if !albumSet.isEmpty && asset.albums.contains(where: { albumSet.contains(Self.normalizeTag($0)) }) {
            return true
        }
        let keywordSet = Set(keepKeywords.map(Self.normalizeTag))
        if !keywordSet.isEmpty && asset.keywords.contains(where: { keywordSet.contains(Self.normalizeTag($0)) }) {
            return true
        }
        return false
    }

    /// True when the asset is recent enough to keep regardless of pinning.
    public func isWithinKeepWindow(_ asset: PhotoAsset, asOf now: Date) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -keepWindowDays, to: now) else {
            // If we somehow can't compute the cutoff, fail safe: treat as within-window (keep).
            return true
        }
        return asset.created >= cutoff
    }

    /// The one decision that gates deletion. Returns true ONLY when the asset is both aged
    /// out of the keep window AND not pinned. Conservative by construction.
    public func isPurgeEligible(_ asset: PhotoAsset, asOf now: Date) -> Bool {
        if isWithinKeepWindow(asset, asOf: now) { return false }
        if isPinned(asset) { return false }
        return true
    }

    /// Human-readable reason a given asset is kept (nil when it is purge-eligible). Used by
    /// the dry-run preview and the detailed log so every retained/dropped item is explained.
    public func keepReason(_ asset: PhotoAsset, asOf now: Date) -> String? {
        if isWithinKeepWindow(asset, asOf: now) {
            return "within \(keepWindowDays)-day keep window"
        }
        if keepFavorites && asset.isFavorite { return "favorite" }
        let albumSet = Set(keepAlbumNames.map(Self.normalizeTag))
        if let hit = asset.albums.first(where: { albumSet.contains(Self.normalizeTag($0)) }) {
            return "in keep album \"\(hit)\""
        }
        let keywordSet = Set(keepKeywords.map(Self.normalizeTag))
        if let hit = asset.keywords.first(where: { keywordSet.contains(Self.normalizeTag($0)) }) {
            return "has keep keyword \"\(hit)\""
        }
        return nil
    }
}
