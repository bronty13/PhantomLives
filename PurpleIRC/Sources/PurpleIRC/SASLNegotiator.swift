import Foundation

/// Pure state machine driving IRCv3 CAP + SASL negotiation and the initial
/// NICK/USER registration burst. IRCClient owns the socket; this type owns the
/// protocol decisions so it can be unit-tested without any networking.
final class SASLNegotiator {
    enum Phase: Equatable {
        case idle          // not yet started
        case awaitingLS    // CAP LS sent, waiting for response
        case awaitingACK   // CAP REQ sent, waiting for ACK/NAK
        case authenticating
        case done          // CAP END sent (success, bypass, or abort)
    }

    /// Caps we want to enable. Order doesn't matter; the server sends them
    /// back in any order it likes. `chathistory` is included so the
    /// IRCConnection can probe `CAP LS` for the upper-bound parameter.
    static let desiredCaps: [String] = [
        "sasl",
        "server-time",
        "multi-prefix",
        "echo-message",
        "away-notify",
        "account-notify",
        "extended-join",
        "account-tag",
        "message-tags",
        "batch",
        "chathistory",
        "draft/chathistory",
        "labeled-response",
        "msgid",
    ]

    /// Caps the server offered AND we asked for (intersection). Filled as
    /// CAP ACK frames arrive so the rest of the client can guard behaviour
    /// on what's actually live.
    private(set) var enabledCaps: Set<String> = []

    /// Server-advertised caps with their `=value` arguments. Lets the rest
    /// of the client read e.g. `chathistory=400` to learn the max replay.
    private(set) var serverCapValues: [String: String] = [:]

    private(set) var phase: Phase = .idle
    private let config: IRCConnectionConfig

    /// Buffer for multi-frame `CAP LS` replies. The server uses
    /// `CAP * LS * :...` to signal "more caps follow"; we don't act until
    /// we see the terminator frame (no `*` separator).
    private var lsBuffer: [(name: String, value: String?)] = []

    init(config: IRCConnectionConfig) {
        self.config = config
    }

    /// Lines to send immediately after the socket becomes ready. Always runs
    /// CAP LS 302 — even without SASL we want server-time, multi-prefix,
    /// echo-message, etc. The negotiator finishes negotiation by sending
    /// CAP END once the wishlist intersection has been requested.
    func registrationCommands() -> [String] {
        var lines: [String] = []
        lines.append("CAP LS 302")
        if let pw = config.serverPassword, !pw.isEmpty {
            lines.append("PASS \(pw)")
        }
        lines.append("NICK \(config.nick)")
        lines.append("USER \(config.user) 0 * :\(config.realName)")
        phase = .awaitingLS
        return lines
    }

    /// Feed every inbound IRCMessage in; returns lines to send in response.
    /// Returning an empty array means "no action" — the caller still delivers
    /// the message to higher layers.
    func handle(_ msg: IRCMessage) -> [String] {
        switch msg.command.uppercased() {
        case "CAP":          return handleCAP(msg)
        case "AUTHENTICATE": return handleAUTHENTICATE(msg)
        case "903":          return finishIfActive()                 // RPL_SASLSUCCESS
        case "902", "904", "905", "906", "907":
            // Aborted / failed / already-authed / abort — close cap negotiation
            // and let the server finish registration anyway.
            return finishIfActive()
        default:
            return []
        }
    }

    private func finishIfActive() -> [String] {
        guard phase != .done else { return [] }
        phase = .done
        return ["CAP END"]
    }

