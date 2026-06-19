import Foundation
import Combine
import IRCKit

/// One inbound DCC SEND we've been offered (and may accept). Observable so the
/// transfer window can show live progress.
@MainActor
final class DCCItem: ObservableObject, Identifiable {
    let id = UUID()
    let peer: String
    let filename: String
    let size: UInt64
    let host: String
    let port: UInt16
    /// True when WE are sending the file (outgoing); false when receiving.
    let isOutgoing: Bool

    @Published var state: DCCItemState = .offered
    @Published var received: UInt64 = 0
    /// Incoming: where the file is saved. Outgoing: the source file (for Reveal).
    var destination: URL?
    var download: DCCDownload?
    var upload: DCCUpload?

    init(peer: String, filename: String, size: UInt64, host: String, port: UInt16, isOutgoing: Bool = false) {
        self.peer = peer; self.filename = filename; self.size = size
        self.host = host; self.port = port; self.isOutgoing = isOutgoing
    }

    func apply(_ s: DCCDownload.State) {
        switch s {
        case .connecting:   state = .connecting
        case .transferring: state = .transferring
        case .completed:    state = .completed
        case .cancelled:    state = .cancelled
        case .failed(let m): state = .failed(m)
        }
    }

    func apply(upload s: DCCUpload.State) {
        switch s {
        case .connecting:   state = .connecting
        case .transferring: state = .transferring
        case .completed:    state = .completed
        case .cancelled:    state = .cancelled
        case .failed(let m): state = .failed(m)
        }
    }
}

enum DCCItemState: Equatable {
    case offered, connecting, transferring, completed, failed(String), declined, cancelled
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .declined, .cancelled: return true
        default: return false
        }
    }
}

/// One line in a DCC chat.
struct DCCChatLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let fromSelf: Bool
}

enum DCCChatState: Equatable {
    case offered, connecting, connected, closed, failed(String), declined
    var isActive: Bool { self == .connecting || self == .connected }
    var isTerminal: Bool {
        switch self { case .closed, .failed, .declined: return true; default: return false }
    }
}

/// An offered/active DCC CHAT (the accept side).
@MainActor
final class DCCChatSession: ObservableObject, Identifiable {
    let id = UUID()
    let peer: String
    let host: String
    let port: UInt16
    /// True when WE offered the chat (we listen + advertise); false when the
    /// peer offered and we dial them.
    let isOutgoing: Bool
    @Published var state: DCCChatState = .offered
    @Published var lines: [DCCChatLine] = []
    var chat: DCCChat?

    init(peer: String, host: String, port: UInt16, isOutgoing: Bool = false) {
        self.peer = peer; self.host = host; self.port = port; self.isOutgoing = isOutgoing
    }

    func apply(_ s: DCCChat.State) {
        switch s {
        case .connecting: state = .connecting
        case .connected:  state = .connected
        case .closed:     state = .closed
        case .failed(let m): state = .failed(m)
        }
    }
}

/// App-side DCC orchestration: holds offered/active transfers, decides the
/// (sanitized, in-Downloads, non-clobbering) save path, and drives IRCKit's
/// `DCCDownload`. Never auto-accepts — the user must accept each offer.
@MainActor
final class IrcleDCC: ObservableObject {
    @Published private(set) var items: [DCCItem] = []
    @Published private(set) var chats: [DCCChatSession] = []

    /// Record an inbound DCC offer (already validated/sanitized by IRCKit's DCC
    /// engine): SEND → a file transfer, CHAT → a chat session.
    func addOffer(_ offer: DCC.Offer, from peer: String) {
        switch offer.kind {
        case .send:
            items.insert(DCCItem(peer: peer, filename: offer.filename ?? "dcc-file",
                                 size: offer.size ?? 0, host: offer.host, port: offer.port), at: 0)
        case .chat:
            chats.insert(DCCChatSession(peer: peer, host: offer.host, port: offer.port), at: 0)
        }
    }

    // MARK: - Chat

    func acceptChat(_ s: DCCChatSession) {
        guard s.state == .offered else { return }
        let chat = DCCChat(host: s.host, port: s.port)
        chat.onState = { [weak s] st in Task { @MainActor in s?.apply(st) } }
        chat.onLine = { [weak s] line in
            Task { @MainActor in s?.lines.append(DCCChatLine(text: line, fromSelf: false)) }
        }
        s.chat = chat
        s.state = .connecting
        chat.start()
    }

