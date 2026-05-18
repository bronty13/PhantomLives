import Foundation
import AVFoundation

/// Kyno-style preset categories. Drives the Convert submenu grouping
/// in `AssetContextMenu` (Editing / Web / Proxies / DNxHR / DNxHD /
/// Audio / Rewrap / Distribution) and the recently-used carousel.
enum TranscodeCategory: String, CaseIterable, Identifiable {
    case editing      // ProRes 422 (FCP timeline-native)
    case web          // H.264 / HEVC (delivery / preview)
    case proxies      // Lower-bitrate ProRes for offline editing
    case dnxhr        // Avid-compatible (kept for breadth even
                       //  though Avid isn't a target NLE)
    case dnxhd        // legacy fixed-raster DNx
    case audio        // audio-only transcode (future)
    case rewrap       // container rewrap (no re-encode)
    case distribution // Cineform / MXF / archival masters

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .editing:      return "Editing"
        case .web:          return "Web"
        case .proxies:      return "Proxies"
        case .dnxhr:        return "DNxHR"
        case .dnxhd:        return "DNxHD"
        case .audio:        return "Audio"
        case .rewrap:       return "Rewrap"
        case .distribution: return "Distribution"
        }
    }
}

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
    let category: TranscodeCategory

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

    static func byCategory(_ cat: TranscodeCategory) -> [TranscodePreset] {
        all.filter { $0.category == cat }
    }

    /// Looks up a preset by id (used for the Recently Used carousel,
    /// where only the id is persisted in UserDefaults).
    static func find(id: String) -> TranscodePreset? {
        all.first { $0.id == id }
    }

    static let all: [TranscodePreset] = [
        // ---- Web --------------------------------------------------
        TranscodePreset(id: "h264-1080p", name: "H.264 1080p",
                        avPresetName: AVAssetExportPreset1920x1080,
                        fileExtension: "mp4", suffix: "_h264_1080p",
                        category: .web,
                        alwaysAvailable: false, ffmpegArgs: nil),
        TranscodePreset(id: "h264-720p", name: "H.264 720p",
                        avPresetName: AVAssetExportPreset1280x720,
                        fileExtension: "mp4", suffix: "_h264_720p",
                        category: .web,
                        alwaysAvailable: false, ffmpegArgs: nil),
        TranscodePreset(id: "hevc-1080p", name: "HEVC 1080p",
                        avPresetName: AVAssetExportPresetHEVC1920x1080,
                        fileExtension: "mp4", suffix: "_hevc_1080p",
                        category: .web,
                        alwaysAvailable: false, ffmpegArgs: nil),

        // ---- Editing (FCP timeline-native) -----------------------
        TranscodePreset(id: "prores-422", name: "ProRes 422",
                        avPresetName: AVAssetExportPresetAppleProRes422LPCM,
                        fileExtension: "mov", suffix: "_prores422",
                        category: .editing,
                        alwaysAvailable: true, ffmpegArgs: nil),

        // ---- Proxies ---------------------------------------------
        TranscodePreset(id: "prores-422-proxy", name: "ProRes Proxy",
                        avPresetName: AVAssetExportPresetAppleProRes422LPCM,
                        fileExtension: "mov", suffix: "_proxy",
                        category: .proxies,
                        alwaysAvailable: true, ffmpegArgs: nil),

        // ---- Rewrap (container-only) -----------------------------
        TranscodePreset(id: "passthrough", name: "Pass-through (rewrap)",
                        avPresetName: AVAssetExportPresetPassthrough,
                        fileExtension: "mov", suffix: "_rewrap",
                        category: .rewrap,
                        alwaysAvailable: true, ffmpegArgs: nil),

        // ---- DNxHR (ffmpeg) --------------------------------------
        TranscodePreset(id: "dnxhr-sq", name: "DNxHR SQ (1080p)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_dnxhr_sq",
                        category: .dnxhr,
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "dnxhd", "-profile:v", "dnxhr_sq",
                            "-pix_fmt", "yuv422p", "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),
        TranscodePreset(id: "dnxhr-hq", name: "DNxHR HQ (1080p)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_dnxhr_hq",
                        category: .dnxhr,
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "dnxhd", "-profile:v", "dnxhr_hq",
                            "-pix_fmt", "yuv422p", "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),

        // ---- Distribution (Cineform / archival) ------------------
        TranscodePreset(id: "cineform", name: "Cineform (1080p)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_cineform",
                        category: .distribution,
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "cfhd", "-quality", "film1",
                            "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),
        TranscodePreset(id: "mxf-prores",
                        name: "ProRes in MXF",
                        avPresetName: "",
                        fileExtension: "mxf", suffix: "_prores_mxf",
                        category: .distribution,
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-c:v", "prores_ks", "-profile:v", "3",
                            "-pix_fmt", "yuv422p10le",
                            "-c:a", "pcm_s24le",
                            "{OUT}",
                        ]),
    ]
}

/// Recently-used preset tracking — persists the IDs of the last six
/// presets the user picked so the Convert submenu can surface them in
/// a "Recently Used" group at the top, matching Kyno's UX.
enum RecentPresets {
    private static let key = "transcodePresetMRU"
    private static let cap = 6

    static func list() -> [TranscodePreset] {
        let ids = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        return ids.compactMap { TranscodePreset.find(id: $0) }
    }

    static func push(_ preset: TranscodePreset) {
        var ids = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        ids.removeAll { $0 == preset.id }
        ids.insert(preset.id, at: 0)
        if ids.count > cap { ids = Array(ids.prefix(cap)) }
        UserDefaults.standard.set(ids, forKey: key)
    }
}
