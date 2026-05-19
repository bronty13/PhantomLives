import Foundation

/// Composable transcode specification. Replaces the monolithic
/// `TranscodePreset.avPresetName` + `ffmpegArgs` pair with a value
/// type the new Convert dialog can edit field-by-field (file format,
/// per-channel Copy vs Re-encode, filters, LUTs, overlays, container
/// settings, trimming).
///
/// A `TranscodePreset` becomes a labeled starting point — it holds an
/// id / name / category plus a `TranscodeOptions` body that the user
/// can mutate downstream and (eventually) save back as a custom preset.
/// The job runner branches off the resolved options:
///
///   - H.264 / HEVC video channel → AVAssetExportSession (hardware
///     encoder; codec + size pick the closest Apple preset constant)
///   - ProRes family → AVAssetWriter (CPU; granular control)
///   - Everything else (DNxHD/HR, Cineform, FLV, WMV, WebM, MXF,
///     audio-only) → ffmpeg
///
/// This file is **pure value types** — Foundation-only, no AVFoundation
/// imports — so it's safe to use from tests and from non-MainActor
/// contexts. The encoder-selection / argv-building logic lives in
/// `TranscodeService` (C3).
struct TranscodeOptions: Codable, Equatable, Hashable {

    var container: ContainerFormat
    var video: VideoChannel
    var audio: AudioChannel
    var filters: FilterChain
    var cameraLUT: LUTSelection
    var creativeLUT: LUTSelection
    var overlays: OverlaySettings
    var containerSettings: ContainerSettings
    var trimming: Trimming

    init(
        container: ContainerFormat = .mov,
        video: VideoChannel = .copy,
        audio: AudioChannel = .copy,
        filters: FilterChain = .init(),
        cameraLUT: LUTSelection = .none,
        creativeLUT: LUTSelection = .none,
        overlays: OverlaySettings = .init(),
        containerSettings: ContainerSettings = .init(),
        trimming: Trimming = .none
    ) {
        self.container = container
        self.video = video
        self.audio = audio
        self.filters = filters
        self.cameraLUT = cameraLUT
        self.creativeLUT = creativeLUT
        self.overlays = overlays
        self.containerSettings = containerSettings
        self.trimming = trimming
    }
}

// MARK: - Container

/// Top-level container format. `.audioOnly` is its own case rather
/// than another video extension because picking it implies video
/// channel = `.disabled` and a different set of audio container
/// choices (Wav / AIFF / M4A / MP3 / MP2).
enum ContainerFormat: String, Codable, CaseIterable {
    case mov
    case mp4
    case mkv
    case mxf
    case audioOnly

    var fileExtension: String {
        switch self {
        case .mov:       return "mov"
        case .mp4:       return "mp4"
        case .mkv:       return "mkv"
        case .mxf:       return "mxf"
        case .audioOnly: return ""   // determined by audio codec
        }
    }

    var displayName: String {
        switch self {
        case .mov:       return "MOV"
        case .mp4:       return "MP4"
        case .mkv:       return "MKV"
        case .mxf:       return "MXF"
        case .audioOnly: return "Audio Only"
        }
    }
}

// MARK: - Video channel

/// Video stream handling. `.copy` is a pass-through rewrap; `.disabled`
/// is for audio-only output. `.reencode` carries the full codec spec.
enum VideoChannel: Codable, Equatable, Hashable {
    case copy
    case disabled
    case reencode(VideoEncoding)

    var displayName: String {
        switch self {
        case .copy:        return "Copy"
        case .disabled:    return "Off"
        case .reencode(_): return "Re-Encode"
        }
    }
}

/// Detailed re-encode parameters for the video channel. Field choices
/// match Kyno's "Video Settings → Encoding" tab.
struct VideoEncoding: Codable, Equatable, Hashable {
    var codec: VideoCodec
    /// Encoder profile (Baseline / Main / High for H.264; Main / Main10
    /// for HEVC; family-specific for ProRes / DNxHR). `.auto` lets the
    /// encoder pick.
    var profile: VideoProfile
    var frameRate: FrameRateSpec
    var size: SizeSpec
    var displayAspectRatio: DisplayAspectRatio
    var rotation: RotationSpec
    var fieldType: FieldType
    var quality: QualityControl