    /// Offer a DCC chat (we listen + advertise). Binds to `advertiseIP`,
    /// inserts a session, and returns the listening port + whether it fell back
    /// to the wildcard (caller should warn), or nil if no port was free.
    func offerChat(to peer: String, advertiseIP: String) -> (session: DCCChatSession, port: UInt16, wildcard: Bool)? {
        let s = DCCChatSession(peer: peer, host: advertiseIP, port: 0, isOutgoing: true)
        let chat = DCCChat()
        guard let (port, wildcard) = chat.listen(bindHost: advertiseIP) else { return nil }
        chat.onState = { [weak s] st in Task { @MainActor in s?.apply(st) } }
        chat.onLine = { [weak s] line in
            Task { @MainActor in s?.lines.append(DCCChatLine(text: line, fromSelf: false)) }
        }
        s.chat = chat
        s.state = .connecting   // waiting for the peer to connect
        chats.insert(s, at: 0)
        return (s, port, wildcard)
    }

    func declineChat(_ s: DCCChatSession) { if s.state == .offered { s.state = .declined } }

    func sendChat(_ s: DCCChatSession, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.state == .connected, !t.isEmpty else { return }
        s.chat?.send(t)
        s.lines.append(DCCChatLine(text: t, fromSelf: true))
    }

    func closeChat(_ s: DCCChatSession) { s.chat?.close() }

    func chat(id: UUID) -> DCCChatSession? { chats.first { $0.id == id } }

    func accept(_ item: DCCItem) {
        guard item.state == .offered else { return }
        let dest = Self.uniqueDestination(for: item.filename, in: Self.downloadsDir)
        item.destination = dest
        let dl = DCCDownload(host: item.host, port: item.port,
                             destination: dest, expectedSize: item.size)
        dl.onState = { [weak item] s in Task { @MainActor in item?.apply(s) } }
        dl.onProgress = { [weak item] n in Task { @MainActor in item?.received = n } }
        item.download = dl
        item.state = .connecting
        dl.start()
    }

    func decline(_ item: DCCItem) { if item.state == .offered { item.state = .declined } }

    func cancel(_ item: DCCItem) { item.download?.cancel(); item.upload?.cancel() }

    /// Offer a file to `peer` (we listen + advertise). Binds to `advertiseIP`,
    /// inserts an outgoing item, and returns the listening port + size + whether
    /// it fell back to the wildcard, or nil if no port was free.
    func offerSend(to peer: String, fileURL: URL, advertiseIP: String)
        -> (item: DCCItem, port: UInt16, size: UInt64, wildcard: Bool)? {
        let upload = DCCUpload(fileURL: fileURL)
        guard let (port, wildcard) = upload.listen(bindHost: advertiseIP) else { return nil }
        let item = DCCItem(peer: peer, filename: fileURL.lastPathComponent, size: upload.fileSize,
                           host: advertiseIP, port: port, isOutgoing: true)
        item.destination = fileURL   // for Reveal
        upload.onState = { [weak item] s in Task { @MainActor in item?.apply(upload: s) } }
        upload.onProgress = { [weak item] n in Task { @MainActor in item?.received = n } }
        item.upload = upload
        item.state = .connecting
        items.insert(item, at: 0)
        return (item, port, upload.fileSize, wildcard)
    }

    func clearFinished() {
        items.removeAll { $0.state.isTerminal }
        chats.removeAll { $0.state.isTerminal }
    }

    /// `~/Downloads/Ircle/DCC/`.
    static var downloadsDir: URL {
        SettingsStore.downloadsDirectory.appendingPathComponent("DCC", isDirectory: true)
    }

    /// A non-clobbering destination URL: `foo.txt`, then `foo (1).txt`,
    /// `foo (2).txt`, … The filename is re-sanitized (defense in depth) so a
    /// save can never escape `dir`. `fileExists` is injectable for tests.
    static func uniqueDestination(for filename: String, in dir: URL,
                                  fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let safe = DCC.sanitizeFilename(filename)
        let first = dir.appendingPathComponent(safe)
        if !fileExists(first) { return first }
        let ext = (safe as NSString).pathExtension
        let base = (safe as NSString).deletingPathExtension
        var n = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fileExists(candidate) { return candidate }
            n += 1
        }
    }
}
