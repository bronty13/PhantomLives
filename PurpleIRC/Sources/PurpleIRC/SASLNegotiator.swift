import Foundation

/// Pure state machine driving IRCv3 CAP + SASL negotiation and the initial
/// NICK/USER registration burst. IRCClient owns the socket; this type owns the
/// protocol decisions so it can be unit-tested without any networking.
final class SASLNegotiator {
    enum Phase: Equatable {
        case idle          // not yet started
        case awaitingLS    // CAP LS sent, waiting for response
        case awaitingACK   // CAP REQ :sasl sent, waiting for ACK/NAK
        case authenticating
        case done          // CAP END sent (success, bypass, or abort)
    }

    private(set) var phase: Phase = .idle
    private let config: IRCConnectionConfig

    init(config: IRCConnectionConfig) {
        self.config = config
    }

    /// Lines to send immediately after the socket becomes ready. Includes the
    /// registration burst (CAP LS / PASS / NICK / USER) and, when SASL is not
    /// requested, a trailing CAP END so the server can complete registration.
    func registrationCommands() -> [String] {
        var lines: [String] = []
        lines.append("CAP LS 302")
        if let pw = config.serverPassword, !pw.isEmpty {
            lines.append("PASS \(pw)")
        }
        lines.append("NICK \(config.nick)")
        lines.append("USER \(config.user) 0 * :\(config.realName)")

        if config.saslMechanism == .none {
            lines.append("CAP END")
            phase = .done
        } else {
            phase = .awaitingLS
        }
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
            let caps = msg.params.last ?? ""
            let hasSASL = caps.split(separator: " ").contains { token in
                let name = token.split(separator: "=").first.map(String.init) ?? String(token)
                return name == "sasl"
            }
            // "CAP * LS * :..." signals another LS frame follows; wait for it
            // unless we've already seen sasl in this frame.
            let isContinuation = msg.params.count >= 4 && msg.params[2] == "*"
            if isContinuation && !hasSASL { return [] }
            if hasSASL {
                phase = .awaitingACK
                return ["CAP REQ :sasl"]
            }
            phase = .done
            return ["CAP END"]

        case "ACK":
            guard phase == .awaitingACK else { return [] }
            phase = .authenticating
            return ["AUTHENTICATE \(config.saslMechanism.rawValue)"]

        case "NAK":
            // Server refused SASL cap — proceed without authenticating.
            phase = .done
            return ["CAP END"]

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
            // PLAIN payloads below 400 bytes fit in a single AUTHENTICATE line.
            return [b64.isEmpty ? "AUTHENTICATE +" : "AUTHENTICATE \(b64)"]

        case .external:
            return ["AUTHENTICATE +"]

        case .none:
            phase = .done
            return ["CAP END"]
        }
    }
}
