import Foundation

/// Strength preset for the voice-isolation pipeline. Each profile maps
/// onto a different set of ffmpeg filter parameters (see
/// `FilterChainBuilder`). The trade-off, as always with denoising, is
/// noise reduction vs. introduced artifacts — aggressive settings can
/// produce "underwater" or "swirly" residue on the cleaned voice.
enum ProcessingProfile: String, CaseIterable, Identifiable, Codable {
    case light
    case medium
    case aggressive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .aggressive: return "Aggressive"
        }
    }

    var blurb: String {
        switch self {
        case .light:
            return "Subtle hiss removal. Best for already-clean recordings."
        case .medium:
            return "Balanced denoise + enhancement. Default for voice memos."
        case .aggressive:
            return "Maximum noise reduction. May add artifacts to the voice."
        }
    }
}

/// Output container. AAC-in-M4A is the default — small, universal, and
/// what voice-memo workflows expect. WAV is offered for downstream
/// editing; MP3 for upload destinations that still require it.
enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case m4a
    case mp3
    case wav

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a: return "M4A (AAC)"
        case .mp3: return "MP3"
        case .wav: return "WAV (PCM 16-bit)"
        }
    }

    var fileExtension: String { rawValue }
}
