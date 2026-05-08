import Foundation

/// Minimal RFC 5322 parser. We only care about three headers
/// (From, Subject, Date) and the body — enough to seed a Matter title
/// and description from a dropped `.eml`.
enum EmailParser {

    struct Parsed {
        let from: String
        let subject: String
        let date: Date?
        let body: String
    }

    static func parse(_ raw: String) -> Parsed {
        // Split on the first blank line (CRLF or LF) — that's headers vs body.
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let headerBlock = parts.first ?? ""
        let body = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Unfold continued headers (lines starting with whitespace are
        // continuations of the previous header per RFC 5322 §2.2.3).
        var unfolded: [String] = []
        for line in headerBlock.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if (line.first == " " || line.first == "\t"), var last = unfolded.last {
                last += " " + line.trimmingCharacters(in: .whitespaces)
                unfolded[unfolded.count - 1] = last
            } else {
                unfolded.append(line)
            }
        }

        var headers: [String: String] = [:]
        for line in unfolded {
            if let i = line.firstIndex(of: ":") {
                let name = line[..<i].lowercased().trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }
        return Parsed(
            from: headers["from"] ?? "",
            subject: headers["subject"] ?? "",
            date: parseEmailDate(headers["date"]),
            body: body
        )
    }

    private static func parseEmailDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let formatters = ["EEE, d MMM yyyy HH:mm:ss Z",
                          "d MMM yyyy HH:mm:ss Z"]
        for fmt in formatters {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
