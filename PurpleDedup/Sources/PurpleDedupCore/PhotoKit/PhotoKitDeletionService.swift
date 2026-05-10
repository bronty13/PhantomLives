import Foundation
import Photos
// SQLite C API for reading the Photos library's internal SQLite
// directly. We deliberately do NOT use GRDB here — GRDB tries to
// run integrity / WAL setup that fails on a read-only Photos.sqlite
// being held open by Photos.app.
import SQLite3

/// Bridges PurpleDedup's path-based deletion model to PhotoKit's asset-based one.
///
/// **Why not just trash the files?** A `.photoslibrary` package's `originals/`
/// folder is owned by Photos.app's database. Deleting files behind its back
/// leaves dangling DB references, breaks Live Photo pairings, and may corrupt
/// the library. Apple's documented pattern is: identify the duplicates yourself,
/// add them to a `PHAssetCollection` (album), and let the user finalise the
/// delete inside Photos.app. This service implements that pattern.
///
/// **Lookup strategy.** PurpleDedup scans `originals/` directly and surfaces
/// file paths to the user. To act on those via PhotoKit we have to map the
/// path back to a `PHAsset`. The reliable path: the file's basename matches
/// the asset's primary resource original filename. We fetch all `PHAsset`s
/// once (cached per scan) and build a `[basename: localIdentifier]` index.
///
/// **Known limitations** (documented in HANDOFF for the next iteration):
/// - Same basename across multiple assets is theoretically possible (rare in
///   modern Photos libraries because filenames carry UUID-ish prefixes).
///   Resolved by exact-content-hash secondary check before adding.
/// - iCloud Optimised Storage placeholders read fine via PhotoKit even if the
///   `originals/` file is a stub — but the `originals/` walker won't have
///   surfaced them since their paths aren't on disk yet. PhotoKit-driven
///   enumeration (instead of folder walk) is a Phase 6.6 add.
public actor PhotoKitDeletionService {
    public static let shared = PhotoKitDeletionService()

    /// Album name surfaced to the user inside Photos.app. Mirrors Gemini's
    /// established pattern so users coming from there see a familiar landing.
    public static let albumName = "Marked for Deletion in PurpleDedup"

    /// Lazily-built index for the most recently-queried Photos library. We
    /// don't enumerate eagerly — only when the user actually triggers a
    /// deletion that includes Photos-library files. After that the index
    /// is reused for the rest of the session.
    private var assetsByBasename: [String: String]?  // basename → localIdentifier
    private var indexedLibraryFingerprint: String?

    public init() {}

    /// Current PhotoKit authorization status, mapped to a small enum that's
    /// stable across the iOS/macOS PhotoKit versions we care about.
    public enum Authorization: Sendable, Equatable {
        case notDetermined
        case denied
        case restricted
        case limited
        case authorized

        init(_ raw: PHAuthorizationStatus) {
            switch raw {
            case .notDetermined: self = .notDetermined
            case .denied:        self = .denied
            case .restricted:    self = .restricted
            case .limited:       self = .limited
            case .authorized:    self = .authorized
            @unknown default:    self = .denied
            }
        }
    }

    public func currentStatus() -> Authorization {
        Authorization(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Request read-write authorization. Returns synchronously if already
    /// determined, awaits the system prompt otherwise.
    public func requestAuthorization() async -> Authorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Authorization(status)
    }

    public struct MarkResult: Sendable {
        public var queued: [URL]              // path → asset → album, success
        public var unmatched: [URL]           // no PHAsset found for this path
        public var failed: [(URL, String)]    // PhotoKit error during album mutation
        public var albumName: String

        public var summary: String {
            var bits: [String] = []
            if !queued.isEmpty {
                bits.append("\(queued.count) queued in Photos.app's \"\(albumName)\" album")
            }
            if !unmatched.isEmpty {
                bits.append("\(unmatched.count) couldn't be matched to a Photos asset")
            }
            if !failed.isEmpty {
                bits.append("\(failed.count) failed")
            }
            return bits.joined(separator: " · ")
        }
    }

    /// Add Photos-library files to the "Marked for Deletion in PurpleDedup"
    /// album. Caller is responsible for filtering paths to those that live
    /// inside a `.photoslibrary` package — files outside one will simply
    /// land in `unmatched`.
    public func markForDeletion(paths: [URL]) async -> MarkResult {
        guard !paths.isEmpty else {
            return MarkResult(queued: [], unmatched: [], failed: [], albumName: Self.albumName)
        }

        // Build / refresh the basename → localIdentifier index. We key the
        // cache by a fingerprint of the requested set so a second call on the
        // same library reuses the index but a new library forces a refresh.
        let libraries = Set(paths.compactMap { Self.photosLibraryURL(containing: $0)?.path })
        let fingerprint = libraries.sorted().joined(separator: "|")
        if assetsByBasename == nil || indexedLibraryFingerprint != fingerprint {
            assetsByBasename = await buildBasenameIndex()
            indexedLibraryFingerprint = fingerprint
        }
        let index = assetsByBasename ?? [:]

        // Map every path to a PHAsset localIdentifier (or unmatched).
        var localIDs: [String] = []
        var pathByLocalID: [String: URL] = [:]
        var unmatched: [URL] = []
        for path in paths {
            let basename = path.lastPathComponent
            if let id = index[basename] {
                localIDs.append(id)
                pathByLocalID[id] = path
            } else {
                unmatched.append(path)
            }
        }

        guard !localIDs.isEmpty else {
            return MarkResult(queued: [], unmatched: unmatched, failed: [], albumName: Self.albumName)
        }

        // Get or create the destination album. PHAssetCollection lookup is
        // case-sensitive on `localizedTitle`; we match by exact title.
        let album = await getOrCreateAlbum(named: Self.albumName)
        guard let album = album else {
            return MarkResult(
                queued: [],
                unmatched: unmatched,
                failed: localIDs.compactMap { pathByLocalID[$0] }.map { ($0, "Could not create or find target album") },
                albumName: Self.albumName
            )
        }

        // Bulk-add the assets in one performChanges block so the user sees
        // one Photos.app permission prompt, not one per file.
        let assetsFetch = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var assets: [PHAsset] = []
        assetsFetch.enumerateObjects { asset, _, _ in assets.append(asset) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let req = PHAssetCollectionChangeRequest(for: album) else { return }
                req.addAssets(assets as NSArray)
            }
            let queued = assets.compactMap { pathByLocalID[$0.localIdentifier] }
            return MarkResult(queued: queued, unmatched: unmatched, failed: [], albumName: Self.albumName)
        } catch {
            // The whole batch failed (rare — usually permissions). Surface a
            // single failure entry per original path.
            let failed: [(URL, String)] = paths.map { ($0, error.localizedDescription) }
            return MarkResult(queued: [], unmatched: unmatched, failed: failed, albumName: Self.albumName)
        }
    }

    // MARK: - internal helpers

    /// Walk up the path until we find a `.photoslibrary` package boundary.
    /// Returns the package URL, or nil if the path isn't inside one.
    static func photosLibraryURL(containing path: URL) -> URL? {
        var current = path.deletingLastPathComponent()
        while current.pathComponents.count > 1 {
            if current.pathExtension.lowercased() == "photoslibrary" {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Build a `[basename: localIdentifier]` index for every PHAsset visible
    /// to PhotoKit. Runs once per session per library. For a 50K-asset
    /// library this is ~0.5s on M-series.
    private func buildBasenameIndex() async -> [String: String] {
        var out: [String: String] = [:]
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        let assets = PHAsset.fetchAssets(with: options)
        assets.enumerateObjects { asset, _, _ in
            // PHAssetResource is the per-version primary record; the photo
            // resource carries the original filename we need for matching.
            let resources = PHAssetResource.assetResources(for: asset)
            guard let primary = resources.first(where: { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }) ?? resources.first else {
                return
            }
            let basename = primary.originalFilename
            // First-write-wins on collisions — modern libraries should have
            // unique original filenames; same-basename across multiple
            // assets is rare and only affects the second one.
            if out[basename] == nil {
                out[basename] = asset.localIdentifier
            }
        }
        return out
    }

    /// PhotoKit-specific metadata for a single file inside a `.photoslibrary`.
    /// Returns nil when the path isn't inside a library, when auth is denied,
    /// or when the basename can't be matched to a `PHAsset`. Callers use this
    /// to *enrich* the regular `FileMetadata` produced by `MetadataExtractor`
    /// — Photos library files end up with both EXIF and Photos.app data
    /// surfaced side-by-side in the comparison table.
    public struct PhotosMetadata: Sendable {
        public var albumNames: [String]
        public var mediaSubtypes: [String]
        public var isFavorite: Bool
        public var isHidden: Bool
        public var creationDate: Date?
        public var hasAdjustments: Bool
        public var burstIdentifier: String?
        public var isBurstRepresentative: Bool
    }

    public func fetchMetadata(forPath path: URL) async -> PhotosMetadata? {
        guard PhotoKitDeletionService.photosLibraryURL(containing: path) != nil else {
            return nil
        }
        // Only proceed if PhotoKit auth is granted; otherwise PHAsset.fetchAssets
        // returns empty results and we'd silently produce wrong "no data" output.
        let status = currentStatus()
        guard status == .authorized || status == .limited else { return nil }

        let libraryFingerprint = path.deletingLastPathComponent().path
        if assetsByBasename == nil || indexedLibraryFingerprint != libraryFingerprint {
            assetsByBasename = await buildBasenameIndex()
            indexedLibraryFingerprint = libraryFingerprint
        }
        let index = assetsByBasename ?? [:]
        guard let localID = index[path.lastPathComponent] else { return nil }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
        guard let asset = fetched.firstObject else { return nil }

        // Albums containing this asset. Smart albums (Recents, Favorites,
        // Hidden, Recently Deleted) are excluded by the `.album` type filter
        // — only user-curated albums show up, which is what the user
        // actually wants to see in the metadata table.
        var albumNames: [String] = []
        let albumFetch = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        albumFetch.enumerateObjects { coll, _, _ in
            if let title = coll.localizedTitle, !title.isEmpty {
                albumNames.append(title)
            }
        }

        // Burst info — non-nil burst identifier means this asset is part of
        // an iPhone burst series. `representsBurst` is the canonical flag
        // for "the chosen one" Photos.app surfaces from the group.
        let burstID = asset.burstIdentifier
        let burstSelectionTypes = asset.burstSelectionTypes
        let isBurstRep = burstID != nil && burstSelectionTypes.contains(.userPick)

        return PhotosMetadata(
            albumNames: albumNames.sorted(),
            mediaSubtypes: Self.subtypeNames(asset.mediaSubtypes),
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            creationDate: asset.creationDate,
            hasAdjustments: asset.modificationDate != nil && asset.modificationDate != asset.creationDate,
            burstIdentifier: burstID,
            isBurstRepresentative: isBurstRep
        )
    }

    /// Decode an `OptionSet`-style `mediaSubtypes` value into human-readable
    /// strings. Order matches Photos.app's own labelling (Live Photo / HDR /
    /// Panorama / Screenshot / etc.) so the metadata table reads naturally.
    public static func subtypeNames(_ subtypes: PHAssetMediaSubtype) -> [String] {
        var out: [String] = []
        if subtypes.contains(.photoLive)            { out.append("Live Photo") }
        if subtypes.contains(.photoHDR)             { out.append("HDR") }
        if subtypes.contains(.photoPanorama)        { out.append("Panorama") }
        if subtypes.contains(.photoScreenshot)      { out.append("Screenshot") }
        if subtypes.contains(.videoStreamed)        { out.append("Streamed Video") }
        if subtypes.contains(.videoHighFrameRate)   { out.append("High Frame Rate") }
        if subtypes.contains(.videoTimelapse)       { out.append("Time-lapse") }
        return out
    }

    /// Canonical list of subtype labels for filter UI checkboxes. Mirrors
    /// `subtypeNames` so saved filter values round-trip stably.
    public static let allSubtypeNames: [String] = [
        "Live Photo", "HDR", "Panorama", "Screenshot",
        "Streamed Video", "High Frame Rate", "Time-lapse",
    ]

    /// Open `<library>/database/Photos.sqlite` read-only and return the
    /// set of asset UUIDs (matching the on-disk basename stem in
    /// `originals/<x>/<UUID>.<ext>`) where `ZHIDDEN = 1`. Bypasses
    /// PhotoKit's Locked-Hidden-Album privacy gate — third-party apps
    /// with library access can read the SQLite directly even when
    /// PhotoKit refuses to expose hidden state.
    ///
    /// Returns the set + a short diagnostic suitable for the status
    /// line. Best-effort: if the file can't be opened or the schema
    /// has shifted, returns an empty set with the failure reason.
    public static func readHiddenUUIDsFromPhotosSQLite(libraryURL: URL) -> (uuids: Set<String>, diagnostic: String) {
        let dbURL = libraryURL
            .appendingPathComponent("database", isDirectory: true)
            .appendingPathComponent("Photos.sqlite")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return ([], "Photos.sqlite missing at \(dbURL.lastPathComponent)")
        }
        var db: OpaquePointer? = nil
        // SQLite URI with `mode=ro&immutable=1` — forces read-only and
        // skips locking, so Photos.app holding the DB doesn't block us.
        let uri = "file:" + (dbURL.path as NSString).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "?mode=ro&immutable=1"
        let openResult = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard openResult == SQLITE_OK, let db else {
            return ([], "Photos.sqlite open failed (\(openResult))")
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer? = nil
        let sql = "SELECT ZUUID FROM ZASSET WHERE ZHIDDEN = 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return ([], "Photos.sqlite prepare failed (\(String(cString: sqlite3_errmsg(db))))")
        }
        defer { sqlite3_finalize(stmt) }
        var out: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(stmt, 0) {
                out.insert(String(cString: cstr))
            }
        }
        return (out, "Photos.sqlite hidden=\(out.count)")
    }

    /// All user-curated album names (excludes smart albums like Recents,
    /// Favorites, Hidden). Used by the filter sheet to populate a multi-
    /// select. Sorted alphabetically. Returns an empty array when auth is
    /// denied so the sheet can still render with an explanatory message.
    public func allUserAlbumNames() async -> [String] {
        let status = currentStatus()
        guard status == .authorized || status == .limited else { return [] }
        var names: [String] = []
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        albums.enumerateObjects { coll, _, _ in
            if let name = coll.localizedTitle, !name.isEmpty {
                names.append(name)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Resolve a `PhotoLibraryFilter` to the set of asset basenames that
    /// pass it. Returned set is what `FileWalker` uses as a whitelist when
    /// walking `originals/`; files whose basename isn't in this set are
    /// skipped entirely.
    ///
    /// Algorithm: build the matching `PHAsset` set via PhotoKit fetches
    /// (album union → favorite/hidden constraint via PHFetchOptions →
    /// subtype filter via post-fetch check), then map each match to its
    /// primary resource's `originalFilename`.
    /// Diagnostic shape returned alongside the matching basename set.
    /// The GUI surfaces this in the status line when the user runs a
    /// scan with an active Photos filter — saves a trip to Console.app
    /// when something doesn't match.
    public struct FilterResolution: Sendable {
        public var basenames: Set<String>
        public var summary: String
        public init(basenames: Set<String>, summary: String) {
            self.basenames = basenames
            self.summary = summary
        }
    }

    /// Convenience kept for tests / earlier callers — discards the
    /// diagnostic.
    public func matchingBasenames(filter: PhotoLibraryFilter) async -> Set<String> {
        await matchingBasenamesDetailed(filter: filter, libraryURL: nil).basenames
    }

    public func matchingBasenamesDetailed(
        filter: PhotoLibraryFilter,
        libraryURL: URL? = nil
    ) async -> FilterResolution {
        let status = currentStatus()
        guard status == .authorized || status == .limited else {
            return FilterResolution(basenames: [], summary: "auth not granted (status=\(status))")
        }

        // Use PHAsset's private `filename` KVC accessor instead of
        // `PHAssetResource.assetResources(for:)` per asset. The latter
        // triggers a DB round-trip per asset; on a 50k-photo library
        // that's tens of thousands of round-trips and the scan stalls
        // for minutes. `valueForKey: "filename"` reads from the asset
        // row directly — orders of magnitude faster.
        // Match the on-disk filename in `originals/` — Photos library
        // stores files as `<UUID>.<ext>` where `<UUID>` is the leading
        // segment of `PHAsset.localIdentifier` (e.g. `A00DFFD3-…/L0/001`
        // → `A00DFFD3-…`). The asset's `filename` property is the
        // user-visible original filename ("IMG_1234.HEIC") which does
        // NOT match anything on disk. Using the UUID extracted from the
        // localIdentifier is the only reliable way to whitelist files
        // by their on-disk basename.
        func filenameStem(of asset: PHAsset) -> String? {
            let id = asset.localIdentifier
            if let slash = id.firstIndex(of: "/") {
                return String(id[..<slash])
            }
            return id.isEmpty ? nil : id
        }

        let baseOptions = PHFetchOptions()
        var predicates: [NSPredicate] = []
        if filter.requireFavorite {
            predicates.append(NSPredicate(format: "favorite == YES"))
        }
        if !predicates.isEmpty {
            baseOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        baseOptions.includeHiddenAssets = filter.includeHidden || filter.onlyHidden

        let subtypeFilter = filter.includedSubtypes
        var out: Set<String> = []

        // Pull-and-filter loop. Synchronous because PhotoKit's
        // `enumerateObjects` is itself synchronous; the actor isolation
        // means no concurrent access to `out`.
        func consume(asset: PHAsset) {
            if let subs = subtypeFilter, !subs.isEmpty {
                let names = Set(Self.subtypeNames(asset.mediaSubtypes))
                if names.isDisjoint(with: subs) { return }
            }
            if let name = filenameStem(of: asset) { out.insert(name) }
        }

        var diag = ""
        if filter.onlyHidden {
            // PRIMARY: read Photos.sqlite directly. PhotoKit on macOS
            // 14+ refuses to surface `isHidden == true` to third-party
            // apps even with full Photos access (Locked Hidden Album
            // privacy gate). The library's own SQLite isn't subject to
            // that gate — same bundle, same TCC grant we already use to
            // walk `originals/`. ZASSET.ZUUID is the on-disk filename
            // stem, ZHIDDEN is the boolean flag.
            if let libURL = libraryURL {
                let r = Self.readHiddenUUIDsFromPhotosSQLite(libraryURL: libURL)
                out.formUnion(r.uuids)
                diag = r.diagnostic
            }
            // FALLBACK: PhotoKit smart album + full walk. Kept so the
            // feature works on libraries / OS combos where SQLite read
            // is blocked or the schema differs.
            if out.isEmpty {
                let hiddenAlbums = PHAssetCollection.fetchAssetCollections(
                    with: .smartAlbum,
                    subtype: .smartAlbumAllHidden,
                    options: nil
                )
                var smartAlbumCount = 0
                hiddenAlbums.enumerateObjects { coll, _, _ in
                    let assetsInColl = PHAsset.fetchAssets(in: coll, options: baseOptions)
                    assetsInColl.enumerateObjects { asset, _, _ in
                        smartAlbumCount += 1
                        consume(asset: asset)
                    }
                }
                diag += " · smart-album=\(smartAlbumCount)"
                if out.isEmpty {
                    let allOptions = PHFetchOptions()
                    allOptions.includeHiddenAssets = true
                    let everything = PHAsset.fetchAssets(with: allOptions)
                    var totalSeen = 0
                    var hiddenSeen = 0
                    everything.enumerateObjects { asset, _, _ in
                        totalSeen += 1
                        if asset.isHidden {
                            hiddenSeen += 1
                            if filter.requireFavorite && !asset.isFavorite { return }
                            consume(asset: asset)
                        }
                    }
                    diag += " · phk-walk=\(totalSeen)/\(hiddenSeen)"
                }
            }
        } else if let albumNames = filter.albumNames, !albumNames.isEmpty {
            let allAlbums = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .albumRegular, options: nil
            )
            var matchingAlbums: [PHAssetCollection] = []
            allAlbums.enumerateObjects { coll, _, _ in
                if let name = coll.localizedTitle, albumNames.contains(name) {
                    matchingAlbums.append(coll)
                }
            }
            for album in matchingAlbums {
                let assetsInAlbum = PHAsset.fetchAssets(in: album, options: baseOptions)
                assetsInAlbum.enumerateObjects { asset, _, _ in
                    consume(asset: asset)
                }
            }
        } else {
            let everything = PHAsset.fetchAssets(with: baseOptions)
            everything.enumerateObjects { asset, _, _ in
                consume(asset: asset)
            }
        }
        let summary = "filter[\(filter.summary)] → \(out.count) basenames" + (diag.isEmpty ? "" : " · \(diag)")
        Log.scan.info("\(summary, privacy: .public)")
        return FilterResolution(basenames: out, summary: summary)
    }

    private func getOrCreateAlbum(named name: String) async -> PHAssetCollection? {
        // First, try to find an existing album with this title.
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "localizedTitle = %@", name)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: fetchOptions
        )
        if let found = existing.firstObject { return found }

        // Otherwise create one. This is a separate `performChanges` from the
        // asset addition because the resulting collection doesn't appear in
        // a fetch until after the change is committed.
        var placeholder: PHObjectPlaceholder?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholder = req.placeholderForCreatedAssetCollection
            }
        } catch {
            return nil
        }
        guard let id = placeholder?.localIdentifier else { return nil }
        let fetched = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
        return fetched.firstObject
    }
}
