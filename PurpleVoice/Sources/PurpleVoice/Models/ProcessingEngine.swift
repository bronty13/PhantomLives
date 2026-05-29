import Foundation

/// Which denoise engine to use for the first (noise removal) stage of
/// processing. The enhancement chain (compression, limiter, loudness)
/// always runs through ffmpeg afterward — the engine choice only
/// affects how the noise is removed.
enum ProcessingEngine: String, CaseIterable, Identifiable, Codable {
    /// Pure ffmpeg pipeline: `afftdn` + optional `anlmdn`. Always
    /// available — ffmpeg is the hard runtime dependency.
    case ffmpegOnly

    /// Run DeepFilterNet (`deep-filter` Rust CLI) as a first pass to
    /// produce a denoised WAV, then hand off to ffmpeg for any
    /// enhancement, loudness normalization, and final encoding. The
    /// quality jump over `afftdn` on real-world voice noise is large.
    case deepFilterNet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ffmpegOnly:    return "ffmpeg (always available)"
        case .deepFilterNet: return "DeepFilterNet (best quality)"
        }
    }

    var blurb: String {
        switch self {
        case .ffmpegOnly:
            return "Classic FFT + non-local-means denoise. Fast, no extra install."
        case .deepFilterNet:
            return "Neural denoise; install `deep-filter` (cargo install deep_filter)."
        }
    }
}
