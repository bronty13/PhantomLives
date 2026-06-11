import Foundation
import Photos

/// The ONLY code in PurpleAttic that deletes from the Photos library. Lives in the app
/// target (never Core/CLI) so deletion can't leak into a headless path. Uses PhotoKit's
/// sanctioned `deleteAssets`, which shows the macOS delete confirmation — a free,
/// un-suppressible human-in-the-loop on the irreversible step. Deletions land in Photos'
/// Recently Deleted for 30 days.
///
/// **Batched deletion (required at scale).** A single `performChanges` deleting tens of
/// thousands of assets is rejected by PhotoKit (`PHPhotosErrorDomain 3300`) — the whole atomic
/// request fails, and one un-deletable asset takes the entire batch down with it. So we delete
/// in chunks: each chunk is its own `performChanges`, a failed chunk is **skipped and counted**
/// (the run continues), and re-running the purge naturally retries anything not yet deleted.
/// macOS shows one confirmation per chunk. (Incident 2026-06-11: 65,627-asset atomic delete →
/// error 3300.)
enum PhotoKitPurger {

    /// Per-chunk asset count. PhotoKit's atomic-delete ceiling sits between 1000 and 5000:
    /// 1000-asset chunks delete reliably (proven — cleared ~24k in a run), but 5000 fails with
    /// `PHPhotosErrorDomain 3300`, same as the full set. So 1000 it is. macOS confirms once per
    /// chunk, so a big purge is many prompts — that's the unavoidable cost of staying under the
    /// ceiling (there's no API to suppress the per-`performChanges` confirmation). A failed chunk
    /// is skipped + retried next run. (2026-06-11: 5000 overshot; reverted to the proven 1000.)
    static let defaultBatchSize = 1000

