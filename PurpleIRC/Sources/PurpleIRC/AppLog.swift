import Foundation
import CryptoKit
import SwiftUI

/// Severity level for app diagnostic logs. `Comparable` so the viewer can
/// filter "everything at or above warn", and `CaseIterable` so the picker can
/// enumerate the choices without hard-coding them.
enum LogLevel: Int, CaseIterable, Comparable, Codable {
    case debug    = 0
    case info     = 1
    case notice   = 2
    case warn     = 3
    case error    = 4
    case critical = 5

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .debug:    return "DEBUG"
        case .info:     return "INFO"
        case .notice:   return "NOTICE"
        case .warn:     return "WARN"
        case .error:    return "ERROR"
        case .critical: return "CRIT"
        }
    }

    /// Color for the level chip in the viewer. Pure UI concern, but keeping
    /// the mapping next to the enum makes the viewer trivial.
    var tint: Color {
        switch self {
        case .debug:    return .secondary
        case .info:     return .accentColor
        case .notice:   return .blue
        case .warn:     return .orange
        case .error:    return .red
        case .critical: return .pink
        }
    }
}

/// One emitted log record. Identifiable so SwiftUI lists are stable;
/// Codable so the viewer can copy/export entire snapshots.
struct AppLogRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    /// Subsystem label — typically a Swift type name. Used for filtering.
    let category: String
    let message: String

    init(level: LogLevel, category: String, message: String,
         timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// In-process diagnostic logger. ChatModel constructs and configures the
/// shared instance so it can write to an encrypted file under the support
/// directory; views observe `changeCount` to refresh the viewer.
///
/// **Thread-safety.** All public mutation is funnelled through `record(...)`,
/// which dispatches to the main actor. SwiftUI consumers therefore see
/// consistent state without any explicit synchronization.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    /// Bumped on every append. Views observe this instead of the (potentially
    /// large) `entries` array, so SwiftUI doesn't diff thousands of rows on
    /// every keystroke into the input field.
    @Published private(set) var changeCount: Int = 0

    /// Minimum level that will be retained or written to disk. Defaults to
    /// `.info` so debug-level chatter doesn't fill the ring buffer in
    /// production. Users can drop it to `.debug` from the viewer.
    @Published var minimumLevel: LogLevel = .info

    /// Most-recent N entries, oldest first. Capped to keep memory bounded
    /// regardless of session length. Persisted only when a writer is bound.
    private(set) var entries: [AppLogRecord] = []
    private let ringCap = 5000

    /// File the logger appends to (one length-prefixed encrypted record per
    /// append, mirroring the LogStore wire format) when `bind(...)` has been
    /// called. nil means in-memory only.
    private var fileURL: URL?
    /// Symmetric DEK for encrypted persistence. nil means write plaintext
    /// (one JSON record per line) — surfaced under the same on-disk filename
    /// so the viewer can detect format on read.
    private var key: SymmetricKey?

    private init() {}

    /// Wire the logger to a file on disk. Safe to call repeatedly — the
    /// latest call wins. Pass `key = nil` for plaintext mode (matches the
    /// rest of PurpleIRC's "encryption is opt-in" stance).
    func bind(fileURL: URL, key: SymmetricKey?) {
        self.fileURL = fileURL
        self.key = key
        // Best-effort restore of recent records if the file already exists.
        // Bounded read keeps a giant log from blocking app start.
        loadFromDisk()
    }

    /// Sever the file binding. The next emit will go to the ring only.
    /// Called when the user re-locks the keystore so we don't write
    /// plaintext records to a file that was previously encrypted.
    func unbind() {
        self.fileURL = nil
        self.key = nil
    }

    /// Replace the in-memory ring with the file's contents. Called from
    /// `bind(...)` and as part of viewer "refresh".
    func loadFromDisk() {
        guard let fileURL else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            changeCount &+= 1
            return
        }
        var rebuilt: [AppLogRecord] = []
        rebuilt.reserveCapacity(min(ringCap, data.count / 64))

        if EncryptedJSON.hasMagic(data) {
            // Encrypted log: stream of [4-byte length][AES-GCM record].
            // Mirror of LogStore's encrypted-log loader.
            let body = data.subdata(in: EncryptedJSON.magic.count..<data.count)
            var offset = 0
            while offset + 4 <= body.count {
                let len = Int(body[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                offset += 4
                guard offset + len <= body.count else { break }
                let chunk = body.subdata(in: offset..<offset+len)
                offset += len
                if let key,
                   let plain = try? Crypto.decrypt(chunk, using: key),
                   let rec = try? JSONDecoder().decode(AppLogRecord.self, from: plain) {
                    rebuilt.append(rec)
                }
            }
        } else {
            // Plaintext log: one JSON object per line.
            for line in data.split(separator: 0x0a) where !line.isEmpty {
                if let rec = try? JSONDecoder().decode(AppLogRecord.self, from: Data(line)) {
                    rebuilt.append(rec)
                }
            }
        }

        if rebuilt.count > ringCap {
            rebuilt.removeFirst(rebuilt.count - ringCap)
        }
        entries = rebuilt
        changeCount &+= 1
    }

    /// Drop every record (memory + disk). Used by the viewer's "Clear".
    func clear() {
        entries = []
        changeCount &+= 1
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Core emit. Adds to the ring, persists when bound, bumps the counter.
    func record(_ level: LogLevel, category: String, _ message: String) {
        guard level >= minimumLevel else { return }
        let rec = AppLogRecord(level: level, category: category, message: message)
        entries.append(rec)
        if entries.count > ringCap {
            entries.removeFirst(entries.count - ringCap)
        }
        appendToFile(rec)
        changeCount &+= 1
    }

    private func appendToFile(_ rec: AppLogRecord) {
        guard let fileURL else { return }
        guard let payload = try? JSONEncoder().encode(rec) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        } catch {
            return
        }

        if let key {
            // Encrypted: 4-byte big-endian length + AES-GCM record. Header
            // written exactly once when the file is first created.
            do {
                let sealed = try Crypto.encrypt(payload, using: key)
                var bytes = Data()
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    bytes.append(contentsOf: EncryptedJSON.magic)
                }
                var len = UInt32(sealed.count).bigEndian
                bytes.append(Data(bytes: &len, count: 4))
                bytes.append(sealed)
                try appendBytes(bytes, to: fileURL)
            } catch {
                return
            }
        } else {
            // Plaintext: one JSON object per line.
            var bytes = payload
            bytes.append(0x0a)
            try? appendBytes(bytes, to: fileURL)
        }
    }

    /// Atomic-ish append. macOS doesn't expose an O_APPEND helper on URL,
    /// so we go through `FileHandle`. Errors swallowed — diagnostic logging
    /// must never crash the app.
    private func appendBytes(_ bytes: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let fh = try FileHandle(forWritingTo: url)
            try fh.seekToEnd()
            try fh.write(contentsOf: bytes)
            try fh.close()
        } else {
            try bytes.write(to: url)
        }
    }

    // MARK: - Convenience

    func debug   (_ message: String, category: String = "App") { record(.debug,    category: category, message) }
    func info    (_ message: String, category: String = "App") { record(.info,     category: category, message) }
    func notice  (_ message: String, category: String = "App") { record(.notice,   category: category, message) }
    func warn    (_ message: String, category: String = "App") { record(.warn,     category: category, message) }
    func error   (_ message: String, category: String = "App") { record(.error,    category: category, message) }
    func critical(_ message: String, category: String = "App") { record(.critical, category: category, message) }
}
