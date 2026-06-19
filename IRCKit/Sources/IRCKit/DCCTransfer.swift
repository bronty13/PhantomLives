import Foundation
import Network

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
    private var inbuf = Data()
    private var done = false

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    public func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            finish(.failed("Invalid port \(port).")); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn
        onState?(.connecting)
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready: self.onState?(.connected); self.receiveLoop()
            case .failed(let e): self.finish(.failed(e.localizedDescription))
            case .cancelled: break
            default: break
            }
        }
        conn.start(queue: queue)
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
        connection?.cancel()
        connection = nil
        onState?(s)
    }
}
