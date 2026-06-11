import Foundation
import Photos

/// Thread-safe cancel flag the UI flips to stop a purge/stage between batches (and during a
/// back-off wait). Passed into `PhotoKitPurger`; checked before every batch and before every retry.
final class PurgeCancellation {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

/// The ONLY code in PurpleAttic that deletes from the Photos library. Lives in the app
/// target (never Core/CLI) so deletion can't leak into a headless path. Uses PhotoKit's
/// sanctioned `deleteAssets`, which shows the macOS delete confirmation — a free,
/// un-suppressible human-in-the-loop on the irreversible step. Deletions land in Photos'
/// Recently Deleted for 30 days.
///
/// **Batched, with auto-pause on a busy library (required at scale).** A single `performChanges`
/// touching tens of thousands of assets is rejected by PhotoKit (`PHPhotosErrorDomain 3300`), so we
/// work in chunks. But 3300 is more than a per-batch hiccup: once a large purge backs up Photos'
/// iCloud sync (e.g. thousands of pending deletes in Recently Deleted), PhotoKit rejects **every**
/// asset-mutation — delete AND album-add — until the backlog drains, and a fresh launch/reboot does
/// NOT clear it. So a 3300 is treated as *"the library is busy"*, not *"this batch is bad"*: we
/// pause on that batch with escalating back-off and re-probe, **resuming automatically** the moment
/// Photos accepts it again, reporting progress throughout so the run never looks frozen. A genuine
/// per-asset error (not 3300) is retried briefly, then the batch is skipped + counted (a later
/// re-run retries it). (Incidents 2026-06-11: 65,627-asset atomic delete → 3300; then after ~24k
/// deletes the whole library rejected all mutations — delete and album-add alike — for hours.)
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
        let cancelled: Bool      // user cancelled / dismissed a macOS confirmation partway
        let pausedOut: Bool      // gave up after the busy-library back-off budget was exhausted
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

    /// Back-off (seconds) for a **genuine per-asset** transient error (NOT 3300): a few quick
    /// retries, then the batch is skipped.
    static let retryBackoff: [Double] = [5, 15, 30]

    /// Escalating back-off (seconds) when the **whole library is busy** (3300). Caps at the last
    /// value and stays there — the run keeps re-probing this same batch at that cadence, auto-
    /// resuming the instant Photos accepts it.
    static let pauseBackoff: [Double] = [30, 60, 120, 300]

    /// How many busy (3300) probes to spend on a single batch before giving up the run (and
    /// reporting `pausedOut` so the user knows to re-run once iCloud settles). 12 probes ≈ up to
    /// ~45 min of waiting on one batch — patient enough to ride out a normal sync backlog without
    /// hanging forever on a truly stuck library.
    static let maxBusyProbesPerBatch = 12

    // MARK: - Delete

    /// Resolve osxphotos UUIDs to `PHAsset`s and delete them in chunks, auto-pausing on a busy
    /// library and resuming when it clears. `progress(done,total)` fires after each chunk; `status`
    /// reports human-readable state (a back-off wait, a retry) so the UI never looks frozen.
    static func deleteAssets(uuids: [String],
                             batchSize: Int = defaultBatchSize,
                             cancellation: PurgeCancellation? = nil,
                             progress: ((_ done: Int, _ total: Int) -> Void)? = nil,
                             status: ((_ message: String) -> Void)? = nil,
                             completion: @escaping (Result<Outcome, Error>) -> Void) {
        authorize { ok in
            guard ok else { completion(.failure(PurgeError.notAuthorized)); return }

            let assets = resolveAssets(uuids)
            guard !assets.isEmpty else { completion(.failure(PurgeError.noAssetsResolved)); return }
            let resolved = assets.count

            runBatches(chunk(assets, batchSize),
                       totalResolved: resolved,
                       cancellation: cancellation,
                       progress: progress,
                       status: status,
                       makeChanges: { batch in PHAssetChangeRequest.deleteAssets(batch as NSArray) }) { sum in
                if sum.doneAssets == 0 {
                    if sum.cancelled { completion(.failure(PurgeError.cancelled)); return }
                    if let e = sum.firstError { completion(.failure(PurgeError.changeFailed(e))); return }
                }
                completion(.success(Outcome(requested: uuids.count, resolved: resolved,
                                            deleted: sum.doneAssets, failed: sum.failedAssets,
                                            batchError: sum.firstError, cancelled: sum.cancelled,
                                            pausedOut: sum.pausedOut)))
            }
        }
    }

