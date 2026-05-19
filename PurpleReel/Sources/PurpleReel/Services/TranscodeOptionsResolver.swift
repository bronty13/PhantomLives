import Foundation
import AVFoundation

/// Backend selection result. `TranscodeJob` already branches on
/// "AVAssetExportSession preset name" vs "ffmpeg argv recipe"; the
/// resolver produces whichever shape fits the requested options.
enum ResolvedBackend: Equatable {
    /// Apple-native path. AVAssetExportSession takes a single
    /// monolithic preset name (`AVAssetExportPreset1920x1080`,
    /// `AVAssetExportPresetAppleProRes422LPCM`, etc.) — the resolver
    /// picks the closest one based on the requested codec + size.
    /// `alwaysAvailable` mirrors `TranscodePreset.alwaysAvailable`
    /// so the job can skip the compatibility probe for ProRes /
    /// pass-through.
    case avAssetExport(presetName: String,
                       fileExtension: String,
                       alwaysAvailable: Bool)
    /// ffmpeg path. The argv already carries `{IN}` / `{OUT}`
    /// placeholders that `TranscodeJob.runFFmpeg()` substitutes at
    /// dispatch time.
    case ffmpeg(args: [String], fileExtension: String)
}

extension TranscodeOptions {

    /// Translate this composable spec into the backend
    /// `TranscodeJob` can execute today. Strategy:
    ///
    ///   1. `video == .copy` (and audio also copy or unspecified) →
    ///      `AVAssetExportPresetPassthrough` (container rewrap).
    ///   2. `container == .audioOnly` (or `video == .disabled`) →
    ///      ffmpeg with `-vn` + audio codec args.
    ///   3. `video == .reencode` with `codec.isAppleNative` → pick the
    ///      best-fit AVAssetExportSession preset name. H.264 / HEVC
    ///      get a size-keyed preset; ProRes 422 and 4444 get the only
    ///      two AVFoundation exposes; ProRes HQ / LT / Proxy fall
    ///      through to ffmpeg (no Apple constant exists).
    ///   4. Anything else → ffmpeg with the codec-specific recipe.
    ///
    /// Filters, LUTs, and overlays are NOT baked in here — they're
    /// applied by `TranscodeJob.applyComposition` on top of the
    /// AVAssetExportSession path. The ffmpeg side currently ignores
    /// them; C5 will fold them into the argv via `-vf` filter chains.
    func resolveBackend() -> ResolvedBackend {

        // 1. Audio-only output. Pick the right audio codec → recipe.
        if container == .audioOnly || video == .disabled {
            return resolveAudioOnly()
        }

        // 2. Full pass-through rewrap (video AND audio = copy).
        if case .copy = video, case .copy = audio {
            return .avAssetExport(
                presetName: AVAssetExportPresetPassthrough,
                fileExtension: container.fileExtension.isEmpty
                    ? "mov" : container.fileExtension,
                alwaysAvailable: true
            )
        }

        // 3. Video re-encode. Branch on codec family.
        if case .reencode(let v) = video {
            if v.codec.isAppleNative {
                if let native = resolveAppleNative(v) {
                    return native
                }
                // Fall through to ffmpeg when no Apple preset fits
                // (ProRes HQ / LT / Proxy on macOS).
            }
            return resolveFFmpegVideo(v)
        }

        // 4. Video copy + audio re-encode → ffmpeg rewrap with audio
        // recipe (AVAssetExportSession can't do per-channel mixing
        // without a full composition).
        return resolveFFmpegPassthroughWithAudio()
    }

    // MARK: - Apple-native picker

    private func resolveAppleNative(
        _ v: VideoEncoding
    ) -> ResolvedBackend? {
        switch v.codec {
        case .h264:
            return .avAssetExport(
                presetName: h264PresetName(for: v.size),
                fileExtension: container == .mp4 ? "mp4" : "mov",
                alwaysAvailable: false
            )
        case .hevc:
            return .avAssetExport(
                presetName: hevcPresetName(for: v.size),
                fileExtension: container == .mp4 ? "mp4" : "mov",
                alwaysAvailable: false
            )
        case .prores422:
            return .avAssetExport(
                presetName: AVAssetExportPresetAppleProRes422LPCM,
                fileExtension: "mov",
                alwaysAvailable: true
            )
        case .prores4444:
            return .avAssetExport(
                presetName: AVAssetExportPresetAppleProRes4444LPCM,
                fileExtension: "mov",
                alwaysAvailable: true
            )
        case .prores422hq, .prores422lt, .prores422proxy:
            // Not exposed as AVAssetExportSession presets on macOS;
            // fall through to ffmpeg via the caller.
            return nil
        default:
            return nil
        }
    }

