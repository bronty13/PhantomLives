import Foundation

/// Stream-decoded shape of a single ripgrep `--json` event.
/// We model only the subset we consume.
public enum RipgrepJSONEvent: Sendable {
    case begin(path: String)
    case match(path: String, lineNumber: Int, lines: String, submatches: [Submatch])
    case end(path: String, stats: Stats)
    case summary(stats: Stats)
    case context(path: String, lineNumber: Int, lines: String)

    public struct Submatch: Sendable, Codable, Hashable {
        public let start: Int
        public let end: Int
        public let matchText: String
    }

    public struct Stats: Sendable, Codable, Hashable {
        public let matches: Int
        public let bytesSearched: Int
    }
}

enum RipgrepJSONDecoder {

    /// Decode one line of `rg --json` output into a high-level event.
    /// Returns nil for events we don't model (we ignore noise).
    static func decode(line: Data) -> RipgrepJSONEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String,
              let data = obj["data"] as? [String: Any]
        else { return nil }

        func textValue(_ any: Any?) -> String {
            if let s = any as? [String: Any] {
                if let t = s["text"] as? String { return t }
                if let b64 = s["bytes"] as? String,
                   let raw = Data(base64Encoded: b64),
                   let s = String(data: raw, encoding: .utf8) {
                    return s
                }
            }
            return any as? String ?? ""
        }

        switch type {
        case "begin":
            let path = textValue((data["path"] as Any))
            return .begin(path: path)

        case "match":
            let path = textValue(data["path"])
            let line = (data["line_number"] as? Int) ?? 0
            let lines = textValue(data["lines"])
            var submatches: [RipgrepJSONEvent.Submatch] = []
            if let arr = data["submatches"] as? [[String: Any]] {
                for sm in arr {
                    let start = sm["start"] as? Int ?? 0
                    let end = sm["end"] as? Int ?? 0
                    let mt = textValue(sm["match"])
                    submatches.append(.init(start: start, end: end, matchText: mt))
                }
            }
            return .match(path: path, lineNumber: line, lines: lines, submatches: submatches)

        case "end":
            let path = textValue(data["path"])
            let stats: RipgrepJSONEvent.Stats
            if let s = data["stats"] as? [String: Any] {
                stats = .init(
                    matches: (s["matches"] as? Int) ?? 0,
                    bytesSearched: (s["bytes_searched"] as? Int) ?? 0
                )
            } else {
                stats = .init(matches: 0, bytesSearched: 0)
            }
            return .end(path: path, stats: stats)

        case "summary":
            let s = (data["stats"] as? [String: Any]) ?? [:]
            return .summary(stats: .init(
                matches: (s["matches"] as? Int) ?? 0,
                bytesSearched: (s["bytes_searched"] as? Int) ?? 0
            ))

        case "context":
            let path = textValue(data["path"])
            let line = (data["line_number"] as? Int) ?? 0
            let lines = textValue(data["lines"])
            return .context(path: path, lineNumber: line, lines: lines)

        default:
            return nil
        }
    }
}
