import Foundation
import Network

/// One remote decision write, described semantically (not as a closure) so the queue can
/// COALESCE repeats, PERSIST across launches, and replay in order. Per `kind`, exactly one of the
/// value fields is meaningful — and `nil` is a legitimate value where the wire allows clearing
/// (`keep: nil` = undecide, `title/caption: nil` = clear), so the kind, not the value, is the
/// discriminator.
struct PendingWrite: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case keep, favorite, hidden, title, caption, keywords, albums
    }

    var id: UUID = UUID()
    let fileId: String
    let kind: Kind
    var intValue: Int?          // keep (nil = undecided)
    var boolValue: Bool?        // favorite / hidden
    var stringValue: String?    // title / caption (nil = clear)
    var listValue: [String]?    // keywords / albums
    var fileName: String = ""   // for the permanent-failure message only

    static func keep(fileId: String, fileName: String, value: Int?) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .keep, intValue: value, fileName: fileName)
    }
    static func favorite(fileId: String, fileName: String, value: Bool) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .favorite, boolValue: value, fileName: fileName)
    }
    static func hidden(fileId: String, fileName: String, value: Bool) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .hidden, boolValue: value, fileName: fileName)
    }
    static func title(fileId: String, fileName: String, value: String?) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .title, stringValue: value, fileName: fileName)
    }
    static func caption(fileId: String, fileName: String, value: String?) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .caption, stringValue: value, fileName: fileName)
    }
    static func keywords(fileId: String, fileName: String, names: [String]) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .keywords, listValue: names, fileName: fileName)
    }
    static func albums(fileId: String, fileName: String, names: [String]) -> PendingWrite {
        PendingWrite(fileId: fileId, kind: .albums, listValue: names, fileName: fileName)
    }
}

/// The offline write queue for remote mode — closes the audit's one data-integrity gap.
///
/// Before this, every remote mutation was an optimistic patch + a fire-and-forget POST whose
/// failure path REVERTED (or resynced away) the user's decision: triage through a 10-second Wi-Fi
/// blip and the keeps you made silently became undecided again. Now every remote write enters
/// this queue, which:
///
///  - **persists** to disk immediately (a blip that outlives the app doesn't lose decisions;
///    the store is per-server-account, reloaded on the next connect),
///  - **coalesces** by (file, field) — only the newest value of a field is ever sent,
///  - **replays in order**, one at a time, so writes can't arrive out of sequence,
///  - **retries** transient failures (connection refused/lost/timeout, 5xx) with backoff, and
///    immediately when NWPathMonitor says the network came back,
///  - **drops + surfaces** permanent failures (4xx/decoding — retrying those forever would wedge
///    the queue behind an unsendable write).
///
/// The UI keeps its optimistic patch while a write is queued (the queue guarantees delivery or a
/// visible failure), and shows a "N unsaved" pill from `onCountChange`.
@MainActor
final class RemoteWriteQueue {
    typealias Sender = (PendingWrite) async throws -> Void

    private(set) var pending: [PendingWrite] = []
    var onCountChange: ((Int) -> Void)?
    var onPermanentFailure: ((PendingWrite, Error) -> Void)?

    private let sender: Sender
    private let storeURL: URL
    private let autoRetry: Bool
    private var draining = false
    private var retryAttempts = 0
    private var retryTask: Task<Void, Never>?
    private var monitor: NWPathMonitor?

    /// `storeURL`: where the queue persists (JSON; one file per server account).
    /// `autoRetry: false` disables the path monitor + backoff timers (tests drive `drainNow()`).
    init(storeURL: URL, autoRetry: Bool = true, sender: @escaping Sender) {
        self.storeURL = storeURL
        self.autoRetry = autoRetry
        self.sender = sender
        if let data = try? Data(contentsOf: storeURL),
           let restored = try? JSONDecoder().decode([PendingWrite].self, from: data) {
            pending = restored
        }
        if autoRetry {
            let m = NWPathMonitor()
            m.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in
                    self?.retryAttempts = 0        // fresh network → fresh backoff
                    await self?.drain()
                }
            }
            m.start(queue: DispatchQueue(label: "purplepeek.writequeue.path"))
            monitor = m
        }
        if !pending.isEmpty { kickDrain() }
    }

    /// Stop timers/monitoring when the owning connection goes away. Pending writes stay
    /// persisted; the next queue for the same account picks them up.
    func shutdown() {
        retryTask?.cancel()
        monitor?.cancel()
        monitor = nil
    }

    /// Enqueue (coalescing away any older write to the same file+field), persist, and try to send.
    func submit(_ write: PendingWrite) {
        pending.removeAll { $0.fileId == write.fileId && $0.kind == write.kind }
        pending.append(write)
        persist()
        onCountChange?(pending.count)
        kickDrain()
    }

    /// Run the queue until empty or the first transient failure. Public for tests and for an
    /// explicit "retry now" affordance.
    func drainNow() async { await drain() }

    private func kickDrain() {
        Task { await drain() }
    }

    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while let next = pending.first {
            do {
                try await sender(next)
                // Remove by id, NOT position: a newer submit may have coalesced-replaced this
                // entry while the send was in flight — that newer write must survive and resend.
                pending.removeAll { $0.id == next.id }
                retryAttempts = 0
                persist()
                onCountChange?(pending.count)
            } catch where Self.isRetryable(error) {
                scheduleRetry()
                return
            } catch {
                pending.removeAll { $0.id == next.id }
                persist()
                onCountChange?(pending.count)
                onPermanentFailure?(next, error)
            }
        }
    }

    private func scheduleRetry() {
        guard autoRetry else { return }
        retryAttempts += 1
        let delay = min(60.0, 5.0 * pow(2.0, Double(retryAttempts - 1)))   // 5,10,20,40,60,60…
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: storeURL)
        } else if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// Transient (keep queued, retry) vs permanent (drop + surface). Transport-level URLErrors
    /// are transient except explicit non-network ones; HTTP 5xx is a server hiccup, 4xx means
    /// this write can never succeed (e.g. the item was deleted server-side).
    nonisolated static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled, .badURL, .unsupportedURL, .dataLengthExceedsMaximum:
                return false
            default:
                return true
            }
        }
        if let peekError = error as? PeekServerError {
            switch peekError {
            case .badResponse(let code): return code >= 500
            case .notFound, .notConfigured, .decoding, .unsupported: return false
            }
        }
        return false
    }

    /// The per-account store file, so pending writes follow their server.
    /// "peek@10.0.0.59:8788" → …/Application Support/PurplePeek/pending-writes-peek@10.0.0.59_8788.json
    nonisolated static func storeURL(account: String) -> URL {
        let safe = account.replacingOccurrences(of: "/", with: "_")
                          .replacingOccurrences(of: ":", with: "_")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PurplePeek", isDirectory: true)
            .appendingPathComponent("pending-writes-\(safe).json")
    }
}
