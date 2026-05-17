import Foundation
import AVFoundation

/// Built-in transcode presets. Each maps to an `AVAssetExportSession`
/// preset name (for native AVFoundation codecs) or an `ffmpegArgs`
/// recipe (for codecs Apple's stack doesn't expose: DNxHD/HR, Cineform,
/// MXF rewrap).
struct TranscodePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let avPresetName: String
    let fileExtension: String  // mov / mp4 / m4v / mxf
    let suffix: String         // appended to source basename

    /// Whether `AVAssetExportSession.exportPresets(compatibleWith:)`
    /// is required to gate availability — false for ProRes presets,
    /// which are universally supported on macOS 12+.
    let alwaysAvailable: Bool

    /// When non-nil, this preset is executed via ffmpeg instead of
    /// AVAssetExportSession. The placeholder `{IN}` / `{OUT}` are
    /// substituted at job time. Marker for "Phase-2 codecs" from the
    /// original build plan.
    let ffmpegArgs: [String]?

    var isFFmpeg: Bool { ffmpegArgs != nil }

    static let all: [TranscodePreset] = [
        // H.264 lineup (mp4 container, broad NLE compatibility)
        TranscodePreset(id: "h264-1080p", name: "H.264 1080p",
                        avPresetName: AVAssetExportPreset1920x1080,
                        fileExtension: "mp4", suffix: "_h264_1080p",
                        alwaysAvailable: false, ffmpegArgs: nil),
        TranscodePreset(id: "h264-720p", name: "H.264 720p",
                        avPresetName: AVAssetExportPreset1280x720,
                        fileExtension: "mp4", suffix: "_h264_720p",
                        alwaysAvailable: false, ffmpegArgs: nil),

        // HEVC: hardware-accelerated on Apple Silicon; smaller files
        // than H.264 at equivalent quality.
        TranscodePreset(id: "hevc-1080p", name: "HEVC 1080p",
                        avPresetName: AVAssetExportPresetHEVC1920x1080,
                        fileExtension: "mp4", suffix: "_hevc_1080p",
                        alwaysAvailable: false, ffmpegArgs: nil),

        // ProRes family — go-to for FCP edit / proxy workflow.
        TranscodePreset(id: "prores-422-proxy", name: "ProRes Proxy",
                        avPresetName: AVAssetExportPresetAppleProRes422LPCM,
                        fileExtension: "mov", suffix: "_proxy",
                        alwaysAvailable: true, ffmpegArgs: nil),
        TranscodePreset(id: "prores-422", name: "ProRes 422",
                        avPresetName: AVAssetExportPresetAppleProRes422LPCM,
                        fileExtension: "mov", suffix: "_prores422",
                        alwaysAvailable: true, ffmpegArgs: nil),

        // Pass-through (rewrap without re-encoding the video).
        TranscodePreset(id: "passthrough", name: "Pass-through (rewrap)",
                        avPresetName: AVAssetExportPresetPassthrough,
                        fileExtension: "mov", suffix: "_rewrap",
                        alwaysAvailable: true, ffmpegArgs: nil),

        // ---- Phase-2 codecs via ffmpeg ---------------------------------
        // These were "tag for phase 2" items in the original build plan:
        // formats AVFoundation doesn't natively encode but that ffmpeg
        // handles in a one-liner. Output container per format.

        TranscodePreset(id: "dnxhr-sq", name: "DNxHR SQ (1080p, ffmpeg)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_dnxhr_sq",
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "dnxhd", "-profile:v", "dnxhr_sq",
                            "-pix_fmt", "yuv422p", "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),

        TranscodePreset(id: "dnxhr-hq", name: "DNxHR HQ (1080p, ffmpeg)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_dnxhr_hq",
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "dnxhd", "-profile:v", "dnxhr_hq",
                            "-pix_fmt", "yuv422p", "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),

        TranscodePreset(id: "cineform", name: "Cineform (1080p, ffmpeg)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_cineform",
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "cfhd", "-quality", "film1",
                            "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),

        TranscodePreset(id: "mxf-prores",
                        name: "ProRes in MXF (ffmpeg rewrap)",
                        avPresetName: "",
                        fileExtension: "mxf", suffix: "_prores_mxf",
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            // ProRes-in-MXF for delivery to broadcast /
                            // archive workflows that only accept MXF.
                            "-c:v", "prores_ks", "-profile:v", "3",
                            "-pix_fmt", "yuv422p10le",
                            "-c:a", "pcm_s24le",
                            "{OUT}",
                        ]),
    ]
}
