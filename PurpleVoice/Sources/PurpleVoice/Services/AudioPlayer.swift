import Foundation
import AVFoundation
import Combine

/// Single-stream playback wrapper used by `ClipDetailView`. Holds at
/// most one `AVAudioPlayer` instance — starting a second playback
/// stops the first. Publishes `isPlaying`, `nowPlayingURL`, and
/// `currentTime` (updated on a display-link-style timer while playing)
/// so SwiftUI can render the play/stop button + waveform playhead.
///
/// v0.2: supports A/B swap. `swap(to:)` switches the active stream to
/// a different URL while preserving the current playback offset and
/// play/pause state — letting the user toggle between original and
/// cleaned audio mid-listen.
@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var nowPlayingURL: URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var delegate: PlayerDelegate?
    private var tickTimer: Timer?

    /// Scrub-lifecycle state. Snapshotted on `beginScrub()` so that
    /// `endScrub()` can decide whether to resume playback. Continuous
    /// `scrubSeek(to:)` updates between begin and end are visual-only
    /// (no audio bursts), which is what the user wants while
    /// dragging the playhead.
    private var isScrubbing: Bool = false
    private var wasPlayingBeforeScrub: Bool = false

    func play(url: URL, at offset: TimeInterval = 0) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            let d = PlayerDelegate { [weak self] in
                Task { @MainActor in self?.handleFinished() }
            }
            p.delegate = d
            p.prepareToPlay()
            if offset > 0 && offset < p.duration {
                p.currentTime = offset
            }
            p.play()
            self.player = p
            self.delegate = d
            self.isPlaying = true
            self.nowPlayingURL = url
            self.duration = p.duration
            self.currentTime = p.currentTime
            startTicker()
        } catch {
            NSLog("[AudioPlayer] failed to play \(url.path): \(error)")
            self.isPlaying = false
            self.nowPlayingURL = nil
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        player?.stop()
        player = nil
        delegate = nil
        isPlaying = false
        nowPlayingURL = nil
        currentTime = 0
    }

    func toggle(url: URL) {
        if isPlaying && nowPlayingURL == url {
            stop()
        } else {
            play(url: url)
        }
    }

    /// Begin a DAW-style scrub gesture. Audio keeps playing so the
    /// user hears the content under the playhead, but the visual
    /// position is now owned entirely by `scrubSeek(to:)` calls — the
    /// background ticker that normally drives the playhead from
    /// `player.currentTime` is suspended for the duration of the
    /// scrub. Without that suspension, holding the drag still while
    /// the player keeps advancing makes the playhead lurch toward
    /// the end of the clip; whenever the drag fires next, it snaps
    /// back. Suspending the ticker keeps the playhead locked to the
    /// drag position, which is what users coming from Logic /
    /// Pro Tools expect.
    func beginScrub(url: URL? = nil) {
        guard !isScrubbing else { return }
        // Make sure SOMETHING is loaded — click-to-seek before play
        // needs us to attach to the source URL first so the playhead
        // has a duration to scrub against.
        if player == nil, let url {
            seek(to: 0, url: url)
        }
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        // Freeze the visual-update ticker. `currentTime` will only
        // change via explicit `scrubSeek(to:)` calls until endScrub.
        tickTimer?.invalidate()
        tickTimer = nil
        // Always make audio audible during the scrub even if the user
        // wasn't playing before — that's the standard DAW behaviour
        // (transport-off scrub still produces audio under the playhead).
        if let p = player, !p.isPlaying {
            p.play()
            isPlaying = true
        }
    }

    /// Move the playhead during a scrub. Sets the player's
    /// `currentTime` so audio plays from the new position, AND
    /// updates the published `currentTime` directly so the SwiftUI
    /// playhead snaps to the drag location instead of waiting on the
    /// (now-suspended) ticker.
    func scrubSeek(to offset: TimeInterval) {
        guard let p = player else { return }
        let clamped = max(0, min(offset, max(p.duration - 0.01, 0)))
        p.currentTime = clamped
        currentTime = clamped
    }

    /// Finish a scrub. Restores the pre-scrub play/pause state: if
    /// the user wasn't playing before, we pause again (we started
    /// audio in `beginScrub` to make the scrub audible). The visual
    /// ticker resumes so the playhead tracks playback again.
    func endScrub() {
        guard isScrubbing else { return }
        let resume = wasPlayingBeforeScrub
        isScrubbing = false
        wasPlayingBeforeScrub = false
        if let p = player {
            if !resume {
                p.pause()
                isPlaying = false
            } else {
                // Still playing — restart the ticker so the playhead
                // tracks the player's natural advancement again.
                startTicker()
            }
        }
    }

    /// Seek to an offset in seconds. Preserves play/pause state — if
    /// nothing is loaded yet, starts paused at the requested offset
    /// against `url` (call sites that don't know the URL pass nil and
    /// the seek is ignored). One-shot seeks (e.g., a single tap on the
    /// waveform with no drag) should use `beginScrub()` →
    /// `scrubSeek(to:)` → `endScrub()` instead for the no-audio-burst
    /// behavior; this `seek` is kept for callers that want the old
    /// "jump and keep playing if playing" semantics.
    func seek(to offset: TimeInterval, url: URL? = nil) {
        // Mid-playback / mid-pause seek on the currently-loaded player.
        if let p = player {
            let clamped = max(0, min(offset, max(p.duration - 0.01, 0)))
            p.currentTime = clamped
            currentTime = clamped
            return
        }
        // Nothing loaded yet — if the caller gave us a URL, load it
        // paused at the requested offset so a subsequent toggle()
        // resumes from there.
        guard let url else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            let d = PlayerDelegate { [weak self] in
                Task { @MainActor in self?.handleFinished() }
            }
            p.delegate = d
            p.prepareToPlay()
            let clamped = max(0, min(offset, max(p.duration - 0.01, 0)))
            p.currentTime = clamped
            self.player = p
            self.delegate = d
            self.nowPlayingURL = url
            self.duration = p.duration
            self.currentTime = clamped
            self.isPlaying = false
        } catch {
            NSLog("[AudioPlayer] seek-load failed for \(url.path): \(error)")
        }
    }

    /// Swap the active stream to `url`, preserving the current
    /// playback offset and play/pause state. If nothing is playing, no
    /// playback is started (the caller should follow with `play(url:)`
    /// or `toggle(url:)`).
    func swap(to url: URL) {
        guard let p = player else {
            // Nothing playing — set the latched URL so the UI shows
            // the right "now playing" label and the next `toggle()`
            // can decide what to do.
            return
        }
        let wasPlaying = p.isPlaying
        let offset = p.currentTime
        if wasPlaying {
            play(url: url, at: offset)
        } else {
            // Was paused — load the new URL, seek, hold.
            stop()
            do {
                let newP = try AVAudioPlayer(contentsOf: url)
                newP.prepareToPlay()
                if offset > 0 && offset < newP.duration {
                    newP.currentTime = offset
                }
                self.player = newP
                self.nowPlayingURL = url
                self.duration = newP.duration
                self.currentTime = newP.currentTime
                self.isPlaying = false
            } catch {
                NSLog("[AudioPlayer] swap failed for \(url.path): \(error)")
            }
        }
    }

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }

    private func handleFinished() {
        tickTimer?.invalidate()
        tickTimer = nil
        isPlaying = false
        nowPlayingURL = nil
        currentTime = 0
    }

    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }
}
