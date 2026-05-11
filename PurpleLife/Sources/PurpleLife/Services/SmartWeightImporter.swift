import Foundation

/// Free-form text → Weight records. Ported from
/// `WeightTracker/Sources/WeightTracker/Services/ImportService.swift`
/// with these changes:
///
/// - Returns Weight values in pounds only (PurpleLife's Weight type
///   stores pounds; the kg path from WeightTracker isn't useful here
///   since the user can pick lb/kg in WeightTracker but PurpleLife
///   normalizes at the storage layer).
/// - Output is `[ParsedWeightEntry]` with `Date` rather than
///   `"yyyy-MM-dd"` strings — keeps Date comparisons / formatting at
///   the boundary.
/// - Duplicate detection takes a `Set<Date>` of existing record-day
///   timestamps; pre-deselects matching parsed rows so the user can
///   uncheck-import a day they didn't realize was already logged.
enum SmartWeightImporter {

    struct ParsedWeightEntry: Identifiable {
        let id = UUID()
        var date: Date          // calendar day (start of day in current TZ)
        var pounds: Double
        var isDuplicate: Bool = false
        var isSelected: Bool = true
        var sourceLine: String  // for the preview UI
    }

    /// Parse free-form text. Each line is examined independently;
    /// lines without both a date and a plausible weight are silently
    /// dropped. Same-day duplicates within the input collapse to the
    /// first occurrence (last-write-wins doesn't apply here because
    /// the user is staging an import, not reconciling history).
    static func parse(text: String, existingDays: Set<Date>) -> [ParsedWeightEntry] {
        var results: [ParsedWeightEntry] = []
        var seen = Set<Date>()

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let date = extractDate(from: trimmed) else { continue }
            guard let pounds = extractPounds(from: trimmed) else { continue }
            let day = Calendar.current.startOfDay(for: date)
            if seen.contains(day) { continue }
            seen.insert(day)
            let isDup = existingDays.contains(day)
            results.append(ParsedWeightEntry(
                date: day,
                pounds: pounds,
                isDuplicate: isDup,
                isSelected: !isDup,         // pre-deselect duplicates
                sourceLine: trimmed
            ))
        }
        return results
    }

    // MARK: - Date extraction

    /// Tries each pattern in order. Returns the first match that
    /// parses to a real calendar date. Returns nil if no pattern
    /// matches or every match fails to validate.
    private static func extractDate(from line: String) -> Date? {
        for pattern in datePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex, options: .caseInsensitive) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            if let dateStr = pattern.handler(match, line),
               let parsed = parseISODateOnly(dateStr) {
                return parsed
            }
        }
        return nil
    }

    private struct DatePattern {
        let regex: String
        let handler: (NSTextCheckingResult, String) -> String?
    }

    private static let datePatterns: [DatePattern] = [
        // ISO-8601: 2024-01-15
        DatePattern(regex: #"(\d{4})-(\d{1,2})-(\d{1,2})"#) { m, s in
            guard let y = substring(s, m.range(at: 1)),
                  let mo = substring(s, m.range(at: 2)).flatMap(Int.init),
                  let d = substring(s, m.range(at: 3)).flatMap(Int.init) else { return nil }
            return String(format: "%@-%02d-%02d", y, mo, d)
        },
        // MM/DD/YYYY or M/D/YYYY
        DatePattern(regex: #"(\d{1,2})/(\d{1,2})/(\d{4})"#) { m, s in
            guard let mo = substring(s, m.range(at: 1)).flatMap(Int.init),
                  let d = substring(s, m.range(at: 2)).flatMap(Int.init),
                  let y = substring(s, m.range(at: 3)) else { return nil }
            return String(format: "%@-%02d-%02d", y, mo, d)
        },
        // MM-DD-YYYY
        DatePattern(regex: #"(\d{1,2})-(\d{1,2})-(\d{4})"#) { m, s in
            guard let mo = substring(s, m.range(at: 1)).flatMap(Int.init),
                  let d = substring(s, m.range(at: 2)).flatMap(Int.init),
                  let y = substring(s, m.range(at: 3)) else { return nil }
            return String(format: "%@-%02d-%02d", y, mo, d)
        },
        // Month name: "January 15, 2024" / "Jan 15 2024"
        DatePattern(regex: #"(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)[.\s]+(\d{1,2})[,\s]+(\d{4})"#) { m, s in
            guard let monthStr = substring(s, m.range(at: 1)),
                  let dayStr = substring(s, m.range(at: 2)),
                  let yearStr = substring(s, m.range(at: 3)),
                  let month = monthNumber(from: monthStr),
                  let day = Int(dayStr) else { return nil }
            return String(format: "%@-%02d-%02d", yearStr, month, day)
        },
    ]

    // MARK: - Weight extraction

    /// Lookarounds prevent matching digits that are part of a longer
    /// number (e.g. year `2024` → avoids matching `202` or `024`).
    /// Plausible bound for pounds: 50 ≤ x ≤ 700. Returns the first
    /// match in plausible range.
    private static func extractPounds(from line: String) -> Double? {
        let pattern = #"(?<!\d)(\d{2,3}(?:\.\d{1,2})?)(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        for match in matches {
            guard let r = Range(match.range(at: 1), in: line),
                  let value = Double(line[r]) else { continue }
            if value >= 50, value <= 700 { return value }
        }
        return nil
    }

    // MARK: - Helpers

    private static func substring(_ s: String, _ range: NSRange) -> String? {
        Range(range, in: s).map { String(s[$0]) }
    }

    private static func parseISODateOnly(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private static func monthNumber(from name: String) -> Int? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        return months[String(name.prefix(3).lowercased())]
    }
}