    private func h264PresetName(for size: SizeSpec) -> String {
        switch size {
        case .likeSource:
            return AVAssetExportPresetHighestQuality
        case .scale:
            return AVAssetExportPresetMediumQuality
        case .fixed(let w, let h):
            // Pick the closest of Apple's discrete size-keyed presets.
            let pixels = w * h
            if pixels >= 3840 * 2160 {
                return AVAssetExportPreset3840x2160
            } else if pixels >= 1920 * 1080 {
                return AVAssetExportPreset1920x1080
            } else if pixels >= 1280 * 720 {
                return AVAssetExportPreset1280x720
            } else {
                return AVAssetExportPreset640x480
            }
        }
    }

    private func hevcPresetName(for size: SizeSpec) -> String {
        switch size {
        case .likeSource:
            return AVAssetExportPresetHEVCHighestQuality
        case .scale:
            return AVAssetExportPresetHEVC1920x1080
        case .fixed(let w, let h):
            let pixels = w * h
            if pixels >= 3840 * 2160 {
                return AVAssetExportPresetHEVC3840x2160
            } else {
                return AVAssetExportPresetHEVC1920x1080
            }
        }
    }

    // MARK: - ffmpeg recipe builders

    private func resolveAudioOnly() -> ResolvedBackend {
        guard case .reencode(let a) = audio else {
            // No audio re-encode spec — best effort: copy audio into a
            // .wav-shaped container.
            return .ffmpeg(args: [
                "-y", "-i", "{IN}", "-vn", "-c:a", "copy", "{OUT}"
            ], fileExtension: "wav")
        }
        let (codecArg, ext) = audioCodecArgsAndExtension(a)
        var args: [String] = ["-y", "-i", "{IN}", "-vn"]
        args.append(contentsOf: codecArg)
        args.append("{OUT}")
        return .ffmpeg(args: args, fileExtension: ext)
    }

    private func resolveFFmpegVideo(_ v: VideoEncoding) -> ResolvedBackend {
        var args: [String] = ["-y", "-i", "{IN}"]

        // Video filter chain (size + filters). Built only if any knob
        // demands it; otherwise omit `-vf` so ffmpeg picks faster
        // paths.
        if let vf = videoFilterString(for: v) {
            args.append("-vf")
            args.append(vf)
        }

        // Video codec.
        args.append("-c:v")
        args.append(ffmpegVideoCodecName(v.codec))

        // Codec-specific quality.
        args.append(contentsOf: videoQualityArgs(v))

        // Pixel format — defaults that keep DITs happy.
        if let pix = defaultPixelFormat(for: v.codec) {
            args.append("-pix_fmt")
            args.append(pix)
        }

        // Frame rate.
        if case .fixed(let fps) = v.frameRate {
            args.append("-r")
            args.append(String(format: "%g", fps))
        }

        // Audio side.
        args.append(contentsOf: audioArgs(for: audio))

        args.append("{OUT}")
        return .ffmpeg(args: args, fileExtension: ffmpegFileExtension(for: v.codec))
    }

    private func resolveFFmpegPassthroughWithAudio() -> ResolvedBackend {
        var args: [String] = ["-y", "-i", "{IN}", "-c:v", "copy"]
        args.append(contentsOf: audioArgs(for: audio))
        args.append("{OUT}")
        return .ffmpeg(args: args,
                        fileExtension: container.fileExtension.isEmpty
                            ? "mov" : container.fileExtension)
    }

    // MARK: - Codec → ffmpeg arg mapping

    private func ffmpegVideoCodecName(_ codec: VideoCodec) -> String {
        switch codec {
        case .h264:             return "libx264"
        case .hevc:             return "libx265"
        case .prores422,
             .prores422hq,
             .prores422lt,
             .prores422proxy,
             .prores4444:       return "prores_ks"
        case .dnxhd, .dnxhr:    return "dnxhd"
        case .cineform:         return "cfhd"
        case .mpeg4:            return "mpeg4"
        case .photoJPEG:        return "mjpeg"
        case .v210Uncompressed: return "v210"
        case .vp8:              return "libvpx"
        case .vp9:              return "libvpx-vp9"
        case .flashVideo:       return "flv"
        case .wmv:              return "wmv2"
        }
    }