    // MARK: - Stage to album (the scalable path for large purges)

    struct StageOutcome {
        let requested: Int
        let resolved: Int
        let added: Int
        let albumName: String
        let cancelled: Bool
        let pausedOut: Bool
    }

    /// Add the verified-deletable assets to a regular album so the user can delete them **inside
    /// Photos.app** with a single confirmation. Adding to an album is **non-destructive → shows no
    /// confirmation**, so this runs fully unattended (batched, with progress + auto-pause), and
    /// Photos' own engine then handles the bulk delete + iCloud pacing far more robustly than
    /// third-party `deleteAssets`. This is the recommended path at scale.
    static func stageToAlbum(uuids: [String],
                             albumName: String,
                             batchSize: Int = 2000,
                             cancellation: PurgeCancellation? = nil,
                             progress: ((_ done: Int, _ total: Int) -> Void)? = nil,
                             status: ((_ message: String) -> Void)? = nil,
                             completion: @escaping (Result<StageOutcome, Error>) -> Void) {
        authorize { ok in
            guard ok else { completion(.failure(PurgeError.notAuthorized)); return }

            let assets = resolveAssets(uuids)
            guard !assets.isEmpty else { completion(.failure(PurgeError.noAssetsResolved)); return }
            let resolved = assets.count

            ensureAlbumIdentifier(named: albumName) { albumID, createError in
                guard let albumID else {
                    completion(.failure(PurgeError.changeFailed(createError ?? "Couldn't create the album."))); return
                }
                runBatches(chunk(assets, batchSize),
                           totalResolved: resolved,
                           cancellation: cancellation,
                           progress: progress,
                           status: status,
                           makeChanges: { batch in
                               // Re-fetch the album FRESH inside the change block — a reference
                               // captured outside can be stale and silently no-op the add. Guard so
                               // a nil never looks like success.
                               guard let album = PHAssetCollection
                                       .fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
                                     let req = PHAssetCollectionChangeRequest(for: album) else { return }
                               req.addAssets(batch as NSArray)
                           }) { sum in
                    // Trust nothing: report the album's ACTUAL membership, not a summed guess.
                    let added = albumAssetCount(albumID: albumID)
                    if added == 0 {
                        if sum.cancelled { completion(.failure(PurgeError.cancelled)); return }
                        if let e = sum.firstError { completion(.failure(PurgeError.changeFailed(e))); return }
                    }
                    completion(.success(StageOutcome(requested: uuids.count, resolved: resolved,
                                                     added: added, albumName: albumName,
                                                     cancelled: sum.cancelled, pausedOut: sum.pausedOut)))
                }
            }
        }
    }

    // MARK: - Shared batch runner (pause-on-busy / skip-on-error / resume)

    private struct BatchRunSummary {
        var doneAssets: Int       // assets in succeeded batches
        var failedAssets: Int     // assets in skipped (non-3300) batches
        var firstError: String?
        var cancelled: Bool
        var pausedOut: Bool       // exhausted the busy-library back-off budget on a batch
    }

    /// `PHPhotosErrorDomain 3300` — the "library is busy / can't complete the change" signal we
    /// must wait out, as opposed to a per-asset failure we should skip.
    private static func isLibraryBusy(_ error: Error) -> Bool {
        (error as NSError).code == 3300
    }

