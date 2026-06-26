import Foundation
import Network

public enum IRCConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Everything IRCClient needs to open + authenticate a connection.
public struct IRCConnectionConfig {
    public var host: String
    public var port: UInt16
    public var useTLS: Bool
    public var nick: String
    public var user: String
    public var realName: String
    public var serverPassword: String?
    public var saslMechanism: SASLMechanism
    public var saslAccount: String
    public var saslPassword: String
    public var proxyType: ProxyType = .none
    public var proxyHost: String = ""
    public var proxyPort: UInt16 = 0
    public var proxyUsername: String = ""
    public var proxyPassword: String = ""

    public init(host: String,
                port: UInt16,
                useTLS: Bool,
                nick: String,
                user: String,
                realName: String,
                serverPassword: String? = nil,
                saslMechanism: SASLMechanism = .none,
                saslAccount: String = "",
                saslPassword: String = "",
                proxyType: ProxyType = .none,
                proxyHost: String = "",
                proxyPort: UInt16 = 0,
                proxyUsername: String = "",
                proxyPassword: String = "") {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.nick = nick
        self.user = user
        self.realName = realName
        self.serverPassword = serverPassword
        self.saslMechanism = saslMechanism
        self.saslAccount = saslAccount
        self.saslPassword = saslPassword
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername
        self.proxyPassword = proxyPassword
    }
}

public final class IRCClient: @unchecked Sendable {
    // THREADING CONTRACT. All mutable connection state below is confined to
    // `queue` (a serial dispatch queue). The NWConnection runs on `queue`, so
    // its callbacks already execute there; the public API stays *synchronous*
    // — the @MainActor session layers in PurpleIRC / Ircle call it from the
    // main thread — but every read/write of this state is funnelled onto
    // `queue` (`connect`/`send` via `queue.async`; `disconnect` and the
    // `enabledCaps`/`host`/… getters via `queue.sync`). That makes the caller
    // and the socket callbacks mutually exclusive, eliminating the data race
    // on `connection`/`buffer`/`negotiator` (TSan-proven; see
    // `IRCClientLoopbackTests`). `@unchecked Sendable` asserts this discipline;
    // the `onMessage`/`onState`/`onRaw` callbacks must be set before `connect`.
    private let queue = DispatchQueue(label: "IRCKit.client")
    private var connection: NWConnection?
    // Bumped on every teardown/redial. Each connection's callbacks capture the
    // value at setup and ignore events once it changes. A value-typed identity
    // token (rather than capturing the NWConnection itself) — this avoids a
    // conn↔handler retain cycle and makes a superseded socket's late events
    // no-ops (incl. stopping an old socket's `.cancelled` from nilling the new).
    private var epoch = 0
    private var buffer = Data()

    public var onMessage: ((IRCMessage) -> Void)?
    public var onState: ((IRCConnectionState) -> Void)?
    public var onRaw: ((String, Bool) -> Void)? // line, isOutbound

    // Connection coordinates. The `_`-prefixed storage is queue-confined;
    // on-queue code (`humanize`, the timeout item) reads it directly. The
    // public getters expose it to off-queue callers race-free via `queue.sync`
    // — never call them from `queue` (self-deadlock); no on-queue code does.
    private var _host: String = ""
    private var _port: UInt16 = 6667
    private var _useTLS: Bool = false
    public var host: String { queue.sync { _host } }
    public var port: UInt16 { queue.sync { _port } }
    public var useTLS: Bool { queue.sync { _useTLS } }

    // Registration / SASL state machine (extracted for unit testing).
    private var negotiator: SASLNegotiator?
    private var pendingConfig: IRCConnectionConfig?

    // Connect-timeout bookkeeping. NWConnection enters `.waiting` (and keeps
    // retrying) when it can't reach the endpoint — e.g. wrong host/port, or a
    // TLS/plaintext port mismatch — which can hang indefinitely. We give up
    // after `connectTimeoutSeconds` with an actionable error.
    private var didBecomeReady = false
    private var connectTimeout: DispatchWorkItem?
    public var connectTimeoutSeconds: TimeInterval = 20

    public init() {}

