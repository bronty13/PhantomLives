import Foundation
import Testing
@testable import PurpleVoice

@Suite("AudioPlayer seek")
struct AudioPlayerTests {

    /// Generate a short sine WAV via ffmpeg, hand it to AudioPlayer,
    /// then seek and confirm `currentTime` reflects the new offset.
    /// AVAudioPlayer is a real-system resource so this skips
    /// gracefully when ffmpeg isn't installed.
    @MainActor
    @Test("seek(to:) updates currentTime against a loaded file")
    func seekUpdatesCurrentTime() async throws {
        guard let ffmpeg = FFmpegLocator.find() else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PVAPSeekTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let wav = tempDir.appendingPathComponent("sine.wav")

        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi",
                       "-i", "sine=frequency=440:duration=5",
                       "-ar", "48000", "-ac", "1", wav.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)

        let player = AudioPlayer()
        // No-op when nothing is loaded and no URL is provided.
        player.seek(to: 2.0)
        #expect(player.currentTime == 0)
        #expect(player.nowPlayingURL == nil)

        // Seek-load: attaches to the URL paused at the offset.
        player.seek(to: 2.0, url: wav)
        #expect(player.nowPlayingURL == wav)
        #expect(abs(player.currentTime - 2.0) < 0.05)
        #expect(player.isPlaying == false)

        // Subsequent seek without URL works against the loaded player.
        player.seek(to: 4.5)
        #expect(abs(player.currentTime - 4.5) < 0.05)

        // Seeking past the end clamps to just before duration.
        player.seek(to: 999)
        #expect(player.currentTime <= player.duration)
        #expect(player.currentTime > 0)
    }

    /// DAW-style scrub: audio stays audible during the drag, the
    /// playhead snaps to the drag position (not the player's
    /// auto-advanced time), and the pre-scrub play/pause state is
    /// restored on end. The auto-advance freeze is the crucial part —
    /// without it, holding the drag still while the player keeps
    /// advancing makes the playhead lurch toward the end of the clip
    /// between drag events, then snap back when the drag fires again.
    @MainActor
    @Test("Scrub lifecycle keeps audio audible and freezes the visual ticker")
    func scrubKeepsAudioAudibleAndFreezesTicker() async throws {
        guard let ffmpeg = FFmpegLocator.find() else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PVAPScrub-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let wav = tempDir.appendingPathComponent("sine.wav")

        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi",
                       "-i", "sine=frequency=440:duration=5",
                       "-ar", "48000", "-ac", "1", wav.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()

        let player = AudioPlayer()

        // Case 1: scrub from paused — audio plays during scrub, then
        // pauses again on end (back to pre-scrub state).
        player.seek(to: 1.0, url: wav)
        #expect(player.isPlaying == false)
        player.beginScrub()
        #expect(player.isPlaying == true,
                "beginScrub from paused must start audio so the scrub is audible")
        player.scrubSeek(to: 2.5)
        #expect(abs(player.currentTime - 2.5) < 0.05)
        player.endScrub()
        #expect(player.isPlaying == false,
                "endScrub from a was-paused scrub must restore the paused state")

        // Case 2: scrub from playing — stays playing throughout, and
        // the visual playhead follows the drag position even when we
        // wait long enough for the player to have auto-advanced past.
        player.play(url: wav, at: 0.5)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(player.isPlaying == true)
        player.beginScrub()
        #expect(player.isPlaying == true,
                "beginScrub on a playing player keeps audio audible")
        player.scrubSeek(to: 3.0)
        #expect(abs(player.currentTime - 3.0) < 0.05)
        // The crucial check: hold the scrub still for 250ms. With the
        // ticker frozen, `currentTime` must not have walked forward
        // to ~3.25 even though the audio is still playing.
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(abs(player.currentTime - 3.0) < 0.05,
                "while scrubbing, currentTime must not auto-advance from the player's playback (would cause the visual playhead to lurch toward the end)")
        player.endScrub()
        #expect(player.isPlaying == true,
                "endScrub from a was-playing scrub keeps playback going")
        player.stop()
    }

    @Test("normalize maps average-power dB onto a clamped 0…1 meter level")
    func normalizeMeterMapping() {
        // 0 dBFS = full scale; the -50 dB floor = silence; midpoint maps
        // halfway. Out-of-range and non-finite readings clamp safely.
        #expect(AudioPlayer.normalize(db: 0) == 1)
        #expect(AudioPlayer.normalize(db: -50) == 0)
        #expect(abs(AudioPlayer.normalize(db: -25) - 0.5) < 0.0001)
        #expect(AudioPlayer.normalize(db: 10) == 1, "above 0 dB clamps to full")
        #expect(AudioPlayer.normalize(db: -120) == 0, "below the floor clamps to silence")
        #expect(AudioPlayer.normalize(db: -.infinity) == 0, "−inf (true silence) reads as 0")
    }
}
