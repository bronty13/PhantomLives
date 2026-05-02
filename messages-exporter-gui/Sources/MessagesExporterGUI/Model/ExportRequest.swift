import Foundation

enum EmojiMode: String, CaseIterable, Identifiable {
    case strip
    case word
    case keep

    var id: String { rawValue }
    var label: String {
        switch self {
        case .strip: return "Strip"
        case .word:  return "Word"
        case .keep:  return "Keep"
        }
    }
}

/// Export pipeline selection. `.sanitized` is the historical default
/// (HEIC→JPG, EXIF/GPS strip, caption-derived filenames). `.raw` is the
/// forensic path (`--raw` on the CLI): byte-identical attachment copies,
/// flat directory layout, sha256 + EXIF dumped into metadata.json, and a
/// chain_of_custody.log alongside the transcript. The CLI ignores
/// `--emoji` when `--raw` is set, so the GUI greys the emoji picker out.
enum ExportMode: String, CaseIterable, Identifiable {
    case sanitized
    case raw

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sanitized: return "Sanitized"
        case .raw:       return "Raw (forensic)"
        }
    }
}

/// Whisper model size for `--transcribe`. The CLI validates the choice
/// (`choices=WHISPER_MODELS`) — this enum just keeps the GUI's picker
/// honest about which values are accepted. `turbo` is the default
/// because it lands at near-large quality with ~8x the throughput.
enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny, base, small, medium, large, turbo

    var id: String { rawValue }
    var label: String {
        switch self {
        case .tiny:   return "tiny — ~1 GB, fastest, lowest quality"
        case .base:   return "base — ~1 GB, fast, acceptable"
        case .small:  return "small — ~2 GB, balanced"
        case .medium: return "medium — ~5 GB, high quality"
        case .large:  return "large — ~10 GB, best quality, slowest"
        case .turbo:  return "turbo — ~6 GB, near-large quality at 8x speed (default)"
        }
    }
    var shortLabel: String { rawValue }
}

struct ExportRequest: Equatable {
    var contact: String
    var start: Date?
    var end: Date?
    var outputDir: URL
    var emoji: EmojiMode
    var mode: ExportMode
    var transcribe: Bool
    var transcribeModel: WhisperModel
    var debug: Bool = false

    func argumentList() -> [String] {
        var args: [String] = [contact]
        if let start { args += ["--start", Self.formatter.string(from: start)] }
        if let end   { args += ["--end",   Self.formatter.string(from: end)] }
        args += ["--output", outputDir.path]
        args += ["--emoji", emoji.rawValue]
        if mode == .raw { args += ["--raw"] }
        if transcribe {
            args += ["--transcribe", "--transcribe-model", transcribeModel.rawValue]
        }
        if debug { args += ["--debug"] }
        return args
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