    static let defaultH264 = VideoEncoding(
        codec: .h264, profile: .auto,
        frameRate: .likeSource, size: .likeSource,
        displayAspectRatio: .physical, rotation: .automatic,
        fieldType: .progressive,
        quality: .bitrate(kbps: 10_000)
    )

    static let defaultProRes422 = VideoEncoding(
        codec: .prores422, profile: .auto,
        frameRate: .likeSource, size: .likeSource,
        displayAspectRatio: .physical, rotation: .automatic,
        fieldType: .progressive,
        quality: .codecDefault
    )
}

enum VideoCodec: String, Codable, CaseIterable {
    case h264, hevc
    case prores422, prores422hq, prores422lt, prores422proxy, prores4444
    case dnxhd, dnxhr
    case cineform
    case mpeg4
    case photoJPEG
    case v210Uncompressed
    case vp8, vp9         // WebM
    case flashVideo       // FLV
    case wmv              // Windows Media

    var displayName: String {
        switch self {
        case .h264:             return "H.264"
        case .hevc:             return "HEVC"
        case .prores422:        return "ProRes 422"
        case .prores422hq:      return "ProRes 422 HQ"
        case .prores422lt:      return "ProRes 422 LT"
        case .prores422proxy:   return "ProRes 422 Proxy"
        case .prores4444:       return "ProRes 4444"
        case .dnxhd:            return "DNxHD"
        case .dnxhr:            return "DNxHR"
        case .cineform:         return "Cineform"
        case .mpeg4:            return "MPEG-4"
        case .photoJPEG:        return "Photo JPEG"
        case .v210Uncompressed: return "V210 Uncompressed"
        case .vp8:              return "VP8 (WebM)"
        case .vp9:              return "VP9 (WebM)"
        case .flashVideo:       return "Flash Video"
        case .wmv:              return "WMV"
        }
    }

    /// True for codecs Apple's AVAssetExportSession + Vide Toolbox can
    /// emit natively. False codecs go through ffmpeg.
    var isAppleNative: Bool {
        switch self {
        case .h264, .hevc,
             .prores422, .prores422hq, .prores422lt,
             .prores422proxy, .prores4444:
            return true
        default:
            return false
        }
    }
}

enum VideoProfile: String, Codable {
    case auto
    case baseline, main, high                // H.264
    case main10                              // HEVC
    case prores422, prores422hq, prores422lt // ProRes
    case prores422proxy, prores4444
    case dnxhr_lb, dnxhr_sq, dnxhr_hq, dnxhr_hqx, dnxhr_444
}

enum FrameRateSpec: Codable, Equatable, Hashable {
    case likeSource
    case fixed(Double)
}

enum SizeSpec: Codable, Equatable, Hashable {
    case likeSource
    case fixed(width: Int, height: Int)
    case scale(Double)   // e.g. 0.5 for half-resolution proxies
}

enum DisplayAspectRatio: String, Codable {
    case physical       // honor pixel grid 1:1
    case sixteenNine    // 16:9
    case fourThree      // 4:3
    case ultrawide      // 2.39:1
}

enum RotationSpec: String, Codable {
    case automatic   // honor container metadata
    case zero
    case ninety
    case oneEighty
    case twoSeventy
}

enum FieldType: String, Codable {
    case progressive
    case interlacedTopFirst
    case interlacedBottomFirst
}

/// Quality / bitrate control. Bitrate-based vs CRF-based vs encoder
/// default (which Apple's AVAssetExportSession uses internally).
enum QualityControl: Codable, Equatable, Hashable {
    case codecDefault
    case bitrate(kbps: Int)
    case crf(value: Int)
}

// MARK: - Audio channel

enum AudioChannel: Codable, Equatable, Hashable {
    case copy
    case disabled
    case reencode(AudioEncoding)

    var displayName: String {
        switch self {
        case .copy:        return "Copy"
        case .disabled:    return "Off"
        case .reencode(_): return "Re-Encode"
        }
    }
}

