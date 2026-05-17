import Foundation
import AVFoundation

/// Built-in transcode presets. Each maps to an `AVAssetExportSession`
/// preset name plus an output file extension. Resolution downscale is
/// applied via the underlying preset (e.g. `1280x720` clamps to that
/// bounding box while preserving aspect).
///
/// FCP-relevant set per the build plan: H.264 / HEVC / ProRes family,
/// AVFoundation-native. DNxHD / MXF are explicitly Phase 2 and would
/// route through ffmpeg, not this file.
struct TranscodePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let avPresetName: String
    let fileExtension: String  // mov / mp4 / m4v
    let suffix: String         // appended to source basename

    /// Whether `AVAssetExportSession.exportPresets(compatibleWith:)`
    /// is required to gate availability — false for ProRes presets,
    /// which are universally supported on macOS 12+.
    let alwaysAvailable: Bool

    static let all: [TranscodePreset] = [
        // H.264 lineup (mp4 container, broad NLE compatibility)
        TranscodePreset(id: "h264-1080p", name: "H.264 1080p",
                        avPresetName: AVAssetExportPreset1920x1080,
                        fileExtension: "mp4", suffix: "_h264_1080p",
                        alwaysAvailable: false),
        TranscodePreset(id: "h264-720p", name: "H.264 720p",
                        avPresetName: AVAssetExportPreset1280x720,
                        fileExtension: "mp4", suffix: "_h264_720p",
                        alwaysAvailable: false),

        // HEVC: hardware-accelerated on Apple Silicon; smaller files
        // than H.264 at equivalent quality.
        TranscodePreset(id: "hevc-1080p", name: "HEVC 1080p",
                        avPresetName: AVAssetExportPresetHEVC1920x1080,
                        fileExtension: "mp4", suffix: "_hevc_1080p",
                        alwaysAvailable: false),

        // ProRes family — go-to for FCP edit / proxy workflow.
        TranscodePreset(id: "prores-422-proxy", name: "ProRes Proxy",
                        avPresetName: AVAssetExportPresetAppleProRes422LPCM,
                        fileExtension: "mov", suffix: "_proxy",
                        alwaysAvailable: true),
        TranscodePreset(id: "prores-422", name: "ProRes 422",
                        avPresetName: AVAssetExportPresetAppleProRes422LPCM,
                        fileExtension: "mov", suffix: "_prores422",
                        alwaysAvailable: true),

        // Pass-through (rewrap to MP4 without re-encoding the video
        // when source codec is already H.264). Useful for trimming
        // metadata-only round-trips.
        TranscodePreset(id: "passthrough", name: "Pass-through (rewrap)",
                        avPresetName: AVAssetExportPresetPassthrough,
                        fileExtension: "mov", suffix: "_rewrap",
                        alwaysAvailable: true),
    ]
}
