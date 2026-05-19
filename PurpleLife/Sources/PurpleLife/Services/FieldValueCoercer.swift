import Foundation

/// Centralized field-value inference and coercion for Purple Import.
/// Replaces the ad-hoc parsing scattered across `StatisticsService`,
/// `WeightCSVImporter`, and `PlaintextSnapshotService`.
///
/// Two responsibilities:
///
/// 1. **Inference** — given a sample of source values from one column
///    (CSV cell strings, JSON leaf values, etc.), guess the best
///    `FieldKind`. The wizard uses this to pre-populate the mapping
///    table's "kind" dropdown; the user can override.
///
/// 2. **Coercion** — given one source value + a target `FieldKind`,
///    produce a value safe to write into `ObjectRecord.fieldsJSON`.
///    Returns a typed result so the import runner can report per-cell
///    errors (skip-row vs fill-default vs abort, per the mapping's
///    `onError` setting).
///
/// All methods are `nonisolated` + pure so they can run from any
/// queue. The wizard preview path calls them from the main actor; the
/// import runner calls them from a Task. No singletons, no side
/// effects.
enum FieldValueCoercer {

    // MARK: - Inference

    /// Best-guess `FieldKind` for a column given up to a few hundred
    /// sample values. Walks the samples once and keeps a vote count
    /// per candidate kind. Ties break in the order: boolean > number
    /// > date > dateTime > url > email > text — i.e. the most
    /// "specific" interpretation wins when ambiguous, so a column of
    /// `"true"`/`"false"` doesn't get classified as text.
    ///
    /// Returns `.text` for empty / all-nil samples — the import is
    /// still possible, the user just has to widen the type in the
    /// mapping editor if they want number / date semantics.
    static func inferKind(samples: [Any?]) -> FieldKind {
        let nonNil = samples.compactMap { $0 }.filter { v in
            if let s = v as? String { return !s.isEmpty }
            return !(v is NSNull)
        }
        guard !nonNil.isEmpty else { return .text }

        var votes: [FieldKind: Int] = [:]
        for v in nonNil {
            if looksBoolean(v) { votes[.boolean, default: 0] += 1 }
            else if looksNumber(v) { votes[.number, default: 0] += 1 }
            else if looksDateOnly(v) { votes[.date, default: 0] += 1 }
            else if looksDateTime(v) { votes[.dateTime, default: 0] += 1 }
            else if looksURL(v) { votes[.url, default: 0] += 1 }
            else if looksEmail(v) { votes[.email, default: 0] += 1 }
            else { votes[.text, default: 0] += 1 }
        }
        let order: [FieldKind] = [.boolean, .number, .date, .dateTime, .url, .email, .text]
        // The "specific wins on tie" rule: pick the kind with the
        // highest vote count, and among kinds with equal counts, pick
        // the one earlier in `order`. We need ≥ 80% of non-nil samples
        // to support a non-text classification — a single typo'd row
        // shouldn't drag a clean number column into .text territory.
        let total = nonNil.count
        var best: FieldKind = .text
        var bestCount = -1
        for kind in order {
            let count = votes[kind] ?? 0
            if kind != .text, Double(count) / Double(total) < 0.8 { continue }
            if count > bestCount {
                bestCount = count
                best = kind
            }
        }
        return best
    }

    // MARK: - Coercion

    enum CoercionError: Error, CustomStringConvertible {
        case empty
        case notBoolean(String)
        case notNumber(String)
        case notDate(String)
        case notDateTime(String)
        case notRating(String)
        case unsupportedTargetKind(FieldKind)

        var description: String {
            switch self {
            case .empty:                       return "empty value"
            case .notBoolean(let s):           return "‘\(s)’ is not a boolean"
            case .notNumber(let s):            return "‘\(s)’ is not a number"
            case .notDate(let s):              return "‘\(s)’ is not a date"
            case .notDateTime(let s):          return "‘\(s)’ is not a date-time"
            case .notRating(let s):            return "‘\(s)’ is not 0–5"
            case .unsupportedTargetKind(let k): return "import to \(k.displayName) not supported"
            }
        }
    }

