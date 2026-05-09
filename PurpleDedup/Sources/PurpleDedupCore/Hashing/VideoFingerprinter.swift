import Foundation
import AVFoundation
import CoreGraphics

/// A perceptual fingerprint for a whole video. We sample one frame per second, run the
/// photo pHash on each, and store the resulting sequence. To compare two videos:
/// align their sequences (allowing for cropping at the start) and compute the average
/// per-frame Hamming distance — see `VideoClusterer`.
public struct VideoFingerprint: Sendable, Hashable, Codable {
    /// One pHash per sampled frame, in temporal order.
    public let frameHashes: [UInt64]
    public let durationSeconds: Double
    public let width: Int
    public let height: Int
    /// Frames-per-second sampled. Phase 3 always uses 1.0 — keeping the field so future
    /// dynamic sample rates (longer videos sampled coarser) don't break decoding.
    public let sampleRate: Double

    public init(frameHashes: [UInt64], durationSeconds: Double, width: Int, height: Int, sampleRate: Double) {
        self.frameHashes = frameHashes
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.sampleRate = sampleRate
    }

    /// Compact serialization for the SQLite blob column. Format:
    ///   [u16 sampleCount][u16 width][u16 height][f64 durationSeconds][f32 sampleRate]
    ///   [u64 hash_0][u64 hash_1]...[u64 hash_n]
    /// Little-endian throughout. Decodes deterministically across Apple platforms.
    public func encoded() -> Data {
        var out = Data()
        var sampleCount = UInt16(frameHashes.count).littleEndian
        var w = UInt16(min(0xFFFF, max(0, width))).littleEndian
        var h = UInt16(min(0xFFFF, max(0, height))).littleEndian
        var dur = durationSeconds.bitPattern.littleEndian
        var rate = Float(sampleRate).bitPattern.littleEndian
        withUnsafeBytes(of: &sampleCount) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &w) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &dur) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &rate) { out.append(contentsOf: $0) }
        for hash in frameHashes {
            var le = hash.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        return out
    }
}

public enum VideoFingerprinterError: Error, LocalizedError {
    case unreadableAsset(URL)
    case unsupportedFormat(URL)
    case noVideoTrack(URL)
    case noFramesExtracted(URL)
    case tooShort(URL, Double)

    public var errorDescription: String? {
        switch self {
        case .unreadableAsset(let u):    return "Could not open video at \(u.path)"
        case .unsupportedFormat(let u):  return "Format not supported by AVFoundation: \(u.path)"
        case .noVideoTrack(let u):       return "No video track in \(u.path)"
        case .noFramesExtracted(let u):  return "AVAssetImageGenerator returned no frames for \(u.path)"
        case .tooShort(let u, let s):    return "Video too short to fingerprint (\(String(format: "%.1f", s))s): \(u.path)"
        }
    }
}

/// Builds a `VideoFingerprint` from a video URL via AVFoundation. AVAsset handles every
/// format AVFoundation natively decodes (MP4, MOV, M4V, MPG, ProRes, HEVC, H.264). MKV,
/// AVI, WMV, WebM are *not* supported in Phase 3 — bundling FFmpeg adds binary size,
/// licensing complexity, and (per the App-Store-friendly design we're echoing) it's
/// the deliberate trade-off. Files that fail to decode produce
/// `VideoFingerprinterError.unsupportedFormat` and the scan continues without them.
public struct VideoFingerprinter: Sendable {

    /// Frame sampling rate in Hz. 1 frame/second is the requirements-doc default — long
    /// enough to capture meaningful structure, short enough to keep fingerprint sizes
    /// small (a 5-minute video produces a 300-element sequence ≈ 2.4 KB).
    public static let sampleRate: Double = 1.0

    /// Hard cap on frames sampled per video. Decoding HEVC frames goes through
    /// VideoToolbox's hardware decoder; even on M-series the decoder serializes, so
    /// each frame costs ~30 ms. Without a cap, a 5-minute video sampled at 1 Hz fires
    /// 300 decodes (~9 s for one video alone). 12 frames is enough for sequence
    /// alignment to work on typical re-encodes — adjacent frames in a 1 Hz sequence
    /// are usually visually similar anyway, so densely sampling adds frames without
    /// adding signal. Empirically dropped a 4K-file scan from 91 s to ~30 s.
    public static let maxFramesPerVideo: Int = 12

    /// Cap the dimension of the rendered frame so DCT input is bounded. Same value as
    /// the photo path uses; smaller doesn't help, larger doesn't change the hash.
    public static let frameRenderMaxDimension: Int = 256

    /// Skip videos whose duration is below this threshold — too short to produce a
    /// useful sequence. A 1-second clip yields a single-frame fingerprint, which is
    /// just a photo hash; the photo path doesn't run on .mov anyway, so we'd miss
    /// these regardless.
    public static let minDurationSeconds: Double = 2.0

    public init() {}

