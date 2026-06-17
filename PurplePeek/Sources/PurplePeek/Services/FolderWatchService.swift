import Foundation

/// Watches a directory subtree for filesystem changes via **FSEvents** and fires a debounced
/// callback when files under it are added, removed, or renamed. PurplePeek uses this to
/// auto-rescan the selected scan root so the browser reflects what's actually on disk.
///
/// Why FSEvents (not a `DispatchSource` vnode source): a vnode source watches a single file
/// descriptor, so it can't see changes deep inside a tree. `FSEventStreamCreate` watches a
/// whole subtree, and its `latency` argument coalesces save-storms for us — so the "debounce"
/// is built in rather than hand-rolled.
///
/// Lifecycle is driven entirely from the main actor (`start`/`stop`); the C callback only
/// reads the immutable `onChange` closure, so there's no shared mutable state to race on.
final class FolderWatchService {

    /// Called (on a private dispatch queue) after a coalesced burst of changes. The closure is
    /// responsible for hopping to whatever actor it needs — keep it cheap and re-entrancy-safe.
    private let onChange: @Sendable () -> Void

    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private let queue = DispatchQueue(label: "com.phantomlives.purplepeek.folderwatch", qos: .utility)

    /// Coalescing window (seconds). Long enough to fold a Finder copy of many files into one
    /// callback, short enough that a refresh feels prompt.
    private let latency: CFTimeInterval = 1.5

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    /// Begin watching `path` (and its subtree). No-op if already watching that exact path.
    func start(path: String) {
        if watchedPath == path, stream != nil { return }
        stop()

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatchService>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        ) else {
            return
        }

        self.stream = stream
        self.watchedPath = path
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Stop watching and release the stream. Safe to call when not watching.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        self.watchedPath = nil
    }

    deinit { stop() }
}
