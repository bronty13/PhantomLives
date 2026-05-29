import Foundation
import Testing
import AVFoundation
@testable import PurpleVoice

@Suite("ClipProcessor + ProcessingQueue")
struct ClipProcessorTests {

    @Test("tail() returns the last N lines")
    func tailReturnsLastNLines() {
        let input = """
        line 1
        line 2
        line 3
        line 4
        line 5
        """
        let tail = ClipProcessor.tail(of: input, lines: 3)
        #expect(tail == "line 3\nline 4\nline 5")
    }

    @Test("tail() handles text shorter than requested length")
    func tailHandlesTextShorterThanRequestedLines() {
        let input = "only one line"
        let tail = ClipProcessor.tail(of: input, lines: 10)
        #expect(tail == "only one line")
    }

    @MainActor
    @Test("Queue de-dupes the same source URL")
    func queueDeDupesSameSourceURL() throws {
        let queue = ProcessingQueue()
        let settings = SettingsStore()
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PurpleVoice-dedupe-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempFile) }

        queue.ingest(urls: [tempFile, tempFile, tempFile], settings: settings)
        #expect(queue.clips.count == 1, "ingest must de-dupe by sourceURL")
    }

    @Test("Accepted extensions cover required formats, case-insensitive")
    func acceptedExtensionsContainsRequiredFormats() {
        for ext in ["m4a", "mp3", "wav", "mp4", "mov", "M4A", "MP3"] {
            #expect(ProcessingQueue.isAcceptedExtension(ext))
        }
        for ext in ["txt", "pdf", "jpg", ""] {
            #expect(!ProcessingQueue.isAcceptedExtension(ext))
        }
    }

    // MARK: - End-to-end (require ffmpeg)

    /// Process a 4-second synthetic clip with a 1.0–3.0s trim window
    /// and verify the output's duration is ~2.0s. Validates that
    /// `-ss`/`-to` are wired through the processor correctly.
    @Test("Trim window produces a shorter output of the expected duration")
    func trimProducesExpectedDuration() async throws {
        guard FFmpegLocator.find() != nil else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PVProcTrim-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let src = try await generateSine(seconds: 4, at: tempDir)
        let out = tempDir.appendingPathComponent("trimmed.wav")

        let clip = Clip(sourceURL: src)
        let options = ProcessingOptions(
            profile: .light,
            enhancementEnabled: false,
            engine: .ffmpegOnly,
            loudnessTarget: .none,
            deEsserEnabled: false,
            deClickerEnabled: false,
            preserveStereo: false,
            dereverbEnabled: false,
            outputFormat: .wav,
            deepFilterPathOverride: nil,
            trimStart: 1.0,
            trimEnd: 3.0
        )
        try await ClipProcessor().process(
            clip: clip,
            options: options,
            outputURL: out,
            progressHandler: { _ in }
        )

        let dur = try await CMTimeGetSeconds(
            AVURLAsset(url: out).load(.duration)
        )
        #expect(abs(dur - 2.0) < 0.1,
                "expected ~2s output for a 1-3s trim, got \(dur)s")
    }

    /// Verify that `preserveStereo: true` produces a 2-channel output
    /// and the default `false` produces mono.
    @Test("preserveStereo controls output channel count")
    func preserveStereoTogglesChannelCount() async throws {
        guard FFmpegLocator.find() != nil else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PVProcStereo-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let src = try await generateStereoSine(seconds: 1, at: tempDir)

        for (preserve, expectChannels) in [(false, 1), (true, 2)] {
            let out = tempDir.appendingPathComponent("out-\(preserve).wav")
            let options = ProcessingOptions(
                profile: .light,
                enhancementEnabled: false,
                engine: .ffmpegOnly,
                loudnessTarget: .none,
                deEsserEnabled: false,
                deClickerEnabled: false,
                preserveStereo: preserve,
                dereverbEnabled: false,
                outputFormat: .wav,
                deepFilterPathOverride: nil,
                trimStart: nil,
                trimEnd: nil
            )
            try await ClipProcessor().process(
                clip: Clip(sourceURL: src),
                options: options,
                outputURL: out,
                progressHandler: { _ in }
            )

            let asset = AVURLAsset(url: out)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let fd = try await tracks.first!.load(.formatDescriptions).first!
            let channels = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?
                .pointee.mChannelsPerFrame ?? 0
            #expect(Int(channels) == expectChannels,
                    "preserveStereo=\(preserve) expected \(expectChannels)ch, got \(channels)ch")
        }
    }

    // MARK: - Helpers

    private func generateSine(seconds: Int, at dir: URL) async throws -> URL {
        let dst = dir.appendingPathComponent("sine.wav")
        let ff = FFmpegLocator.find()!
        let p = Process()
        p.executableURL = ff
        p.arguments = ["-y",
                       "-f", "lavfi",
                       "-i", "sine=frequency=440:duration=\(seconds)",
                       "-ar", "48000", "-ac", "1",
                       dst.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return dst
    }

    private func generateStereoSine(seconds: Int, at dir: URL) async throws -> URL {
        let dst = dir.appendingPathComponent("stereo.wav")
        let ff = FFmpegLocator.find()!
        let p = Process()
        p.executableURL = ff
        p.arguments = ["-y",
                       "-f", "lavfi",
                       "-i", "sine=frequency=440:duration=\(seconds)",
                       "-f", "lavfi",
                       "-i", "sine=frequency=660:duration=\(seconds)",
                       "-filter_complex", "[0][1]amerge=inputs=2",
                       "-ar", "48000", "-ac", "2",
                       dst.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return dst
    }
}
