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

    // Registration / SASL state machine (extracted for unit testing).
    private var negotiator: SASLNegotiator?
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
                self.onState?(.failed("Waiting: \(self.humanize(err))"))
            case .failed(let err):
                let proxyReason = ProxyFramer.lastError
                ProxyFramer.lastError = nil
                let detail = self.humanize(err)
                if let proxyReason {
                    self.onState?(.failed("\(proxyReason) (\(detail))"))
                } else {
                    self.onState?(.failed(detail))
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
        negotiator = nil
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

    // MARK: - Error presentation

    /// Translate raw `NWError` values into something a human can act on. The
    /// biggest win is catching TLS handshake failures (errSSLBadProtocolVersion
    /// is -9836) that happen when TLS is on but the server is plaintext — a
    /// very common footgun with older IRC networks.
    private func humanize(_ err: NWError) -> String {
        let base = err.localizedDescription
        if useTLS, case .tls(let status) = err {
            let hint: String
            switch status {
            case -9836:   // errSSLBadProtocolVersion — server closed the TLS handshake
                hint = "server on \(host):\(port) doesn't appear to support TLS. Try turning TLS off, or use the network's TLS port (often 6697/9999)."
            case -9807, -9808, -9809, -9810, -9812, -9813, -9814, -9815, -9816:
                // Various SSL trust / cert-chain errors
                hint = "TLS certificate was rejected. The server may be using a self-signed or untrusted cert."
            default:
                hint = "TLS handshake failed (status \(status)). Check whether this port actually serves TLS."
            }
            return "\(base) — \(hint)"
        }
        return base
    }

    // MARK: - Registration / SASL

    private func startRegistration() {
        guard let cfg = pendingConfig else { return }
        let n = SASLNegotiator(config: cfg)
        negotiator = n
        for line in n.registrationCommands() { send(line) }
    }

    /// Drive CAP/AUTHENTICATE/SASL numerics through the negotiator. The
    /// message is still forwarded to `onMessage` so ChatModel can log it.
    private func interceptForSASL(_ msg: IRCMessage) {
        guard let n = negotiator else { return }
        for line in n.handle(msg) { send(line) }
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
