import Foundation
import Photos

/// Imports files from disk INTO the Apple Photos library via `PHAssetCreationRequest`.
///
/// This is the write-side counterpart to `PhotoKitDeletionService` (which maps existing
/// library files to assets for album-based deletion). Import creates brand-new assets,
/// so it needs no basename index — just `.readWrite` authorization, which the app
/// already requests.
///
/// **Originals are copied, never moved** (`shouldMoveFile = false`): the user's folder
/// files stay exactly where they are. Imported assets are optionally collected into an
/// "Imported by PurpleDedup" album so they're easy to find and review in Photos.app.
///
/// **Live Photo limitation (v1):** a still + its `.MOV` companion import as two
/// independent assets, not a reconstituted Live Photo. True pairing requires adding
/// both resources to a single creation request and is a planned follow-up.
public actor PhotoKitImportService {
    public static let shared = PhotoKitImportService()

    /// Default album new imports are collected into. `nil` album → no album.
    public static let defaultAlbumName = "Imported by PurpleDedup"

    /// Files committed per `performChanges` block — bounds peak memory and gives the
    /// progress callback something to report on large imports.
    private static let batchSize = 200

    public init() {}

    // MARK: - Authorization (reuses the deletion service's enum)

    public nonisolated func currentStatus() -> PhotoKitDeletionService.Authorization {
        PhotoKitDeletionService.Authorization(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAuthorization() async -> PhotoKitDeletionService.Authorization {
        PhotoKitDeletionService.Authorization(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    // MARK: - Result

    public struct ImportResult: Sendable {
        public var imported: [URL]
        public var failed: [(URL, String)]
        public var skipped: [URL]            // unsupported extension
        public var albumName: String?

        public init(imported: [URL] = [], failed: [(URL, String)] = [],
                    skipped: [URL] = [], albumName: String? = nil) {
            self.imported = imported
            self.failed = failed
            self.skipped = skipped
            self.albumName = albumName
        }

        public var summary: String {
            var bits: [String] = []
            if !imported.isEmpty {
                var s = "Imported \(imported.count)"
                if let albumName { s += " into \"\(albumName)\"" }
                bits.append(s)
            }
            if !failed.isEmpty  { bits.append("\(failed.count) failed") }
            if !skipped.isEmpty { bits.append("\(skipped.count) skipped (unsupported)") }
            return bits.isEmpty ? "Nothing to import" : bits.joined(separator: " · ")
        }
    }

    /// Partition URLs by how they'll import. Pure + `nonisolated` so it's unit-testable
    /// without a live Photos library.
    public nonisolated static func classifyForImport(urls: [URL]) -> (photos: [URL], videos: [URL], skipped: [URL]) {
        var photos: [URL] = [], videos: [URL] = [], skipped: [URL] = []
        for u in urls {
            let ext = u.pathExtension.lowercased()
            if FileKind.photoExtensions.contains(ext) { photos.append(u) }
            else if FileKind.videoExtensions.contains(ext) { videos.append(u) }
            else { skipped.append(u) }
        }
        return (photos, videos, skipped)
    }

    // MARK: - Import

    /// Import `urls` into Photos. Photos/videos are created via `PHAssetCreationRequest`;
    /// unsupported extensions are skipped. When `addToAlbumNamed` is non-nil the new
    /// assets are added to that (created-on-demand) album.
    public func importFiles(
        _ urls: [URL],
        addToAlbumNamed albumName: String? = defaultAlbumName,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> ImportResult {
        let (photos, videos, skipped) = Self.classifyForImport(urls: urls)
        var result = ImportResult(skipped: skipped, albumName: albumName)
        let toImport = photos.map { ($0, PHAssetResourceType.photo) }
                     + videos.map { ($0, PHAssetResourceType.video) }
        guard !toImport.isEmpty else { return result }

        // Authorization gate. `.limited` cannot reliably create assets.
        let status = currentStatus()
        if status == .notDetermined {
            _ = await requestAuthorization()
        }
        let finalStatus = currentStatus()
        guard finalStatus == .authorized else {
            let reason = finalStatus == .limited
                ? "Photos access is limited — full access is required to import."
                : "Photos access not granted."
            result.failed = toImport.map { ($0.0, reason) }
            return result
        }

        // Resolve / create the destination album once.
        var albumPlaceholderID: String?
        if let albumName {
            albumPlaceholderID = await getOrCreateAlbumIdentifier(named: albumName)
            if albumPlaceholderID == nil {
                Log.scan.notice("Import: could not create album \(albumName, privacy: .public); importing without an album")
                result.albumName = nil
            }
        }

        let album = albumPlaceholderID.flatMap {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
        }

        var done = 0
        let total = toImport.count
        for chunk in toImport.chunked(into: Self.batchSize) {
            var placeholderByURL: [URL: String] = [:]
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    var created: [PHObjectPlaceholder] = []
                    for (url, type) in chunk {
                        let req = PHAssetCreationRequest.forAsset()
                        let opts = PHAssetResourceCreationOptions()
                        opts.shouldMoveFile = false       // copy — never move the user's original
                        req.addResource(with: type, fileURL: url, options: opts)
                        if let ph = req.placeholderForCreatedAsset {
                            placeholderByURL[url] = ph.localIdentifier
                            created.append(ph)
                        }
                    }
                    if let album, let req = PHAssetCollectionChangeRequest(for: album), !created.isEmpty {
                        req.addAssets(created as NSArray)
                    }
                }
                // Verify which assets actually exist post-commit.
                let ids = Array(placeholderByURL.values)
                let existing = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var liveIDs: Set<String> = []
                existing.enumerateObjects { a, _, _ in liveIDs.insert(a.localIdentifier) }
                for (url, id) in placeholderByURL {
                    if liveIDs.contains(id) { result.imported.append(url) }
                    else { result.failed.append((url, "Asset was not created")) }
                }
            } catch {
                for (url, _) in chunk { result.failed.append((url, error.localizedDescription)) }
            }
            done += chunk.count
            progress?(done, total)
        }
        return result
    }

    // MARK: - Album helper

    /// Find or create an album by title; returns its local identifier. Mirrors the
    /// pattern in `PhotoKitDeletionService.getOrCreateAlbum`.
    private func getOrCreateAlbumIdentifier(named name: String) async -> String? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "localizedTitle = %@", name)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: fetchOptions
        )
        if let found = existing.firstObject { return found.localIdentifier }

        var placeholder: PHObjectPlaceholder?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholder = req.placeholderForCreatedAssetCollection
            }
        } catch {
            return nil
        }
        return placeholder?.localIdentifier
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
