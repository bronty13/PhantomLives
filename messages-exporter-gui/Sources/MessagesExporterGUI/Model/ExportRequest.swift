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

struct ExportRequest: Equatable {
    var contact: String
    var start: Date?
    var end: Date?
    var outputDir: URL
    var emoji: EmojiMode

    func argumentList() -> [String] {
        var args: [String] = [contact]
        if let start { args += ["--start", Self.formatter.string(from: start)] }
        if let end   { args += ["--end",   Self.formatter.string(from: end)] }
        args += ["--output", outputDir.path]
        args += ["--emoji", emoji.rawValue]
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
