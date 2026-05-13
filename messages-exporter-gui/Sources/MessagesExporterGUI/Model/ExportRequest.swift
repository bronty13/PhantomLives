import Foundation

enum EmojiMode: String, CaseIterable, Identifiable, Codable {
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
enum ExportMode: String, CaseIterable, Identifiable, Codable {
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
enum WhisperModel: String, CaseIterable, Identifiable, Codable {
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
    /// Exact chat.db handle ids (phone numbers / emails) to query
    /// directly via the CLI's `--handle` flag. When non-empty the CLI
    /// skips `get_handles()` and the fuzzy AddressBook match entirely
    /// — `contact` remains as the output-folder label only. Populated
    /// by `SenderCombobox` when the user picks a row from the chat.db
    /// enumeration; empty when they typed free-form text (legacy
    /// behavior preserved).
    var handles: [String] = []
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
        if !handles.isEmpty {
            // CLI accepts comma-separated handles. We avoid spaces in
            // the joined value so a misbehaving shell can't split it
            // into adjacent argv slots.
            args += ["--handle", handles.joined(separator: ",")]
        }
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

    /// Seconds precision is intentional — Messages.app's swipe-to-reveal
    /// time display can round, so users picking the minute they see next
    /// to a message could otherwise miss it on a tight forensic export.
    /// The CLI's `parse()` accepts both `HH:MM` and `HH:MM:SS`; we always
    /// emit `HH:MM:SS` so the GUI never silently drops the seconds the
    /// user has dialed in (or the 60-second start buffer applied to handle
    /// Messages.app's rounding).
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

/// Range-resolution helpers used by `RootView` (and the test suite) to
/// translate the form's HH:MM picker + SS stepper + buffer toggle into
/// the actual `Date` values handed to `ExportRequest`.
///
/// The picker is minute-precision because SwiftUI's `DatePicker` doesn't
/// expose a seconds component; the stepper is the seconds knob. Keeping
/// these as free functions (rather than methods on a view) lets the unit
/// tests pin the exact resolution behavior without instantiating any UI.
enum RangeResolver {
    /// The 60-second cushion that handles Messages.app's display-time
    /// rounding. If the user picks the minute they see in Messages as the
    /// start of the range, the actual `message.date` may be up to ~30s
    /// before that minute — extending one full minute earlier is a safe
    /// over-include rather than risking a silent drop of the first message.
    static let startBufferSeconds: TimeInterval = 60

    /// Replace `date`'s second component without disturbing year/month/
    /// day/hour/minute. `Calendar.date(bySetting:)` would advance to the
    /// *next* date matching the value (which can roll the minute over);
    /// we want a strict in-place replace so seconds 0…59 are valid.
    static func setSeconds(_ s: Int, on date: Date,
                           calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        c.second = max(0, min(59, s))
        return calendar.date(from: c) ?? date
    }

    /// Pull the picker's HH:MM + the stepper's SS into a single `Date`,
    /// then back off by one full minute when `expandStartByOneMinute` is
    /// on to cover Messages.app display rounding.
    static func resolvedStart(picker date: Date, seconds: Int,
                              expandStartByOneMinute: Bool,
                              calendar: Calendar = .current) -> Date {
        let base = setSeconds(seconds, on: date, calendar: calendar)
        return expandStartByOneMinute
            ? base.addingTimeInterval(-startBufferSeconds)
            : base
    }

    /// Same as `resolvedStart` minus the buffer. End-of-range gets only
    /// the seconds stepper applied; no asymmetric forward cushion because
    /// over-extending the end would pull in messages the user can plainly
    /// see are after their chosen window.
    static func resolvedEnd(picker date: Date, seconds: Int,
                            calendar: Calendar = .current) -> Date {
        setSeconds(seconds, on: date, calendar: calendar)
    }
}
