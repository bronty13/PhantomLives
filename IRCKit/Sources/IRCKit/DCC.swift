import Foundation

/// Pure DCC (Direct Client-to-Client) helpers: parsing inbound offers,
/// sanitizing offered filenames, and validating offered peer addresses. No
/// sockets and no UI — the security-critical logic lives here, in ONE audited
/// copy shared by every PhantomLives IRC app. Transport (NWListener /
/// NWConnection) and orchestration (accept prompts, transfer windows) belong in
/// the app layer that consumes this.
///
/// Why this matters: a DCC SEND/CHAT offer carries the peer's IP and port,
/// which the client dials when the user accepts — so an unvalidated host is an
/// SSRF primitive. `validatedPeerHost` accepts only real IP literals (rejecting
/// hostnames, loopback, unspecified, and link-local) while still allowing
/// RFC1918 ranges so on-LAN DCC keeps working. Offered filenames are sanitized
/// so a `../` or absolute path can't escape the downloads directory.
public enum DCC {

    public enum Kind: String, Equatable, Sendable { case chat, send }

    /// A parsed, validated inbound DCC offer.
    public struct Offer: Equatable, Sendable {
        public let kind: Kind
        /// SEND only; already sanitized to a safe single filename.
        public let filename: String?
        /// Validated IP literal (dotted IPv4 or IPv6) — safe to dial.
        public let host: String
        public let port: UInt16
        /// SEND only; advertised byte count (0 if absent/unparseable).
        public let size: UInt64?

        public init(kind: Kind, filename: String?, host: String, port: UInt16, size: UInt64?) {
            self.kind = kind; self.filename = filename; self.host = host; self.port = port; self.size = size
        }
    }

    /// Outcome of parsing the argument string of a `CTCP DCC <args>` message.
    public enum OfferParse: Equatable, Sendable {
        case offer(Offer)
        /// A SEND/CHAT whose peer address failed validation (SSRF guard). The
        /// associated value is the offending token, for surfacing to the user.
        case rejectedUnsafeAddress(String)
        /// Not a DCC SEND/CHAT we act on (unknown subcommand, bad arity/port).
        case unsupported
    }

    /// Parse a `CTCP DCC <args>` argument string (the part after "DCC ").
    public static func parseOffer(_ args: String) -> OfferParse {
        let t = tokenize(args)
        guard let sub = t.first?.uppercased() else { return .unsupported }
        switch sub {
        case "SEND":
            guard t.count >= 5, let port = UInt16(t[3]) else { return .unsupported }
            guard let host = validatedPeerHost(t[2]) else { return .rejectedUnsafeAddress(t[2]) }
            return .offer(Offer(kind: .send, filename: sanitizeFilename(t[1]),
                                host: host, port: port, size: UInt64(t[4]) ?? 0))
        case "CHAT":
            guard t.count >= 4, t[1].lowercased() == "chat", let port = UInt16(t[3]) else { return .unsupported }
            guard let host = validatedPeerHost(t[2]) else { return .rejectedUnsafeAddress(t[2]) }
            return .offer(Offer(kind: .chat, filename: nil, host: host, port: port, size: nil))
        default:
            return .unsupported
        }
    }

    // MARK: - Filename sanitization

    /// Strip every character class an attacker could use to escape the intended
    /// filename (directory separators, NUL, control bytes, `..`), returning a
    /// safe single path component. Never empty.
    public static func sanitizeFilename(_ s: String) -> String {
        var cleaned = String(s.unicodeScalars.map { sc -> Character in
            if sc.value < 0x20 || sc.value == 0x7F { return "_" }
            switch sc {
            case "/", "\\", ":": return "_"
            default: return Character(sc)
            }
        })
        cleaned = cleaned.replacingOccurrences(of: "..", with: "_")
        let lastComponent = (cleaned as NSString).lastPathComponent
        let trimmed = lastComponent
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "." })
        let final = String(trimmed)
        if final.isEmpty || final.allSatisfy({ $0 == "." || $0 == "_" }) {
            return "dcc-file"
        }
        return String(final.prefix(255))
    }

    // MARK: - Peer-address validation (SSRF guard)

    /// Validate a DCC-offered peer address. Accepts the classic integer-IPv4
    /// encoding, dotted IPv4, and IPv6 literals; returns a dialable host string,
    /// or nil for hostnames / loopback / unspecified / link-local / garbage.
    public static func validatedPeerHost(_ token: String) -> String? {
        if let n = UInt32(token) {
            let dotted = "\((n >> 24) & 0xFF).\((n >> 16) & 0xFF).\((n >> 8) & 0xFF).\(n & 0xFF)"
            return isSafeIPv4(dotted) ? dotted : nil
        }
        var v4 = in_addr()
        if inet_pton(AF_INET, token, &v4) == 1 {
            return isSafeIPv4(token) ? token : nil
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, token, &v6) == 1 {
            let lower = token.lowercased()
            if lower == "::1" || lower == "::" || lower.hasPrefix("fe80") { return nil }
            return token
        }
        return nil   // not an IP literal — no hostname dialing
    }

    /// True if `dotted` is a routable IPv4 we'll dial: rejects 0.x, 127.x
    /// (loopback), and 169.254.x (link-local). RFC1918 LAN ranges are allowed.
    public static func isSafeIPv4(_ dotted: String) -> Bool {
        let o = dotted.split(separator: ".").compactMap { UInt32($0) }
        guard o.count == 4, o.allSatisfy({ $0 <= 255 }) else { return false }
        if o[0] == 0 || o[0] == 127 { return false }
        if o[0] == 169 && o[1] == 254 { return false }
        return true
    }

    /// Dotted IPv4 → classic DCC 32-bit integer; 0 on malformed input.
    public static func ipv4StringToInt(_ s: String) -> UInt32 {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    // MARK: - Initiating (advertising)

    /// The CTCP body to offer a DCC chat: `DCC CHAT chat <ip-int> <port>`.
    public static func chatOfferCommand(ip: String, port: UInt16) -> String {
        "DCC CHAT chat \(ipv4StringToInt(ip)) \(port)"
    }

    /// The CTCP body to offer a file: `DCC SEND <name> <ip-int> <port> <size>`.
    /// The filename is sanitized (and, if it contains spaces, quoted).
    public static func sendOfferCommand(filename: String, ip: String, port: UInt16, size: UInt64) -> String {
        let name = sanitizeFilename(filename)
        let field = name.contains(" ") ? "\"\(name)\"" : name
        return "DCC SEND \(field) \(ipv4StringToInt(ip)) \(port) \(size)"
    }

    /// Our primary routable IPv4 to advertise in an offer (prefers `en0`).
    /// Returns nil if only loopback is up.
    public static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }
        var candidate: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let c = cursor {
            let name = String(cString: c.pointee.ifa_name)
            let flags = Int32(c.pointee.ifa_flags)
            if let addrPtr = c.pointee.ifa_addr, addrPtr.pointee.sa_family == UInt8(AF_INET),
               (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addrPtr, socklen_t(addrPtr.pointee.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let addr = String(cString: host)
                    if name == "en0" { return addr }
                    if candidate == nil { candidate = addr }
                }
            }
            cursor = c.pointee.ifa_next
        }
        return candidate
    }

    // MARK: - Internal

    /// Split a DCC argument string on spaces, honoring "double quotes" (so a
    /// filename with spaces stays one token).
    static func tokenize(_ args: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for ch in args {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == " ", !inQuotes {
                if !current.isEmpty { out.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
