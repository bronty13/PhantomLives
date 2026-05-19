import Foundation
import AVFoundation

/// Extended preset catalog. Augments `TranscodePreset.all` with the
/// long-tail of Kyno-style presets (Audio, more Distribution, DNxHD
/// variants, DNxHR variants, Editing extras, Proxies, Web). The legacy
/// `all` list stays as-is so `⌘1..⌘0` menu shortcuts keep pointing at
/// the same canonical 10 presets; everything here surfaces via
/// `TranscodePreset.combined()` so the right-click Convert / Combine /
/// Export Subclips submenus get the full Kyno-shaped tree.
///
/// **Curated, not exhaustive.** Kyno ships ~28 DNxHD and ~30 DNxHR
/// variants; the curated subset here covers the framerates DITs
/// actually deliver to (23.98 / 29.97 / 50 / 59.94 at the standard
/// bitrate ladder). User can request more via "Save as Preset…" once
/// the new Convert dialog lands (C4).
///
/// Every entry is **executable today** — preset uses either an
/// AVAssetExportSession preset name (for Apple-native codecs) or an
/// `ffmpegArgs` recipe (for everything ffmpeg owns), wired to the
/// same TranscodeJob runner that the existing 12 built-ins use.
enum PresetCatalog {

    static let extended: [TranscodePreset] = {
        var presets: [TranscodePreset] = []
        presets.append(contentsOf: audioPresets)
        presets.append(contentsOf: distributionPresets)
        presets.append(contentsOf: dnxhdPresets)
        presets.append(contentsOf: dnxhrPresets)
        presets.append(contentsOf: editingExtras)
        presets.append(contentsOf: proxyPresets)
        presets.append(contentsOf: webPresets)
        presets.append(contentsOf: rewrapVariants)
        return presets
    }()

    // MARK: - Audio
    //
    // Audio-only output. Container extension follows the codec
    // (Wav → .wav, AIFF → .aiff, M4A → .m4a, MP3 → .mp3, etc.). All
    // routed through ffmpeg because AVAssetExportSession doesn't
    // emit standalone PCM / MP3 / MP2 streams the way Kyno wants.

    private static let audioPresets: [TranscodePreset] = [
        ffmpegAudio("audio-wav16",  "Wav 16bit",  ext: "wav",
                     args: ["-vn", "-c:a", "pcm_s16le"]),
        ffmpegAudio("audio-wav24",  "Wav 24bit",  ext: "wav",
                     args: ["-vn", "-c:a", "pcm_s24le"]),
        ffmpegAudio("audio-wav32",  "Wav 32bit",  ext: "wav",
                     args: ["-vn", "-c:a", "pcm_s32le"]),
        ffmpegAudio("audio-aiff16", "AIFF 16bit", ext: "aiff",
                     args: ["-vn", "-c:a", "pcm_s16be"]),
        ffmpegAudio("audio-aiff32", "AIFF 32bit", ext: "aiff",
                     args: ["-vn", "-c:a", "pcm_s32be"]),
        ffmpegAudio("audio-m4a128", "M4A 128kbps", ext: "m4a",
                     args: ["-vn", "-c:a", "aac", "-b:a", "128k"]),
        ffmpegAudio("audio-m4a192", "M4A 192kbps", ext: "m4a",
                     args: ["-vn", "-c:a", "aac", "-b:a", "192k"]),
        ffmpegAudio("audio-m4a256", "M4A 256kbps", ext: "m4a",
                     args: ["-vn", "-c:a", "aac", "-b:a", "256k"]),
        ffmpegAudio("audio-mp3-128", "MP3 128kbps", ext: "mp3",
                     args: ["-vn", "-c:a", "libmp3lame", "-b:a", "128k"]),
        ffmpegAudio("audio-mp3-256", "MP3 256kbps", ext: "mp3",
                     args: ["-vn", "-c:a", "libmp3lame", "-b:a", "256k"]),
    ]

    // MARK: - Distribution (delivery / archival masters)

