import Foundation

/// Renders a template body by substituting date/time tokens at entry-creation
/// time. Pure and local. Supported tokens (case-insensitive):
///
/// - `{{date}}`       → medium date, e.g. "May 31, 2026"
/// - `{{date_long}}`  → full date,   e.g. "Sunday, May 31, 2026"
/// - `{{time}}`       → short time,  e.g. "4:05 PM"
/// - `{{weekday}}`    → "Sunday"
/// - `{{year}}`       → "2026"
enum TemplateService {

    static func render(_ body: String, date: Date = Date(), locale: Locale = .current) -> String {
        func formatted(_ configure: (DateFormatter) -> Void) -> String {
            let f = DateFormatter(); f.locale = locale; configure(f); return f.string(from: date)
        }
        let tokens: [String: String] = [
            "date":      formatted { $0.dateStyle = .medium; $0.timeStyle = .none },
            "date_long": formatted { $0.dateStyle = .full;   $0.timeStyle = .none },
            "time":      formatted { $0.dateStyle = .none;   $0.timeStyle = .short },
            "weekday":   formatted { $0.dateFormat = "EEEE" },
            "year":      formatted { $0.dateFormat = "yyyy" },
        ]
        var out = body
        for (key, value) in tokens {
            // Case-insensitive {{ key }} with optional inner whitespace.
            let pattern = "\\{\\{\\s*\(key)\\s*\\}\\}"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..., in: out)
                out = re.stringByReplacingMatches(in: out, range: range,
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: value))
            }
        }
        return out
    }
}
