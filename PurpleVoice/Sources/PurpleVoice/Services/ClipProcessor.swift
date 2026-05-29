import Foundation
import AVFoundation

/// All the per-run inputs a clip needs to be processed. Bundled into a
/// struct so call-sites (queue, CLI) don't have to thread a dozen
/// individual parameters.
struct ProcessingOptions {
    var profile: ProcessingProfile
    var enhancementEnabled: Bool
    var engine: ProcessingEngine
    var loudnessTarget: LoudnessTarget
    var deEsserEnabled: Bool
    var deClickerEnabled: Bool
    var preserveStereo: Bool
    var dereverbEnabled: Bool
    var outputFormat: OutputFormat
    /// Optional override path for the `deep-filter` binary. `nil` /
    /// empty string means "let the locator search the standard paths."
    var deepFilterPathOverride: String?
    /// Trim window in seconds. Both bounds must be non-negative and
    /// `start < end`; the UI enforces this.
    var trimStart: Double?
    var trimEnd: Double?
    /// Per-filter tunables. `inherited` (default) means every
    /// parameter uses the profile-baked default.
    var tuning: FilterTuning = .inherited
}

/// Runs the processing pipeline against a clip and streams progress
/// back to the caller. Two-stage when the user picks DeepFilterNet:
///
///   source → deep-filter → temp WAV → ffmpeg (enhancement + encode) → output
///
/// One-stage otherwise:
///
///   source → ffmpeg (denoise + enhancement + encode) → output
actor ClipProcessor {

    func process(clip: Clip,
                 options: ProcessingOptions,
                 outputURL: URL,
                 progressHandler: @escaping @Sendable (Double) -> Void) async throws {

        guard let ffmpegURL = FFmpegLocator.find() else {
            throw ClipProcessorError.ffmpegNotFound
        }

        // Inspect source for duration → progress denominator.
        let asset = AVURLAsset(url: clip.sourceURL)
        let durationSeconds: Double
        do {
            let d = try await asset.load(.duration)
            durationSeconds = CMTimeGetSeconds(d)
        } catch {
            durationSeconds = 0
        }
        await MainActor.run { clip.durationSeconds = durationSeconds > 0 ? durationSeconds : nil }

        // Effective duration honors the trim window so the progress
        // bar tracks the slice we're actually rendering.
        let trimSpan: Double = {
            guard durationSeconds > 0 else { return 0 }
            let start = options.trimStart ?? 0
            let end = options.trimEnd ?? durationSeconds
            return max(0, end - start)
        }()
        let progressDenominator = trimSpan > 0 ? trimSpan : durationSeconds

        // Stage 1: optional DeepFilterNet pass. Produces a denoised
        // WAV in a temp dir; ffmpeg picks it up as its input below.
        // Trim is applied here (before DFN) so we only denoise the
        // slice we care about — saves work on long inputs.
        var ffmpegInputURL = clip.sourceURL
        var ffmpegSkipDenoise = false
        var dfnCleanupURL: URL?

        if options.engine == .deepFilterNet {
            let dfnURL: URL
            if let found = DeepFilterNetLocator.find(
                override: options.deepFilterPathOverride
            ) {
                dfnURL = found
            } else {
                throw ClipProcessorError.deepFilterNotFound
            }
            let denoised = try await runDeepFilterNet(
                binaryURL: dfnURL,
                ffmpegURL: ffmpegURL,
                source: clip.sourceURL,
                options: options,
                progressHandler: { p in
                    // DFN is the first half of the run; map its
                    // internal progress (0–1) to 0–0.5 of the overall.
                    progressHandler(p * 0.5)
                }
            )
            ffmpegInputURL = denoised
            ffmpegSkipDenoise = true
            dfnCleanupURL = denoised
        }

        defer {
            if let url = dfnCleanupURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Stage 2: ffmpeg — enhancement + loudness + encode (and
        // denoise too, if Stage 1 was skipped).
        let chainOptions = FilterChainBuilder.Options(
            profile: options.profile,
            enhancementEnabled: options.enhancementEnabled,
            skipDenoise: ffmpegSkipDenoise,
            loudnessTarget: options.loudnessTarget,
            deEsserEnabled: options.deEsserEnabled,
            deClickerEnabled: options.deClickerEnabled,
            tuning: options.tuning
        )
        let chain = FilterChainBuilder.chain(options: chainOptions)

        // -ss before -i is fastest (seek by keyframe); -to caps end
        // time. When DFN already trimmed, skip these — its output WAV
        // is exactly the trimmed slice.
        var args: [String] = ["-y"]
        if !ffmpegSkipDenoise {
            if let start = options.trimStart, start > 0 {
                args.append(contentsOf: ["-ss", String(format: "%.3f", start)])
            }
            if let end = options.trimEnd {
                args.append(contentsOf: ["-to", String(format: "%.3f", end)])
            }
        }
        args.append(contentsOf: ["-i", ffmpegInputURL.path])
        args.append("-vn")                    // drop video for movie inputs
        args.append(contentsOf: ["-af", chain])
        args.append(contentsOf: ["-ar", "48000"])
        if !options.preserveStereo {
            args.append(contentsOf: ["-ac", "1"])
        }
        args.append(contentsOf: ["-progress", "pipe:1", "-nostats"])
        args.append(contentsOf: encoderArgs(for: options.outputFormat))
        args.append(outputURL.path)

        let isTwoStage = (options.engine == .deepFilterNet)
        let progressMap: @Sendable (Double) -> Void = { p in
            if isTwoStage {
                progressHandler(0.5 + p * 0.5)
            } else {
                progressHandler(p)
            }
        }

        try await runFFmpeg(
            ffmpegURL: ffmpegURL,
            args: args,
            durationSeconds: progressDenominator,
            progressHandler: progressMap
        )
    }

    // MARK: - DeepFilterNet stage

    /// Runs `deep-filter` against the source. DFN's CLI consumes any
    /// libsndfile-readable format directly, but on real Macs it tends
    /// to be flakier with compressed input — to keep the failure mode
    /// predictable we always feed it a 48kHz PCM WAV that ffmpeg
    /// produces from the source. That's one extra pass through ffmpeg
    /// in exchange for not having to special-case m4a / mp4 / mov.
    private func runDeepFilterNet(binaryURL: URL,
                                   ffmpegURL: URL,
                                   source: URL,
                                   options: ProcessingOptions,
                                   progressHandler: @escaping @Sendable (Double) -> Void)
        async throws -> URL {

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurpleVoice-DFN-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                withIntermediateDirectories: true)
        let prepWAV = tempDir.appendingPathComponent("input.wav")
        let outWAV  = tempDir.appendingPathComponent("output.wav")

        // 1a. Decode source → 48kHz PCM WAV. Honor trim here so DFN
        //     only processes the slice we care about.
        var decodeArgs: [String] = ["-y"]
        if let start = options.trimStart, start > 0 {
            decodeArgs.append(contentsOf: ["-ss", String(format: "%.3f", start)])
        }
        if let end = options.trimEnd {
            decodeArgs.append(contentsOf: ["-to", String(format: "%.3f", end)])
        }
        decodeArgs.append(contentsOf: ["-i", source.path,
                                       "-vn",
                                       "-ar", "48000"])
        if !options.preserveStereo {
            decodeArgs.append(contentsOf: ["-ac", "1"])
        }
        decodeArgs.append(contentsOf: ["-c:a", "pcm_s16le", prepWAV.path])

        try await runFFmpeg(ffmpegURL: ffmpegURL,
                             args: decodeArgs,
                             durationSeconds: 0,
                             progressHandler: { _ in })

        // 1b. Run DFN. Latest `deep-filter` CLIs accept positional
        //     input + `-o <path>`; older versions write next to the
        //     input. We pass both styles so either works.
        var dfnArgs = [prepWAV.path, "-o", outWAV.path]
        if options.dereverbEnabled {
            // DeepFilterNet's post-filter beta controls how aggressively
            // residual reverb/blur is suppressed. Higher = more dereverb,
            // at the cost of slight voice coloration. 0.05 is a safe
            // middle ground; the default ~0.02 lets reverb through.
            dfnArgs.append(contentsOf: ["--post-filter-beta", "0.05"])
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = dfnArgs

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stderrAccum = ConcurrentDataBuffer()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrAccum.append(chunk) }
        }
        // DFN doesn't emit machine-readable progress on stdout. Send
        // synthetic ticks so the UI doesn't appear frozen.
        let tickerTask = Task { [progressHandler] in
            var p: Double = 0.05
            while !Task.isCancelled {
                progressHandler(p)
                try? await Task.sleep(nanoseconds: 250_000_000)
                p = min(p + 0.02, 0.95)
            }
        }

        try process.run()
        await withTaskCancellationHandler {
            await waitForExit(process)
        } onCancel: {
            process.terminate()
        }
        tickerTask.cancel()
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let status = process.terminationStatus
        if status != 0 {
            let stderr = String(data: stderrAccum.snapshot, encoding: .utf8) ?? ""
            throw ClipProcessorError.deepFilterFailed(
                status: status,
                stderrTail: Self.tail(of: stderr, lines: 12)
            )
        }
        guard FileManager.default.fileExists(atPath: outWAV.path) else {
            throw ClipProcessorError.deepFilterFailed(
                status: status,
                stderrTail: "deep-filter exited cleanly but produced no output at \(outWAV.path)"
            )
        }
        try? FileManager.default.removeItem(at: prepWAV)
        progressHandler(1.0)
        return outWAV
    }

    // MARK: - ffmpeg stage

    private func runFFmpeg(ffmpegURL: URL,
                            args: [String],
                            durationSeconds: Double,
                            progressHandler: @escaping @Sendable (Double) -> Void)
        async throws {

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stderrAccum = ConcurrentDataBuffer()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrAccum.append(chunk) }
        }

        let progressTask = Task { [durationSeconds] in
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[..<nl]
                    buffer.removeSubrange(...nl)
                    guard let line = String(data: lineData, encoding: .utf8) else { continue }
                    if line.hasPrefix("out_time_us="),
                       let microStr = line.split(separator: "=").last.map(String.init),
                       let micro = Double(microStr),
                       durationSeconds > 0 {
                        let p = min(max(micro / 1_000_000 / durationSeconds, 0), 0.99)
                        progressHandler(p)
                    }
                }
            }
        }

        try process.run()
        await withTaskCancellationHandler {
            await waitForExit(process)
        } onCancel: {
            process.terminate()
        }
        progressTask.cancel()
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let status = process.terminationStatus
        if status != 0 {
            let stderr = String(data: stderrAccum.snapshot, encoding: .utf8) ?? ""
            throw ClipProcessorError.ffmpegFailed(
                status: status,
                stderrTail: Self.tail(of: stderr, lines: 12)
            )
        }
    }

    // MARK: - Helpers

    private func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
    }

    private func encoderArgs(for format: OutputFormat) -> [String] {
        switch format {
        case .m4a: return ["-c:a", "aac", "-b:a", "192k"]
        case .mp3: return ["-c:a", "libmp3lame", "-q:a", "2"]
        case .wav: return ["-c:a", "pcm_s16le"]
        }
    }

    /// Return the last `lines` lines of `text` for surfacing as an
    /// error tail in the UI. ffmpeg's stderr is verbose — the last
    /// few lines almost always contain the actionable bit.
    static func tail(of text: String, lines: Int) -> String {
        let split = text.split(omittingEmptySubsequences: false,
                                whereSeparator: { $0 == "\n" })
        let n = min(lines, split.count)
        return split.suffix(n).joined(separator: "\n")
    }

    /// Thread-safe `Data` accumulator used by `Process` readability
    /// handlers, which fire on a background queue and need a Sendable
    /// reference to mutate.
    private final class ConcurrentDataBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        func append(_ chunk: Data) {
            lock.lock()
            buffer.append(chunk)
            lock.unlock()
        }
        var snapshot: Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }
    }
}

enum ClipProcessorError: Error {
    case ffmpegNotFound
    case ffmpegFailed(status: Int32, stderrTail: String)
    case deepFilterNotFound
    case deepFilterFailed(status: Int32, stderrTail: String)

    var userMessage: String {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Install with `brew install ffmpeg`."
        case .ffmpegFailed(let status, let tail):
            return "ffmpeg exited \(status).\n\(tail)"
        case .deepFilterNotFound:
            return "DeepFilterNet not found. Install with `cargo install deep_filter`, then re-check in Settings → Advanced."
        case .deepFilterFailed(let status, let tail):
            return "deep-filter exited \(status).\n\(tail)"
        }
    }
}
