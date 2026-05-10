import Foundation
import CoreGraphics
import ImageIO

/// FFmpeg-based equivalent of `VideoFingerprinter` for formats AVFoundation
/// can't decode (MKV, AVI, WMV, WebM, etc.). Uses ffprobe for metadata and
/// ffmpeg to extract a small set of frames as PNGs into a temp directory,
/// then runs the same `PerceptualHasher` photo path the AVFoundation path
/// uses — so the resulting `VideoFingerprint`s are directly comparable.
///
/// **Why per-frame `-ss` invocations?** ffmpeg's `select` filter would
/// extract all frames in one decode pass, but we'd then have to write them
/// with predictable indices (`select=…,scale=…` keeps them numbered by
/// occurrence, not by source PTS). N short calls keeps the code simple and
/// each `-ss` before `-i` triggers a fast keyframe seek; for the 12-frame
/// cap the wall-time difference is in the hundreds of milliseconds.
public struct FFmpegFingerprinter: Sendable {
    public let probe: FFmpegProbe.Probe

    public init(probe: FFmpegProbe.Probe) {
        self.probe = probe
    }

    public func fingerprint(videoAt url: URL) async throws -> VideoFingerprint {
        let metadata = try probeMetadata(videoAt: url)
        guard metadata.duration >= VideoFingerprinter.minDurationSeconds else {
            throw VideoFingerprinterError.tooShort(url, metadata.duration)
        }

        // Same sample-time math as VideoFingerprinter so AVFoundation-decoded
        // and ffmpeg-decoded fingerprints of the same content cluster
        // together — we don't want a same-content match to fail just because
        // the fallback path produced a structurally different sequence.
        let firstSample = 0.5
        let lastSample = max(firstSample, metadata.duration - 0.5)
        let naturalCount = max(1, Int((lastSample - firstSample) / (1.0 / VideoFingerprinter.sampleRate)) + 1)
        let n = min(VideoFingerprinter.maxFramesPerVideo, naturalCount)
        var sampleTimes: [Double] = []
        if n == 1 {
            sampleTimes.append(firstSample)
        } else {
            let step = (lastSample - firstSample) / Double(n - 1)
            for i in 0..<n { sampleTimes.append(firstSample + step * Double(i)) }
        }

        let scratch = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let hasher = PerceptualHasher()
        var frameHashes: [(Double, UInt64)] = []
        for (idx, t) in sampleTimes.enumerated() {
            try Task.checkCancellation()
            let framePath = scratch.appendingPathComponent("frame_\(idx).png")
            do {
                try extractFrame(at: t, of: url, to: framePath)
            } catch {
                Log.hash.notice("FFmpeg frame extract failed at \(t)s in \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            do {
                let h = try hasher.hash(imageAt: framePath)
                frameHashes.append((t, h.phash))
            } catch {
                Log.hash.notice("FFmpeg frame hash failed at \(t)s in \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !frameHashes.isEmpty else {
            throw VideoFingerprinterError.noFramesExtracted(url)
        }

        // Already in time order; preserve.
        return VideoFingerprint(
            frameHashes: frameHashes.map(\.1),
            durationSeconds: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            sampleRate: VideoFingerprinter.sampleRate
        )
    }

    // MARK: - ffprobe

    private struct Metadata {
        let duration: Double
        let width: Int
        let height: Int
    }

    private func probeMetadata(videoAt url: URL) throws -> Metadata {
        // -v error                  silence unless real failure
        // -select_streams v:0       only the first video stream
        // -show_entries stream=...  pick the fields we need
        // -of json                  JSON is more reliable to parse than CSV
        let p = Process()
        p.executableURL = probe.ffprobeURL
        p.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height:format=duration",
            "-of", "json",
            url.path,
        ]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            throw VideoFingerprinterError.unreadableAsset(url)
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw VideoFingerprinterError.unsupportedFormat(url)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let format = json["format"] as? [String: Any],
            let durationStr = format["duration"] as? String,
            let duration = Double(durationStr),
            let streams = json["streams"] as? [[String: Any]],
            let stream = streams.first,
            let width = stream["width"] as? Int,
            let height = stream["height"] as? Int
        else {
            throw VideoFingerprinterError.unsupportedFormat(url)
        }
        return Metadata(duration: duration, width: width, height: height)
    }

    // MARK: - ffmpeg frame extraction

    private func extractFrame(at seconds: Double, of input: URL, to output: URL) throws {
        // -ss before -i triggers fast (keyframe) seek; the small mis-alignment
        // is fine for perceptual hashing where adjacent frames hash similarly.
        // -frames:v 1 stops after the first frame, -an drops audio entirely,
        // -y overwrites without prompting. -vf scale caps the rendered size
        // matching the photo path's downsample target.
        let p = Process()
        p.executableURL = probe.ffmpegURL
        p.arguments = [
            "-hide_banner", "-loglevel", "error",
            "-ss", String(format: "%.3f", seconds),
            "-i", input.path,
            "-frames:v", "1",
            "-an",
            "-vf", "scale='min(\(VideoFingerprinter.frameRenderMaxDimension),iw)':-2",
            "-y",
            output.path,
        ]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            throw VideoFingerprinterError.unreadableAsset(input)
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw VideoFingerprinterError.unsupportedFormat(input)
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw VideoFingerprinterError.noFramesExtracted(input)
        }
    }

    private func makeScratchDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PurpleDedup-FFmpeg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
