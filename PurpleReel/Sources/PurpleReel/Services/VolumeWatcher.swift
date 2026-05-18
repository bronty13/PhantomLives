import Foundation
import AppKit

/// Volume mount/unmount + filesystem-change observer.
///
/// Consumes the user's Settings → Devices toggles:
/// - `selectDeviceWhenConnected` — on mount, navigate to the new volume
///   root so the user lands there immediately.
/// - `autoDrilldownCameraMedia` — on mount of a volume that contains a
///   DCIM / AVCHD / PRIVATE folder at its top level, enable drilldown
///   on the volume root so the catalogue picks up every clip.
/// - `reactLocalDrives` / `reactRemovableDrives` / `reactNetworkDrives`
///   — gate the per-workspace-root FSEventStream so a workspace root
///   that lives on an unwatched drive class never auto-rescans when
///   its contents change.
///
/// One `FSEventStream` covers every enabled workspace root in a single
/// stream. The stream is rebuilt whenever the workspace set, the
/// react-toggles, or the mounted-volume set changes. Bursts of change
/// events coalesce into one rescan via a 5-second debounce.
final class VolumeWatcher {
    weak var appState: AppState?

    private var fsStream: FSEventStreamRef?
    private var observedRootPaths: [String] = []
    private var debounceWork: DispatchWorkItem?

    enum VolumeKind: String { case local, removable, network, unknown }

    @MainActor
    func start(appState: AppState) {
        self.appState = appState
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            self,
            selector: #selector(volumeDidMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(volumeDidUnmount(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        // Rebuild the stream when react-toggles flip in Settings so
        // the user doesn't have to relaunch.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        rebuildStream()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        stopStream()
    }

    // MARK: - Volume classification

