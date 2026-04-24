import Foundation

struct IRCMessage {
    let raw: String
    let prefix: String?
    let command: String
    let params: [String]

    var nickFromPrefix: String? {
        guard let prefix else { return nil }
        if let bang = prefix.firstIndex(of: "!") {
            return String(prefix[prefix.startIndex..<bang])
        }
        return prefix
    }

    static func parse(_ line: String) -> IRCMessage? {
        var rest = line.trimmingCharacters(in: .newlines)
        if rest.isEmpty { return nil }

        var prefix: String?
        if rest.hasPrefix(":") {
            rest.removeFirst()
            if let sp = rest.firstIndex(of: " ") {
                prefix = String(rest[rest.startIndex..<sp])
                rest = String(rest[rest.index(after: sp)...])
            } else {
                return nil
            }
        }

        // Split trailing (prefixed with " :") from the rest
        var trailing: String?
        if let trailingRange = rest.range(of: " :") {
            trailing = String(rest[trailingRange.upperBound...])
            rest = String(rest[rest.startIndex..<trailingRange.lowerBound])
        } else if rest.hasPrefix(":") {
            trailing = String(rest.dropFirst())
            rest = ""
        }

        var tokens = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty || trailing != nil else { return nil }
        let command = tokens.isEmpty ? "" : tokens.removeFirst()
        var params = tokens
        if let trailing { params.append(trailing) }
        return IRCMessage(raw: line, prefix: prefix, command: command.uppercased(), params: params)
    }
}
