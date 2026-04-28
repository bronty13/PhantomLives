import Foundation

/// Parses the `#{start,step,format}` counter token used in replacement strings.
public struct CounterToken: Sendable, Equatable {
    public let start: Int
    public let step: Int
    public let format: String   // printf-style, e.g. "%04d"
    public let raw: String      // the substring to substitute

    /// Returns the FIRST counter token found in the template, or nil.
    public static func parse(template: String) -> CounterToken? {
        // Match #{int,int,format}
        let pattern = #"#\{(-?\d+),(-?\d+),([^}]*)\}"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = template as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: template, range: range) else { return nil }
        let raw = ns.substring(with: m.range)
        let start = Int(ns.substring(with: m.range(at: 1))) ?? 0
        let step = Int(ns.substring(with: m.range(at: 2))) ?? 1
        let format = ns.substring(with: m.range(at: 3))
        return CounterToken(start: start, step: step, format: format, raw: raw)
    }

    public func render(value: Int, template: String) -> String {
        let formatted = String(format: format.isEmpty ? "%d" : format, value)
        return template.replacingOccurrences(of: raw, with: formatted)
    }
}
