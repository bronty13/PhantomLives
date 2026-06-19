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

    @Published var state: DCCItemState = .offered
    @Published var received: UInt64 = 0
    var destination: URL?
    var download: DCCDownload?

    init(peer: String, filename: String, size: UInt64, host: String, port: UInt16) {
        self.peer = peer; self.filename = filename; self.size = size
        self.host = host; self.port = port
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

/// App-side DCC orchestration: holds offered/active transfers, decides the
/// (sanitized, in-Downloads, non-clobbering) save path, and drives IRCKit's
/// `DCCDownload`. Never auto-accepts — the user must accept each offer.
@MainActor
final class IrcleDCC: ObservableObject {
    @Published private(set) var items: [DCCItem] = []

    /// Record an inbound SEND offer (already validated/sanitized by IRCKit's
    /// DCC engine). CHAT offers are not handled here yet (Stage 3).
    func addOffer(_ offer: DCC.Offer, from peer: String) {
        guard offer.kind == .send else { return }
        items.insert(DCCItem(peer: peer, filename: offer.filename ?? "dcc-file",
                             size: offer.size ?? 0, host: offer.host, port: offer.port), at: 0)
    }

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

    func cancel(_ item: DCCItem) { item.download?.cancel() }

    func clearFinished() { items.removeAll { $0.state.isTerminal } }

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
