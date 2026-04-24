import Foundation
import Network

enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case none = "NONE"
    case socks5 = "SOCKS5"
    case http = "HTTP"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "None"
        case .socks5: return "SOCKS5"
        case .http: return "HTTP CONNECT"
        }
    }
}

struct ProxyConfig {
    var type: ProxyType
    var host: String
    var port: UInt16
    var username: String
    var password: String
    var targetHost: String
    var targetPort: UInt16
}

/// NWProtocolFramer that performs a SOCKS5 or HTTP CONNECT handshake against a
/// proxy before marking itself ready. Once ready, the framer is a transparent
/// pass-through, so TLS (if any) and the IRC line protocol above can operate
/// normally.
///
/// Config flows into the framer via a FIFO static queue because NWProtocolFramer
/// only receives an `NWProtocolFramer.Instance` in its initializer and doesn't
/// expose a user-data channel on `NWProtocolFramer.Options`.
final class ProxyFramer: NWProtocolFramerImplementation {
    static let label = "PurpleIRCProxy"
    static let definition = NWProtocolFramer.Definition(implementation: ProxyFramer.self)

    private static let configQueueLock = NSLock()
    private static var pendingConfigs: [ProxyConfig] = []

    /// Most recent handshake failure reason — IRCClient reads this when the
    /// connection fails so we can surface a useful error.
    static var lastError: String?

    static func pushConfig(_ c: ProxyConfig) {
        configQueueLock.lock()
        pendingConfigs.append(c)
        configQueueLock.unlock()
    }

    private static func popConfig() -> ProxyConfig? {
        configQueueLock.lock()
        defer { configQueueLock.unlock() }
        guard !pendingConfigs.isEmpty else { return nil }
        return pendingConfigs.removeFirst()
    }

    private enum Phase {
        case initial
        case socks5GreetingSent
        case socks5AuthSent
        case socks5ConnectSent
        case httpConnectSent
        case ready
        case failed
    }

    private let config: ProxyConfig?
    private var phase: Phase = .initial
    private var accumulator: [UInt8] = []

    required init(framer: NWProtocolFramer.Instance) {
        self.config = ProxyFramer.popConfig()
    }