    public func connect(config: IRCConnectionConfig) {
        queue.async { [weak self] in self?._connect(config) }
    }

    /// Runs on `queue`. Tears down any prior connection (best-effort QUIT,
    /// fire-and-forget — we can't block-wait on `queue`) then dials the new one.
    private func _connect(_ config: IRCConnectionConfig) {
        flushQuitAndCancel(detach(), quitMessage: nil, awaitFlush: false)
        _host = config.host
        _port = config.port
        _useTLS = config.useTLS
        pendingConfig = config

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

        let gen = epoch
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            // Runs on `queue`. `detach()`/`connect` bump `epoch`, so a
            // superseded connection (its captured `gen` no longer current)
            // fails this check and its late events are ignored — including an
            // old socket's `.cancelled` after a redial. `gen` is captured by
            // value, so the handler does not retain `conn`.
            guard self.epoch == gen else { return }
            switch state {
            case .ready:
                self.didBecomeReady = true
                self.cancelConnectTimeout()
                self.onState?(.connected)
                self.startRegistration()
                self.receiveLoop(gen)
            case .waiting(let err):
                // `.waiting` is transient — NWConnection keeps retrying and may
                // still reach `.ready`. Don't surface it as a hard failure
                // (that's what alarmed users with "Waiting: … timed out"); stay
                // in "connecting" and let the connect timeout decide. Leave a
                // breadcrumb in the raw log for diagnosis.
                self.onRaw?("(connecting — \(self.humanize(err)))", false)
                self.onState?(.connecting)
            case .failed(let err):
                self.cancelConnectTimeout()
                let proxyReason = ProxyFramer.takeLastError()
                let detail = self.humanize(err)
                if let proxyReason {
                    self.onState?(.failed("\(proxyReason) (\(detail))"))
                } else {
                    self.onState?(.failed(detail))
                }
                self.connection = nil
            case .cancelled:
                self.cancelConnectTimeout()
                self.onState?(.disconnected)
                self.connection = nil
            case .preparing, .setup:
                self.onState?(.connecting)
            @unknown default:
                break
            }
        }
        didBecomeReady = false
        scheduleConnectTimeout()
        onState?(.connecting)
        conn.start(queue: queue)
    }

    private func scheduleConnectTimeout() {
        connectTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.didBecomeReady else { return }
            self.onState?(.failed(
                "Timed out connecting to \(self._host):\(self._port). The server didn't respond — "
                + "check the host and port, and whether TLS should be \(self._useTLS ? "OFF" : "ON") "
                + "for this port (commonly 6697 = TLS, 6667 = plain)."))
            self.connection?.cancel()
            self.connection = nil
        }
        connectTimeout = item
        queue.asyncAfter(deadline: .now() + connectTimeoutSeconds, execute: item)
    }

    private func cancelConnectTimeout() {
        connectTimeout?.cancel()
        connectTimeout = nil
    }

    /// Synchronous, on purpose: flushes a best-effort QUIT (≤1s) before closing
    /// so a server gets a proper goodbye even when the app is terminating (see
    /// `ChatModel.performQuit`). Call from the main thread. The state teardown
    /// runs on `queue` (`queue.sync`), but the QUIT flush waits on the *caller*
    /// thread — never on `queue` — so it cannot deadlock against the send
    /// completion (which is delivered on `queue`).
    public func disconnect(quitMessage: String? = nil) {
        let conn = queue.sync { detach() }
        flushQuitAndCancel(conn, quitMessage: quitMessage, awaitFlush: true)
        onState?(.disconnected)
    }

    /// Runs on `queue`. Clears all connection state and returns the previous
    /// NWConnection so the caller can flush/cancel it. We don't detach the
    /// state handler — the `connection === conn` guard inside it already makes
    /// the returned connection's later events no-ops.
    private func detach() -> NWConnection? {
        cancelConnectTimeout()
        epoch &+= 1
        let c = connection
        connection = nil
        buffer.removeAll()
        negotiator = nil
        pendingConfig = nil
        didBecomeReady = false
        return c
    }

    private func quitData(_ quitMessage: String?) -> Data? {
        let safe = IRCSanitize.line("QUIT :\(quitMessage ?? "Client closed")")
        guard !safe.isEmpty else { return nil }
        return (safe + "\r\n").data(using: .utf8)
    }

    /// Flush a QUIT (when the connection is `.ready`) then cancel. With
    /// `awaitFlush == true` the *caller* blocks ≤1s for the bytes to drain —
    /// only ever pass `true` when NOT on `queue`, since the completion fires on
    /// `queue`. With `false` the cancel is chained off the completion (no wait),
    /// which is the only safe form on `queue`.
    private func flushQuitAndCancel(_ conn: NWConnection?, quitMessage: String?, awaitFlush: Bool) {
        guard let conn else { return }
        guard conn.state == .ready, let data = quitData(quitMessage) else {
            conn.cancel()
            return
        }
        if awaitFlush {
            let sem = DispatchSemaphore(value: 0)
            conn.send(content: data, completion: .contentProcessed { _ in sem.signal() })
            _ = sem.wait(timeout: .now() + 1.0)
            conn.cancel()
        } else {
            conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    public func send(_ line: String) {
        queue.async { [weak self] in self?._send(line) }
    }

    /// Runs on `queue`. Also the in-order send used by registration / SASL,
    /// which are already on `queue` and must enqueue their lines synchronously.
    private func _send(_ line: String) {
        guard let conn = connection else { return }
        // Strip CR / LF / NUL inside the payload before re-appending the
        // single CRLF terminator. Anything else would let an attacker-
        // controlled field smuggle a second IRC command.
        let safe = IRCSanitize.line(line)
        guard !safe.isEmpty else { return }
        let trimmed = safe + "\r\n"
        guard let data = trimmed.data(using: .utf8) else { return }
        onRaw?(IRCSanitize.maskForDisplay(safe), true)
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onState?(.failed("send failed: \(error.localizedDescription)"))
            }
        })
    }

    // MARK: - Error presentation

    /// Translate raw `NWError` values into something a human can act on. The
    /// biggest win is catching TLS handshake failures (errSSLBadProtocolVersion
    /// is -9836) that happen when TLS is on but the server is plaintext — a
    /// very common footgun with older IRC networks.
    private func humanize(_ err: NWError) -> String {
        let base = err.localizedDescription
        if _useTLS, case .tls(let status) = err {
            let hint: String
            switch status {
            case -9836:   // errSSLBadProtocolVersion — server closed the TLS handshake
                hint = "server on \(_host):\(_port) doesn't appear to support TLS. Try turning TLS off, or use the network's TLS port (often 6697/9999)."
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
        for line in n.registrationCommands() { _send(line) }
    }

    /// Drive CAP/AUTHENTICATE/SASL numerics through the negotiator. The
    /// message is still forwarded to `onMessage` so the caller can log it.
    private func interceptForSASL(_ msg: IRCMessage) {
        guard let n = negotiator else { return }
        for line in n.handle(msg) { _send(line) }
    }

    /// Caps the server actually granted us this session. Empty when CAP
    /// negotiation hasn't completed yet. Read by the session layer to decide
    /// whether to honour `@time` tags, expect echo-message, etc.
    public var enabledCaps: Set<String> {
        queue.sync { negotiator?.enabledCaps ?? [] }
    }

    /// Server-side cap values (e.g. `chathistory=1000`). Same lifetime as
    /// `enabledCaps` — keyed by cap name.
    public var serverCapValues: [String: String] {
        queue.sync { negotiator?.serverCapValues ?? [:] }
    }

    // MARK: - Receive pipeline

    private func receiveLoop(_ gen: Int) {
        guard epoch == gen, let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            // Runs on `queue`. Ignore reads from a superseded connection.
            guard let self, self.epoch == gen else { return }
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
            self.receiveLoop(gen)
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
            // The parser must see the unmasked line; only the raw-log
            // display gets masked so credentials in echo-message replies
            // and SASL replays don't surface in the viewer.
            onRaw?(IRCSanitize.maskForDisplay(line), false)
            if let msg = IRCMessage.parse(line) {
                interceptForSASL(msg)
                onMessage?(msg)
            }
        }
    }
}
