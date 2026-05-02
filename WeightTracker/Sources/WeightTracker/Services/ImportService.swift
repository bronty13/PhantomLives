import Foundation

struct ParsedEntry: Identifiable {
    let id = UUID()
    var date: String
    var weightLbs: Double
    var isDuplicate: Bool = false
    var isSelected: Bool = true
}

struct ImportService {
    static func parse(text: String, unit: WeightUnit, existingDates: Set<String>) -> [ParsedEntry] {
        var results: [ParsedEntry] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let date = extractDate(from: line) else { continue }
            guard let weight = extractWeight(from: line, unit: unit) else { continue }
            let weightLbs = unit == .lbs ? weight : weight / 0.453592
            let isDup = existingDates.contains(date)
            results.append(ParsedEntry(date: date, weightLbs: weightLbs, isDuplicate: isDup))
        }

        let seen = NSMutableOrderedSet()
        return results.filter { entry in
            if seen.contains(entry.date) { return false }
            seen.add(entry.date)
            return true
        }
    }

    private static func extractDate(from line: String) -> String? {
        let patterns: [(regex: String, handler: (NSTextCheckingResult, String) -> String?)] = [
            // ISO-8601: 2024-01-15
            (#"(\d{4})-(\d{1,2})-(\d{1,2})"#, { m, s in
                let y = substring(s, m.range(at: 1))
                let mo = substring(s, m.range(at: 2)).map { String(format: "%02d", Int($0)!) }
                let d = substring(s, m.range(at: 3)).map { String(format: "%02d", Int($0)!) }
                return [y, mo, d].compactMap { $0 }.joined(separator: "-")
            }),
            // MM/DD/YYYY or M/D/YYYY
            (#"(\d{1,2})/(\d{1,2})/(\d{4})"#, { m, s in
                let mo = substring(s, m.range(at: 1)).map { String(format: "%02d", Int($0)!) }
                let d = substring(s, m.range(at: 2)).map { String(format: "%02d", Int($0)!) }
                let y = substring(s, m.range(at: 3))
                return [y, mo, d].compactMap { $0 }.joined(separator: "-")
            }),
            // MM-DD-YYYY
            (#"(\d{1,2})-(\d{1,2})-(\d{4})"#, { m, s in
                let mo = substring(s, m.range(at: 1)).map { String(format: "%02d", Int($0)!) }
                let d = substring(s, m.range(at: 2)).map { String(format: "%02d", Int($0)!) }
                let y = substring(s, m.range(at: 3))
                return [y, mo, d].compactMap { $0 }.joined(separator: "-")
            }),
            // Month name: January 15, 2024 or Jan 15 2024
            (#"(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)[.\s]+(\d{1,2})[,\s]+(\d{4})"#, { m, s in
                guard let monthStr = substring(s, m.range(at: 1)),
                      let dayStr = substring(s, m.range(at: 2)),
                      let yearStr = substring(s, m.range(at: 3)),
                      let month = monthNumber(from: monthStr),
                      let day = Int(dayStr) else { return nil }
                return String(format: "%@-%02d-%02d", yearStr, month, day)
            }),
        ]

        for (pattern, handler) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if let date = handler(match, line), isValidDate(date) {
                    return date
                }
            }
        }
        return nil
    }

    private static func extractWeight(from line: String, unit: WeightUnit) -> Double? {
        // Lookarounds prevent matching digits that are part of a longer number (e.g. year 2024 → avoids matching 202)
        let pattern = #"(?<!\d)(\d{2,3}(?:\.\d{1,2})?)(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)

        for match in matches {
            guard let r = Range(match.range(at: 1), in: line),
                  let value = Double(line[r]) else { continue }
            // Plausible weight range
            if unit == .lbs && value >= 50 && value <= 700 { return value }
            if unit == .kg && value >= 20 && value <= 320 { return value }
        }
        return nil
    }

    private static func substring(_ s: String, _ range: NSRange) -> String? {
        Range(range, in: s).map { String(s[$0]) }
    }

    private static func isValidDate(_ dateStr: String) -> Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: dateStr) != nil
    }

    private static func monthNumber(from name: String) -> Int? {
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        return months[String(name.prefix(3).lowercased())]
    }
}