    /// Run `batches` sequentially through `performChanges(makeChanges)`. Success → next batch.
    /// 3300 → pause on this batch with escalating back-off and re-probe (auto-resume), giving up
    /// only after `maxBusyProbesPerBatch`. Other error → brief retries, then skip + count the
    /// batch. `nil` error (user dismissed the delete dialog) or a flipped cancel flag → stop.
    private static func runBatches(_ batches: [[PHAsset]],
                                   totalResolved: Int,
                                   cancellation: PurgeCancellation?,
                                   progress: ((_ done: Int, _ total: Int) -> Void)?,
                                   status: ((_ message: String) -> Void)?,
                                   makeChanges: @escaping ([PHAsset]) -> Void,
                                   completion: @escaping (BatchRunSummary) -> Void) {
        var doneAssets = 0
        var failedAssets = 0
        var firstError: String?

        func report(cancelled: Bool, pausedOut: Bool) {
            completion(BatchRunSummary(doneAssets: doneAssets, failedAssets: failedAssets,
                                       firstError: firstError, cancelled: cancelled, pausedOut: pausedOut))
        }

        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) {
                if cancellation?.isCancelled == true { report(cancelled: true, pausedOut: false); return }
                work()
            }
        }

        func run(_ i: Int, busyTries: Int, errTries: Int) {
            if cancellation?.isCancelled == true { report(cancelled: true, pausedOut: false); return }
            if i >= batches.count { report(cancelled: false, pausedOut: false); return }
            let batch = batches[i]
            PHPhotoLibrary.shared().performChanges {
                makeChanges(batch)
            } completionHandler: { success, error in
                if success {
                    doneAssets += batch.count
                    progress?(min(doneAssets + failedAssets, totalResolved), totalResolved)
                    run(i + 1, busyTries: 0, errTries: 0)
                    return
                }
                guard let error else {
                    // nil error = user dismissed the macOS confirmation → stop here.
                    report(cancelled: true, pausedOut: false); return
                }
                if cancellation?.isCancelled == true { report(cancelled: true, pausedOut: false); return }

                if isLibraryBusy(error) {
                    // Whole-library block: don't advance — wait it out on THIS batch and resume.
                    if busyTries >= maxBusyProbesPerBatch {
                        if firstError == nil { firstError = error.localizedDescription }
                        report(cancelled: false, pausedOut: true); return
                    }
                    let wait = pauseBackoff[min(busyTries, pauseBackoff.count - 1)]
                    let pct = totalResolved > 0 ? Int(Double(doneAssets) / Double(totalResolved) * 100) : 0
                    status?("Photos/iCloud is catching up on pending changes — paused, auto-resuming in \(Int(wait))s. \(doneAssets)/\(totalResolved) done (\(pct)%).")
                    after(wait) { run(i, busyTries: busyTries + 1, errTries: errTries) }
                } else if errTries < retryBackoff.count {
                    let wait = retryBackoff[errTries]
                    status?("A batch hit a temporary error — retrying in \(Int(wait))s (\(errTries + 1)/\(retryBackoff.count))…")
                    after(wait) { run(i, busyTries: busyTries, errTries: errTries + 1) }
                } else {
                    // Genuine per-asset failure → skip this batch, keep going; a re-run retries it.
                    failedAssets += batch.count
                    if firstError == nil { firstError = error.localizedDescription }
                    progress?(min(doneAssets + failedAssets, totalResolved), totalResolved)
                    run(i + 1, busyTries: 0, errTries: 0)
                }
            }
        }
        run(0, busyTries: 0, errTries: 0)
    }

    // MARK: - Resolution helpers

    /// Resolve osxphotos UUIDs to live `PHAsset`s. `PHAsset.localIdentifier` is `"<UUID>/L0/001"`
    /// with the UUID **uppercase**, and `fetchAssets(withLocalIdentifiers:)` is **case-sensitive**
    /// — a lowercase UUID resolves to nothing. osxphotos already emits uppercase, but normalise
    /// defensively so a future metadata source can't silently match zero. (2026-06-11: a lowercased
    /// UUID resolved 0/8 in testing; uppercase resolved 8/8.)
    private static func resolveAssets(_ uuids: [String]) -> [PHAsset] {
        let ids = uuids.map { "\($0.uppercased())/L0/001" }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private static func chunk(_ assets: [PHAsset], _ size: Int) -> [[PHAsset]] {
        let step = max(1, size)
        return stride(from: 0, to: assets.count, by: step).map {
            Array(assets[$0 ..< min($0 + step, assets.count)])
        }
    }

    /// Local-identifier of the regular album named `name`, creating it if absent. Returns
    /// `(nil, error)` if creation fails. Album create/modify is non-destructive → no prompt.
    private static func ensureAlbumIdentifier(named name: String,
                                              completion: @escaping (_ albumID: String?, _ error: String?) -> Void) {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", name)
        if let existing = PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts).firstObject {
            completion(existing.localIdentifier, nil); return
        }
        var placeholderID: String?
        PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholderID = req.placeholderForCreatedAssetCollection.localIdentifier
        } completionHandler: { success, error in
            completion(success ? placeholderID : nil, error?.localizedDescription)
        }
    }

    /// The true number of assets currently in the album — used to VERIFY staging worked rather
    /// than trusting `performChanges` success (which is `true` even when an add no-ops).
    private static func albumAssetCount(albumID: String) -> Int {
        guard let album = PHAssetCollection
            .fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return 0 }
        return PHAsset.fetchAssets(in: album, options: nil).count
    }
}