    private func ffmpegFileExtension(for codec: VideoCodec) -> String {
        switch codec {
        case .vp8, .vp9:        return "webm"
        case .flashVideo:       return "flv"
        case .wmv:              return "wmv"
        default:
            return container.fileExtension.isEmpty ? "mov" : container.fileExtension
        }
    }

    private func videoQualityArgs(_ v: VideoEncoding) -> [String] {
        switch v.codec {
        case .prores422:        return ["-profile:v", "2"]
        case .prores422hq:      return ["-profile:v", "3"]
        case .prores422lt:      return ["-profile:v", "1"]
        case .prores422proxy:   return ["-profile:v", "0"]
        case .prores4444:       return ["-profile:v", "4"]
        case .dnxhr:
            return ["-profile:v", dnxhrProfileString(v.profile)]
        default:
            switch v.quality {
            case .codecDefault:
                return []
            case .bitrate(let kbps):
                return ["-b:v", "\(kbps)k"]
            case .crf(let value):
                return ["-crf", "\(value)"]
            }
        }
    }

    private func dnxhrProfileString(_ profile: VideoProfile) -> String {
        switch profile {
        case .dnxhr_lb:  return "dnxhr_lb"
        case .dnxhr_sq:  return "dnxhr_sq"
        case .dnxhr_hq:  return "dnxhr_hq"
        case .dnxhr_hqx: return "dnxhr_hqx"
        case .dnxhr_444: return "dnxhr_444"
        default:         return "dnxhr_hq"
        }
    }

    private func defaultPixelFormat(for codec: VideoCodec) -> String? {
        switch codec {
        case .prores422, .prores422hq, .prores422lt,
             .prores422proxy:                       return "yuv422p10le"
        case .prores4444:                           return "yuv444p10le"
        case .dnxhd:                                return "yuv422p"
        case .dnxhr:                                return "yuv422p"
        case .cineform:                             return "yuv422p10le"
        case .photoJPEG:                            return "yuvj422p"
        default:                                    return nil
        }
    }

    private func videoFilterString(for v: VideoEncoding) -> String? {
        var filters: [String] = []
        switch v.size {
        case .fixed(let w, let h):
            filters.append("scale=\(w):\(h)")
        case .scale(let factor) where factor != 1.0:
            let inv = 1.0 / factor
            filters.append("scale='trunc(iw/\(inv)/2)*2':-2")
        case .likeSource, .scale:
            break
        }
        if filters.isEmpty { return nil }
        return filters.joined(separator: ",")
    }

    // MARK: - Audio

    private func audioArgs(for channel: AudioChannel) -> [String] {
        switch channel {
        case .copy:
            return ["-c:a", "copy"]
        case .disabled:
            return ["-an"]
        case .reencode(let a):
            return audioCodecArgsAndExtension(a).0
        }
    }

    /// Returns the audio codec argv plus the recommended container
    /// extension when the audio drives the container choice (audio-
    /// only output). For mixed-container output the caller picks the
    /// extension from `container.fileExtension`.
    private func audioCodecArgsAndExtension(
        _ a: AudioEncoding
    ) -> ([String], String) {
        switch a.codec {
        case .aac:
            return (["-c:a", "aac",
                      "-ar", "\(a.sampleRate)",
                      "-b:a", "\(a.bitrateKbps)k"], "m4a")
        case .alac:
            return (["-c:a", "alac",
                      "-ar", "\(a.sampleRate)"], "m4a")
        case .pcm16:
            return (["-c:a", "pcm_s16le",
                      "-ar", "\(a.sampleRate)"], "wav")
        case .pcm24:
            return (["-c:a", "pcm_s24le",
                      "-ar", "\(a.sampleRate)"], "wav")
        case .pcm32:
            return (["-c:a", "pcm_s32le",
                      "-ar", "\(a.sampleRate)"], "wav")
        case .mp3:
            return (["-c:a", "libmp3lame",
                      "-ar", "\(a.sampleRate)",
                      "-b:a", "\(a.bitrateKbps)k"], "mp3")
        case .mp2:
            return (["-c:a", "mp2",
                      "-ar", "\(a.sampleRate)",
                      "-b:a", "\(a.bitrateKbps)k"], "mp2")
        case .vorbis:
            return (["-c:a", "libvorbis",
                      "-ar", "\(a.sampleRate)",
                      "-b:a", "\(a.bitrateKbps)k"], "webm")
        }
    }
}
