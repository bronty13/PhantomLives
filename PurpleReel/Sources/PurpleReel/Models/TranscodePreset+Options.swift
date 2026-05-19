import Foundation
import AVFoundation

/// Materializes a starting `TranscodeOptions` from an existing
/// preset's `avPresetName` / `ffmpegArgs`. The Convert dialog's
/// Settings… sheets need a "what does this preset actually do"
/// answer to open with — without it, every preset would land on
/// `TranscodeOptions()` (= Copy/Copy MOV) regardless of what the
/// user picked from the menu, which is a UX lie.
///
/// **Not exhaustive.** Maps the common cases (H.264, HEVC, ProRes
/// family, pass-through rewrap, DNxHR, audio-only) and falls back to
/// a sensible default for everything else. Mapped values are the
/// user's *starting point* — they can edit any field downstream.
extension TranscodePreset {

    func defaultOptions() -> TranscodeOptions {
        // 1. Pass-through rewrap → both channels copy.
        if avPresetName == AVAssetExportPresetPassthrough {
            return TranscodeOptions(
                container: containerFromExtension(),
                video: .copy, audio: .copy
            )
        }

        // 2. Apple-native AVAssetExportSession presets.
        if !avPresetName.isEmpty {
            return optionsFromAVPreset()
        }

        // 3. ffmpeg-routed presets. Sniff the codec name out of the
        //    `-c:v <codec>` argument; map it to a VideoCodec case.
        if let args = ffmpegArgs {
            return optionsFromFFmpegArgs(args)
        }

        // 4. Fallback — preset shipped malformed; assume copy/copy.
        return TranscodeOptions(container: containerFromExtension())
    }

    // MARK: - Apple-native mapping

    private func optionsFromAVPreset() -> TranscodeOptions {
        let codec = appleCodec(from: avPresetName)
        let size = appleSize(from: avPresetName)
        let container = containerFromExtension()
        if let codec {
            return TranscodeOptions(
                container: container,
                video: .reencode(VideoEncoding(
                    codec: codec, profile: .auto,
                    frameRate: .likeSource,
                    size: size,
                    displayAspectRatio: .physical,
                    rotation: .automatic,
                    fieldType: .progressive,
                    quality: .codecDefault
                )),
                audio: .reencode(AudioEncoding.defaultAAC)
            )
        }
        return TranscodeOptions(container: container)
    }

    private func appleCodec(from preset: String) -> VideoCodec? {
        if preset.contains("HEVC") { return .hevc }
        if preset.contains("AppleProRes4444") { return .prores4444 }
        if preset.contains("AppleProRes422") { return .prores422 }
        // H.264 has no codec marker in the constant name — it's just
        // the size-keyed presets ("AVAssetExportPreset1920x1080" etc.)
        if preset.contains("x") { return .h264 }
        if preset == AVAssetExportPresetHighestQuality { return .h264 }
        return nil
    }

    private func appleSize(from preset: String) -> SizeSpec {
        // Mine the "WxH" tail out of the constant name. Conveniently
        // the AVFoundation constants all end in their target size.
        let map: [(String, Int, Int)] = [
            ("3840x2160", 3840, 2160),
            ("1920x1080", 1920, 1080),
            ("1280x720",  1280,  720),
            ("960x540",    960,  540),
            ("640x480",    640,  480),
        ]
        for (needle, w, h) in map where preset.contains(needle) {
            return .fixed(width: w, height: h)
        }
        return .likeSource
    }

    // MARK: - ffmpeg mapping

    private func optionsFromFFmpegArgs(_ args: [String]) -> TranscodeOptions {
        let videoCodec = ffmpegVideoCodec(from: args)
        let audioCodec = ffmpegAudioCodec(from: args)
        let isAudioOnly = args.contains("-vn")
        let container: ContainerFormat = isAudioOnly
            ? .audioOnly : containerFromExtension()

        let videoChannel: VideoChannel
        if isAudioOnly {
            videoChannel = .disabled
        } else if let videoCodec {
            videoChannel = .reencode(VideoEncoding(
                codec: videoCodec, profile: .auto,
                frameRate: .likeSource, size: .likeSource,
                displayAspectRatio: .physical, rotation: .automatic,
                fieldType: .progressive,
                quality: ffmpegQuality(from: args)
            ))
        } else {
            videoChannel = .copy
        }

        let audioChannel: AudioChannel
        if let audioCodec {
            audioChannel = .reencode(AudioEncoding(
                codec: audioCodec, sampleRate: 48_000,
                bitrateKbps: ffmpegAudioBitrate(from: args) ?? 192
            ))
        } else {
            audioChannel = .copy
        }

        return TranscodeOptions(
            container: container,
            video: videoChannel,
            audio: audioChannel
        )
    }

