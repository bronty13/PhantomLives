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
    /// Decoded screen-size display images (remote Preview mode). Few but large — small count cap.
    private let displayCache = NSCache<NSString, NSImage>()
    /// In-flight remote fetches keyed by cache key, so actor reentrancy across the network await
    /// can't start a second identical download (two grid cells asking for the same id, or a
    /// prefetch racing the on-screen load, coalesce onto one request).
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    /// Set in remote mode: thumbnails are fetched from PeekServer's `/thumb/<id>` instead of
    /// generated locally (the originals aren't on this Mac). nil ⇒ local QuickLook path.
    private var remoteProvider: PeekMediaProvider?
    func setRemoteProvider(_ provider: PeekMediaProvider?) { remoteProvider = provider }

    /// PeekServer's on-disk thumbnail cache (sharded by the first 2 chars of the id; 512px JPEGs).
    private let sharedThumbDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/PeekServer/thumbs", isDirectory: true)
    private let sharedThumbMaxPx: CGFloat = 512

    private init() {
        cache.countLimit = 1000   // larger window so fast scrolling a big grid re-decodes less
        displayCache.countLimit = 24
    }

    /// The shared-cache id for a file path — must match PeekServer's `sha1(path)[:16]`.
    static func sharedThumbID(forPath path: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(path.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// Thumbnail for a media file — the entry point cells/panels use. In remote mode it fetches
    /// PeekServer's cached `/thumb/<id>` JPEG; locally it falls through to the QuickLook path.
    func thumbnail(for file: MediaFile, size: CGSize, scale: CGFloat = 2.0) async -> NSImage? {
        if let provider = remoteProvider {
            return await remoteThumbnail(id: file.id, provider: provider, size: size)
        }
        return await thumbnail(for: file.fileURL, size: size, scale: scale)
    }

    /// Fetch + cache a PeekServer thumbnail by id. Keyed by id ONLY: the server has exactly one
    /// 512px JPEG per id, so keying by requested size (as before) re-downloaded identical bytes
    /// for the grid (160pt) and the detail panel (520pt) separately. Rides `PeekTransport
    /// .interactive`, whose disk URLCache persists the server's immutable-cache thumbs across
    /// launches — a relaunch no longer refetches the whole grid over Wi-Fi.
    private func remoteThumbnail(id: String, provider: PeekMediaProvider, size: CGSize) async -> NSImage? {
        let key = NSURL(string: "peek://\(id)")!
        if let cached = cache.object(forKey: key) { return cached }
        let taskKey = "thumb:\(id)"
        if let running = inflight[taskKey] { return await running.value }
        let task = Task<NSImage?, Never> {
            var req = URLRequest(url: provider.thumbURL(id: id))
            for (k, v) in provider.httpHeaders { req.setValue(v, forHTTPHeaderField: k) }
            guard let (data, resp) = try? await PeekTransport.interactive.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { return nil }
            return image
        }
        inflight[taskKey] = task
        let image = await task.value
        inflight[taskKey] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// Screen-size display image for the remote Preview pane: PeekServer's `/display/<id>`
    /// (~2048px JPEG, ~20× fewer bytes than the original), falling back to `/full` for
    /// non-images or a pre-0.7 server. In-flight-deduped so the next-item PREFETCH and the
    /// on-arrival load coalesce, and disk-cached by the interactive session's URLCache.
    func displayImage(for file: MediaFile, provider: PeekMediaProvider) async -> NSImage? {
        let key = "display:\(file.id)"
        if let cached = displayCache.object(forKey: key as NSString) { return cached }
        if let running = inflight[key] { return await running.value }
        let task = Task<NSImage?, Never> {
            for url in [provider.displayURL(id: file.id), provider.fullURL(id: file.id)] {
                var req = URLRequest(url: url)
                for (k, v) in provider.httpHeaders { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await PeekTransport.interactive.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let image = NSImage(data: data) {
                    return image
                }
            }
            return nil
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { displayCache.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Fire-and-forget warm of the NEXT item's display image, so advancing in Preview shows the
    /// photo instantly instead of starting its download on arrival.
    func prefetchDisplay(for file: MediaFile, provider: PeekMediaProvider) async {
        _ = await displayImage(for: file, provider: provider)
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
