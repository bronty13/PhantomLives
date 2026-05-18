import Foundation
import AVFoundation
import AppKit
import CryptoKit
import ImageIO

/// Concurrency cap for video thumbnail generation. The Apple
/// Silicon hardware HEVC decoder serializes — running more than a
/// few decoders in parallel doesn't actually overlap and just
/// burns CPU on context switches. 6 is the PurpleDedup-validated
/// sweet spot for perceptual hashing of HEIC; same applies here.
@MainActor
final class ThumbnailGenerationGate {
    static let shared = ThumbnailGenerationGate()
    private var inflight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrent = 6

    func acquire() async {
        if inflight < maxConcurrent {
            inflight += 1
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
        inflight += 1
    }

    func release() {
        inflight -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

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

    static let defaultFrameCount = 12
    static let thumbWidth: CGFloat = 240
    static let jpegQuality: Float = 0.7

    /// In-memory cache of (cache-key → URL array). Skips the
    /// per-cell `FileManager.contentsOfDirectory` listing on
    /// warm hits — most rows in a 1000-asset workspace
    /// previously paid that disk cost on every appear, despite
    /// the URLs being deterministic. Capped via an LRU-ish
    /// strategy: when count exceeds the limit we drop the
    /// oldest half. Backed by an actor for async-safe access.
    private actor InMemoryCache {
        private var store: [String: [URL]] = [:]
        private let limit: Int = 4000

        func get(_ key: String) -> [URL]? {
            store[key]
        }

        func set(_ key: String, _ urls: [URL]) {
            if store.count >= limit {
                let keysToDrop = Array(store.keys.prefix(limit / 2))
                for k in keysToDrop { store.removeValue(forKey: k) }
            }
            store[key] = urls
        }
    }
    private static let inMemoryCache = InMemoryCache()

    /// Returns thumbnail URLs for the asset, generating on first call.
    /// Safe to call from any actor; the heavy work happens on a
    /// detached task. `count` is encoded into the cache directory so
    /// different counts (hover-scrub = 12, Content grid = 30) cache
    /// independently and don't clobber each other.
    static func thumbnails(for asset: Asset,
                            count: Int = defaultFrameCount) async -> [URL] {
        do {
            let dir = try cacheDirectory(for: asset, count: count)
            let memoryKey = dir.lastPathComponent
            // Tier 1: in-memory cache (zero disk I/O).
            if let cached = await inMemoryCache.get(memoryKey),
               cached.count == count {
                return cached
            }
            // Tier 2: on-disk cache (one directory listing).
            if let existing = try? cachedThumbnailURLs(in: dir),
               existing.count == count {
                await inMemoryCache.set(memoryKey, existing)
                return existing
            }
            // Tier 3: generate. Gate via the concurrency cap so
            // we don't pile 1000 AVAssetImageGenerator tasks on
            // the hardware HEVC decoder.
            return await Task.detached(priority: .utility) {
                await ThumbnailGenerationGate.shared.acquire()
                let urls = await generateAsync(asset: asset, count: count, into: dir)
                await MainActor.run {
                    ThumbnailGenerationGate.shared.release()
                }
                if !urls.isEmpty {
                    await inMemoryCache.set(memoryKey, urls)
                }
                return urls
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

    /// Render a single thumbnail at the user's poster-frame time
    /// (seconds into the clip) and return its URL. Cached by
    /// (path, modtime, seconds) so the same poster pick re-resolves
    /// instantly on every subsequent render, and bumping the time
    /// invalidates without nuking the hover-scrub strip.
    /// Image assets (already a single frame) return nil and the
    /// caller falls back to the strip's first frame.
    static func posterFrame(for asset: Asset, seconds: Double) async -> URL? {
        do {
            let dir = try cacheRoot().appendingPathComponent("posters", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let key = "\(asset.path)|\(asset.modifiedAt.timeIntervalSince1970)|\(seconds)"
            let digest = SHA256.hash(data: Data(key.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            let out = dir.appendingPathComponent("\(String(hex.prefix(32))).jpg")
            if FileManager.default.fileExists(atPath: out.path) { return out }

            return await Task.detached(priority: .utility) {
                let url = URL(fileURLWithPath: asset.path)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let ext = (asset.path as NSString).pathExtension.lowercased()
                let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic",
                                               "tif", "tiff", "gif", "bmp", "webp"]
                if imageExts.contains(ext) { return nil }
                let avAsset = AVURLAsset(url: url)
                let dur: Double
                if let cm = try? await avAsset.load(.duration) {
                    dur = CMTimeGetSeconds(cm)
                } else {
                    return nil
                }
                guard dur.isFinite, dur > 0 else { return nil }
                let clamped = max(0, min(seconds, dur - 0.01))
                let gen = AVAssetImageGenerator(asset: avAsset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter  = .zero
                gen.maximumSize = CGSize(width: thumbWidth, height: thumbWidth)
                do {
                    let cg = try gen.copyCGImage(
                        at: CMTime(seconds: clamped, preferredTimescale: 600),
                        actualTime: nil
                    )
                    if writeJPEG(cgImage: cg, to: out) { return out }
                } catch {
                    NSLog("[PurpleReel] poster-frame generate failed: \(error)")
                }
                return nil
            }.value
        } catch {
            NSLog("[PurpleReel] poster-frame dir setup failed: \(error)")
            return nil
        }
    }

    // MARK: - Internals

    private static func generateAsync(asset: Asset, count: Int, into dir: URL) async -> [URL] {
        let url = URL(fileURLWithPath: asset.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // For image assets there's nothing to seek through — write
        // the same frame `count` times so the hover-scrub cell still
        // renders cleanly and the Content view's grid has thumbnails.
        let ext = (asset.path as NSString).pathExtension.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic",
                                       "tif", "tiff", "gif", "bmp", "webp"]
        if imageExts.contains(ext) {
            return generateImageThumbs(url: url, count: count, into: dir)
        }

        let avAsset = AVURLAsset(url: url)
        let duration: Double
        if let cm = try? await avAsset.load(.duration) {
            duration = CMTimeGetSeconds(cm)
        } else {
            return []
        }
        guard duration.isFinite, duration > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .init(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = .init(seconds: 0.5, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: thumbWidth, height: thumbWidth) // bounding

        var urls: [URL] = []
        urls.reserveCapacity(count)
        for i in 0..<count {
            // Spread frames across the middle 90% of the clip so we
            // skip slates/leader at start and end.
            let t = (Double(i) + 0.5) / Double(count)        // (0.5/N) … (N-0.5)/N
            let bias = 0.05 + t * 0.90                        // 5% … 95%
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

    /// Image-asset path: produce one thumbnail then write it
    /// `count` times so the hover-scrub strip and the Content
    /// grid see a uniform set of URLs.
    ///
    /// For HEIC / HEIF / RAW we go through ImageIO's
    /// `CGImageSourceCreateThumbnailAtIndex` — it can either
    /// return the file's embedded thumbnail (10-100× faster than
    /// decoding the full image) or downsample directly to the
    /// requested size without ever decoding the full pixel buffer.
    /// `NSImage(contentsOf:)` decoded the full image then
    /// re-rendered it through `lockFocus` — orders of magnitude
    /// slower on a 48 MP iPhone HEIC.
    private static func generateImageThumbs(url: URL, count: Int, into dir: URL) -> [URL] {
        guard let cg = generateImageThumbCG(url: url) else {
            return generateImageThumbsNSImageFallback(url: url, count: count, into: dir)
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: NSNumber(value: jpegQuality)]
        ) else {
            return generateImageThumbsNSImageFallback(url: url, count: count, into: dir)
        }
        var urls: [URL] = []
        urls.reserveCapacity(count)
        for i in 0..<count {
            let outURL = dir.appendingPathComponent("\(i).jpg")
            if (try? data.write(to: outURL)) != nil {
                urls.append(outURL)
            }
        }
        return urls
    }

    /// ImageIO-backed thumbnail generator. Returns nil for source
    /// formats ImageIO can't decode (extremely rare for our
    /// extension set); callers fall back to NSImage.
    private static func generateImageThumbCG(url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            // Use the embedded thumbnail when the file has one
            // (HEIC commonly does); fall back to a fresh
            // downsample when not.
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(thumbWidth),
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        return cg
    }

    /// Original NSImage-based path, retained as the fallback for
    /// formats ImageIO doesn't recognise.
    private static func generateImageThumbsNSImageFallback(url: URL, count: Int, into dir: URL) -> [URL] {
        guard let nsImage = NSImage(contentsOf: url) else { return [] }
        let pxSize = nsImage.size
        guard pxSize.width > 0, pxSize.height > 0 else { return [] }

        let scale = thumbWidth / max(pxSize.width, pxSize.height)
        let target = NSSize(width: pxSize.width * scale,
                              height: pxSize.height * scale)
        let scaled = NSImage(size: target)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        nsImage.draw(in: NSRect(origin: .zero, size: target),
                       from: NSRect(origin: .zero, size: pxSize),
                       operation: .copy, fraction: 1.0)
        scaled.unlockFocus()

        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: NSNumber(value: jpegQuality)])
        else { return [] }

        var urls: [URL] = []
        urls.reserveCapacity(count)
        for i in 0..<count {
            let outURL = dir.appendingPathComponent("\(i).jpg")
            if (try? data.write(to: outURL)) != nil {
                urls.append(outURL)
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

    private static func cacheDirectory(for asset: Asset, count: Int) throws -> URL {
        // Hash: path + modification date + count. Different counts
        // cache independently (12 for hover-scrub vs. 30 for the
        // Content grid).
        let key = "\(asset.path)|\(asset.modifiedAt.timeIntervalSince1970)|\(count)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return try cacheRoot().appendingPathComponent(String(hex.prefix(32)))
    }
}
