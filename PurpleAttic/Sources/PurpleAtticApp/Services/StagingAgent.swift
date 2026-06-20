import Foundation
import PurpleAtticCore

/// The headless companion to the nightly CLI archive. The CLI (`pattic export`) archives, verifies,
/// and writes the purge **manifest** — but it deliberately cannot touch Photos. So when auto-stage
/// is enabled it launches the GUI app with `--stage-agent`; this runs that mode: it reads the fresh
/// manifest and moves the verified-deletable photos into the "To Delete" album (a **non-destructive**
/// PhotoKit album-add — no macOS confirmation, safe unattended), records an audit entry, and quits.
///
/// It NEVER deletes. The only way photos leave the library is the user emptying that album in Photos.
enum StagingAgent {

    /// Manifest older than this is refused — the agent must act only on a plan that still reflects
    /// the library/archive. In practice the manifest is seconds old (the CLI launches us right after
    /// writing it); this wide bound just guards against a stale launch (e.g. app opened by hand).
    static let maxManifestAge: TimeInterval = 12 * 60 * 60

    /// Run the staging pass, then call `completion` (always, on the main queue) so the caller can
    /// terminate the app. Every early exit logs a reason to the dedicated stage-agent log.
    static func run(completion: @escaping () -> Void) {
        let logger = AtticLogger(runName: "stage-agent", echo: true)
        func finish(_ message: String) {
            logger.info(message)
            DispatchQueue.main.async { completion() }
        }

        logger.info("=== PurpleAttic stage-agent ===")

        // 1. Load the profile + the freshly-written manifest.
        guard let profile = try? ProfileStore.load(from: ProfileStore.defaultProfileURL()) else {
            finish("No profile found — nothing to stage."); return
        }
        guard profile.purgeEnabled, profile.purgeAutoStage else {
            finish("Auto-stage is not enabled in the profile — exiting."); return
        }
        guard let manifest = PurgeManifestStore.read() else {
            finish("No purge manifest found — nothing to stage."); return
        }
        if manifest.isStale(asOf: Date(), maxAge: maxManifestAge) {
            finish("Purge manifest is stale (computed \(manifest.computedAt)) — refusing to stage; the next archive run will refresh it.")
            return
        }
        guard !manifest.items.isEmpty else {
            finish("Manifest has 0 verified-deletable photos — nothing to stage."); return
        }

        // 2. Re-confirm the ≥2-copy archive is still mounted (defense in depth — the manifest items
        //    were verified at plan time, but a drive could have detached since). If the primary or
        //    every mirror is gone, refuse: the safety guarantee behind the manifest no longer holds.
        let primaryReady = VolumeReadiness.destinationReady(profile.primaryDestination).ready
        let anyMirrorReady = profile.mirrorDestinations.contains { VolumeReadiness.destinationReady($0).ready }
        guard primaryReady && anyMirrorReady else {
            finish("Archive drive(s) not mounted (primary ready: \(primaryReady), a mirror ready: \(anyMirrorReady)) — refusing to stage.")
            return
        }

        // 3. Stage to the album (non-destructive; no confirmation). Batched, pause-on-busy, resumes.
        let uuids = manifest.items.map { $0.uuid }
        let album = AppState.toDeleteAlbumName
        logger.info("→ Staging \(uuids.count) verified-deletable photo(s) to “\(album)”…")
        PhotoKitPurger.stageToAlbum(
            uuids: uuids,
            albumName: album,
            status: { msg in logger.info("   \(msg)") }
        ) { result in
            switch result {
            case .success(let o):
                // Proportional byte estimate (stage doesn't free space, but record what was queued).
                let bytes = manifest.verifiedCount > 0
                    ? Int64(Double(manifest.verifiedBytes) * Double(o.added) / Double(manifest.verifiedCount))
                    : 0
                PurgeAuditStore.append(PurgeAuditRecord(
                    timestamp: Date(), trigger: .auto, action: .stage,
                    requested: o.requested, resolved: o.resolved, succeeded: o.added,
                    failed: max(0, o.resolved - o.added), bytes: bytes, album: o.albumName,
                    note: o.pausedOut ? "paused on busy library — re-run to stage the rest" : nil))
                finish("← Staged \(o.added)/\(o.requested) photo(s) to “\(o.albumName)”. Delete them in Photos when ready. Done.")
            case .failure(let error):
                PurgeAuditStore.append(PurgeAuditRecord(
                    timestamp: Date(), trigger: .auto, action: .stage,
                    requested: uuids.count, resolved: 0, succeeded: 0, failed: 0,
                    bytes: 0, album: album, note: "failed: \(error.localizedDescription)"))
                finish("← Staging failed: \(error.localizedDescription)")
            }
        }
    }
}
