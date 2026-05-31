import Foundation
import Photos
import AppKit

/// Bridges the system Photos library into the "auto-assembled day" flow:
/// request read access, find the photos taken on a given calendar day, and
/// load their bytes for import. All access is read-only and on-device — the
/// chosen photos are copied into the encrypted journal; nothing is uploaded.
@MainActor
enum PhotosImportService {

    /// A photo the user can choose to attach, paired with a preview the grid
    /// renders. `localIdentifier` dedupes against already-imported photos.
    struct Suggestion: Identifiable, Hashable {
        let localIdentifier: String
        let creationDate: Date?
        var preview: NSImage?
        var id: String { localIdentifier }
    }

    // MARK: - Authorization

    static var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Request read access. Returns true once authorized (full or limited).
    static func requestAccess() async -> Bool {
        let current = authorizationStatus
        if current == .authorized || current == .limited { return true }
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { cont.resume(returning: $0) }
        }
        return granted == .authorized || granted == .limited
    }

    // MARK: - Fetch

    /// All image assets created on the same calendar day as `date`, newest
    /// first. Caller must already hold authorization.
    static func assets(on date: Date, calendar: Calendar = .current) -> [PHAsset] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// A small preview image for the suggestion grid (fast, may be degraded).
    static func preview(for asset: PHAsset, edge: CGFloat = 200) async -> NSImage? {
        await requestImage(asset, target: CGSize(width: edge * 2, height: edge * 2),
                           mode: .aspectFill, deliveryMode: .opportunistic)
    }

    /// Full-resolution JPEG bytes for an asset, for import. Returns the encoded
    /// (downscaled) image ready to store, plus the original filename if known.
    static func loadForImport(_ asset: PHAsset) async -> (image: ImageProcessing.EncodedImage, filename: String)? {
        // Pull the original data and let ImageProcessing downscale + re-encode
        // so HEIC/large originals land as a sane JPEG.
        let data: Data? = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                cont.resume(returning: data)
            }
        }
        guard let data, let encoded = ImageProcessing.downscaledJPEG(from: data) else { return nil }
        let filename = (PHAssetResource.assetResources(for: asset).first?.originalFilename)
            ?? "photo-\(asset.localIdentifier.prefix(8)).jpg"
        return (encoded, filename)
    }

    // MARK: - Private

    private static func requestImage(_ asset: PHAsset, target: CGSize,
                                     mode: PHImageContentMode,
                                     deliveryMode: PHImageRequestOptionsDeliveryMode) async -> NSImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = deliveryMode
            options.resizeMode = .fast
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: target,
                                                  contentMode: mode, options: options) { image, info in
                // opportunistic delivery can call back twice; resume once on the
                // final (non-degraded) image, or whatever we get.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if resumed { return }
                if !isDegraded || image != nil {
                    resumed = true
                    cont.resume(returning: image)
                }
            }
        }
    }
}
