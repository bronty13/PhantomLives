import Foundation

/// Tiny helpers for formatting `Int64` cents as currency, and round-tripping
/// user-entered dollar strings (e.g. "1,234.56") back to cents. Storing money
/// as integer cents avoids floating-point drift on totals.
enum Money {
    static func format(cents: Int64?) -> String {
        guard let cents else { return "—" }
        let dollars = Double(cents) / 100.0
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = Locale(identifier: "en_US")
        return fmt.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }

    /// Parse a user-entered dollar string into cents. Strips `$`, commas, and
    /// whitespace. Returns `nil` on empty input.
    static func parse(_ text: String) -> Int64? {
        let trimmed = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let v = Double(trimmed) else { return nil }
        return Int64((v * 100).rounded())
    }
}