    private static let distributionPresets: [TranscodePreset] = [
        // H.264 size variants beyond Web's 1080p / 720p
        avNative("distrib-h264-480p", "H.264 480p",
                  avPresetName: AVAssetExportPreset640x480,
                  ext: "mp4", suffix: "_h264_480p",
                  category: .distribution, alwaysAvailable: false),
        // HEVC at delivery sizes
        avNative("distrib-hevc-4k", "HEVC 4K UHD",
                  avPresetName: AVAssetExportPresetHEVC3840x2160,
                  ext: "mp4", suffix: "_hevc_4k",
                  category: .distribution, alwaysAvailable: false),
        // Legacy distribution formats — FLV, WMV, WebM (all ffmpeg)
        ffmpegPreset("distrib-flv", "Flash Video (FLV)",
                      ext: "flv", suffix: "_flv",
                      category: .distribution,
                      args: ["-c:v", "flv", "-b:v", "1500k",
                              "-c:a", "libmp3lame", "-b:a", "128k"]),
        ffmpegPreset("distrib-wmv-hq", "WMV HQ",
                      ext: "wmv", suffix: "_wmv_hq",
                      category: .distribution,
                      args: ["-c:v", "wmv2", "-b:v", "4000k",
                              "-c:a", "wmav2", "-b:a", "192k"]),
        ffmpegPreset("distrib-webm-vp8", "WebM VP8 / Vorbis",
                      ext: "webm", suffix: "_webm_vp8",
                      category: .distribution,
                      args: ["-c:v", "libvpx", "-b:v", "2000k",
                              "-c:a", "libvorbis", "-b:a", "192k"]),
        ffmpegPreset("distrib-webm-vp9", "WebM VP9 / Vorbis",
                      ext: "webm", suffix: "_webm_vp9",
                      category: .distribution,
                      args: ["-c:v", "libvpx-vp9", "-b:v", "1500k",
                              "-c:a", "libvorbis", "-b:a", "192k"]),
    ]

    // MARK: - DNxHD variants (curated bitrate ladder at common framerates)

    private static let dnxhdPresets: [TranscodePreset] = [
        // 23.98 fps
        dnxhdPreset("dnxhd-1080p2398-115", "DNxHD 1080p/23.98 115",
                     bitrateMbps: 115, framerate: "24000/1001"),
        dnxhdPreset("dnxhd-1080p2398-175", "DNxHD 1080p/23.98 175",
                     bitrateMbps: 175, framerate: "24000/1001"),
        // 25 fps
        dnxhdPreset("dnxhd-1080p25-120", "DNxHD 1080p/25 120",
                     bitrateMbps: 120, framerate: "25"),
        dnxhdPreset("dnxhd-1080p25-185", "DNxHD 1080p/25 185",
                     bitrateMbps: 185, framerate: "25"),
        // 29.97 fps
        dnxhdPreset("dnxhd-1080p2997-145", "DNxHD 1080p/29.97 145",
                     bitrateMbps: 145, framerate: "30000/1001"),
        dnxhdPreset("dnxhd-1080p2997-220", "DNxHD 1080p/29.97 220",
                     bitrateMbps: 220, framerate: "30000/1001"),
        // 50 fps
        dnxhdPreset("dnxhd-1080p50-240", "DNxHD 1080p/50 240",
                     bitrateMbps: 240, framerate: "50"),
        dnxhdPreset("dnxhd-1080p50-365", "DNxHD 1080p/50 365",
                     bitrateMbps: 365, framerate: "50"),
        // 59.94 fps
        dnxhdPreset("dnxhd-1080p5994-220", "DNxHD 1080p/59.94 220",
                     bitrateMbps: 220, framerate: "60000/1001"),
        dnxhdPreset("dnxhd-1080p5994-440", "DNxHD 1080p/59.94 440",
                     bitrateMbps: 440, framerate: "60000/1001"),
    ]

    // MARK: - DNxHR variants (resolution-independent + 4K/UHD framerates)
    //
    // ffmpeg DNxHR uses a profile string (`dnxhr_sq` / `dnxhr_hq` /
    // `dnxhr_hqx` / `dnxhr_444`) and is resolution-independent, so a
    // single recipe handles UHD and 4K — the encoder reads the input
    // size. We name presets after the resolution for menu legibility.

