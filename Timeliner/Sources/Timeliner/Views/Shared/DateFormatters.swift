import Foundation

enum TimelineDateFormatters {
    static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayMonth = make("MMM d")
    static let dayMonthYear = make("MMM d, yyyy")
    static let monthYear = make("MMMM yyyy")
    static let yearOnly = make("yyyy")
    static let timeOnly = make("h:mm a")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    static func formatStyle(_ key: String) -> Date.FormatStyle.DateStyle {
        switch key {
        case "short": return .numeric
        case "long":  return .long
        case "full":  return .complete
        default:      return .abbreviated
        }
    }
}
