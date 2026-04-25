import Foundation
import Combine
import CryptoKit

/// Collects RPL_LISTSTART (321), RPL_LIST (322), and RPL_LISTEND (323) replies
/// into a structured list the UI can search, sort, and act on. One instance
/// per IRCConnection; results are per-network.
///
/// When given a cache location via `setCacheLocation(baseDir:slug:)`, the
/// finished list is persisted to `baseDir/<slug>.json` on every RPL_LISTEND
/// and reloaded on bind — re-opening the sheet on the same network skips the
/// slow LIST roundtrip until the user explicitly refreshes.
@MainActor
final class ChannelListService: ObservableObject {

    struct Listing: Identifiable, Hashable, Codable {
        /// Channel names are unique per network, so they're stable row IDs.
        var id: String { name }
        let name: String
        let users: Int
        let topic: String
    }

    @Published private(set) var listings: [Listing] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastUpdated: Date? = nil

    private var cacheFileURL: URL?
    /// DEK used to wrap the on-disk snapshot. ChatModel pushes this in
    /// whenever the keystore unlocks/locks. Nil = plaintext file (which is
    /// also the path legacy installs are reading from on disk today).
    private var currentKey: SymmetricKey?

    /// ChatModel calls this on every keystore state change. A flip in
    /// presence triggers a reload so we re-decode through the new key.
    func setEncryptionKey(_ key: SymmetricKey?) {
        let changed = (key != nil) != (currentKey != nil)
        currentKey = key
        if changed { loadCache() }
    }

    /// Wire this service to a persistent cache file. Loads any prior snapshot
    /// so the UI can show stale data immediately while the user decides
    /// whether to refresh. Safe to call multiple times.
    func setCacheLocation(baseDir: URL, slug: String) {
        guard !slug.isEmpty else { return }
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        cacheFileURL = baseDir.appendingPathComponent("\(slug).json")
        loadCache()
    }

    /// Called when the user kicks off a fresh /LIST. Clears any previous state
    /// and flips the loading flag so the UI can show a spinner.
    func begin() {
        listings = []
        isLoading = true
    }

    /// Feed a parsed 322 reply in. Duplicate channel names replace the earlier
    /// entry so a refresh updates in-place instead of stacking.
    func append(from msg: IRCMessage) {
        // :server 322 ourNick <channel> <users> :<topic>
        guard msg.params.count >= 3 else { return }
        let name = msg.params[1]
        let users = Int(msg.params[2]) ?? 0
        let topic = msg.params.count >= 4 ? msg.params[3] : ""
        let entry = Listing(name: name, users: users, topic: topic)
        if let i = listings.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            listings[i] = entry
        } else {
            listings.append(entry)
        }
    }

    /// 323 arrived — server is done listing.
    func end() {
        isLoading = false
        lastUpdated = Date()
        saveCache()
    }

    /// Wipe cached data both in memory and on disk. Called by the "Refresh"
    /// UI path and by the `/list full` command so a fresh LIST starts clean.
    func clearCache() {
        listings = []
        lastUpdated = nil
        if let url = cacheFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Cache persistence

    private struct Snapshot: Codable {
        let updatedAt: Date
        let listings: [Listing]
    }

    private func loadCache() {
        guard let url = cacheFileURL,
              let raw = try? Data(contentsOf: url) else { return }
        // Encrypted snapshot with no key yet → leave the in-memory state
        // alone; setEncryptionKey will trigger another loadCache later.
        guard let json = try? EncryptedJSON.unwrap(raw, key: currentKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(Snapshot.self, from: json) else { return }
        self.listings = snap.listings
        self.lastUpdated = snap.updatedAt
    }

    private func saveCache() {
        guard let url = cacheFileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let snap = Snapshot(updatedAt: lastUpdated ?? Date(), listings: listings)
        guard let plain = try? encoder.encode(snap) else { return }
        guard let bytes = try? EncryptedJSON.wrap(plain, key: currentKey) else { return }
        try? bytes.write(to: url, options: .atomic)
    }
}
