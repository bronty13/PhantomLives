import Foundation
import Photos

/// Imports photos/videos into the Apple Photos library. Adapted from PurpleDedup's proven
/// importer: originals are copied (never moved), and each asset is added to its per-file
/// albums and marked favorite. Album lookups are cached for the lifetime of an import run.
///
/// Title/caption/keywords are NOT set here — PhotoKit can't write them; they're embedded
/// into a staged copy by `MetadataStagingService` before the URL reaches this service.
actor PhotoKitService {
    static let shared = PhotoKitService()
    private init() {}

    private var albumCache: [String: PHAssetCollection] = [:]

    enum ImportError: Error, LocalizedError {
        case notAuthorized(String)
        case notCreated
        case changeFailed(String)
        var errorDescription: String? {
            switch self {
            case .notAuthorized(let s): return s
            case .notCreated:           return "Photos did not create the asset."
            case .changeFailed(let s):  return s
            }
        }
    }

    // MARK: - Authorization

    nonisolated func currentStatusAuthorized() -> Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    func requestAuthorization() async -> Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined {
            let r = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return r == .authorized || r == .limited
        }
        return s == .authorized || s == .limited
    }

    /// Reset the per-run album cache (call at the start of an import run).
    func beginRun() { albumCache.removeAll() }

    // MARK: - Import one file

    /// Import a single photo/video. Returns the created asset's local identifier.
    func importOne(url: URL, type: PHAssetResourceType, isFavorite: Bool, albums: [String]) async throws -> String {
        // Resolve target albums (create on demand), cached.
        var collections: [PHAssetCollection] = []
        for name in albums {
            if let c = try await albumCollection(named: name) { collections.append(c) }
        }

        var placeholderID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let opts = PHAssetResourceCreationOptions()
                opts.shouldMoveFile = false          // copy — never move the user's original
                req.addResource(with: type, fileURL: url, options: opts)
                guard let ph = req.placeholderForCreatedAsset else { return }
                placeholderID = ph.localIdentifier
                for collection in collections {
                    if let cReq = PHAssetCollectionChangeRequest(for: collection) {
                        cReq.addAssets([ph] as NSArray)
                    }
                }
            }
        } catch {
            throw ImportError.changeFailed(error.localizedDescription)
        }

        guard let pid = placeholderID,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [pid], options: nil).firstObject
        else { throw ImportError.notCreated }

        if isFavorite {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = true
            }
        }
        return asset.localIdentifier
    }

    // MARK: - Album helper (cached)

    private func albumCollection(named name: String) async throws -> PHAssetCollection? {
        if let cached = albumCache[name] { return cached }

        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "localizedTitle = %@", name)
        if let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts).firstObject {
            albumCache[name] = found
            return found
        }

        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholderID = req.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let pid = placeholderID,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [pid], options: nil).firstObject
        else { return nil }
        albumCache[name] = created
        return created
    }
}
