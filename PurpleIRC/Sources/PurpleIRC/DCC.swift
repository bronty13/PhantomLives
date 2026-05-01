import Foundation
import Network
import AppKit
import Combine
import Darwin

/// DCC (Direct Client-to-Client) support for file transfers and private
/// chats. This is the classic out-of-band flow: one side listens on a TCP
/// port, the other side dials in, and the handshake is negotiated inline over
/// IRC via a CTCP PRIVMSG:
///
///   ->  DCC SEND filename ip port size
///   ->  DCC CHAT chat ip port
///
/// Real-world caveats documented in the UI:
///   - Both peers must be reachable at the advertised IP:port. Behind NAT
///     this typically requires port forwarding on the listener side and a
///     manual external-IP override (auto-detect only returns LAN addresses).
///   - Passive / reverse DCC and DCC RESUME are not yet implemented.
///   - Transfers use the classic "4-byte cumulative ACK" convention on the
///     receiver side.
enum DCCDirection { case sending, receiving }

enum DCCState: Equatable {
    case offered       // inbound offer awaiting user accept
    case listening     // outbound, waiting for peer to dial in
    case connecting    // inbound, dialing peer
    case transferring
    case completed
    case failed(String)
    case cancelled
}

@MainActor
final class DCCTransfer: Identifiable, ObservableObject {
    let id = UUID()
    let direction: DCCDirection
    let peerNick: String
    let filename: String
    let totalBytes: UInt64
    let createdAt = Date()

    @Published var bytesTransferred: UInt64 = 0
    @Published var state: DCCState

    // Inbound offer detail.
    let offeredHost: String?
    let offeredPort: UInt16?

    // Outbound source / inbound destination (set on accept).
    let sourceURL: URL?
    var destinationURL: URL?

    // Live network state.
    var listener: NWListener?
    var connection: NWConnection?
    var fileHandle: FileHandle?

    init(direction: DCCDirection, peerNick: String, filename: String,
         totalBytes: UInt64, state: DCCState,
         offeredHost: String? = nil, offeredPort: UInt16? = nil,
         sourceURL: URL? = nil, destinationURL: URL? = nil) {
        self.direction = direction
        self.peerNick = peerNick
        self.filename = filename
        self.totalBytes = totalBytes
        self.state = state
        self.offeredHost = offeredHost
        self.offeredPort = offeredPort
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }

    var progress: Double {
        totalBytes == 0 ? 0 : min(1.0, Double(bytesTransferred) / Double(totalBytes))
    }
}

struct DCCChatLine: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let isSelf: Bool
    let text: String
}

@MainActor
final class DCCChatSession: Identifiable, ObservableObject {
    let id = UUID()
    let direction: DCCDirection
    let peerNick: String
    @Published var state: DCCState
    @Published var lines: [DCCChatLine] = []

    let offeredHost: String?
    let offeredPort: UInt16?

    var listener: NWListener?
    var connection: NWConnection?
    var receiveBuffer = Data()

    init(direction: DCCDirection, peerNick: String, state: DCCState,
         offeredHost: String? = nil, offeredPort: UInt16? = nil) {
        self.direction = direction
        self.peerNick = peerNick
        self.state = state
        self.offeredHost = offeredHost
        self.offeredPort = offeredPort
    }

    func append(_ line: DCCChatLine) { lines.append(line) }
}

@MainActor
final class DCCService: ObservableObject {
    @Published var transfers: [DCCTransfer] = []
    @Published var chats: [DCCChatSession] = []

    // Settings-pushed.
    var externalIPOverride: String = ""
    var portRangeStart: Int = 49152
    var portRangeEnd: Int = 49200
    var downloadsDir: URL

    weak var chatModel: ChatModel?