    enum CoercionResult {
        case value(Any)         // a value safe to write into fields_json
        case empty              // source was empty/nil; caller applies default/required
        case failure(CoercionError)
    }

    /// Coerce a single source value to the target kind. The returned
    /// `.value(Any)` payload is in the shape `ObjectRecord.fieldsJSON`
    /// expects: `String` / `Double` / `Bool` / ISO-8601 string for
    /// dates / array of option ids for multiSelect / etc.
    ///
    /// Field kinds that can't be sensibly auto-coerced from a primitive
    /// source value (`.richText`, `.noteLog`, `.attachment`, `.link`)
    /// fail with `.unsupportedTargetKind` — the wizard surfaces this
    /// in the preview step so the user picks a different target kind
    /// or maps the column elsewhere. `.attachment` is handled
    /// separately by the runner (file path → sha256 via
    /// `AttachmentService.add`); the coercer just rejects raw values.
    static func coerce(_ value: Any?, to kind: FieldKind, fieldOptions: [FieldOption] = []) -> CoercionResult {
        // Treat nil / NSNull / empty-trimmed-string as empty.
        if value == nil || value is NSNull {
            return .empty
        }
        if let s = value as? String, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        let raw = value!

        switch kind {
        case .text:
            return .value(stringValue(raw))
        case .longText:
            return .value(stringValue(raw))
        case .url:
            return .value(stringValue(raw))
        case .email:
            return .value(stringValue(raw))

        case .boolean:
            if let b = asBool(raw) { return .value(b) }
            return .failure(.notBoolean(stringValue(raw)))

        case .number:
            if let n = asNumber(raw) { return .value(n) }
            return .failure(.notNumber(stringValue(raw)))

        case .rating:
            // Always clip to 0…5. The rejection-on-overflow shape was
            // too strict — sourced data routinely has "7 stars" or
            // negative values from older systems; the safer default is
            // to clip and proceed.
            if let n = asNumber(raw) {
                let clipped = max(0, min(5, Int(n.rounded())))
                return .value(clipped)
            }
            return .failure(.notRating(stringValue(raw)))

        case .date:
            if let d = asDate(raw) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                // Match the parse-side timezone (UTC) so a date that
                // came in as "2024-01-15" doesn't shift back to the
                // 14th when stringified through the user's local
                // timezone offset.
                f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = "yyyy-MM-dd"
                return .value(f.string(from: d))
            }
            return .failure(.notDate(stringValue(raw)))

        case .dateTime:
            if let d = asDate(raw) {
                let f = ISO8601DateFormatter()
                return .value(f.string(from: d))
            }
            return .failure(.notDateTime(stringValue(raw)))

        case .select:
            // Match on option name (case-insensitive). If the value
            // doesn't match any option, fall through to text — the
            // wizard's preview shows a warning and the user can either
            // add the option to the schema (inline edit) or remap.
            let s = stringValue(raw)
            if let match = fieldOptions.first(where: {
                $0.name.caseInsensitiveCompare(s) == .orderedSame
            }) {
                return .value(match.id)
            }
            return .value(s)  // unknown option → store the raw label

        case .multiSelect:
            // Accept either an array of option labels or a single
            // delimiter-joined string ("a, b, c" or "a; b; c").
            let strings: [String]
            if let arr = raw as? [Any] {
                strings = arr.map { stringValue($0) }
            } else {
                let s = stringValue(raw)
                strings = s.components(separatedBy: CharacterSet(charactersIn: ",;|"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            let ids: [String] = strings.map { label in
                fieldOptions.first { $0.name.caseInsensitiveCompare(label) == .orderedSame }?.id ?? label
            }
            return .value(ids)

        case .richText, .noteLog, .attachment, .link:
            return .failure(.unsupportedTargetKind(kind))
        }
    }

    // MARK: - Type probes (also used as voting predicates)

    private static let booleanTrueLiterals: Set<String> = ["true", "yes", "y", "1", "t"]
    private static let booleanFalseLiterals: Set<String> = ["false", "no", "n", "0", "f"]

    private static func looksBoolean(_ v: Any) -> Bool {
        if let b = v as? Bool { _ = b; return true }
        let s = stringValue(v).trimmingCharacters(in: .whitespaces).lowercased()
        return booleanTrueLiterals.contains(s) || booleanFalseLiterals.contains(s)
    }

    private static func looksNumber(_ v: Any) -> Bool {
        if v is Bool { return false }
        if let _ = v as? Double { return true }
        if let _ = v as? Int { return true }
        if let n = v as? NSNumber {
            return CFGetTypeID(n) != CFBooleanGetTypeID()
        }
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return false }
        // Allow comma thousands separators but not commas as decimal.
        let cleaned = s.replacingOccurrences(of: ",", with: "")
        return Double(cleaned) != nil
    }

    private static func looksDateOnly(_ v: Any) -> Bool {
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        // YYYY-MM-DD, YYYY/MM/DD, MM/DD/YYYY, M/D/YYYY (US-ish)
        let patterns = [
            "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
            "^[0-9]{4}/[0-9]{2}/[0-9]{2}$",
            "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$",
        ]
        return patterns.contains { matchesRegex(s, pattern: $0) }
    }

    private static func looksDateTime(_ v: Any) -> Bool {
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        // ISO-8601 with a 'T' separator is the unambiguous form.
        return s.contains("T") && ISO8601DateFormatter().date(from: s) != nil
    }

    private static func looksURL(_ v: Any) -> Bool {
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        return s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    private static func looksEmail(_ v: Any) -> Bool {
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        // Cheap probe — not a full RFC 5321 validator. Voting only.
        return s.contains("@") && s.contains(".") && !s.contains(" ") && s.count >= 5
    }

    // MARK: - Coercion helpers

    private static func stringValue(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        }
        return String(describing: v)
    }

    private static func asBool(_ v: Any) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
            return n.boolValue
        }
        let s = stringValue(v).trimmingCharacters(in: .whitespaces).lowercased()
        if booleanTrueLiterals.contains(s) { return true }
        if booleanFalseLiterals.contains(s) { return false }
        return nil
    }

    private static func asNumber(_ v: Any) -> Double? {
        if v is Bool { return nil }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            return n.doubleValue
        }
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return Double(s.replacingOccurrences(of: ",", with: ""))
    }

    /// Tries ISO-8601 (with and without fractional seconds), then
    /// `yyyy-MM-dd`, then a few common slash-separated forms. As a
    /// final fallback, if the input is a numeric value in the Excel
    /// date-serial range, treat it as a serial (days since
    /// 1899-12-30). Returns nil if nothing matches.
    static func asDate(_ v: Any) -> Date? {
        if let d = v as? Date { return d }
        let s = stringValue(v).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "M/d/yyyy", "MM/dd/yyyy"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }

        // Excel-serial fallback. Pivot tables and certain other
        // workbook shapes drop the date number-format from the
        // underlying cells, so XLSXReader's style-aware date
        // conversion misses them and we end up seeing values like
        // "43478" land here. Range gate: 1..100000 covers
        // 1900-01-01 through 2173, which more than covers any
        // realistic spreadsheet date. Below 1 we'd map to negative
        // dates; above 100000 it's almost certainly a real number.
        if let serial = Double(s), serial >= 1, serial <= 100_000 {
            return dateFromExcelSerial(serial)
        }
        return nil
    }

    /// Excel's day count starts at 1899-12-30 (the offset that
    /// reconciles the 1900-leap-year bug). Fractional part is the
    /// time of day. UTC throughout — same as `asDate`'s other paths.
    private static func dateFromExcelSerial(_ serial: Double) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let epoch = cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 1899, month: 12, day: 30
        )) else { return nil }
        let wholeDays = Int(serial.rounded(.towardZero))
        let fractional = serial - Double(wholeDays)
        guard let dayDate = cal.date(byAdding: .day, value: wholeDays, to: epoch) else {
            return nil
        }
        let seconds = Int((fractional * 86_400).rounded())
        return dayDate.addingTimeInterval(TimeInterval(seconds))
    }

    private static func matchesRegex(_ s: String, pattern: String) -> Bool {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return r.firstMatch(in: s, options: [], range: range) != nil
    }
}
