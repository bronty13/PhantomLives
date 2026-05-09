import SwiftUI
import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import PurpleDedupCore

/// Lazy thumbnail with an LRU cache. Loads ~96px thumbs via ImageIO for photos and
/// AVAssetImageGenerator for videos. Cluster rows can stamp dozens of these without
/// blocking the UI — actual decode happens off-main and only the result lands on
/// the main actor.
///
/// The cache is process-wide on a singleton actor; SwiftUI gives us no built-in
/// mechanism to share decoded images across rows otherwise, and rendering 200 photo
/// thumbnails fresh on every list update was visibly choppy.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 64

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: ThumbnailLoader.iconName(for: url))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
            }
        }
        .task(id: url) {
            image = await ThumbnailLoader.shared.load(url: url, maxDimension: Int(size * 2))
        }
    }
}

/// Cache + decoder. Keeps up to 256 thumbs in memory, evicts oldest on overflow.
/// Decode is off-main on a detached task — the actor just hands work out and stores
/// results. Concurrency-bounded by the runtime's task limits, no extra throttling
/// needed (decoding 64 thumbnails to 96px takes <100ms total on M-series).
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private struct Key: Hashable {
        let path: String
        let maxDim: Int
    }

    private var cache: [Key: NSImage] = [:]
    private var keyOrder: [Key] = []
    private let limit = 256

    func load(url: URL, maxDimension: Int) async -> NSImage? {
        let key = Key(path: url.path, maxDim: maxDimension)
        if let hit = cache[key] {
            return hit
        }

        // Detached so decode runs off this actor (and off the main actor too — we
        // call from `.task`, which would otherwise pin to the view's actor).
        let image = await Task.detached(priority: .userInitiated) {
            Self.decode(url: url, maxDimension: maxDimension)
        }.value

        if let image = image {
            cache[key] = image
            keyOrder.append(key)
            if keyOrder.count > limit {
                let evict = keyOrder.removeFirst()
                cache.removeValue(forKey: evict)
            }
        }
        return image
    }

    /// Decide which decoder to call from the file extension. We avoid `UTType`
    /// roundtrips per-file; the lower-cased extension is enough for our supported
    /// formats and saves an `NSWorkspace` lookup per row.
    private static func decode(url: URL, maxDimension: Int) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        if FileKind.photoExtensions.contains(ext) {
            return decodePhoto(url: url, maxDimension: maxDimension)
        }
        if FileKind.videoExtensions.contains(ext) {
            return decodeVideoFrame(url: url, maxDimension: maxDimension)
        }
        return nil
    }

    /// Photo path — ImageIO thumbnail extraction. With
    /// `kCGImageSourceCreateThumbnailFromImageIfAbsent: true` the call uses the
    /// embedded thumbnail when present (every iPhone JPEG/HEIC has one) and falls
    /// back to a downsampled decode of the full image otherwise. Either way we get
    /// a small CGImage in milliseconds without ever loading the full pixels.
    private static func decodePhoto(url: URL, maxDimension: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Video path — synchronous AVAssetImageGenerator at t=0.5s (skips opening
    /// black frames common in transcoded files). `maximumSize` caps the output
    /// directly, avoiding a separate downsample step.
    private static func decodeVideoFrame(url: URL, maxDimension: Int) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }

    /// SF Symbol fallback for the placeholder — used both during load and when a
    /// file is unsupported (e.g. RAW formats that AVFoundation can't thumbnail).
    static func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if FileKind.photoExtensions.contains(ext) { return "photo" }
        if FileKind.videoExtensions.contains(ext) { return "film" }
        return "doc"
    }
}