    private static let dnxhrPresets: [TranscodePreset] = [
        dnxhrPreset("dnxhr-hq-uhd-2398",  "DNxHR HQ UHD 23.98",  profile: "dnxhr_hq",  framerate: "24000/1001"),
        dnxhrPreset("dnxhr-hq-uhd-2997",  "DNxHR HQ UHD 29.97",  profile: "dnxhr_hq",  framerate: "30000/1001"),
        dnxhrPreset("dnxhr-hq-uhd-50",    "DNxHR HQ UHD 50",     profile: "dnxhr_hq",  framerate: "50"),
        dnxhrPreset("dnxhr-hq-4k-2398",   "DNxHR HQ 4K 23.98",   profile: "dnxhr_hq",  framerate: "24000/1001"),
        dnxhrPreset("dnxhr-hq-4k-2997",   "DNxHR HQ 4K 29.97",   profile: "dnxhr_hq",  framerate: "30000/1001"),
        dnxhrPreset("dnxhr-hqx-uhd-2398", "DNxHR HQX UHD 23.98", profile: "dnxhr_hqx", framerate: "24000/1001",
                     pixFmt: "yuv422p10le"),
        dnxhrPreset("dnxhr-hqx-4k-2398",  "DNxHR HQX 4K 23.98",  profile: "dnxhr_hqx", framerate: "24000/1001",
                     pixFmt: "yuv422p10le"),
        dnxhrPreset("dnxhr-444-uhd-2398", "DNxHR 444 UHD 23.98", profile: "dnxhr_444", framerate: "24000/1001",
                     pixFmt: "yuv444p10le"),
        dnxhrPreset("dnxhr-444-4k-2398",  "DNxHR 444 4K 23.98",  profile: "dnxhr_444", framerate: "24000/1001",
                     pixFmt: "yuv444p10le"),
    ]

    // MARK: - Editing extras (FCP timeline-native beyond ProRes 422)

    private static let editingExtras: [TranscodePreset] = [
        // ProRes family. Only the base 422 + 4444 are exposed as
        // AVAssetExportSession presets on macOS; HQ / LT / Proxy live
        // in ffmpeg's `prores_ks` (profile 0=Proxy, 1=LT, 2=422,
        // 3=HQ, 4=4444). All routed through ffmpeg here for uniform
        // bitrate control — when C3 swaps the runtime over to
        // AVAssetWriter we can move 422 / 4444 back to native paths.
        proresPreset("editing-prores-hq",    "ProRes 422 HQ",    profile: 3),
        proresPreset("editing-prores-lt",    "ProRes 422 LT",    profile: 1),
        proresPreset("editing-prores-proxy", "ProRes 422 Proxy", profile: 0),
        proresPreset("editing-prores-4444",  "ProRes 4444",      profile: 4,
                      pixFmt: "yuv444p10le"),
        // Editorial extras (ffmpeg)
        ffmpegPreset("editing-photo-jpeg", "Photo JPEG",
                      ext: "mov", suffix: "_photojpeg",
                      category: .editing,
                      args: ["-c:v", "mjpeg", "-q:v", "2",
                              "-pix_fmt", "yuvj422p",
                              "-c:a", "pcm_s16le"]),
        ffmpegPreset("editing-v210", "V210 Uncompressed",
                      ext: "mov", suffix: "_v210",
                      category: .editing,
                      args: ["-c:v", "v210",
                              "-c:a", "pcm_s24le"]),
    ]

    // MARK: - Proxies (full ladder beyond the existing smart-proxy half/quarter)