    private func ffmpegVideoCodec(from args: [String]) -> VideoCodec? {
        guard let idx = args.firstIndex(of: "-c:v"),
              idx + 1 < args.count else { return nil }
        let name = args[idx + 1]
        if name == "copy" { return nil }
        switch name {
        case "libx264":     return .h264
        case "libx265":     return .hevc
        case "prores_ks":   return ffmpegProResProfile(from: args)
        case "dnxhd":       return ffmpegDNxFamily(from: args)
        case "cfhd":        return .cineform
        case "mjpeg":       return .photoJPEG
        case "v210":        return .v210Uncompressed
        case "libvpx":      return .vp8
        case "libvpx-vp9":  return .vp9
        case "flv":         return .flashVideo
        case "wmv2":        return .wmv
        default:            return nil
        }
    }

    private func ffmpegProResProfile(from args: [String]) -> VideoCodec {
        guard let pIdx = args.firstIndex(of: "-profile:v"),
              pIdx + 1 < args.count else { return .prores422 }
        switch args[pIdx + 1] {
        case "0": return .prores422proxy
        case "1": return .prores422lt
        case "2": return .prores422
        case "3": return .prores422hq
        case "4": return .prores4444
        default:  return .prores422
        }
    }

    private func ffmpegDNxFamily(from args: [String]) -> VideoCodec {
        // ffmpeg's `dnxhd` encoder covers both DNxHD (with -b:v) and
        // DNxHR (with -profile:v dnxhr_*). Distinguishing matters
        // because the dialog presents different bitrate ladders.
        if let pIdx = args.firstIndex(of: "-profile:v"),
           pIdx + 1 < args.count,
           args[pIdx + 1].hasPrefix("dnxhr_") {
            return .dnxhr
        }
        return .dnxhd
    }

    private func ffmpegQuality(from args: [String]) -> QualityControl {
        if let idx = args.firstIndex(of: "-b:v"), idx + 1 < args.count {
            let raw = args[idx + 1]
            let kbps = parseBitrateKbps(raw) ?? 0
            if kbps > 0 { return .bitrate(kbps: kbps) }
        }
        if let idx = args.firstIndex(of: "-crf"), idx + 1 < args.count,
           let value = Int(args[idx + 1]) {
            return .crf(value: value)
        }
        return .codecDefault
    }

    private func parseBitrateKbps(_ raw: String) -> Int? {
        // ffmpeg accepts "10000k" / "10M" / plain "10000000"
        if raw.hasSuffix("M") || raw.hasSuffix("m"),
           let mbps = Double(raw.dropLast()) {
            return Int(mbps * 1000)
        }
        if raw.hasSuffix("k") || raw.hasSuffix("K"),
           let kbps = Int(raw.dropLast()) {
            return kbps
        }
        if let bps = Int(raw) {
            return bps / 1000
        }
        return nil
    }

    private func ffmpegAudioCodec(from args: [String]) -> AudioCodec? {
        guard let idx = args.firstIndex(of: "-c:a"),
              idx + 1 < args.count else { return nil }
        let name = args[idx + 1]
        if name == "copy" { return nil }
        switch name {
        case "aac":          return .aac
        case "alac":         return .alac
        case "pcm_s16le", "pcm_s16be": return .pcm16
        case "pcm_s24le", "pcm_s24be": return .pcm24
        case "pcm_s32le", "pcm_s32be": return .pcm32
        case "libmp3lame":   return .mp3
        case "mp2":          return .mp2
        case "libvorbis":    return .vorbis
        default:             return nil
        }
    }

    private func ffmpegAudioBitrate(from args: [String]) -> Int? {
        guard let idx = args.firstIndex(of: "-b:a"),
              idx + 1 < args.count else { return nil }
        return parseBitrateKbps(args[idx + 1])
    }

    // MARK: - Container

    private func containerFromExtension() -> ContainerFormat {
        switch fileExtension.lowercased() {
        case "mov":  return .mov
        case "mp4":  return .mp4
        case "mkv":  return .mkv
        case "mxf":  return .mxf
        case "wav", "aiff", "m4a", "mp3", "mp2": return .audioOnly
        default:     return .mov
        }
    }
}
