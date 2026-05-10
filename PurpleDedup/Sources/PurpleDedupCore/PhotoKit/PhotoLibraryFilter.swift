import Foundation

/// Per-Photos-library scan filter. Applied at scan time — `PhotoKitDeletionService`
/// resolves the filter against the library and returns the set of matching
/// asset basenames, which `FileWalker` then uses as a whitelist when traversing
/// `originals/`. Files outside the filter never enter the scan pipeline, so
/// hashing / clustering / metadata extraction all skip them entirely.
///
/// All fields are independently optional. `nil` for a constraint means "no
/// constraint on this dimension." Combining constraints AND-style: a file
/// must satisfy every active constraint to pass.
public struct PhotoLibraryFilter: Sendable, Hashable, Codable {

    /// When non-nil, only include assets that belong to at least one of these
    /// albums (by name). Album titles match Photos.app's own listing — what
    /// you see in `My Albums` is what you write here.
    public var albumNames: Set<String>?

    /// When non-nil, only include assets where Photos has detected a face
    /// matching at least one of these named people. Names match the
    /// "Add Name" labels in Photos → People.
    ///
    /// Resolved by reading `<library>/database/Photos.sqlite` directly
    /// (PhotoKit's `smartAlbumPeople` is iOS-only). Same TCC grant that
    /// lets us walk `originals/` opens this file read-only, so no extra
    /// permission prompt is required. People without an "Add Name"
    /// label aren't selectable — Photos exposes them as "Person 1" /
    /// "Person 2" placeholders that wouldn't be useful as filter axes.
    public var personNames: Set<String>?

    /// When non-nil, only include assets whose `mediaSubtypes` contain at
    /// least one of these strings. Strings match the canonical
    /// `PhotoKitDeletionService.subtypeNames` output: "Live Photo", "HDR",
    /// "Panorama", "Screenshot", "Streamed Video", "High Frame Rate",
    /// "Time-lapse".
    public var includedSubtypes: Set<String>?

    /// When true, only include assets where `PHAsset.isFavorite == true`
    /// (the heart in Photos.app).
    public var requireFavorite: Bool

    /// When true, hidden assets are included alongside non-hidden ones.
    /// Default false — matches Photos.app's main Library view, which
    /// excludes them. Mutually exclusive with `onlyHidden` (which wins).
    public var includeHidden: Bool

    /// When true, ONLY hidden assets are scanned — non-hidden assets are
    /// skipped. Lets the user dedup the Hidden album in isolation.
    public var onlyHidden: Bool

    public init(
        albumNames: Set<String>? = nil,
        personNames: Set<String>? = nil,
        includedSubtypes: Set<String>? = nil,
        requireFavorite: Bool = false,
        includeHidden: Bool = false,
        onlyHidden: Bool = false
    ) {
        self.albumNames = albumNames
        self.personNames = personNames
        self.includedSubtypes = includedSubtypes
        self.requireFavorite = requireFavorite
        self.includeHidden = includeHidden
        self.onlyHidden = onlyHidden
    }

    /// Decode tolerantly so adding fields (like `onlyHidden`) doesn't
    /// invalidate older saved filters. Missing fields fall back to the
    /// memberwise defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.albumNames = try c.decodeIfPresent(Set<String>.self, forKey: .albumNames)
        self.personNames = try c.decodeIfPresent(Set<String>.self, forKey: .personNames)
        self.includedSubtypes = try c.decodeIfPresent(Set<String>.self, forKey: .includedSubtypes)
        self.requireFavorite = try c.decodeIfPresent(Bool.self, forKey: .requireFavorite) ?? false
        self.includeHidden = try c.decodeIfPresent(Bool.self, forKey: .includeHidden) ?? false
        self.onlyHidden = try c.decodeIfPresent(Bool.self, forKey: .onlyHidden) ?? false
    }

    /// True when the filter actually constrains anything. Sources with an
    /// inactive filter take the unconstrained walk path — saves a PhotoKit
    /// fetch round-trip on every scan.
    public var isActive: Bool {
        albumNames != nil || personNames != nil || includedSubtypes != nil
            || requireFavorite || includeHidden || onlyHidden
    }

    /// Short human-readable summary for the sources strip ("Photos albums:
    /// Family · Favorites · Live Photo only"). Empty string when inactive.
    public var summary: String {
        var bits: [String] = []
        if let albums = albumNames, !albums.isEmpty {
            bits.append("albums: \(albums.sorted().joined(separator: ", "))")
        }
        if let people = personNames, !people.isEmpty {
            bits.append("people: \(people.sorted().joined(separator: ", "))")
        }
        if let subs = includedSubtypes, !subs.isEmpty {
            bits.append("subtypes: \(subs.sorted().joined(separator: ", "))")
        }
        if requireFavorite { bits.append("favorites only") }
        if onlyHidden { bits.append("hidden only") }
        else if includeHidden { bits.append("incl. hidden") }
        return bits.joined(separator: " · ")
    }
}
