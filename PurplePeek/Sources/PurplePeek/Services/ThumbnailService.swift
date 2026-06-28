import AppKit
import CryptoKit
import Foundation
import QuickLookThumbnailing

/// Generates and caches thumbnails for media files via `QLThumbnailGenerator` (the same
/// engine Finder uses, so videos/RAW/HEIC all render). An `actor` because
/// `QLThumbnailGenerator` is not documented thread-safe and the in-memory cache is shared;
/// callers `await` from the main actor and the work hops off it automatically.
///
/// **Shared cache:** before generating, it checks PeekServer's persistent on-disk thumbnail
/// cache (`~/Library/Caches/PeekServer/thumbs`), keyed by `sha1(file_path)[:16]` — identical to
/// PeekServer. Because both tools index the same files at the same paths, a thumbnail PeekServer
/// already warmed loads instantly from the local SSD instead of re-reading the original off slow
/// or remote storage (e.g. the REDONE archive). Falls back to QuickLook on a miss, so it degrades
/// cleanly where that cache doesn't exist.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSURL, NSImage>()

    /// PeekServer's on-disk thumbnail cache (sharded by the first 2 chars of the id; 512px JPEGs).
    private let sharedThumbDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/PeekServer/thumbs", isDirectory: true)
    private let sharedThumbMaxPx: CGFloat = 512

    private init() {
        cache.countLimit = 1000   // larger window so fast scrolling a big grid re-decodes less
    }

    /// The shared-cache id for a file path — must match PeekServer's `sha1(path)[:16]`.
    static func sharedThumbID(forPath path: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(path.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// Best available thumbnail for `url` at `size` points. Returns nil if the file is gone
    /// or QuickLook can't render it. Cached by URL (keyed including the requested size so a
    /// grid thumb and a larger preview don't collide).
    func thumbnail(for url: URL, size: CGSize, scale: CGFloat = 2.0) async -> NSImage? {
        let key = NSURL(string: "\(url.absoluteString)#\(Int(size.width))x\(Int(size.height))")
            ?? (url as NSURL)
        if let cached = cache.object(forKey: key) { return cached }

        // Reuse PeekServer's warmed thumbnail when the request fits within its 512px cache —
        // a local SSD read instead of generating from the (possibly slow/remote) original.
        if max(size.width, size.height) * scale <= sharedThumbMaxPx,
           let shared = loadSharedThumb(for: url) {
            cache.setObject(shared, forKey: key)
            return shared
        }

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

    private func sharedThumbURL(for url: URL) -> URL {
        let id = Self.sharedThumbID(forPath: url.path)
        return sharedThumbDir.appendingPathComponent(String(id.prefix(2)), isDirectory: true)
                             .appendingPathComponent(id + ".jpg")
    }

    private func loadSharedThumb(for url: URL) -> NSImage? {
        let p = sharedThumbURL(for: url)
        guard FileManager.default.fileExists(atPath: p.path) else { return nil }
        return NSImage(contentsOf: p)
    }

    /// Drop a single entry (e.g. after a file is deleted from disk).
    func invalidate(_ url: URL) {
        // Size is part of the key, so clear the whole cache pragmatically when asked to
        // invalidate — entries are cheap to regenerate and deletions are infrequent.
        cache.removeAllObjects()
    }
}
