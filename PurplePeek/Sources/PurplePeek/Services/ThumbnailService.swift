import AppKit
import QuickLookThumbnailing

/// Generates and caches thumbnails for media files via `QLThumbnailGenerator` (the same
/// engine Finder uses, so videos/RAW/HEIC all render). An `actor` because
/// `QLThumbnailGenerator` is not documented thread-safe and the in-memory cache is shared;
/// callers `await` from the main actor and the work hops off it automatically.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 1000   // larger window so fast scrolling a big grid re-decodes less
    }

    /// Best available thumbnail for `url` at `size` points. Returns nil if the file is gone
    /// or QuickLook can't render it. Cached by URL (keyed including the requested size so a
    /// grid thumb and a larger preview don't collide).
    func thumbnail(for url: URL, size: CGSize, scale: CGFloat = 2.0) async -> NSImage? {
        let key = NSURL(string: "\(url.absoluteString)#\(Int(size.width))x\(Int(size.height))")
            ?? (url as NSURL)
        if let cached = cache.object(forKey: key) { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: scale, representationTypes: .thumbnail
        )
        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// Drop a single entry (e.g. after a file is deleted from disk).
    func invalidate(_ url: URL) {
        // Size is part of the key, so clear the whole cache pragmatically when asked to
        // invalidate — entries are cheap to regenerate and deletions are infrequent.
        cache.removeAllObjects()
    }
}
