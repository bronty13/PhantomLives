import Foundation
import Photos

/// The ONLY code in PurpleAttic that deletes from the Photos library. Lives in the app
/// target (never Core/CLI) so deletion can't leak into a headless path. Uses PhotoKit's
/// sanctioned `deleteAssets`, which **always shows the macOS delete confirmation** — a free,
/// un-suppressible human-in-the-loop on the irreversible step. Deletions land in Photos'
/// Recently Deleted for 30 days.
enum PhotoKitPurger {

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
        let requested: Int
        let resolved: Int
        let deleted: Int
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

    /// Resolve osxphotos UUIDs to `PHAsset`s and request their deletion. macOS shows its own
    /// confirmation dialog; cancelling it surfaces as `.cancelled`.
    static func deleteAssets(uuids: [String], completion: @escaping (Result<Outcome, Error>) -> Void) {
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
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                if success {
                    completion(.success(Outcome(requested: uuids.count, resolved: resolved, deleted: resolved)))
                } else if let error {
                    completion(.failure(PurgeError.changeFailed(error.localizedDescription)))
                } else {
                    completion(.failure(PurgeError.cancelled))
                }
            }
        }
    }
}
