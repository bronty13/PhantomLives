import Foundation
import AVFoundation

/// Re-encodes an MP4 to a smaller `<Title>_reduced.mp4` companion using
/// AVFoundation's `AVAssetExportSession`. No ffmpeg dependency — Apple's
/// HEVC encoder ships with macOS and produces files roughly half the size
/// of the H.264 source for the same perceptual quality.
///
/// Strategy: pick the export preset whose declared file-size ceiling is
/// just under the configured threshold, run the export, and report the
/// resulting size. The HEVC presets gracefully clamp to the source's
/// dimensions, so we don't have to introspect the input.
///
/// Apple's per-preset size estimate is approximate — if the produced file
/// still exceeds the threshold, we step down one tier and re-export. Two
/// tiers is the practical limit (1920x1080 → 1280x720 → 960x540) before
/// quality starts visibly degrading; beyond that the user should reach
/// for a real encoder.
@MainActor
enum ClipReduceService {

    enum ReduceError: LocalizedError {
        case sourceMissing(String)
        case sourceNotMP4(String)
        case alreadyExists(String)
        case exportFailed(String)
        case noEncoderForAsset
        case stillTooLarge(Int64, Int64)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let p):     return "Source file not found: \(p)"
            case .sourceNotMP4(let p):      return "Source is not an MP4: \(p)"
            case .alreadyExists(let p):     return "Reduced file already exists: \(p) — delete it first to re-run"
            case .exportFailed(let s):      return "AVAssetExportSession failed: \(s)"
            case .noEncoderForAsset:        return "No HEVC export preset is compatible with this clip"
            case .stillTooLarge(let s, let t):
                let f = ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
                let tf = ByteCountFormatter.string(fromByteCount: t, countStyle: .file)
                return "Reduced output is \(f), still over the \(tf) threshold. Try a smaller preset or use a dedicated encoder."
            }
        }
    }

    struct Outcome {
        let outputURL: URL
        let outputSizeBytes: Int64
        let inputSizeBytes: Int64
        let presetUsed: String

        var ratio: Double {
            guard inputSizeBytes > 0 else { return 0 }
            return Double(outputSizeBytes) / Double(inputSizeBytes)
        }
    }

    /// Tier list, highest quality → most aggressive. AVFoundation only ships
    /// HEVC presets at the top end (HighestQuality, 1920x1080, 3840x2160) —
    /// for smaller resolutions we drop back to H.264 presets, which still
    /// give meaningful size reductions when the source is 1080p.
    /// Starts at HEVC-at-source-resolution (best quality-per-byte without
    /// down-rezzing) and steps down through H.264 resolution tiers.
    private static let presetTiers: [String] = [
        AVAssetExportPresetHEVCHighestQuality,
        AVAssetExportPreset1920x1080,
        AVAssetExportPreset1280x720,
        AVAssetExportPreset960x540,
    ]

    /// Async-throws style. Caller awaits the entire reduce on a background
    /// task; UI shows a spinner until the outcome is returned. Steps down
    /// presets internally if the first attempt is still over threshold.
    static func reduce(
        sourcePath: String,
        outputPath: String,
        thresholdBytes: Int64
    ) async throws -> Outcome {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourcePath) else {
            throw ReduceError.sourceMissing(sourcePath)
        }
        guard sourcePath.lowercased().hasSuffix(".mp4") else {
            throw ReduceError.sourceNotMP4(sourcePath)
        }
        if fm.fileExists(atPath: outputPath) {
            throw ReduceError.alreadyExists(outputPath)
        }

        let inputURL  = URL(fileURLWithPath: sourcePath)
        let outputURL = URL(fileURLWithPath: outputPath)
        let inputSize = (try? fm.attributesOfItem(atPath: sourcePath)[.size] as? NSNumber)?.int64Value ?? 0

        let asset = AVURLAsset(url: inputURL)
        let compatible = await AVAssetExportSession.compatibilityCheck(for: asset, presets: presetTiers)
        guard !compatible.isEmpty else {
            throw ReduceError.noEncoderForAsset
        }

        var lastError: Error?
        for preset in compatible {
            // If a previous attempt left a file behind, remove it so the export can start.
            try? fm.removeItem(at: outputURL)

            do {
                try await runExport(asset: asset, outputURL: outputURL, preset: preset)
                let outSize = (try? fm.attributesOfItem(atPath: outputPath)[.size] as? NSNumber)?.int64Value ?? 0
                if outSize <= thresholdBytes || preset == compatible.last {
                    if outSize > thresholdBytes {
                        // Last preset, still too big — surface what we got but with an error.
                        throw ReduceError.stillTooLarge(outSize, thresholdBytes)
                    }
                    return Outcome(
                        outputURL: outputURL,
                        outputSizeBytes: outSize,
                        inputSizeBytes: inputSize,
                        presetUsed: preset
                    )
                }
                // Over threshold — step down to the next preset.
            } catch {
                lastError = error
                // Try the next preset.
            }
        }

        throw lastError ?? ReduceError.exportFailed("All presets exhausted")
    }

    private static func runExport(asset: AVAsset, outputURL: URL, preset: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ReduceError.exportFailed("Could not create session for preset \(preset)")
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        switch session.status {
        case .completed:
            return
        case .failed:
            throw ReduceError.exportFailed(session.error?.localizedDescription ?? "unknown")
        case .cancelled:
            throw ReduceError.exportFailed("cancelled")
        default:
            throw ReduceError.exportFailed("unexpected status \(session.status.rawValue)")
        }
    }
}

// MARK: - Compat helpers

private extension AVAssetExportSession {
    /// Returns the subset of `presets` that the encoder reports as compatible
    /// for this asset. Concurrency-safe wrapper over the legacy callback API.
    static func compatibilityCheck(for asset: AVAsset, presets: [String]) async -> [String] {
        var out: [String] = []
        for p in presets {
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAssetExportSession.determineCompatibility(
                    ofExportPreset: p,
                    with: asset,
                    outputFileType: .mp4
                ) { result in
                    cont.resume(returning: result)
                }
            }
            if ok { out.append(p) }
        }
        return out
    }
}
