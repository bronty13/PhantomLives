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

struct ExportRequest: Equatable {
    var contact: String
    var start: Date?
    var end: Date?
    var outputDir: URL
    var emoji: EmojiMode
    var mode: ExportMode

    func argumentList() -> [String] {
        var args: [String] = [contact]
        if let start { args += ["--start", Self.formatter.string(from: start)] }
        if let end   { args += ["--end",   Self.formatter.string(from: end)] }
        args += ["--output", outputDir.path]
        args += ["--emoji", emoji.rawValue]
        if mode == .raw { args += ["--raw"] }
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
