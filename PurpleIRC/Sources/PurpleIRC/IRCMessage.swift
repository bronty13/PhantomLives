import Foundation

struct IRCMessage {
    let raw: String
    /// IRCv3 message tags. Empty when the server didn't send a leading
    /// `@`-block. Values are already unescaped (`\:`→`;`, `\s`→space, etc.)
    /// per the IRCv3 message-tags spec.
    let tags: [String: String]
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

    /// Parsed `@time=` ISO-8601 tag, or nil. Servers use this in CHATHISTORY
    /// replays and any time the `server-time` cap is negotiated, so the
    /// client should prefer it over `Date()` when available.
    var serverTime: Date? {
        guard let raw = tags["time"] else { return nil }
        return IRCMessage.iso8601Parser.date(from: raw)
            ?? IRCMessage.iso8601ParserNoFraction.date(from: raw)
    }

    /// IRCv3 message-id, used by reactions / replies / message-redaction
    /// drafts. Surfaced now so the UI can attach data to specific lines as
    /// the spec lands.
    var msgID: String? { tags["msgid"] ?? tags["draft/msgid"] }

    /// `account-tag` cap value — the user's services account, when available.
    /// nil before the cap is negotiated or for unauthed users.
    var account: String? {
        guard let v = tags["account"], !v.isEmpty, v != "*" else { return nil }
        return v
    }

    /// IRCv3 BATCH membership reference. Server tags this on every line
    /// that belongs to a batch the client is currently buffering.
    var batchRef: String? { tags["batch"] }

    static func parse(_ line: String) -> IRCMessage? {
        var rest = line.trimmingCharacters(in: .newlines)
        if rest.isEmpty { return nil }
        // Reject lines containing NUL (forbidden by RFC 1459) so a server
        // can't smuggle binary garbage into nick / channel / target fields
        // that downstream code uses as buffer keys or file slugs.
        if rest.contains("\0") { return nil }

        // IRCv3 message tags — leading "@k1=v1;k2=v2 ".
        var tags: [String: String] = [:]
        if rest.hasPrefix("@") {
            rest.removeFirst()
            if let sp = rest.firstIndex(of: " ") {
                tags = parseTags(String(rest[rest.startIndex..<sp]))
                rest = String(rest[rest.index(after: sp)...])
            } else {
                return nil
            }
        }

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
        return IRCMessage(raw: line, tags: tags, prefix: prefix,
                          command: command.uppercased(), params: params)
    }

    /// Split `@`-block content (`k1=v1;k2;k3=v3`) into a dictionary, applying
    /// IRCv3 tag-value escapes. Tags without `=` map to an empty string.
    private static func parseTags(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for token in s.split(separator: ";", omittingEmptySubsequences: true) {
            let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair[0])
            guard !key.isEmpty else { continue }
            let raw = pair.count > 1 ? String(pair[1]) : ""
            out[key] = unescapeTagValue(raw)
        }
        return out
    }

    /// IRCv3 tag-value escape table. The spec is small enough that a single
    /// pass over the string is faster than running a regex.
    private static func unescapeTagValue(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = String()
        out.reserveCapacity(s.count)
        var iter = s.makeIterator()
        while let c = iter.next() {
            guard c == "\\" else { out.append(c); continue }
            switch iter.next() {
            case ":"?:  out.append(";")
            case "s"?:  out.append(" ")
            case "r"?:  out.append("\r")
            case "n"?:  out.append("\n")
            case "\\"?: out.append("\\")
            case let other?: out.append(other)
            case nil:
                // Dangling backslash: malformed per IRCv3 but preserve it
                // so debugging a buggy server doesn't have to guess where
                // the value got truncated.
                out.append("\\")
            }
        }
        return out
    }

    private static let iso8601Parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601ParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// IRC line / field sanitization. Outbound lines must not contain CR, LF, or
/// NUL — those are protocol terminators and any user-controlled string that
/// ends up in a PRIVMSG, NOTICE, JOIN, channel name, or topic must be
/// scrubbed before it's interpolated into the wire format.
enum IRCSanitize {
    /// Strip CR / LF / NUL from a single field (nick, channel, target, body).
    /// Use at API boundaries that take user/script input *before* assembling
    /// the IRC line. This collapses a multi-line `text` into a single line
    /// rather than silently truncating it at the first newline.
    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) else { return s }
        return String(s.unicodeScalars.filter { $0 != "\r" && $0 != "\n" && $0 != "\0" })
    }

    /// Strip CR / LF / NUL from a fully-assembled IRC line. Defence-in-depth
    /// at the wire seam — every send() path runs through this so a missed
    /// callsite can't smuggle a second command.
    static func line(_ s: String) -> String { field(s) }

    /// Mask credentials in a raw IRC line for *display / log* purposes only.
    /// Recognises the three credential-bearing patterns we send:
    ///   - `PRIVMSG NickServ :IDENTIFY <pw>` (and `IDENTIFY <acct> <pw>`)
    ///   - `PASS <pw>` (server password, sent before NICK/USER)
    ///   - `AUTHENTICATE <base64>` (SASL — non-control payloads)
    /// The wire send is left untouched. Returns the input unchanged when
    /// no credential pattern matches.
    static func maskForDisplay(_ line: String) -> String {
        if let r = line.range(of: #"^PASS\s+\S.*$"#,
                              options: [.regularExpression, .caseInsensitive]) {
            return line.replacingCharacters(in: r, with: "PASS ****")
        }
        if let r = line.range(of: #"^AUTHENTICATE\s+\S+"#,
                              options: [.regularExpression, .caseInsensitive]) {
            // Leave control markers (+, *) visible — they carry no secret.
            let payload = line[r].split(separator: " ", maxSplits: 1)
                .last.map(String.init) ?? ""
            if payload == "+" || payload == "*" { return line }
            return line.replacingCharacters(in: r, with: "AUTHENTICATE ****")
        }
        // PRIVMSG NickServ :IDENTIFY [acct] pass — match outbound (no prefix)
        // and the inbound echo (`:nick!user@host PRIVMSG NickServ :IDENTIFY ...`)
        // both. The regex looks for the verb anywhere on the line so the
        // optional `:prefix ` part doesn't hide the secret in echo-message.
        if line.range(of: #"(?i)PRIVMSG\s+NickServ\s+:IDENTIFY\s+.+$"#,
                      options: .regularExpression) != nil,
           let identifyEnd = line.range(of: "IDENTIFY", options: .caseInsensitive)?.upperBound {
            return String(line[..<identifyEnd]) + " ****"
        }
        return line
    }
}
