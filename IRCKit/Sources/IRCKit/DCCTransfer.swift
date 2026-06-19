import Foundation
import Network

/// Shared listener-binding for the DCC initiate side. Binds to `bindHost` (the
/// advertised IP) scanning `range`, falling back to the wildcard (reported via
/// the flag — a footgun the caller should warn about) only if no host-bound port
/// is free. Lifted from PurpleIRC's hardened createListener.
enum DCCNet {
    static func makeListener(bindHost: String,
                             range: ClosedRange<UInt16>) -> (NWListener, UInt16, Bool)? {
        for p in range {
            guard let port = NWEndpoint.Port(rawValue: p) else { continue }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(bindHost), port: port)
            if let l = try? NWListener(using: params, on: port) { return (l, p, false) }
        }
        for p in range {
            guard let port = NWEndpoint.Port(rawValue: p) else { continue }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if let l = try? NWListener(using: params, on: port) { return (l, p, true) }
        }
        return nil
    }
}

/// Receives a DCC file (the *accept*/GET side): connects out to the peer's
/// validated `host:port`, streams bytes to `destination`, sends the classic
/// 4-byte big-endian "total received" acknowledgements, and stops at
/// `expectedSize` so a peer can't write past what it advertised. Pure
/// Network+Foundation — the app decides the (sanitized, in-sandbox) destination
/// path and drives the UI.
///
/// Only ever *connects out* to an address IRCKit's `DCC.validatedPeerHost` has
/// already vetted; it never listens. Callbacks fire on an internal queue — hop
/// to your actor before touching UI state.
public final class DCCDownload {

    public enum State: Equatable, Sendable {
        case connecting, transferring, completed, failed(String), cancelled
    }

    public var onState: ((State) -> Void)?
    /// Total bytes written so far (for a progress bar).
    public var onProgress: ((UInt64) -> Void)?

    private let host: String
    private let port: UInt16
    private let destination: URL
    private let expectedSize: UInt64
    private let queue = DispatchQueue(label: "IRCKit.dcc.download")

    private var connection: NWConnection?
    private var handle: FileHandle?
    private var received: UInt64 = 0
    private var done = false

    public init(host: String, port: UInt16, destination: URL, expectedSize: UInt64) {
        self.host = host
        self.port = port
        self.destination = destination
        self.expectedSize = expectedSize
    }

    public func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            finish(.failed("Invalid port \(port).")); return
        }
        // Create/truncate the destination file up front.
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        guard fm.createFile(atPath: destination.path, contents: nil),
              let h = try? FileHandle(forWritingTo: destination) else {
            finish(.failed("Couldn't create \(destination.lastPathComponent).")); return
        }
        handle = h

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn
        emit(.connecting)
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:   self.emit(.transferring); self.receiveLoop()
            case .failed(let e): self.finish(.failed(e.localizedDescription))
            case .cancelled: break
            default: break
            }
        }
        conn.start(queue: queue)
    }

    public func cancel() {
        guard !done else { return }
        finish(.cancelled)
    }

    // MARK: - Internals

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.finish(.failed(error.localizedDescription)); return }

            if let data, !data.isEmpty {
                // Don't write past the advertised size (guards a runaway peer).
                let remaining = self.expectedSize == 0 ? UInt64(data.count)
                                                        : self.expectedSize - self.received
                let take = self.expectedSize == 0 ? data : data.prefix(Int(min(UInt64(data.count), remaining)))
                if !take.isEmpty {
                    try? self.handle?.write(contentsOf: take)
                    self.received += UInt64(take.count)
                    self.sendAck()
                    self.onProgress?(self.received)
                }
            }

            // Done when we've got the whole advertised file, or the peer closed.
            if self.expectedSize != 0 && self.received >= self.expectedSize {
                self.finish(.completed); return
            }
            if isComplete {
                self.finish(self.expectedSize == 0 || self.received >= self.expectedSize
                            ? .completed : .failed("Connection closed early (\(self.received)/\(self.expectedSize) bytes)."))
                return
            }
            self.receiveLoop()
        }
    }

    /// Classic DCC ack: 4-byte big-endian total bytes received.
    private func sendAck() {
        var ack = UInt32(truncatingIfNeeded: received).bigEndian
        let data = Data(bytes: &ack, count: 4)
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func emit(_ s: State) { onState?(s) }

    private func finish(_ s: State) {
        guard !done else { return }
        done = true
        try? handle?.close()
        handle = nil
        connection?.cancel()
        connection = nil
        onState?(s)
    }
}

/// A DCC CHAT session (the *accept* side): connects out to the peer's validated
/// `host:port` and exchanges newline-delimited text lines. Pure Network — the
/// app owns the conversation buffer and UI. Connects out only, never listens.
public final class DCCChat {

    public enum State: Equatable, Sendable { case connecting, connected, closed, failed(String) }

