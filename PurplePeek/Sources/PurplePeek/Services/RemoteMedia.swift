import AppKit
import Foundation

/// Cached answer to "is this file reachable as a real local file?" — the SMB-vs-HTTP policy
/// question every remote-mode media view asks.
///
/// The old pattern was a synchronous `FileManager.fileExists(atPath:)` at each ask-site, several
/// times per SwiftUI `body` evaluation, on the main thread. Against a healthy SMB mount that's a
/// network syscall per render; against a STALE mount (server rebooted, Wi-Fi dropped — the exact
/// mid-session failure) `stat` blocks for tens of seconds and the whole app beachballs.
///
/// This class answers from a per-VOLUME cache (`/Volumes/<name>` → reachable) that only ever
/// probes on a background queue: the first ask for an unknown volume returns `false` (pessimistic
/// → HTTP fallback, which always works) and kicks a probe; once the probe lands the answer flips
/// and stays stable until a mount/unmount notification or the TTL re-probe changes it. A hung
/// probe strands one background thread, never the UI.
///
/// Volume granularity is deliberate: per-file stats are exactly the per-render network I/O this
/// exists to remove, and a mounted volume implies the server's paths resolve on it. (It shares the
/// verbatim-path assumption of the SMB-direct design: a local volume that merely shares the
/// server volume's name still false-positives — pre-existing, documented in the audit.)
final class LocalReachability {
    static let shared = LocalReachability()

    private let lock = NSLock()
    private var reachableVolumes: [String: Bool] = [:]
    private var probedAt: [String: Date] = [:]
    private var probing: Set<String> = []
    private let ttl: TimeInterval = 30
    private let probeQueue = DispatchQueue(label: "purplepeek.reachability", qos: .utility)

    private init() {
        // Mounts changing is the one event that genuinely flips answers — drop the cache so the
        // next ask re-probes.
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.invalidate()
            }
        }
    }

    /// Cheap, synchronous, safe from any thread. Non-`/Volumes/` paths (classic local mode) are
    /// answered with a direct local-disk stat — the hang risk is network mounts, not the boot disk.
    func isReachable(_ path: String) -> Bool {
        guard let volume = Self.volumePrefix(of: path) else {
            return FileManager.default.fileExists(atPath: path)
        }
        lock.lock()
        let cached = reachableVolumes[volume]
        let stale = (probedAt[volume].map { Date().timeIntervalSince($0) > ttl }) ?? true
        lock.unlock()
        if stale { probe(volume) }
        return cached ?? false
    }

    /// Kick probes for the volumes of `paths` ahead of need (e.g. on root selection), so the
    /// SMB-vs-HTTP answer is already settled by the time a player builds its URL.
    func prime(_ paths: [String]) {
        for p in paths {
            if let v = Self.volumePrefix(of: p) { probe(v) }
        }
    }

    private func invalidate() {
        lock.lock()
        let known = Array(reachableVolumes.keys)
        reachableVolumes.removeAll()
        probedAt.removeAll()
        lock.unlock()
        for v in known { probe(v) }
    }

    private func probe(_ volume: String) {
        lock.lock()
        guard !probing.contains(volume) else { lock.unlock(); return }
        probing.insert(volume)
        lock.unlock()
        probeQueue.async { [weak self] in
            let ok = FileManager.default.fileExists(atPath: volume)   // may block on a stale mount — off-main by design
            guard let self else { return }
            self.lock.lock()
            self.reachableVolumes[volume] = ok
            self.probedAt[volume] = Date()
            self.probing.remove(volume)
            self.lock.unlock()
        }
    }

    /// "/Volumes/ROG_AIRY/a/b.jpg" → "/Volumes/ROG_AIRY"; nil for non-/Volumes paths.
    static func volumePrefix(of path: String) -> String? {
        let comps = path.split(separator: "/", omittingEmptySubsequences: true)
        guard comps.count >= 2, comps[0] == "Volumes" else { return nil }
        return "/Volumes/\(comps[1])"
    }
}

/// The two URLSessions remote mode runs on — replacing `URLSession.shared` everywhere.
///
/// Why not `.shared`: it has no disk cache worth mentioning (so the server's
/// `Cache-Control: immutable` thumb/display headers bought nothing), a 60 s request timeout (a
/// hung server parks a pool slot for a minute), and ONE 6-connection-per-host pool shared between
/// gigabyte original pulls and the thumbnails the user is actively waiting on.
enum PeekTransport {
    /// Small, latency-sensitive requests: thumbs, display images, JSON metadata, decision POSTs.
    /// Disk-backed URLCache makes the server's immutable/ETag headers persist across launches —
    /// a revisited thumb or display image is a local disk hit, not a Wi-Fi round trip.
    static let interactive: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.urlCache = URLCache(
            memoryCapacity: 64 << 20,
            diskCapacity: 512 << 20,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PurplePeek/PeekHTTP", isDirectory: true)
        )
        return URLSession(configuration: cfg)
    }()

    /// Whole-original transfers: QuickLook pre-downloads, import pulls. A separate session =
    /// a separate connection pool, so a 500 MB pull can never starve the interactive tier.
    static let bulk: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 900
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.urlCache = nil          // originals are cached as temp FILES by their consumers
        return URLSession(configuration: cfg)
    }()
}