    init(downloadsDir: URL) {
        self.downloadsDir = downloadsDir
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    // MARK: - Inbound CTCP

    /// Called by IRCConnection when a CTCP DCC arrives. Returns true if we
    /// consumed it (so the CTCP doesn't get logged as a plain "CTCP request").
    func handleIncomingDCC(connection: IRCConnection, from: String, args: String) -> Bool {
        let tokens = tokenizeDCC(args)
        guard let sub = tokens.first?.uppercased() else { return false }
        switch sub {
        case "SEND":
            guard tokens.count >= 5 else { return false }
            let filename = sanitizeFilename(tokens[1])
            let host = decodeHost(tokens[2])
            guard let port = UInt16(tokens[3]) else { return false }
            let size = UInt64(tokens[4]) ?? 0
            let t = DCCTransfer(
                direction: .receiving, peerNick: from,
                filename: filename, totalBytes: size, state: .offered,
                offeredHost: host, offeredPort: port
            )
            transfers.insert(t, at: 0)
            connection.appendInfoOnSelected("DCC SEND offer from \(from): \(filename) (\(formatBytes(size))). Open DCC Transfers to accept.")
            chatModel?.showDCC = true
            NSApp.requestUserAttention(.informationalRequest)
            return true
        case "CHAT":
            guard tokens.count >= 4, tokens[1].lowercased() == "chat" else { return false }
            let host = decodeHost(tokens[2])
            guard let port = UInt16(tokens[3]) else { return false }
            let c = DCCChatSession(
                direction: .receiving, peerNick: from, state: .offered,
                offeredHost: host, offeredPort: port
            )
            chats.insert(c, at: 0)
            connection.appendInfoOnSelected("DCC CHAT offer from \(from). Open DCC Transfers to accept.")
            chatModel?.showDCC = true
            NSApp.requestUserAttention(.informationalRequest)
            return true
        default:
            return false
        }
    }

    // MARK: - Outbound

    func offerSend(to nick: String, fileURL: URL, on connection: IRCConnection) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? UInt64) ?? 0
        let t = DCCTransfer(
            direction: .sending, peerNick: nick,
            filename: fileURL.lastPathComponent,
            totalBytes: size, state: .listening,
            sourceURL: fileURL
        )
        transfers.insert(t, at: 0)

        // Resolve the address we'll advertise BEFORE binding the listener so
        // we can bind to that specific interface — listening on the wildcard
        // 0.0.0.0 would let any host that can reach the port race the peer.
        guard let ipString = resolveExternalIP() else {
            t.state = .failed("No external IP — set one in Setup ▸ Behavior ▸ DCC.")
            return
        }
        guard let (listener, port) = createListener(bindHost: ipString) else {
            t.state = .failed("No available port in DCC range")
            return
        }
        t.listener = listener
        startSendListener(transfer: t, listener: listener)

