import Foundation
import AVFoundation

/// Kyno-style preset categories. Drives the Convert submenu grouping
/// in `AssetContextMenu` (Editing / Web / Proxies / DNxHR / DNxHD /
/// Audio / Rewrap / Distribution) and the recently-used carousel.
enum TranscodeCategory: String, CaseIterable, Identifiable, Codable {
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
struct TranscodePreset: Identifiable, Hashable, Codable {
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

    /// True for presets that run through Apple Silicon's hardware
    /// video encoder (H.264 / HEVC via AVAssetExportSession). The
    /// VTHEncoder serializes internally — running two H.264 jobs
    /// in parallel doesn't actually speed anything up, it just
    /// burns context-switch CPU. CPU-bound codecs (ProRes,
    /// DNxHR, Cineform) and pass-through (no encode at all) can
    /// genuinely run in parallel. Drives the two-pool dispatcher
    /// in TranscodeQueue.
    var usesHardwareEncoder: Bool {
        if isFFmpeg { return false }
        // Inferred from avPresetName because AVAssetExportSession
        // doesn't expose the encoder family directly. Hardware-
        // bound presets are the H.264 / HEVC family.
        let name = avPresetName
        return name == AVAssetExportPreset1920x1080
            || name == AVAssetExportPreset1280x720
            || name == AVAssetExportPreset640x480
            || name == AVAssetExportPreset3840x2160
            || name == AVAssetExportPresetHEVC1920x1080
            || name == AVAssetExportPresetHEVC3840x2160
    }

    /// True if this preset was loaded from the user's custom-presets
    /// directory, false for built-ins. Drives the badge in the
    /// Convert menu and the delete affordance in Settings.
    var isCustom: Bool {
        !TranscodePreset.builtInIDs.contains(id)
    }

    /// Built-in ID set — frozen, used by `isCustom` lookup and to
    /// keep ⌘1..⌘0 menu indices stable across releases.
    static let builtInIDs: Set<String> = [
        "h264-1080p", "h264-720p", "hevc-1080p",
        "prores-422", "prores-422-proxy",
        "passthrough",
        "dnxhr-sq", "dnxhr-hq",
        "cineform", "mxf-prores",
    ]

    /// Built-ins plus the extended catalog (PresetCatalog) plus user
    /// customs. Used by `byCategory(_:)` and `find(id:)`. The legacy
    /// `all` list comes first so the ⌘1..⌘0 menu indices and any
    /// previously-pinned MRU IDs keep pointing at the same presets;
    /// PresetCatalog.extended slots after; user customs come last.
    static func combined() -> [TranscodePreset] {
        all + PresetCatalog.extended + CustomPresets.load()
    }

    static func byCategory(_ cat: TranscodeCategory) -> [TranscodePreset] {
        combined().filter { $0.category == cat }
    }

    /// Looks up a preset by id (used for the Recently Used carousel,
    /// where only the id is persisted in UserDefaults). Searches
    /// customs too so a recently-used custom preset survives a relaunch.
    static func find(id: String) -> TranscodePreset? {
        if let builtIn = all.first(where: { $0.id == id }) {
            return builtIn
        }
        return CustomPresets.load().first { $0.id == id }
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

        // ---- Smart proxies (Kyno 1.9) ----------------------------
        // Auto-scale to a fraction of the source resolution. ffmpeg's
        // `scale='trunc(iw/N/2)*2':-2` rounds to even dimensions to
        // keep H.264 / ProRes encoders happy. Slot AFTER index 9 so
        // the ⌘1..⌘0 menu shortcuts keep pointing at the original
        // built-in catalogue (`TranscodePreset.all[0...9]`).
        TranscodePreset(id: "proxy-half",
                        name: "Smart Proxy 1/2 (ProRes Proxy)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_proxy_half",
                        category: .proxies,
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-vf", "scale='trunc(iw/2/2)*2':-2",
                            "-c:v", "prores_ks", "-profile:v", "0",
                            "-pix_fmt", "yuv422p10le",
                            "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),
        TranscodePreset(id: "proxy-quarter",
                        name: "Smart Proxy 1/4 (ProRes Proxy)",
                        avPresetName: "",
                        fileExtension: "mov", suffix: "_proxy_qtr",
                        category: .proxies,
                        alwaysAvailable: true,
                        ffmpegArgs: [
                            "-y", "-i", "{IN}",
                            "-vf", "scale='trunc(iw/4/2)*2':-2",
                            "-c:v", "prores_ks", "-profile:v", "0",
                            "-pix_fmt", "yuv422p10le",
                            "-c:a", "pcm_s16le",
                            "{OUT}",
                        ]),

        // ---- Audio-only -----------------------------------------
        // C18 — extract the audio track only, AAC in an m4a
        // container. Combine Clips uses this for "glue dialogue
        // takes" without rendering video. Stand-alone transcode
        // can also pick this when the audio is the only thing
        // wanted (interview transcript prep, podcast cut-down).
        TranscodePreset(id: "m4a-audio-only",
                        name: "Audio Only (AAC m4a)",
                        avPresetName: AVAssetExportPresetAppleM4A,
                        fileExtension: "m4a", suffix: "_audio",
                        category: .audio,
                        alwaysAvailable: true, ffmpegArgs: nil),
    ]

    /// C18 — true when this preset writes audio without video. The
    /// Combine Clips composition skips the video track entirely for
    /// these so the export session doesn't try (and fail) to encode
    /// a video stream into an audio-only container.
    var isAudioOnly: Bool {
        category == .audio
            || avPresetName == AVAssetExportPresetAppleM4A
            || fileExtension == "m4a"
            || fileExtension == "wav"
            || fileExtension == "aiff"
    }
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
