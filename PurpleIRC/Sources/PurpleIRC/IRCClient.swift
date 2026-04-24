import Foundation
import Network

enum IRCConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Everything IRCClient needs to open + authenticate a connection.
struct IRCConnectionConfig {
    var host: String
    var port: UInt16
    var useTLS: Bool
    var nick: String
    var user: String
    var realName: String
    var serverPassword: String?
    var saslMechanism: SASLMechanism
    var saslAccount: String
    var saslPassword: String
    var proxyType: ProxyType = .none
    var proxyHost: String = ""
    var proxyPort: UInt16 = 0
    var proxyUsername: String = ""
    var proxyPassword: String = ""
}

final class IRCClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "PurpleIRC.client")
    private var buffer = Data()

    var onMessage: ((IRCMessage) -> Void)?
    var onState: ((IRCConnectionState) -> Void)?
    var onRaw: ((String, Bool) -> Void)? // line, isOutbound

    private(set) var host: String = ""
    private(set) var port: UInt16 = 6667
    private(set) var useTLS: Bool = false

    // SASL state
    private enum SASLPhase {
        case idle         // not attempting SASL
        case awaitingLS   // waiting for CAP LS response
        case awaitingACK  // CAP REQ sent, waiting for ACK/NAK
        case authenticating
        case done         // CAP END sent (success or bypass)
    }
    private var saslPhase: SASLPhase = .idle
    private var pendingConfig: IRCConnectionConfig?

    func connect(config: IRCConnectionConfig) {
        disconnect()
        self.host = config.host
        self.port = config.port
        self.useTLS = config.useTLS
        self.pendingConfig = config

        let params: NWParameters
        if config.useTLS {
            params = NWParameters(tls: .init(), tcp: .init())
        } else {
            params = NWParameters.tcp
        }
        params.allowLocalEndpointReuse = true

        // If a proxy is configured, insert the ProxyFramer at the bottom of
        // the application-protocol stack so the handshake runs before any TLS
        // or plaintext application data flows.
        let useProxy = config.proxyType != .none && !config.proxyHost.isEmpty && config.proxyPort > 0
        if useProxy {
            ProxyFramer.pushConfig(ProxyConfig(
                type: config.proxyType,
                host: config.proxyHost,
                port: config.proxyPort,
                username: config.proxyUsername,
                password: config.proxyPassword,
                targetHost: config.host,
                targetPort: config.port
            ))
            let framerOpts = NWProtocolFramer.Options(definition: ProxyFramer.definition)
            params.defaultProtocolStack.applicationProtocols.insert(framerOpts, at: 0)
        }

        let endpointHost: NWEndpoint.Host
        let endpointPortRaw: UInt16
        if useProxy {
            endpointHost = NWEndpoint.Host(config.proxyHost)
            endpointPortRaw = config.proxyPort
        } else {
            endpointHost = NWEndpoint.Host(config.host)
            endpointPortRaw = config.port
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: endpointPortRaw) else {
            onState?(.failed("Invalid port"))
            return
        }

        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onState?(.connected)
                self.startRegistration()
                self.receiveLoop()
            case .waiting(let err):
                self.onState?(.failed("Waiting: \(err.localizedDescription)"))
            case .failed(let err):
                let proxyReason = ProxyFramer.lastError
                ProxyFramer.lastError = nil
                if let proxyReason {
                    self.onState?(.failed("\(proxyReason) (\(err.localizedDescription))"))
                } else {
                    self.onState?(.failed(err.localizedDescription))
                }
                self.connection = nil
            case .cancelled:
                self.onState?(.disconnected)
                self.connection = nil
            case .preparing, .setup:
                self.onState?(.connecting)
            @unknown default:
                break
            }
        }
        onState?(.connecting)
        conn.start(queue: queue)
    }

    func disconnect(quitMessage: String? = nil) {
        if let conn = connection, conn.state == .ready {
            let msg = quitMessage ?? "Client closed"
            sendSync("QUIT :\(msg)")
        }
        connection?.cancel()
        connection = nil
        buffer.removeAll()
        saslPhase = .idle
        pendingConfig = nil
    }

    func send(_ line: String) {
        guard let conn = connection else { return }
        let trimmed = line.hasSuffix("\r\n") ? line : line + "\r\n"
        guard let data = trimmed.data(using: .utf8) else { return }
        let outbound = String(trimmed.dropLast(2))
        onRaw?(outbound, true)
        conn.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.onState?(.failed("send failed: \(error.localizedDescription)"))
            }
        })
    }

    private func sendSync(_ line: String) {
        guard let conn = connection else { return }
        let trimmed = line.hasSuffix("\r\n") ? line : line + "\r\n"
        guard let data = trimmed.data(using: .utf8) else { return }
        let sem = DispatchSemaphore(value: 0)
        conn.send(content: data, completion: .contentProcessed { _ in sem.signal() })
        _ = sem.wait(timeout: .now() + 1.0)
    }

    // MARK: - Registration / SASL

    private func startRegistration() {
        guard let cfg = pendingConfig else { return }

        // Start capability negotiation before USER/NICK — server holds
        // registration open until we send CAP END.
        send("CAP LS 302")
        if let pw = cfg.serverPassword, !pw.isEmpty {
            send("PASS \(pw)")
        }
        send("NICK \(cfg.nick)")
        send("USER \(cfg.user) 0 * :\(cfg.realName)")

        if cfg.saslMechanism == .none {
            // No SASL — close CAP immediately so server moves on.
            send("CAP END")
            saslPhase = .done
        } else {
            saslPhase = .awaitingLS
        }
    }

    private func handleCAP(_ msg: IRCMessage) {
        // CAP <target> <subcommand> [<...>] [:payload]
        guard msg.params.count >= 2 else { return }
        let sub = msg.params[1].uppercased()
        switch sub {
        case "LS":
            guard saslPhase == .awaitingLS else { return }
            let caps = msg.params.last ?? ""
            let hasSASL = caps.split(separator: " ").contains { token in
                let name = token.split(separator: "=").first.map(String.init) ?? String(token)
                return name == "sasl"
            }
            // If the server sent a continuation ("* LS * :..."), wait for the rest.
            let isContinuation = msg.params.count >= 4 && msg.params[2] == "*"
            if isContinuation && !hasSASL { return }
            if hasSASL, let cfg = pendingConfig {
                send("CAP REQ :sasl")
                saslPhase = .awaitingACK
                _ = cfg // just to silence unused warning if we change logic
            } else {
                send("CAP END")
                saslPhase = .done
            }
        case "ACK":
            guard saslPhase == .awaitingACK, let cfg = pendingConfig else { return }
            send("AUTHENTICATE \(cfg.saslMechanism.rawValue)")
            saslPhase = .authenticating
        case "NAK":
            // Server refused SASL cap — proceed without auth.
            send("CAP END")
            saslPhase = .done
        default:
            break
        }
    }

    private func handleAUTHENTICATE(_ msg: IRCMessage) {
        guard saslPhase == .authenticating, let cfg = pendingConfig else { return }
        let token = msg.params.last ?? ""
        guard token == "+" else { return }

        switch cfg.saslMechanism {
        case .plain:
            let account = cfg.saslAccount.isEmpty ? cfg.nick : cfg.saslAccount
            let payload = "\(account)\0\(account)\0\(cfg.saslPassword)"
            let b64 = Data(payload.utf8).base64EncodedString()
            // PLAIN payloads below 400 bytes fit in one AUTHENTICATE line.
            if b64.isEmpty {
                send("AUTHENTICATE +")
            } else {
                send("AUTHENTICATE \(b64)")
            }
        case .external:
            send("AUTHENTICATE +")
        case .none:
            send("CAP END")
            saslPhase = .done
        }
    }

    /// Intercept CAP/AUTHENTICATE/SASL numerics to drive the handshake. We
    /// still forward everything via `onMessage` so ChatModel can log it.
    private func interceptForSASL(_ msg: IRCMessage) {
        switch msg.command.uppercased() {
        case "CAP":
            handleCAP(msg)
        case "AUTHENTICATE":
            handleAUTHENTICATE(msg)
        case "903": // RPL_SASLSUCCESS
            if saslPhase != .done {
                send("CAP END")
                saslPhase = .done
            }
        case "902", "904", "905", "906", "907":
            // Aborted / failed / already-authed / abort client. Close cap
            // negotiation and let the server finish registration; the user
            // will see the numeric in the server buffer.
            if saslPhase != .done {
                send("CAP END")
                saslPhase = .done
            }
        default:
            break
        }
    }

    // MARK: - Receive pipeline

    private func receiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainBuffer()
            }
            if let error {
                self.onState?(.failed(error.localizedDescription))
                return
            }
            if isComplete {
                self.onState?(.disconnected)
                return
            }
            self.receiveLoop()
        }
    }

    private func drainBuffer() {
        while let nlIndex = buffer.firstIndex(of: 0x0A) {
            let lineRange = buffer.startIndex..<nlIndex
            var lineData = buffer.subdata(in: lineRange)
            if lineData.last == 0x0D { lineData.removeLast() }
            buffer.removeSubrange(buffer.startIndex...nlIndex)
            guard let line = String(data: lineData, encoding: .utf8)
                ?? String(data: lineData, encoding: .isoLatin1) else { continue }
            onRaw?(line, false)
            if let msg = IRCMessage.parse(line) {
                interceptForSASL(msg)
                onMessage?(msg)
            }
        }
    }
}