struct AudioEncoding: Codable, Equatable, Hashable {
    var codec: AudioCodec
    var sampleRate: Int     // 44100 / 48000 / 96000
    var bitrateKbps: Int    // 128 / 192 / 256 / 384

    static let defaultAAC = AudioEncoding(
        codec: .aac, sampleRate: 48_000, bitrateKbps: 192
    )
}

enum AudioCodec: String, Codable, CaseIterable {
    case aac
    case alac
    case pcm16, pcm24, pcm32      // Wav / AIFF backing
    case mp3, mp2
    case vorbis                   // WebM

    var displayName: String {
        switch self {
        case .aac:    return "AAC"
        case .alac:   return "Apple Lossless"
        case .pcm16:  return "PCM 16-bit"
        case .pcm24:  return "PCM 24-bit"
        case .pcm32:  return "PCM 32-bit"
        case .mp3:    return "MP3"
        case .mp2:    return "MP2"
        case .vorbis: return "Vorbis"
        }
    }
}

// MARK: - Filters

/// Video filter chain mirroring Kyno's Filters tab. All filters are
/// off by default — a non-zero strength or duration is what turns one
/// on at run time.
struct FilterChain: Codable, Equatable, Hashable {
    var denoise: Bool = false
    var sharpenBlurEnabled: Bool = false
    var sharpenBlur: SharpenBlur = .init()
    var addNoiseEnabled: Bool = false
    var addNoise: AddNoise = .init()
    var fadeInSeconds: Double = 0
    var fadeOutSeconds: Double = 0
}

struct SharpenBlur: Codable, Equatable, Hashable {
    var lumaRadius: Double = 5.0      // negative = blur, positive = sharpen
    var lumaStrength: Double = 1.0
    var chromaRadius: Double = 5.0
    var chromaStrength: Double = 0.0
}

struct AddNoise: Codable, Equatable, Hashable {
    var lumaStrength: Double = 0.05
    var chromaStrength: Double = 0.0
}

// MARK: - LUTs

/// Per-channel LUT selection. Kyno splits LUTs into Camera (input
/// correction, e.g. ARRI LogC → Rec.709) and Creative (look, applied
/// after camera LUT). PurpleReel currently has one slot per clip; this
/// model carries both so the dialog can expose them independently.
enum LUTSelection: Codable, Equatable, Hashable {
    case none
    case automatic                  // pick from filename hints
    case sidecarIfPresent
    case asDefinedInPlayer          // honor the player's active LUT
    case file(path: String)         // absolute path to a .cube
}

// MARK: - Overlays

struct OverlaySettings: Codable, Equatable, Hashable {
    var timecodeEnabled: Bool = false
    var timecodeSize: OverlaySize = .regular
    var timecodePosition: OverlayPosition = .bottomCenter
    var timecodeOpacity: Double = 1.0
}

enum OverlaySize: String, Codable {
    case small, regular, large
}

/// Nine-cell grid positioning, matching Kyno's Overlays tab dropdown.
enum OverlayPosition: String, Codable, CaseIterable {
    case topLeft, topCenter, topRight
    case left, center, right
    case bottomLeft, bottomCenter, bottomRight

    var displayName: String {
        switch self {
        case .topLeft:      return "Top Left"
        case .topCenter:    return "Top Center"
        case .topRight:     return "Top Right"
        case .left:         return "Left"
        case .center:       return "Center"
        case .right:        return "Right"
        case .bottomLeft:   return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight:  return "Bottom Right"
        }
    }
}

// MARK: - Container settings

/// "File & Container Settings" sheet from Image #85. Streamability,
/// timestamp preservation, source TC handling, XMP embedding.
struct ContainerSettings: Codable, Equatable, Hashable {
    var streamable: Bool = true
    var keepSourceTimestamps: Bool = false
    var timecodeSource: TimecodeSource = .fromSourceIfAvailable
    var embedXMPMetadata: Bool = false
}

enum TimecodeSource: String, Codable {
    case fromSourceIfAvailable
    case zeroBased
    case custom
}

// MARK: - Trimming

enum Trimming: String, Codable, CaseIterable {
    case none
    case inToOut

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .inToOut: return "In - Out"
        }
    }
}