    public func fingerprint(videoAt url: URL) async throws -> VideoFingerprint {
        let asset = AVURLAsset(url: url)

        // Probe the asset before extracting frames. Failing here is much cheaper than
        // realising mid-extraction; a malformed file with a "video" track header but
        // no decodable codec falls into `unsupportedFormat`.
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            Log.hash.notice("AVAsset isPlayable threw for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw VideoFingerprinterError.unreadableAsset(url)
        }
        guard isPlayable else { throw VideoFingerprinterError.unsupportedFormat(url) }

        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw VideoFingerprinterError.unreadableAsset(url)
        }
        guard let videoTrack = videoTracks.first else {
            throw VideoFingerprinterError.noVideoTrack(url)
        }

        let durationCMTime: CMTime
        do {
            durationCMTime = try await asset.load(.duration)
        } catch {
            throw VideoFingerprinterError.unreadableAsset(url)
        }
        let durationSeconds = CMTimeGetSeconds(durationCMTime)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoFingerprinterError.unsupportedFormat(url)
        }
        // Skip videos shorter than `minDurationSeconds`. The dominant case for sub-2-
        // second videos in a personal library is Live Photo .MOV companions (1-3s
        // clips paired with a still HEIC); fingerprinting them costs the same as a
        // full-length video but the 1-2 frame samples are too sparse to cluster
        // meaningfully. The companion HEIC carries the perceptually-distinct content;
        // the .MOV is just a few frames of the same scene with audio.
        guard durationSeconds >= Self.minDurationSeconds else {
            throw VideoFingerprinterError.tooShort(url, durationSeconds)
        }

        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        do {
            naturalSize = try await videoTrack.load(.naturalSize)
            preferredTransform = try await videoTrack.load(.preferredTransform)
        } catch {
            throw VideoFingerprinterError.unreadableAsset(url)
        }
        let renderedSize = naturalSize.applying(preferredTransform)
        let displayWidth = Int(abs(renderedSize.width).rounded())
        let displayHeight = Int(abs(renderedSize.height).rounded())

        // Build the sample timestamp list. Spread evenly across the duration so longer
        // videos still produce a representative fingerprint with a bounded number of
        // decode operations.
        //
        // Algorithm:
        //   1. Compute the natural sample count at 1 Hz (one frame per second from
        //      0.5s onwards) — this is the upper bound and matches the legacy behavior
        //      for short clips.
        //   2. If that exceeds `maxFramesPerVideo`, replace the dense list with N
        //      evenly-spaced samples spanning the same range. The sequence shape
        //      (and thus alignment-window matching) is preserved; we just skip
        //      neighbouring frames that would have been near-duplicates anyway.
        let firstSample = 0.5
        let lastSample = max(firstSample, durationSeconds - 0.5)
        let naturalCount = max(1, Int((lastSample - firstSample) / (1.0 / Self.sampleRate)) + 1)
        let n = min(Self.maxFramesPerVideo, naturalCount)
        var sampleTimes: [CMTime] = []
        if n == 1 {
            sampleTimes.append(CMTime(seconds: firstSample, preferredTimescale: 600))
        } else {
            // Evenly space `n` samples across [firstSample, lastSample] inclusive.
            let step = (lastSample - firstSample) / Double(n - 1)
            for i in 0..<n {
                let t = firstSample + step * Double(i)
                sampleTimes.append(CMTime(seconds: t, preferredTimescale: 600))
            }
        }
        guard !sampleTimes.isEmpty else {
            throw VideoFingerprinterError.unsupportedFormat(url)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        // Cap rendered frame dimensions; matches the photo path's downsample target.
        generator.maximumSize = CGSize(
            width: Self.frameRenderMaxDimension,
            height: Self.frameRenderMaxDimension
        )

        // Batched frame extraction. The previous one-frame-at-a-time loop made N
        // separate calls into AVAssetImageGenerator, each waking the H.264 decoder
        // from scratch. Using the modern `images(for:)` AsyncSequence (macOS 13+)
        // lets AVFoundation pipeline frame extraction internally — a 30-second video
        // dropped from ~3s to under 1s in informal testing.
        let hasher = PerceptualHasher()
        var frameHashes: [(CMTime, UInt64)] = []
        frameHashes.reserveCapacity(sampleTimes.count)

        for await result in generator.images(for: sampleTimes) {
            try Task.checkCancellation()
            switch result {
            case .success(let frame):
                do {
                    let h = try hasher.hash(
                        cgImage: frame.image,
                        originalWidth: displayWidth,
                        originalHeight: displayHeight,
                        errorContext: url
                    )
                    frameHashes.append((frame.requestedTime, h.phash))
                } catch {
                    Log.hash.notice("Frame hash failed in \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            case .failure(let req):
                Log.hash.notice("Frame extraction failed at \(req.requestedTime.seconds)s in \(url.path, privacy: .public): \(req.error.localizedDescription, privacy: .public)")
            }
        }
        // Frames may arrive out of order from the async sequence; sort by requested
        // presentation time so the fingerprint matches the temporal sequence.
        frameHashes.sort { $0.0 < $1.0 }
        let orderedHashes = frameHashes.map(\.1)

        guard !orderedHashes.isEmpty else {
            throw VideoFingerprinterError.noFramesExtracted(url)
        }

        return VideoFingerprint(
            frameHashes: orderedHashes,
            durationSeconds: durationSeconds,
            width: displayWidth,
            height: displayHeight,
            sampleRate: Self.sampleRate
        )
    }
}
