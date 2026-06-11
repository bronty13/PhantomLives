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

    /// Resolve osxphotos UUIDs to `PHAsset`s and delete them in chunks. `progress(done,total)`
    /// fires after each chunk. macOS shows its confirmation per chunk; dismissing one stops the
    /// run and reports what was already deleted.
    static func deleteAssets(uuids: [String],
                             batchSize: Int = defaultBatchSize,
                             progress: ((_ done: Int, _ total: Int) -> Void)? = nil,
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

            func run(_ i: Int) {
                if i >= batches.count { finish(); return }
                let batch = batches[i]
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(batch as NSArray)
                } completionHandler: { success, error in
                    if success {
                        deleted += batch.count
                    } else if let error {
                        failed += batch.count
                        if firstError == nil { firstError = error.localizedDescription }
                    } else {
                        // nil error = user dismissed the macOS confirmation → stop here.
                        cancelled = true
                        finish()
                        return
                    }
                    progress?(min(deleted + failed, resolved), resolved)
                    run(i + 1)
                }
            }
            run(0)
        }
    }
}
