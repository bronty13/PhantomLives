import Foundation
import CryptoKit

/// Per-network archive of recent chat lines, sealed with the keystore DEK
/// when one is available. Mirrors the `SeenStore` pattern: one JSON file
/// per network slug, encrypted via `EncryptedJSON` so locked sessions
/// can't peek and the format gracefully accepts plaintext fallback for
/// unencrypted users.
///
/// Used by ChatModel to capture the trailing window of each open buffer
/// at quit time (and at every disconnect) so the next launch can replay
/// those lines into the buffer with a "previous session" separator. The
/// store does NOT track ALL history — it caps at `Self.linesPerBuffer`
/// per buffer to keep file sizes bounded.
@MainActor
final class SessionHistoryStore: ObservableObject {
    /// Per-buffer ChatLine cap. Tuned so a busy 5-buffer network produces
    /// ~150KB of JSON before encryption — comfortable to roundtrip on
    /// every save without burning the disk.
    static let linesPerBuffer = 200

    private let baseDir: URL
    private var key: SymmetricKey?
    private let fm = FileManager.default

    /// Wire format. Keyed by the original buffer name (case-preserved) so
    /// the lookup at restore time matches the channel/query the user joined.
    struct NetworkHistory: Codable {
        var buffers: [String: [ChatLine]] = [:]
    }

    init(supportDirectoryURL: URL) {
        self.baseDir = supportDirectoryURL.appendingPathComponent("history",
                                                                  isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    /// Same DEK ChatModel pushes into every other persistence subsystem.
    /// `nil` switches the next save back to plaintext. Reads continue to
    /// auto-detect format via `EncryptedJSON.hasMagic`.
    func setEncryptionKey(_ key: SymmetricKey?) {
        self.key = key
    }

    /// Read the saved history for a network. Returns an empty default if
    /// the file is missing, can't be unwrapped, or fails to decode — never
    /// throws, because a corrupt history file should never block restore.
    func load(networkSlug: String) -> NetworkHistory {
        let url = fileURL(for: networkSlug)
        guard let data = try? Data(contentsOf: url) else {
            return NetworkHistory()
        }
        guard let plain = try? EncryptedJSON.unwrap(data, key: key),
              let decoded = try? JSONDecoder().decode(NetworkHistory.self, from: plain)
        else {
            return NetworkHistory()
        }
        return decoded
    }

    /// Persist the trailing-window snapshot of every buffer on this
    /// network. Empty buffers are dropped so the file shrinks naturally
    /// when channels are PARTed.
    func save(networkSlug: String, history: NetworkHistory) {
        let url = fileURL(for: networkSlug)
        // Drop empty buffer entries; save space and keep load() simple.
        var trimmed = history
        trimmed.buffers = trimmed.buffers.filter { !$0.value.isEmpty }
        do {
            let data = try JSONEncoder().encode(trimmed)
            let result = try EncryptedJSON.safeWrite(data, to: url, key: key)
            if case .skippedLockedEncrypted = result {
                // The file is encrypted on disk and we have no key — refuse
                // to overwrite. Same hard guarantee SettingsStore uses to
                // prevent the lock-time clobber pattern.
                return
            }
        } catch {
            // Persistence failures shouldn't crash the app; log and move on.
            return
        }
    }

    /// Clear the saved history for a network — used by a future "Forget
    /// session" action; not currently surfaced in the UI.
    func clear(networkSlug: String) {
        try? fm.removeItem(at: fileURL(for: networkSlug))
    }

    private func fileURL(for slug: String) -> URL {
        baseDir.appendingPathComponent("\(slug).json", isDirectory: false)
    }
}
