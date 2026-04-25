import Foundation
import CryptoKit

/// Single last-seen record for a nick. One is kept per network; a new event
/// overwrites the earlier one.
struct SeenEntry: Codable, Hashable, Identifiable {
    /// Lowercased nick — unique per network, stable across edits.
    var id: String { nick.lowercased() }
    /// Original-case nick as it appeared on the wire.
    var nick: String
    var timestamp: Date
    /// "msg", "join", "part", "quit", "nick". Stored as String for forward
    /// compatibility with future categories.
    var kind: String
    /// Channel where the event occurred (nil for .quit / .nick events).
    var channel: String?
    /// Message text, part/quit reason, or new nick — context-dependent.
    var detail: String?
    /// On nick-change, points at the new nick so lookups by the old nick
    /// can forward the user to the fresh record. Nil for everything else.
    var renamedTo: String?
}

/// Per-network last-seen index. JSON files live at
/// `supportDir/seen/<networkSlug>.json`. Writes are debounced ~2 seconds so a
/// busy channel doesn't thrash the disk.
@MainActor
final class SeenStore {
    private let baseURL: URL
    /// networkID → lowercased-nick → entry.
    private var tables: [UUID: [String: SeenEntry]] = [:]
    private var pendingWrite: [UUID: Task<Void, Never>] = [:]
    private static let debounceSeconds: UInt64 = 2

    /// Current data-encryption key. ChatModel pushes this in whenever the
    /// keystore unlocks or locks. Nil = files written/read as plaintext for
    /// backward compatibility (and so the store works at all when the user
    /// hasn't enabled encryption).
    private var currentKey: SymmetricKey?

    init(supportDirectoryURL: URL) {
        self.baseURL = supportDirectoryURL.appendingPathComponent("seen", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    /// ChatModel pushes the DEK in whenever keystore state changes. Setting
    /// it forces a re-read of any in-memory tables that were populated when
    /// no key was available (so a freshly-unlocked keystore can pull the
    /// real data instead of the empty fallback).
    func setEncryptionKey(_ key: SymmetricKey?) {
        let changed = (key != nil) != (currentKey != nil)
        self.currentKey = key
        if changed {
            // Flush all in-memory tables so the next lookup re-reads from
            // disk through the new key.
            tables.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - Public API

    /// Record an activity event. `kind` must be one of "msg"/"join"/"part"/"quit"/"nick".
    func record(networkID: UUID,
                networkSlug: String,
                nick: String,
                kind: String,
                channel: String?,
                detail: String?) {
        guard !nick.isEmpty else { return }
        ensureLoaded(networkID: networkID, slug: networkSlug)
        let entry = SeenEntry(
            nick: nick,
            timestamp: Date(),
            kind: kind,
            channel: channel,
            detail: detail,
            renamedTo: nil
        )
        tables[networkID, default: [:]][nick.lowercased()] = entry
        scheduleWrite(networkID: networkID, slug: networkSlug)
    }

    /// Record a nick change. The old nick's entry is updated to point at the
    /// new nick so a later `/seen <old>` can forward the user.
    func recordNickChange(networkID: UUID,
                          networkSlug: String,
                          oldNick: String,
                          newNick: String) {
        guard !oldNick.isEmpty, !newNick.isEmpty else { return }
        ensureLoaded(networkID: networkID, slug: networkSlug)
        let now = Date()
        // Carry forward timestamp/detail into the old nick's forwarding record.
        var forward = SeenEntry(
            nick: oldNick,
            timestamp: now,
            kind: "nick",
            channel: nil,
            detail: newNick,
            renamedTo: newNick
        )
        if let existing = tables[networkID]?[oldNick.lowercased()] {
            // Preserve earlier channel context in case useful for display.
            forward.channel = existing.channel
        }
        tables[networkID, default: [:]][oldNick.lowercased()] = forward

        // Seed the new nick with an entry too, so `/seen <new>` immediately works.
        let fresh = SeenEntry(
            nick: newNick,
            timestamp: now,
            kind: "nick",
            channel: tables[networkID]?[oldNick.lowercased()]?.channel,
            detail: "was \(oldNick)",
            renamedTo: nil
        )
        tables[networkID, default: [:]][newNick.lowercased()] = fresh
        scheduleWrite(networkID: networkID, slug: networkSlug)
    }

    /// All known entries for a network — used by SeenListView to populate
    /// the table. Returned in no particular order; UI sorts as it likes.
    func entries(networkID: UUID, networkSlug: String) -> [SeenEntry] {
        ensureLoaded(networkID: networkID, slug: networkSlug)
        return Array(tables[networkID]?.values ?? [:].values)
    }

    /// Find the most recent entry for a nick. If the stored entry is a
    /// forwarding record (renamedTo set), the caller can follow it manually
    /// — we deliberately return the raw entry so the UI can say "alice is
    /// now known as bob; last seen …".
    func lookup(networkID: UUID, networkSlug: String, nick: String) -> SeenEntry? {
        ensureLoaded(networkID: networkID, slug: networkSlug)
        return tables[networkID]?[nick.lowercased()]
    }

    /// Wipe the on-disk + in-memory table for a network. Used by the Setup UI's
    /// "Clear seen data for this network" button.
    func clear(networkID: UUID, networkSlug: String) {
        tables[networkID] = [:]
        let url = fileURL(for: networkSlug)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Internal

    private func ensureLoaded(networkID: UUID, slug: String) {
        if tables[networkID] != nil { return }
        let url = fileURL(for: slug)
        guard let raw = try? Data(contentsOf: url) else {
            tables[networkID] = [:]
            return
        }
        // If the file is encrypted but we don't have a key yet, leave the
        // table empty — the next call after `setEncryptionKey(...)` will
        // reload from disk through the unlocked key.
        let json: Data
        do {
            json = try EncryptedJSON.unwrap(raw, key: currentKey)
        } catch {
            tables[networkID] = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: SeenEntry].self, from: json) {
            tables[networkID] = decoded
        } else {
            tables[networkID] = [:]
        }
    }

    private func scheduleWrite(networkID: UUID, slug: String) {
        pendingWrite[networkID]?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds * NSEC_PER_SEC)
            guard !Task.isCancelled else { return }
            await self?.flush(networkID: networkID, slug: slug)
        }
        pendingWrite[networkID] = task
    }

    /// Exposed for unit tests — synchronously write the current table for a
    /// network, bypassing debounce.
    func flushNow(networkID: UUID, slug: String) {
        pendingWrite[networkID]?.cancel()
        pendingWrite[networkID] = nil
        writeToDisk(networkID: networkID, slug: slug)
    }

    private func flush(networkID: UUID, slug: String) async {
        writeToDisk(networkID: networkID, slug: slug)
    }

    private func writeToDisk(networkID: UUID, slug: String) {
        guard let table = tables[networkID] else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let plain = try? encoder.encode(table) else { return }
        // Use safeWrite so a stale call with no key can't clobber an
        // encrypted seen-data file with plaintext.
        _ = try? EncryptedJSON.safeWrite(plain, to: fileURL(for: slug), key: currentKey)
    }

    private func fileURL(for slug: String) -> URL {
        baseURL.appendingPathComponent("\(slug).json")
    }

    /// URL-safe file slug for a network name. Exported so the engine can
    /// derive a stable filename from the IRCConnection's displayName.
    static func slug(for raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(cleaned).lowercased()
        return s.isEmpty ? "network" : s
    }
}