    // MARK: - NWProtocolFramerImplementation

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        guard let cfg = config, cfg.type != .none else {
            return .ready
        }
        switch cfg.type {
        case .socks5:
            sendSOCKS5Greeting(framer: framer, cfg: cfg)
            phase = .socks5GreetingSent
        case .http:
            sendHTTPConnect(framer: framer, cfg: cfg)
            phase = .httpConnectSent
        case .none:
            return .ready
        }
        return .willMarkReady
    }

    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    func handleOutput(framer: NWProtocolFramer.Instance,
                      message: NWProtocolFramer.Message,
                      messageLength: Int,
                      isComplete: Bool) {
        // Upper protocols only start writing after markReady(), so anything
        // that arrives here is post-handshake pass-through.
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            // Best effort — dropping bytes here will surface as a send failure
            // on the IRCClient side.
        }
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        // Drain anything the transport has for us.
        accumulate(framer: framer)

        while true {
            switch phase {
            case .initial, .failed:
                return 0

            case .ready:
                deliverAccumulator(framer: framer)
                // Pass through any further bytes directly.
                _ = framer.parseInput(minimumIncompleteLength: 1, maximumLength: .max) { buffer, isComplete in
                    guard let buffer = buffer, !buffer.isEmpty else { return 0 }
                    let msg = NWProtocolFramer.Message(definition: ProxyFramer.definition)
                    _ = framer.deliverInputNoCopy(length: buffer.count, message: msg, isComplete: isComplete)
                    return buffer.count
                }
                return 0

            case .socks5GreetingSent:
                guard accumulator.count >= 2 else { return 2 - accumulator.count }
                let ver = accumulator[0]
                let method = accumulator[1]
                accumulator.removeFirst(2)
                guard ver == 0x05 else { fail(framer, "SOCKS5: bad greeting reply"); return 0 }
                switch method {
                case 0x00:
                    guard let cfg = config else { fail(framer, "no config"); return 0 }
                    sendSOCKS5Connect(framer: framer, cfg: cfg)
                    phase = .socks5ConnectSent
                case 0x02:
                    guard let cfg = config else { fail(framer, "no config"); return 0 }
                    sendSOCKS5UserPass(framer: framer, cfg: cfg)
                    phase = .socks5AuthSent
                default:
                    fail(framer, "SOCKS5: proxy rejected auth methods")
                    return 0
                }

            case .socks5AuthSent:
                guard accumulator.count >= 2 else { return 2 - accumulator.count }
                let ver = accumulator[0]
                let status = accumulator[1]
                accumulator.removeFirst(2)
                guard ver == 0x01, status == 0x00 else {
                    fail(framer, "SOCKS5: authentication rejected")
                    return 0
                }
                guard let cfg = config else { fail(framer, "no config"); return 0 }
                sendSOCKS5Connect(framer: framer, cfg: cfg)
                phase = .socks5ConnectSent

            case .socks5ConnectSent:
                guard accumulator.count >= 4 else { return 4 - accumulator.count }
                let ver = accumulator[0]
                let rep = accumulator[1]
                let atyp = accumulator[3]
                guard ver == 0x05 else { fail(framer, "SOCKS5: bad CONNECT reply"); return 0 }
                guard rep == 0x00 else {
                    fail(framer, "SOCKS5 CONNECT rejected: \(socks5ReplyString(rep))")
                    return 0
                }
                let addrLen: Int
                switch atyp {
                case 0x01: addrLen = 4
                case 0x04: addrLen = 16
                case 0x03:
                    guard accumulator.count >= 5 else { return 5 - accumulator.count }
                    addrLen = 1 + Int(accumulator[4])
                default:
                    fail(framer, "SOCKS5: unknown address type \(atyp)")
                    return 0
                }
                let total = 4 + addrLen + 2
                guard accumulator.count >= total else { return total - accumulator.count }
                accumulator.removeFirst(total)
                phase = .ready
                framer.markReady()

            case .httpConnectSent:
                let data = Data(accumulator)
                guard let range = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
                    return 1 // need at least more bytes
                }
                let headerEnd = range.upperBound
                let header = String(data: data.subdata(in: 0..<headerEnd), encoding: .utf8) ?? ""
                accumulator.removeFirst(headerEnd)
                let firstLine = header
                    .split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
                    .first.map(String.init) ?? ""
                let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 2, parts[1] == "200" else {
                    fail(framer, "HTTP CONNECT rejected: \(firstLine)")
                    return 0
                }
                phase = .ready
                framer.markReady()
            }
        }
    }

    // MARK: - Private helpers

    private func accumulate(framer: NWProtocolFramer.Instance) {
        while true {
            var consumed = 0
            let ok = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 65536) { buffer, _ in
                guard let buffer = buffer, !buffer.isEmpty, let base = buffer.baseAddress else { return 0 }
                let data = Data(bytes: base, count: buffer.count)
                self.accumulator.append(contentsOf: data)
                consumed = buffer.count
                return buffer.count
            }
            if !ok || consumed == 0 { break }
        }
    }

    private func deliverAccumulator(framer: NWProtocolFramer.Instance) {
        guard !accumulator.isEmpty else { return }
        let data = Data(accumulator)
        accumulator.removeAll()
        let msg = NWProtocolFramer.Message(definition: ProxyFramer.definition)
        framer.deliverInput(data: data, message: msg, isComplete: false)
    }

    private func fail(_ framer: NWProtocolFramer.Instance, _ reason: String) {
        phase = .failed
        ProxyFramer.lastError = reason
        let msg = NWProtocolFramer.Message(definition: ProxyFramer.definition)
        _ = framer.deliverInputNoCopy(length: 0, message: msg, isComplete: true)
    }

    private func sendSOCKS5Greeting(framer: NWProtocolFramer.Instance, cfg: ProxyConfig) {
        var methods: [UInt8] = [0x00] // no auth
        if !cfg.username.isEmpty {
            methods = [0x00, 0x02] // no auth OR user/pass
        }
        var req: [UInt8] = [0x05, UInt8(methods.count)]
        req.append(contentsOf: methods)
        framer.writeOutput(data: Data(req))
    }

    private func sendSOCKS5UserPass(framer: NWProtocolFramer.Instance, cfg: ProxyConfig) {
        let u = Array(cfg.username.utf8)
        let p = Array(cfg.password.utf8)
        guard u.count <= 255, p.count <= 255 else {
            fail(framer, "SOCKS5: credential too long")
            return
        }
        var req: [UInt8] = [0x01, UInt8(u.count)]
        req.append(contentsOf: u)
        req.append(UInt8(p.count))
        req.append(contentsOf: p)
        framer.writeOutput(data: Data(req))
    }

    private func sendSOCKS5Connect(framer: NWProtocolFramer.Instance, cfg: ProxyConfig) {
        let hostBytes = Array(cfg.targetHost.utf8)
        guard hostBytes.count <= 255 else {
            fail(framer, "SOCKS5: target host name too long")
            return
        }
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(hostBytes.count)]
        req.append(contentsOf: hostBytes)
        req.append(UInt8(cfg.targetPort >> 8))
        req.append(UInt8(cfg.targetPort & 0xFF))
        framer.writeOutput(data: Data(req))
    }

    private func sendHTTPConnect(framer: NWProtocolFramer.Instance, cfg: ProxyConfig) {
        let target = "\(cfg.targetHost):\(cfg.targetPort)"
        var req = "CONNECT \(target) HTTP/1.1\r\nHost: \(target)\r\n"
        if !cfg.username.isEmpty {
            let creds = "\(cfg.username):\(cfg.password)"
            let b64 = Data(creds.utf8).base64EncodedString()
            req += "Proxy-Authorization: Basic \(b64)\r\n"
        }
        req += "\r\n"
        framer.writeOutput(data: Data(req.utf8))
    }

    private func socks5ReplyString(_ code: UInt8) -> String {
        switch code {
        case 0x01: return "general server failure"
        case 0x02: return "connection not allowed by ruleset"
        case 0x03: return "network unreachable"
        case 0x04: return "host unreachable"
        case 0x05: return "connection refused"
        case 0x06: return "TTL expired"
        case 0x07: return "command not supported"
        case 0x08: return "address type not supported"
        default: return "code \(code)"
        }
    }
}