    private static let proxyPresets: [TranscodePreset] = [
        // H.264 Web Proxy ladder — three sizes × LQ/HQ
        ffmpegPreset("proxy-h264-1080-lq", "H.264 1080 Web Proxy LQ",
                      ext: "mp4", suffix: "_h264_1080_lq",
                      category: .proxies,
                      args: ["-vf", "scale=-2:1080",
                              "-c:v", "libx264", "-b:v", "3000k",
                              "-c:a", "aac", "-b:a", "128k"]),
        ffmpegPreset("proxy-h264-720-lq", "H.264 720 Web Proxy LQ",
                      ext: "mp4", suffix: "_h264_720_lq",
                      category: .proxies,
                      args: ["-vf", "scale=-2:720",
                              "-c:v", "libx264", "-b:v", "2000k",
                              "-c:a", "aac", "-b:a", "128k"]),
        ffmpegPreset("proxy-h264-540-lq", "H.264 540 Web Proxy LQ",
                      ext: "mp4", suffix: "_h264_540_lq",
                      category: .proxies,
                      args: ["-vf", "scale=-2:540",
                              "-c:v", "libx264", "-b:v", "1200k",
                              "-c:a", "aac", "-b:a", "128k"]),
        ffmpegPreset("proxy-h264-1080-hq", "H.264 1080 Web Proxy HQ",
                      ext: "mp4", suffix: "_h264_1080_hq",
                      category: .proxies,
                      args: ["-vf", "scale=-2:1080",
                              "-c:v", "libx264", "-b:v", "8000k",
                              "-c:a", "aac", "-b:a", "192k"]),
        ffmpegPreset("proxy-h264-720-hq", "H.264 720 Web Proxy HQ",
                      ext: "mp4", suffix: "_h264_720_hq",
                      category: .proxies,
                      args: ["-vf", "scale=-2:720",
                              "-c:v", "libx264", "-b:v", "5000k",
                              "-c:a", "aac", "-b:a", "192k"]),
        // Prores editing-proxy at fixed sizes
        ffmpegPreset("proxy-prores-1080", "ProRes 1080 Editing Proxy",
                      ext: "mov", suffix: "_prores_1080_proxy",
                      category: .proxies,
                      args: ["-vf", "scale=-2:1080",
                              "-c:v", "prores_ks", "-profile:v", "0",
                              "-pix_fmt", "yuv422p10le",
                              "-c:a", "pcm_s16le"]),
        ffmpegPreset("proxy-prores-720", "ProRes 720 Editing Proxy",
                      ext: "mov", suffix: "_prores_720_proxy",
                      category: .proxies,
                      args: ["-vf", "scale=-2:720",
                              "-c:v", "prores_ks", "-profile:v", "0",
                              "-pix_fmt", "yuv422p10le",
                              "-c:a", "pcm_s16le"]),
    ]

    // MARK: - Web (delivery-grade encodes — distinct from Distribution
    // by Kyno's split: Web is for the open internet, Distribution is
    // for archival masters / legacy NLEs)

    private static let webPresets: [TranscodePreset] = [
        // 8K HEVC for the rare-but-real "shoot to deliver" path
        avNative("web-hevc-8k", "HEVC 8K UHD",
                  avPresetName: AVAssetExportPresetHEVCHighestQuality,
                  ext: "mp4", suffix: "_hevc_8k",
                  category: .web, alwaysAvailable: false),
        avNative("web-hevc-720", "HEVC 720p",
                  avPresetName: AVAssetExportPresetHEVC1920x1080,
                  ext: "mp4", suffix: "_hevc_720p",
                  category: .web, alwaysAvailable: false),
    ]

    // MARK: - Rewrap (container-only)

    private static let rewrapVariants: [TranscodePreset] = [
        ffmpegPreset("rewrap-mov", "Rewrap to MOV",
                      ext: "mov", suffix: "_rewrap_mov",
                      category: .rewrap,
                      args: ["-c", "copy"]),
        ffmpegPreset("rewrap-mxf", "Rewrap to MXF",
                      ext: "mxf", suffix: "_rewrap_mxf",
                      category: .rewrap,
                      args: ["-c", "copy"]),
    ]

    // MARK: - Builders

    /// Shorthand for a preset that runs through AVAssetExportSession.
    private static func avNative(
        _ id: String, _ name: String,
        avPresetName: String, ext: String, suffix: String,
        category: TranscodeCategory, alwaysAvailable: Bool
    ) -> TranscodePreset {
        TranscodePreset(
            id: id, name: name, avPresetName: avPresetName,
            fileExtension: ext, suffix: suffix,
            category: category,
            alwaysAvailable: alwaysAvailable, ffmpegArgs: nil
        )
    }

