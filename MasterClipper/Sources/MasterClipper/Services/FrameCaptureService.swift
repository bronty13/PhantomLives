import Foundation
import AVFoundation
import AppKit
import MasterClipperCore

/// Pulls N still frames out of an MP4 using `AVAssetImageGenerator` and
/// writes them as PNGs into the production folder as
/// `<Title>_frame_01.png` … `<Title>_frame_NN.png`.
///
/// Frame 1 is sampled from the 1–9 s window so it usually catches the
/// title card. The remaining N-1 frames are randomly distributed across
/// the rest of the clip in evenly-sized segments — one frame per
/// segment — so coverage is uniform but picks aren't on a deterministic
/// grid.
///
/// The audit walks these files and lets the user pick which one is the
/// canonical thumbnail; the picked frame's filename is stored on the
/// clip's `thumbnailFilename` column. We deliberately do NOT write a
/// separate `<Title>.png` mirror — the chosen frame *is* the thumbnail.
@MainActor
enum FrameCaptureService {

    enum CaptureError: LocalizedError {
        case sourceMissing(String)
        case productionFolderMissing(String)
        case titleEmpty
        case durationUnknown
        case durationTooShort(Double)
        case frameGenerateFailed(timeSeconds: Double, underlying: String)
        case pngEncodeFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let p):              return "Source file not found: \(p)"
            case .productionFolderMissing(let p):    return "Production folder not found: \(p)"
            case .titleEmpty:                        return "Clip has no title — set the title and re-run"
            case .durationUnknown:                   return "Couldn't determine the clip's duration"
            case .durationTooShort(let s):           return "Clip is only \(String(format: "%.1f", s))s — too short to sample frames from"
            case .frameGenerateFailed(let t, let u): return "Frame at \(String(format: "%.1f", t))s failed: \(u)"
            case .pngEncodeFailed:                   return "Couldn't encode CGImage as PNG"
            case .writeFailed(let p):                return "Couldn't write \(p)"
            }
        }
    }

    struct Outcome {
        /// `<Title>_frame_NN.png` files, in capture order. Frame 01 is the
        /// title-card sample (1–9 s window); the rest are evenly-spaced
        /// random samples through the remainder of the clip.
        let framePaths: [String]
        /// Wall-clock seconds spent generating frames.
        let durationSeconds: TimeInterval

        var totalFrames: Int { framePaths.count }
    }

    /// Generate `numFrames` frames from `sourcePath` into `productionFolder`.
    /// `numFrames` is clamped to ≥ 1 — passing 0 still produces the title
    /// thumbnail but no `_frame_*` companions. Caller awaits the entire
    /// pass on a Task; AVAssetImageGenerator is fast enough that we don't
    /// need progress reporting for the typical 15-frame run.
    static func capture(
        sourcePath: String,
        productionFolder: String,
        title: String,
        numFrames: Int
    ) async throws -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else {
            throw CaptureError.sourceMissing(sourcePath)
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: productionFolder, isDirectory: &isDir), isDir.boolValue else {
            throw CaptureError.productionFolderMissing(productionFolder)
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw CaptureError.titleEmpty }

        let safeTitle = sanitize(trimmedTitle)
        let started = Date()

        let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
        let durationCMTime = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(durationCMTime)
        guard totalDuration.isFinite, totalDuration > 0 else {
            throw CaptureError.durationUnknown
        }
        // Below ~2s there's nowhere to sample multiple frames from.
        guard totalDuration >= 2.0 else {
            throw CaptureError.durationTooShort(totalDuration)
        }

        // Title-card window: 1 → min(9, duration). For very short clips
        // we clamp the upper bound so we never sample past EOF.
        let titleWindowEnd = min(9.0, totalDuration)
        let titleWindowStart = min(1.0, titleWindowEnd - 0.1)
        let titleTime = Double.random(in: titleWindowStart...titleWindowEnd)

        // Remaining N-1 frames: divide the rest of the clip into equal
        // segments, pick one random point per segment.
        let extras = max(0, numFrames - 1)
        var sampleTimes: [Double] = [titleTime]
        if extras > 0 {
            let segmentStart = titleWindowEnd
            let segmentTotal = max(0.1, totalDuration - segmentStart - 0.1)
            // -0.1 keeps us from sampling at the very last frame, which
            // some encoders won't return.
            let segLen = segmentTotal / Double(extras)
            for i in 0..<extras {
                let lo = segmentStart + Double(i) * segLen
                let hi = lo + segLen
                let t = Double.random(in: lo..<max(lo + 0.05, hi))
                sampleTimes.append(t)
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

        let timescale: CMTimeScale = 600

        var framePaths: [String] = []
        for (idx, t) in sampleTimes.enumerated() {
            let cm = CMTime(seconds: t, preferredTimescale: timescale)
            do {
                let cg = try await generator.image(at: cm).image
                let n = idx + 1
                let frameName = String(format: "%@_frame_%02d.png", safeTitle, n)
                let outPath = path(in: productionFolder, name: frameName)
                try writePNG(cg, to: outPath)
                framePaths.append(outPath)
            } catch let captureErr as CaptureError {
                throw captureErr
            } catch {
                throw CaptureError.frameGenerateFailed(timeSeconds: t, underlying: error.localizedDescription)
            }
        }

        return Outcome(
            framePaths: framePaths,
            durationSeconds: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Helpers

    private static func sanitize(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/",  with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":",  with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func path(in folder: String, name: String) -> String {
        (folder as NSString).appendingPathComponent(name)
    }

    private static func writePNG(_ cg: CGImage, to path: String) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.pngEncodeFailed
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw CaptureError.writeFailed(path)
        }
    }
}