    /// Map a URL's underlying volume to one of three buckets the
    /// Settings panel exposes. Apple's `URLResourceValues` returns
    /// `volumeIsLocal == false` for network mounts; among local mounts
    /// the removable / ejectable flag distinguishes USB sticks &
    /// SD cards from the boot disk.
    static func classify(_ url: URL) -> VolumeKind {
        let keys: Set<URLResourceKey> = [
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else {
            return .unknown
        }
        if v.volumeIsLocal == false { return .network }
        if v.volumeIsRemovable == true || v.volumeIsEjectable == true {
            return .removable
        }
        return .local
    }

    static func isWatched(_ url: URL,
                            defaults: UserDefaults = .standard) -> Bool {
        switch classify(url) {
        case .local:     return defaults.object(forKey: "reactLocalDrives")     as? Bool ?? true
        case .removable: return defaults.object(forKey: "reactRemovableDrives") as? Bool ?? true
        case .network:   return defaults.object(forKey: "reactNetworkDrives")   as? Bool ?? true
        case .unknown:   return false
        }
    }

    // MARK: - Mount / unmount

    @objc private func volumeDidMount(_ note: Notification) {
        guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        else { return }
        let kind = Self.classify(url)
        NSLog("[PurpleReel] volume mounted: \(url.path) kind=\(kind.rawValue)")
        Task { @MainActor [weak self] in
            self?.handleMounted(url)
        }
    }

    @MainActor
    private func handleMounted(_ url: URL) {
        let defaults = UserDefaults.standard
        // Offline-index reconnect (Kyno-parity row 57): if the
        // newly-mounted volume carries catalogue rows, repath them
        // under the new mount point (in case macOS appended " 2"
        // to the volume name to avoid a collision) and flip them
        // back to online.
        if let app = appState {
            let info = MediaScanner.resolveVolume(forPath: url.path)
            if let uuid = info.uuid {
                app.reconnectVolume(uuid: uuid, newRoot: url.path)
            }
            app.recomputeOnlinePaths()
        }
        // "Select device when connected" — navigate the user to the
        // new mount. We don't add it to the workspace; Kyno surfaces
        // it in the Devices pane and selects it there.
        if defaults.object(forKey: "selectDeviceWhenConnected") as? Bool ?? true {
            appState?.navigate(to: url.path)
        }
        // "Automatically turn on drilldown for camera media" — DCIM
        // (iPhone / GoPro / most cameras), AVCHD (Sony / Panasonic
        // consumer cams), PRIVATE/BPAV (broadcast). Cheap heuristic;
        // false positives just mean an unneeded recursive scan, no
        // catalogue corruption.
        let isCameraMedia = Self.looksLikeCameraMedia(url)
        if defaults.object(forKey: "autoDrilldownCameraMedia") as? Bool ?? true,
           isCameraMedia,
           let app = appState,
           !app.isDrilldownEnabled(forPath: url.path) {
            app.toggleDrilldown(forPath: url.path)
        }
        // Workflow-chain auto-trigger (row 66 stretch): when the
        // volume looks like camera media AND the user has at least
        // one chain flagged `runOnCameraMediaMount`, offer to run
        // it. Dialog-driven — never starts work without consent.
        if isCameraMedia, let app = appState {
            app.offerWorkflowChainOnMount(volumeURL: url)
        }
        // Newly-mounted volume might host a workspace root the user
        // pre-configured before the drive was attached — rebuild so
        // it's covered by FSEvents going forward.
        rebuildStream()
    }

    @objc private func volumeDidUnmount(_ note: Notification) {
        guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        else { return }
        NSLog("[PurpleReel] volume unmounted: \(url.path)")
        Task { @MainActor [weak self] in
            self?.rebuildStream()
            self?.appState?.recomputeOnlinePaths()
        }
    }

    /// Lightweight camera-card heuristic. Apple's DCF spec mandates
    /// `DCIM/` at the card root; Sony / Panasonic consumer formats add
    /// `AVCHD/`; XDCAM proxies add `XDROOT/`. We deliberately don't
    /// recurse — the directory listing is one syscall regardless of
    /// card size.
    private static func looksLikeCameraMedia(_ root: URL) -> Bool {
        let fm = FileManager.default
        let markers = ["DCIM", "AVCHD", "PRIVATE", "BPAV", "XDROOT"]
        for marker in markers {
            let candidate = root.appendingPathComponent(marker, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue {
                return true
            }
        }
        return false
    }

    // MARK: - FSEvents

    @objc private func defaultsDidChange() {
        // `UserDefaults.didChangeNotification` fires on EVERY defaults
        // write — far more often than we care about. Rebuilding the
        // stream is cheap if the candidate set is unchanged, so we
        // don't bother key-filtering here.
        Task { @MainActor [weak self] in
            self?.rebuildStream()
        }
    }

    @MainActor
    func rebuildStream() {
        guard let app = appState else { return }
        let candidates: [String] = app.workspaceRoots
            .filter { Self.isWatched($0) }
            .map { $0.path }
        // No-op if the set is unchanged — avoids tearing down a
        // healthy stream every time UserDefaults wiggles.
        if candidates == observedRootPaths { return }
        stopStream()
        observedRootPaths = candidates
        guard !candidates.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<VolumeWatcher>.fromOpaque(info)
                .takeUnretainedValue()
            watcher.eventCoalesced()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            candidates as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,   // FSEvents-level coalesce; we layer a debounce on top
            flags
        ) else {
            NSLog("[PurpleReel] FSEventStreamCreate failed for \(candidates)")
            return
        }
        FSEventStreamSetDispatchQueue(stream,
                                        DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        self.fsStream = stream
        NSLog("[PurpleReel] FSEventStream watching \(candidates)")
    }

    private func stopStream() {
        guard let stream = fsStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsStream = nil
        observedRootPaths = []
    }

    /// Coalesce a burst of FSEvents into one rescan ~5 seconds after
    /// the LAST event. Video editor saves and bulk copies can rip
    /// through hundreds of events in a few seconds; we don't want to
    /// rescan that many times.
    nonisolated private func eventCoalesced() {
        Task { @MainActor [weak self] in
            self?.debounceWork?.cancel()
            let work = DispatchWorkItem {
                Task { @MainActor [weak self] in
                    await self?.appState?.rescan()
                }
            }
            self?.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
        }
    }
}