        let ipInt = ipv4StringToInt(ipString)
        let safeName = fileURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let cmd = "DCC SEND \(safeName) \(ipInt) \(port) \(size)"
        connection.sendRaw("PRIVMSG \(nick) :\u{01}\(cmd)\u{01}")
        connection.appendInfoOnSelected("Offered DCC SEND \(fileURL.lastPathComponent) → \(nick) (\(formatBytes(size)), port \(port)).")
        chatModel?.showDCC = true
    }

    func offerChat(to nick: String, on connection: IRCConnection) {
        let c = DCCChatSession(direction: .sending, peerNick: nick, state: .listening)
        chats.insert(c, at: 0)

        guard let ipString = resolveExternalIP() else {
            c.state = .failed("No external IP — set one in Setup ▸ Behavior ▸ DCC.")
            return
        }
        guard let (listener, port) = createListener(bindHost: ipString) else {
            c.state = .failed("No available port in DCC range")
            return
        }
        c.listener = listener
        startChatListener(session: c, listener: listener)

        let ipInt = ipv4StringToInt(ipString)
        let cmd = "DCC CHAT chat \(ipInt) \(port)"
        connection.sendRaw("PRIVMSG \(nick) :\u{01}\(cmd)\u{01}")
        connection.appendInfoOnSelected("Offered DCC CHAT → \(nick) (port \(port)).")
        chatModel?.showDCC = true
    }

    // MARK: - Accept

    func acceptTransfer(_ t: DCCTransfer, savingTo destination: URL) {
        guard let host = t.offeredHost, let port = t.offeredPort else {
            t.state = .failed("Missing peer address")
            return
        }
        t.destinationURL = destination
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: destination) else {
            t.state = .failed("Can't open destination file")
            return
        }
        t.fileHandle = fh
        t.state = .connecting
        guard let portEP = NWEndpoint.Port(rawValue: port) else {
            t.state = .failed("Bad port \(port)"); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: portEP, using: .tcp)
        t.connection = conn
        conn.stateUpdateHandler = { [weak self, weak t] state in
            Task { @MainActor [weak self, weak t] in
                guard let self, let t else { return }
                switch state {
                case .ready:
                    t.state = .transferring
                    self.readLoop(transfer: t)
                case .failed(let err):
                    self.finish(transfer: t, failure: err.localizedDescription)
                case .cancelled:
                    if t.state == .transferring,
                       t.bytesTransferred < t.totalBytes {
                        self.finish(transfer: t, failure: "Connection closed early")
                    }
                default:
                    break
                }
            }
        }
        conn.start(queue: .global())
    }

    func acceptChat(_ c: DCCChatSession) {
        guard let host = c.offeredHost, let port = c.offeredPort else {
            c.state = .failed("Missing peer address"); return
        }
        guard let portEP = NWEndpoint.Port(rawValue: port) else {
            c.state = .failed("Bad port \(port)"); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: portEP, using: .tcp)
        c.connection = conn
        c.state = .connecting
        conn.stateUpdateHandler = { [weak self, weak c] state in
            Task { @MainActor [weak self, weak c] in
                guard let self, let c else { return }
                switch state {
                case .ready:
                    c.state = .transferring
                    self.chatReadLoop(session: c)
                case .failed(let err):
                    c.state = .failed(err.localizedDescription)
                case .cancelled:
                    if c.state == .transferring { c.state = .completed }
                default: break
                }
            }
        }
        conn.start(queue: .global())
    }

    // MARK: - Cancel / chat send

    func cancelTransfer(_ t: DCCTransfer) {
        t.listener?.cancel(); t.listener = nil
        t.connection?.cancel(); t.connection = nil
        try? t.fileHandle?.close(); t.fileHandle = nil
        if case .transferring = t.state {
            t.state = .cancelled
        } else if case .offered = t.state {
            t.state = .cancelled
        } else if case .listening = t.state {
            t.state = .cancelled
        } else if case .connecting = t.state {
            t.state = .cancelled
        }
    }

    func cancelChat(_ c: DCCChatSession) {
        c.listener?.cancel(); c.listener = nil
        c.connection?.cancel(); c.connection = nil
        c.state = .cancelled
    }

    func sendChat(_ c: DCCChatSession, text: String) {
        guard let conn = c.connection, case .transferring = c.state else { return }
        let line = text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
        c.append(DCCChatLine(isSelf: true, text: text))
    }

    func clearInactive() {
        transfers.removeAll { t in
            switch t.state {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }
        chats.removeAll { c in
            switch c.state {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    // MARK: - Listener plumbing

    private func createListener(bindHost: String) -> (NWListener, UInt16)? {
        // Bind to the specific advertised IP so we don't accept connections
        // on every interface. Failing that (interface not present, IP not
        // resolvable), fall back to wildcard so DCC still works on hosts
        // whose advertised address isn't the bind address (NAT, manual
        // override). Wildcard remains a known footgun documented in HANDOFF.
        for p in portRangeStart...portRangeEnd {
            guard let port = NWEndpoint.Port(rawValue: UInt16(p)) else { continue }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(bindHost), port: port
            )
            if let listener = try? NWListener(using: params, on: port) {
                return (listener, UInt16(p))
            }
        }
        // Last-ditch wildcard fallback (LAN-only setups where bind to a
        // public-facing IP is denied by the OS).
        for p in portRangeStart...portRangeEnd {
            guard let port = NWEndpoint.Port(rawValue: UInt16(p)) else { continue }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if let listener = try? NWListener(using: params, on: port) {
                return (listener, UInt16(p))
            }
        }
        return nil
    }

    private func startSendListener(transfer t: DCCTransfer, listener: NWListener) {
        listener.newConnectionHandler = { [weak self, weak t] conn in
            Task { @MainActor [weak self, weak t] in
                guard let self, let t else { conn.cancel(); return }
                listener.cancel()
                t.listener = nil
                t.connection = conn
                conn.stateUpdateHandler = { [weak self, weak t] state in
                    Task { @MainActor [weak self, weak t] in
                        guard let self, let t else { return }
                        switch state {
                        case .ready:
                            t.state = .transferring
                            self.sendLoop(transfer: t, connection: conn)
                        case .failed(let err):
                            self.finish(transfer: t, failure: err.localizedDescription)
                        case .cancelled:
                            if t.state == .transferring,
                               t.bytesTransferred < t.totalBytes {
                                self.finish(transfer: t, failure: "Peer closed")
                            }
                        default: break
                        }
                    }
                }
                conn.start(queue: .global())
            }
        }
        listener.start(queue: .global())
    }

    private func startChatListener(session c: DCCChatSession, listener: NWListener) {
        listener.newConnectionHandler = { [weak self, weak c] conn in
            Task { @MainActor [weak self, weak c] in
                guard let self, let c else { conn.cancel(); return }
                listener.cancel()
                c.listener = nil
                c.connection = conn
                conn.stateUpdateHandler = { [weak self, weak c] state in
                    Task { @MainActor [weak self, weak c] in
                        guard let self, let c else { return }
                        switch state {
                        case .ready:
                            c.state = .transferring
                            self.chatReadLoop(session: c)
                        case .failed(let err):
                            c.state = .failed(err.localizedDescription)
                        case .cancelled:
                            if c.state == .transferring { c.state = .completed }
                        default: break
                        }
                    }
                }
                conn.start(queue: .global())
            }
        }
        listener.start(queue: .global())
    }

    // MARK: - Byte streaming

    private func sendLoop(transfer t: DCCTransfer, connection: NWConnection) {
        guard let url = t.sourceURL,
              let handle = try? FileHandle(forReadingFrom: url) else {
            finish(transfer: t, failure: "Can't open source file")
            return
        }
        pumpNextSendChunk(t: t, handle: handle, conn: connection)
    }

    private func pumpNextSendChunk(t: DCCTransfer, handle: FileHandle, conn: NWConnection) {
        guard case .transferring = t.state else {
            try? handle.close(); return
        }
        let chunk = handle.readData(ofLength: 8192)
        if chunk.isEmpty {
            try? handle.close()
            conn.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                Task { @MainActor [weak t] in
                    guard let t else { return }
                    t.bytesTransferred = t.totalBytes
                    t.state = .completed
                    t.connection?.cancel(); t.connection = nil
                }
            })
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self, weak t] err in
            Task { @MainActor [weak self, weak t] in
                guard let self, let t else { return }
                if let err {
                    try? handle.close()
                    self.finish(transfer: t, failure: err.localizedDescription)
                    return
                }
                t.bytesTransferred += UInt64(chunk.count)
                self.pumpNextSendChunk(t: t, handle: handle, conn: conn)
            }
        })
    }

    private func readLoop(transfer t: DCCTransfer) {
        guard let conn = t.connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak t] data, _, isComplete, error in
            Task { @MainActor [weak self, weak t] in
                guard let self, let t else { return }
                if let data, !data.isEmpty {
                    try? t.fileHandle?.write(contentsOf: data)
                    t.bytesTransferred += UInt64(data.count)
                    // Cumulative 4-byte big-endian ack.
                    let ackVal = UInt32(truncatingIfNeeded: t.bytesTransferred).bigEndian
                    let ackData = withUnsafeBytes(of: ackVal) { Data($0) }
                    conn.send(content: ackData, completion: .contentProcessed { _ in })
                }
                if let error {
                    self.finish(transfer: t, failure: error.localizedDescription)
                    return
                }
                if isComplete || (t.totalBytes > 0 && t.bytesTransferred >= t.totalBytes) {
                    try? t.fileHandle?.close()
                    t.fileHandle = nil
                    t.state = .completed
                    t.connection?.cancel(); t.connection = nil
                    return
                }
                self.readLoop(transfer: t)
            }
        }
    }

    private func chatReadLoop(session c: DCCChatSession) {
        guard let conn = c.connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak c] data, _, isComplete, error in
            Task { @MainActor [weak self, weak c] in
                guard let self, let c else { return }
                if let data, !data.isEmpty {
                    c.receiveBuffer.append(data)
                    while let nl = c.receiveBuffer.firstIndex(of: 0x0A) {
                        let lineData = c.receiveBuffer.subdata(in: c.receiveBuffer.startIndex..<nl)
                        c.receiveBuffer.removeSubrange(c.receiveBuffer.startIndex...nl)
                        var lineStr = String(data: lineData, encoding: .utf8) ?? ""
                        if lineStr.hasSuffix("\r") { lineStr.removeLast() }
                        if !lineStr.isEmpty {
                            c.append(DCCChatLine(isSelf: false, text: lineStr))
                        }
                    }
                }
                if let error { c.state = .failed(error.localizedDescription); return }
                if isComplete { c.state = .completed; return }
                self.chatReadLoop(session: c)
            }
        }
    }

    private func finish(transfer t: DCCTransfer, failure: String) {
        try? t.fileHandle?.close(); t.fileHandle = nil
        t.connection?.cancel(); t.connection = nil
        t.listener?.cancel(); t.listener = nil
        t.state = .failed(failure)
    }

    // MARK: - Address helpers

    private func resolveExternalIP() -> String? {
        let trimmed = externalIPOverride.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return Self.primaryIPv4()
    }

    private static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }
        var candidate: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let c = cursor {
            let name = String(cString: c.pointee.ifa_name)
            let flags = Int32(c.pointee.ifa_flags)
            if let addrPtr = c.pointee.ifa_addr {
                let family = addrPtr.pointee.sa_family
                if family == UInt8(AF_INET),
                   (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let res = getnameinfo(addrPtr, socklen_t(addrPtr.pointee.sa_len),
                                          &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    if res == 0 {
                        let addr = String(cString: host)
                        if name == "en0" { return addr }
                        if candidate == nil { candidate = addr }
                    }
                }
            }
            cursor = c.pointee.ifa_next
        }
        return candidate
    }

    private func ipv4StringToInt(_ s: String) -> UInt32 {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func decodeHost(_ s: String) -> String {
        if let n = UInt32(s) {
            let a = (n >> 24) & 0xFF
            let b = (n >> 16) & 0xFF
            let c = (n >> 8) & 0xFF
            let d = n & 0xFF
            return "\(a).\(b).\(c).\(d)"
        }
        return s
    }

    private func tokenizeDCC(_ args: String) -> [String] {
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

    private func sanitizeFilename(_ s: String) -> String {
        // Strip every character class an attacker could use to escape the
        // intended filename: directory separators, NUL, control bytes, and
        // a literal `..` segment that would survive Unicode round-trips.
        var cleaned = String(s.unicodeScalars.map { sc -> Character in
            if sc.value < 0x20 || sc.value == 0x7F { return "_" }
            switch sc {
            case "/", "\\", ":": return "_"
            default: return Character(sc)
            }
        })
        cleaned = cleaned.replacingOccurrences(of: "..", with: "_")
        // Take only the last path component in case the platform's URL
        // construction would still split on a remaining separator we missed.
        let lastComponent = (cleaned as NSString).lastPathComponent
        // Trim leading dots (hidden files) and surrounding whitespace; reject
        // names that collapse to empty or to dot-only strings.
        let trimmed = lastComponent
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "." })
        let final = String(trimmed)
        if final.isEmpty || final.allSatisfy({ $0 == "." || $0 == "_" }) {
            return "dcc-file"
        }
        // Cap length so a 64KB filename can't blow up downstream UI.
        return String(final.prefix(255))
    }

    private func formatBytes(_ n: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
