import Foundation
import AVFoundation
import AppKit
import CryptoKit

/// On-demand video thumbnail strip generator with a persistent disk
/// cache.
///
/// Workflow:
///   1. View asks for thumbnails(for: asset).
///   2. We hash the asset's path + modification date into a cache
///      directory name. If the directory exists and is non-empty,
///      we return the existing URLs (zero-cost re-hover).
///   3. Otherwise we extract N evenly-spaced frames via
///      AVAssetImageGenerator, JPEG-encode each at a modest size,
///      drop them into the cache directory, and return the URLs.
///
/// Cache layout:
///   ~/Library/Application Support/PurpleReel/thumbnails/<sha>/
///       0.jpg, 1.jpg, … N-1.jpg
///
/// Re-encoding when the source file changes is handled by including
/// the modification date in the hash input — touching the file
/// invalidates the cache.
enum ThumbnailService {

    static let frameCount = 12
    static let thumbWidth: CGFloat = 240
    static let jpegQuality: Float = 0.7

    /// Returns thumbnail URLs for the asset, generating on first call.
    /// Safe to call from any actor; the heavy work happens on a
    /// detached task.
    static func thumbnails(for asset: Asset) async -> [URL] {
        do {
            let dir = try cacheDirectory(for: asset)
            // Fast path: cache hit.
            if let existing = try? cachedThumbnailURLs(in: dir),
               existing.count == frameCount {
                return existing
            }
            return await Task.detached(priority: .utility) {
                generateSync(asset: asset, into: dir)
            }.value
        } catch {
            NSLog("[PurpleReel] thumbnail dir setup failed: \(error)")
            return []
        }
    }

    /// Purge the entire on-disk thumbnail cache (useful when the user
    /// wants to reclaim space). Not surfaced in the UI yet.
    static func purgeCache() {
        guard let root = try? cacheRoot() else { return }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Internals

    private static func generateSync(asset: Asset, into dir: URL) -> [URL] {
        let url = URL(fileURLWithPath: asset.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let avAsset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(avAsset.duration)
        guard duration.isFinite, duration > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .init(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = .init(seconds: 0.5, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: thumbWidth, height: thumbWidth) // bounding

        var urls: [URL] = []
        urls.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            // Spread frames across the middle 90% of the clip so we
            // skip slates/leader at start and end.
            let t = (Double(i) + 0.5) / Double(frameCount)   // (0.5/N) … (N-0.5)/N
            let bias = 0.05 + t * 0.90                       // 5% … 95%
            let secs = bias * duration
            let cm = CMTime(seconds: secs, preferredTimescale: 600)
            do {
                let cg = try generator.copyCGImage(at: cm, actualTime: nil)
                let outURL = dir.appendingPathComponent("\(i).jpg")
                if writeJPEG(cgImage: cg, to: outURL) { urls.append(outURL) }
            } catch {
                // Drop the frame; continue with the rest. A clip with
                // a corrupt middle won't kill the whole strip.
                continue
            }
        }
        return urls
    }

    private static func writeJPEG(cgImage: CGImage, to url: URL) -> Bool {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: NSNumber(value: jpegQuality)]
        ) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func cachedThumbnailURLs(in dir: URL) throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: dir,
                                                                  includingPropertiesForKeys: nil)
        let jpgs = files
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { lhs, rhs in
                let li = Int(lhs.deletingPathExtension().lastPathComponent) ?? 0
                let ri = Int(rhs.deletingPathExtension().lastPathComponent) ?? 0
                return li < ri
            }
        return jpgs
    }

    private static func cacheRoot() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("PurpleReel/thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport,
                                                  withIntermediateDirectories: true)
        return appSupport
    }

    private static func cacheDirectory(for asset: Asset) throws -> URL {
        // Hash: path + modification date. If the user touches the
        // file, the directory name changes and we regenerate.
        let key = "\(asset.path)|\(asset.modifiedAt.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return try cacheRoot().appendingPathComponent(String(hex.prefix(32)))
    }
}