    private func handleCAP(_ msg: IRCMessage) -> [String] {
        // CAP <target> <subcommand> [<args>...] [:payload]
        guard msg.params.count >= 2 else { return [] }
        let sub = msg.params[1].uppercased()
        switch sub {
        case "LS":
            guard phase == .awaitingLS else { return [] }
            // "CAP * LS * :..." signals another LS frame follows. Buffer until
            // we see the non-continuation frame, then act once on the union.
            let isContinuation = msg.params.count >= 4 && msg.params[2] == "*"
            let payload = msg.params.last ?? ""
            for token in payload.split(separator: " ", omittingEmptySubsequences: true) {
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                let value = parts.count > 1 ? String(parts[1]) : nil
                lsBuffer.append((name, value))
            }
            if isContinuation { return [] }

            // Final frame received — record what the server offers and pick
            // the intersection with our wishlist.
            for entry in lsBuffer {
                if let v = entry.value { serverCapValues[entry.name] = v }
            }
            let offered = Set(lsBuffer.map { $0.name })
            lsBuffer.removeAll(keepingCapacity: false)

            let toRequest = Self.desiredCaps.filter { offered.contains($0) }
            guard !toRequest.isEmpty else {
                phase = .done
                return ["CAP END"]
            }
            phase = .awaitingACK
            // Server-side line-length limit is 510 bytes; our request list is
            // short enough that splitting isn't worth the complexity here.
            return ["CAP REQ :" + toRequest.joined(separator: " ")]

        case "ACK":
            guard phase == .awaitingACK else { return [] }
            // Record the granted caps so callers can guard behaviour. The
            // payload is space-separated names, optionally each prefixed with
            // `-` (server is dropping a cap we previously held).
            let payload = msg.params.last ?? ""
            for token in payload.split(separator: " ", omittingEmptySubsequences: true) {
                let raw = String(token)
                if raw.hasPrefix("-") {
                    enabledCaps.remove(String(raw.dropFirst()))
                } else {
                    enabledCaps.insert(raw)
                }
            }
            // SASL is the only cap that needs an additional handshake. Skip
            // ahead if it wasn't part of this batch (e.g. user disabled SASL
            // but we still asked for tag caps).
            if enabledCaps.contains("sasl") && config.saslMechanism != .none {
                phase = .authenticating
                return ["AUTHENTICATE \(config.saslMechanism.rawValue)"]
            }
            phase = .done
            return ["CAP END"]

        case "NAK":
            // Server refused some/all of our requested caps. Soldier on — we
            // already registered them as "asked"; treat NAK as "none granted
            // from this batch" and finish CAP. SASL not granted ⇒ no auth.
            phase = .done
            return ["CAP END"]

        case "NEW":
            // Server announces a new cap mid-session. We don't request these
            // dynamically yet — record the value and move on.
            let payload = msg.params.last ?? ""
            for token in payload.split(separator: " ", omittingEmptySubsequences: true) {
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count > 1 {
                    serverCapValues[String(parts[0])] = String(parts[1])
                }
            }
            return []

        case "DEL":
            let payload = msg.params.last ?? ""
            for token in payload.split(separator: " ", omittingEmptySubsequences: true) {
                enabledCaps.remove(String(token))
            }
            return []

        default:
            return []
        }
    }

    private func handleAUTHENTICATE(_ msg: IRCMessage) -> [String] {
        guard phase == .authenticating else { return [] }
        let token = msg.params.last ?? ""
        guard token == "+" else { return [] }

        switch config.saslMechanism {
        case .plain:
            let account = config.saslAccount.isEmpty ? config.nick : config.saslAccount
            let payload = "\(account)\0\(account)\0\(config.saslPassword)"
            let b64 = Data(payload.utf8).base64EncodedString()
            return Self.chunkedAuthenticate(b64)

        case .external:
            return ["AUTHENTICATE +"]

        case .none:
            phase = .done
            return ["CAP END"]
        }
    }

    /// Split a SASL payload across 400-byte AUTHENTICATE lines per IRCv3 SASL.
    /// A payload that's an exact multiple of 400 bytes — including 0 — gets a
    /// trailing `AUTHENTICATE +` to signal "no more chunks coming." A short
    /// payload (1–399 bytes) fits in a single line and needs no terminator.
    static func chunkedAuthenticate(_ b64: String) -> [String] {
        guard !b64.isEmpty else { return ["AUTHENTICATE +"] }
        let chunkSize = 400
        if b64.count < chunkSize {
            return ["AUTHENTICATE \(b64)"]
        }
        var lines: [String] = []
        var idx = b64.startIndex
        while idx < b64.endIndex {
            let end = b64.index(idx, offsetBy: chunkSize, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append("AUTHENTICATE \(b64[idx..<end])")
            idx = end
        }
        // Per spec: payloads that are an exact multiple of 400 bytes need a
        // trailing `AUTHENTICATE +` so the server knows the message is done.
        if b64.count % chunkSize == 0 {
            lines.append("AUTHENTICATE +")
        }
        return lines
    }
}
