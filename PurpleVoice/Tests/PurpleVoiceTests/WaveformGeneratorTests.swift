import Foundation
import Testing
@testable import PurpleVoice

@Suite("WaveformGenerator")
struct WaveformGeneratorTests {

    /// Generate a short ffmpeg-produced sine + noise file, run it
    /// through the waveform generator, and confirm the bucket counts
    /// and normalization meet contract.
    @Test("Downsamples a real audio file to the requested bucket count")
    func generatesNormalizedPeaks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PVWGTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Find ffmpeg; skip the test gracefully if it's not on this
        // machine (run-tests.sh on a stripped CI runner).
        guard let ffmpeg = FFmpegLocator.find() else {
            return
        }

        let wav = tempDir.appendingPathComponent("source.wav")
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y",
                       "-f", "lavfi",
                       "-i", "sine=frequency=440:duration=1",
                       "-ar", "48000", "-ac", "1",
                       wav.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0, "ffmpeg sine generation failed")

        let result = try await WaveformGenerator.generate(url: wav,
                                                          targetPeaks: 500)
        #expect(result.minPeaks.count == 500)
        #expect(result.maxPeaks.count == 500)
        // Normalized: at least one bucket must hit ~1.0 (the peak).
        let topPeak = max(result.maxPeaks.max() ?? 0,
                          result.minPeaks.max() ?? 0)
        #expect(topPeak >= 0.99, "expected normalization to push the global peak to ~1.0; got \(topPeak)")
        // Sine wave never exceeds 1.0; all values must be in [0, 1].
        #expect(result.maxPeaks.allSatisfy { $0 >= 0 && $0 <= 1.0001 })
        #expect(result.minPeaks.allSatisfy { $0 >= 0 && $0 <= 1.0001 })
        #expect(result.sampleRate == 48000)
        #expect(result.totalSamples > 47000)  // ~1 sec at 48kHz, minus header padding
    }

    @Test("Cache round-trips a generated waveform")
    func cacheRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PVWGCacheTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fake = WaveformGenerator.Result(
            minPeaks: [0.1, 0.2, 0.3],
            maxPeaks: [0.4, 0.5, 0.6],
            sampleRate: 48000,
            totalSamples: 144000
        )
        // Plant a small fake source file so the key derivation has a
        // real path/size/mtime to hash.
        let src = tempDir.appendingPathComponent("source.wav")
        try Data([0x01, 0x02, 0x03]).write(to: src)

        let cacheDir = tempDir.appendingPathComponent("cache")
        let cache = WaveformCache(directory: cacheDir)
        await cache.store(fake, for: src)
        let loaded = await cache.load(for: src)
        #expect(loaded == fake, "cache must round-trip the result exactly")
    }
}