    /// Shorthand for an ffmpeg-routed preset. The full argv is built
    /// by prepending `-y -i {IN}` and appending `{OUT}` to the
    /// per-preset codec/quality body.
    private static func ffmpegPreset(
        _ id: String, _ name: String,
        ext: String, suffix: String,
        category: TranscodeCategory,
        args: [String]
    ) -> TranscodePreset {
        TranscodePreset(
            id: id, name: name, avPresetName: "",
            fileExtension: ext, suffix: suffix,
            category: category, alwaysAvailable: true,
            ffmpegArgs: ["-y", "-i", "{IN}"] + args + ["{OUT}"]
        )
    }

    /// Audio-only ffmpeg recipe builder. Sets `-vn` upstream so the
    /// audio-codec argv stays terse, and pins the audio category.
    private static func ffmpegAudio(
        _ id: String, _ name: String,
        ext: String, args: [String]
    ) -> TranscodePreset {
        TranscodePreset(
            id: id, name: name, avPresetName: "",
            fileExtension: ext, suffix: "_audio",
            category: .audio, alwaysAvailable: true,
            ffmpegArgs: ["-y", "-i", "{IN}"] + args + ["{OUT}"]
        )
    }

    /// DNxHD recipe builder. Bitrate in Mbps, framerate as ffmpeg's
    /// rational-string form ("24000/1001" for 23.98, "30000/1001" for
    /// 29.97, "60000/1001" for 59.94).
    private static func dnxhdPreset(
        _ id: String, _ name: String,
        bitrateMbps: Int, framerate: String
    ) -> TranscodePreset {
        TranscodePreset(
            id: id, name: name, avPresetName: "",
            fileExtension: "mov", suffix: "_\(id)",
            category: .dnxhd, alwaysAvailable: true,
            ffmpegArgs: [
                "-y", "-i", "{IN}",
                "-c:v", "dnxhd", "-b:v", "\(bitrateMbps)M",
                "-r", framerate,
                "-pix_fmt", "yuv422p",
                "-c:a", "pcm_s16le",
                "{OUT}",
            ]
        )
    }

    /// ProRes via ffmpeg's `prores_ks`. Profile 0=Proxy, 1=LT,
    /// 2=422, 3=HQ, 4=4444. Pixel format defaults to yuv422p10le;
    /// 4444 wants yuv444p10le.
    private static func proresPreset(
        _ id: String, _ name: String,
        profile: Int, pixFmt: String = "yuv422p10le"
    ) -> TranscodePreset {
        TranscodePreset(
            id: id, name: name, avPresetName: "",
            fileExtension: "mov", suffix: "_\(id)",
            category: .editing, alwaysAvailable: true,
            ffmpegArgs: [
                "-y", "-i", "{IN}",
                "-c:v", "prores_ks", "-profile:v", "\(profile)",
                "-pix_fmt", pixFmt,
                "-c:a", "pcm_s16le",
                "{OUT}",
            ]
        )
    }

    /// DNxHR recipe builder. Profile string (`dnxhr_sq` / `_hq` /
    /// `_hqx` / `_444`); resolution-independent, so framerate + pixel
    /// format are the only knobs that change per variant.
    private static func dnxhrPreset(
        _ id: String, _ name: String,
        profile: String, framerate: String,
        pixFmt: String = "yuv422p"
    ) -> TranscodePreset {
        TranscodePreset(
            id: id, name: name, avPresetName: "",
            fileExtension: "mov", suffix: "_\(id)",
            category: .dnxhr, alwaysAvailable: true,
            ffmpegArgs: [
                "-y", "-i", "{IN}",
                "-c:v", "dnxhd", "-profile:v", profile,
                "-r", framerate,
                "-pix_fmt", pixFmt,
                "-c:a", "pcm_s16le",
                "{OUT}",
            ]
        )
    }
}