    public var onState: ((State) -> Void)?
    public var onLine: ((String) -> Void)?

    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "IRCKit.dcc.chat")
    private var connection: NWConnection?
    private var listener: NWListener?
    private var inbuf = Data()
    private var done = false

    /// Connect-out (accept side): dial the peer's `host:port`.
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    /// Listen side (initiate): we don't dial — we await an incoming connection.
    public init() {
        self.host = ""
        self.port = 0
    }

    public func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            finish(.failed("Invalid port \(port).")); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        onState?(.connecting)
        adopt(conn)
        conn.start(queue: queue)
    }

    /// Listen for an inbound DCC chat on a port (initiate side). Binds to
    /// `bindHost` (the advertised IP) so we don't accept on every interface;
    /// returns the chosen port and whether it fell back to the wildcard (a
    /// security footgun the caller should warn about), or nil if no port was
    /// free. The first incoming connection is adopted; the listener then closes.
    public func listen(bindHost: String,
                       portRange: ClosedRange<UInt16> = 49152...49200) -> (port: UInt16, wildcard: Bool)? {
        guard let (l, port, wildcard) = DCCNet.makeListener(bindHost: bindHost, range: portRange) else {
            return nil
        }
        listener = l
        onState?(.connecting)   // "waiting for peer"
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { conn.cancel(); return }
            self.queue.async {
                self.listener?.cancel()
                self.listener = nil
                self.adopt(conn)
                conn.start(queue: self.queue)
            }
        }
        l.start(queue: queue)
        return (port, wildcard)
    }

    /// Wire an established/accepted connection: ready → connected + receive.
    private func adopt(_ conn: NWConnection) {
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready: self.onState?(.connected); self.receiveLoop()
            case .failed(let e): self.finish(.failed(e.localizedDescription))
            case .cancelled: break
            default: break
            }
        }
    }

    /// Send a line (a trailing newline is appended).
    public func send(_ line: String) {
        guard !done, let data = (line + "\n").data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    public func close() { finish(.closed) }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.finish(.failed(error.localizedDescription)); return }
            if let data, !data.isEmpty {
                self.inbuf.append(data)
                self.drainLines()
            }
            if isComplete { self.finish(.closed); return }
            self.receiveLoop()
        }
    }

    /// Split the inbound buffer on `\n`, deliver complete lines (CR-trimmed).
    private func drainLines() {
        while let nl = inbuf.firstIndex(of: 0x0A) {
            let lineData = inbuf[inbuf.startIndex..<nl]
            inbuf.removeSubrange(inbuf.startIndex...nl)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            onLine?(line)
        }
    }

    private func finish(_ s: State) {
        guard !done else { return }
        done = true
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        onState?(s)
    }
}

/// Offers and sends a file (the *initiate*/SEND side): listens on a vetted local
/// port (advertised to the peer via a CTCP DCC SEND offer), accepts the first
/// inbound connection, and streams the file in chunks with backpressure,
/// draining the receiver's 4-byte acks. Pure Network+Foundation.
public final class DCCUpload {

    public enum State: Equatable, Sendable {
        case connecting, transferring, completed, failed(String), cancelled
    }

    public var onState: ((State) -> Void)?
    /// Total bytes sent so far (for a progress bar).
    public var onProgress: ((UInt64) -> Void)?

    /// Advertised file size (bytes) — goes in the DCC SEND offer.
    public let fileSize: UInt64

    private let fileURL: URL
    private let queue = DispatchQueue(label: "IRCKit.dcc.upload")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var handle: FileHandle?
    private var sent: UInt64 = 0
    private var done = false
    private static let chunk = 65536

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.fileSize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Bind a listener and await the peer. Returns the chosen port + whether it
    /// fell back to the wildcard (caller should warn), or nil if no port was free.
    public func listen(bindHost: String,
                       portRange: ClosedRange<UInt16> = 49152...49200) -> (port: UInt16, wildcard: Bool)? {
        guard let (l, port, wildcard) = DCCNet.makeListener(bindHost: bindHost, range: portRange) else {
            return nil
        }
        listener = l
        onState?(.connecting)
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { conn.cancel(); return }
            self.queue.async {
                self.listener?.cancel()
                self.listener = nil
                self.adopt(conn)
                conn.start(queue: self.queue)
            }
        }
        l.start(queue: queue)
        return (port, wildcard)
    }

    public func cancel() {
        guard !done else { return }
        finish(.cancelled)
    }

    private func adopt(_ conn: NWConnection) {
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.handle = try? FileHandle(forReadingFrom: self.fileURL)
                guard self.handle != nil else { self.finish(.failed("Couldn't open file to send.")); return }
                self.onState?(.transferring)
                self.drainAcks()
                self.sendNextChunk()
            case .failed(let e): self.finish(.failed(e.localizedDescription))
            case .cancelled: break
            default: break
            }
        }
    }

    private func sendNextChunk() {
        guard !done else { return }
        let data = (try? handle?.read(upToCount: Self.chunk)) ?? nil
        guard let data, !data.isEmpty else {
            finish(.completed); return   // EOF — whole file sent
        }
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error { self.finish(.failed(error.localizedDescription)); return }
            self.sent += UInt64(data.count)
            self.onProgress?(self.sent)
            self.sendNextChunk()
        })
    }

    /// Drain the receiver's 4-byte acks so its buffer can't back up (advisory —
    /// we complete on EOF, not on ack count).
    private func drainAcks() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, _ in
            guard let self, !self.done, !isComplete else { return }
            self.drainAcks()
        }
    }

    private func finish(_ s: State) {
        guard !done else { return }
        done = true
        try? handle?.close()
        handle = nil
        listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil
        onState?(s)
    }
}