    enum PurgeError: LocalizedError {
        case notAuthorized
        case noAssetsResolved
        case changeFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notAuthorized:      return "Photos access was denied. Grant it in System Settings → Privacy & Security → Photos."
            case .noAssetsResolved:   return "None of the selected photos could be matched in Photos (nothing deleted)."
            case .changeFailed(let m): return "Photos refused the deletion: \(m)"
            case .cancelled:          return "Deletion was cancelled."
            }
        }
    }

    struct Outcome {
        let requested: Int       // uuids handed in
        let resolved: Int        // PHAssets actually matched in Photos
        let deleted: Int         // confirmed deleted
        let failed: Int          // resolved assets in chunks that failed (retry on next run)
        let batchError: String?  // first non-cancel chunk error, if any
        let cancelled: Bool      // user dismissed a macOS confirmation partway
    }

    static func authorize(_ completion: @escaping (Bool) -> Void) {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                completion(status == .authorized || status == .limited)
            }
        default:
            completion(false)
        }
    }

    /// How many times to retry a chunk that fails, and the back-off (seconds) before each retry.
    /// Error 3300 is often **transient** — Photos chokes while syncing a bulk deletion, then
    /// recovers — so waiting and retrying the same chunk turns a skip into a success. After these
    /// are exhausted the chunk is skipped (and a later re-run picks it up).
    static let retryBackoff: [Double] = [5, 15, 30]

    /// Resolve osxphotos UUIDs to `PHAsset`s and delete them in chunks. `progress(done,total)`
    /// fires after each chunk; `status` reports human-readable state (e.g. a back-off wait) so the
    /// UI doesn't look frozen. macOS shows its confirmation per chunk; dismissing one stops the
    /// run and reports what was already deleted. A chunk that fails is retried with back-off
    /// (transient 3300), then skipped if it still won't go.
    static func deleteAssets(uuids: [String],
                             batchSize: Int = defaultBatchSize,
                             progress: ((_ done: Int, _ total: Int) -> Void)? = nil,
                             status: ((_ message: String) -> Void)? = nil,
                             completion: @escaping (Result<Outcome, Error>) -> Void) {
        authorize { ok in
            guard ok else { completion(.failure(PurgeError.notAuthorized)); return }

            // An osxphotos uuid is the prefix of PHAsset.localIdentifier ("<uuid>/L0/001").
            let ids = uuids.map { "\($0)/L0/001" }
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assets: [PHAsset] = []
            fetch.enumerateObjects { asset, _, _ in assets.append(asset) }

            guard !assets.isEmpty else {
                completion(.failure(PurgeError.noAssetsResolved)); return
            }

            let resolved = assets.count
            let step = max(1, batchSize)
            let batches: [[PHAsset]] = stride(from: 0, to: resolved, by: step).map {
                Array(assets[$0 ..< min($0 + step, resolved)])
            }

            var deleted = 0
            var failed = 0
            var firstError: String?
            var cancelled = false

            func finish() {
                if deleted == 0 {
                    if cancelled { completion(.failure(PurgeError.cancelled)); return }
                    if let e = firstError { completion(.failure(PurgeError.changeFailed(e))); return }
                }
                completion(.success(Outcome(requested: uuids.count, resolved: resolved,
                                            deleted: deleted, failed: failed,
                                            batchError: firstError, cancelled: cancelled)))
            }

            // `tries` = retries already spent on batch `i`.
            func run(_ i: Int, _ tries: Int = 0) {
                if i >= batches.count { finish(); return }
                let batch = batches[i]
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(batch as NSArray)
                } completionHandler: { success, error in
                    if success {
                        deleted += batch.count
                        progress?(min(deleted + failed, resolved), resolved)
                        run(i + 1)
                    } else if let error {
                        if tries < retryBackoff.count {
                            // Transient (3300 while Photos syncs a bulk delete) → back off + retry.
                            let wait = retryBackoff[tries]
                            status?("A batch hit a temporary Photos error — waiting \(Int(wait))s and retrying (\(tries + 1)/\(retryBackoff.count))…")
                            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + wait) {
                                run(i, tries + 1)
                            }
                        } else {
                            failed += batch.count
                            if firstError == nil { firstError = error.localizedDescription }
                            progress?(min(deleted + failed, resolved), resolved)
                            run(i + 1)
                        }
                    } else {
                        // nil error = user dismissed the macOS confirmation → stop here.
                        cancelled = true
                        finish()
                        return
                    }
                }
            }
            run(0)
        }
    }

    // MARK: - Stage to album (the scalable path for large purges)

    struct StageOutcome {
        let requested: Int
        let resolved: Int
        let added: Int
        let albumName: String
    }

    /// Add the verified-deletable assets to a regular album so the user can delete them **inside
    /// Photos.app** with a single confirmation. Adding to an album is **non-destructive → shows no
    /// confirmation**, so this runs fully unattended (batched, with progress), and Photos' own
    /// engine then handles the bulk delete + iCloud pacing far more robustly than third-party
    /// `deleteAssets` (no per-batch prompts, no 3300 choke). This is the recommended path at scale.
    static func stageToAlbum(uuids: [String],
                             albumName: String,
                             batchSize: Int = 2000,
                             progress: ((_ done: Int, _ total: Int) -> Void)? = nil,
                             status: ((_ message: String) -> Void)? = nil,
                             completion: @escaping (Result<StageOutcome, Error>) -> Void) {
        authorize { ok in
            guard ok else { completion(.failure(PurgeError.notAuthorized)); return }

            let ids = uuids.map { "\($0)/L0/001" }
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assets: [PHAsset] = []
            fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
            guard !assets.isEmpty else { completion(.failure(PurgeError.noAssetsResolved)); return }
            let resolved = assets.count

            findOrCreateAlbum(named: albumName) { albumResult in
                switch albumResult {
                case .failure(let e):
                    completion(.failure(e))
                case .success(let album):
                    let step = max(1, batchSize)
                    let batches: [[PHAsset]] = stride(from: 0, to: resolved, by: step).map {
                        Array(assets[$0 ..< min($0 + step, resolved)])
                    }
                    var added = 0
                    func run(_ i: Int) {
                        if i >= batches.count {
                            completion(.success(StageOutcome(requested: uuids.count, resolved: resolved,
                                                             added: added, albumName: albumName)))
                            return
                        }
                        let batch = batches[i]
                        PHPhotoLibrary.shared().performChanges {
                            let req = PHAssetCollectionChangeRequest(for: album)
                            req?.addAssets(batch as NSArray)
                        } completionHandler: { success, _ in
                            if success { added += batch.count }   // add failures are non-fatal: just continue
                            status?("Staging to “\(albumName)”…")
                            progress?(min((i + 1) * step, resolved), resolved)
                            run(i + 1)
                        }
                    }
                    run(0)
                }
            }
        }
    }

    /// Fetch the regular album named `name`, creating it if absent. Album create/modify is
    /// non-destructive, so neither step prompts.
    private static func findOrCreateAlbum(named name: String,
                                          completion: @escaping (Result<PHAssetCollection, Error>) -> Void) {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", name)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts)
        if let album = existing.firstObject { completion(.success(album)); return }

        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = req.placeholderForCreatedAssetCollection
        } completionHandler: { success, error in
            if success, let id = placeholder?.localIdentifier,
               let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
                completion(.success(album))
            } else {
                completion(.failure(PurgeError.changeFailed(error?.localizedDescription ?? "Couldn't create the album.")))
            }
        }
    }
}
