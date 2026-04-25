import Foundation
import CryptoKit

/// One observation of a nick at a specific moment. SeenEntry holds the
/// most recent values for quick `/seen` lookup; the `history` array is a
/// rolling list of these so the user can audit every recorded sighting.
struct SeenSighting: Codable, Hashable {
    var timestamp: Date
    /// "msg" / "join" / "part" / "quit" / "nick" — same vocabulary as the
    /// top-level entry kind. Kept as String for forward compatibility.
    var kind: String
    var channel: String?
    var detail: String?
    /// `user@host` portion of the IRC prefix at the moment of this sighting.
    /// Lets the user spot when a familiar nick connects from a new host or
    /// when two nicks share a host (potentially the same person).
    var userHost: String?
}

/// Most-recent sighting for a nick, plus a rolling history. One per nick
/// per network. New events both overwrite the top-level fields *and* prepend
/// to `history` so `/seen` stays fast while a separate "View history" UI
/// can surface every captured sighting.
struct SeenEntry: Codable, Hashable, Identifiable {
    /// Lowercased nick — unique per network, stable across edits.
    var id: String { nick.lowercased() }
    /// Original-case nick as it appeared on the wire.
    var nick: String
    var timestamp: Date
    var kind: String
    var channel: String?
    var detail: String?
    /// On nick-change, points at the new nick so lookups by the old nick
    /// can forward the user to the fresh record. Nil for everything else.
    var renamedTo: String?
    /// `user@host` of the most recent sighting. Same as `history.first?.userHost`
    /// going forward; kept as a top-level field so `/seen` doesn't have to
    /// poke into the history array for the common case.
    var lastUserHost: String?
    /// Rolling history of recent sightings (newest first). Capped to keep
    /// per-nick storage bounded — `SeenStore.historyCap` is the limit.
    var history: [SeenSighting] = []

    init(nick: String,
         timestamp: Date,
         kind: String,
         channel: String? = nil,
         detail: String? = nil,
         renamedTo: String? = nil,
         lastUserHost: String? = nil,
         history: [SeenSighting] = []) {
        self.nick = nick
        self.timestamp = timestamp
        self.kind = kind
        self.channel = channel
        self.detail = detail
        self.renamedTo = renamedTo
        self.lastUserHost = lastUserHost
        self.history = history
    }

    /// Backward-compatible decoder so older seen JSON (no `lastUserHost` /
    /// `history`) keeps loading on upgrade. Without this, a single missing
    /// key would null the whole table.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.nick         = try c.decode(String.self, forKey: .nick)
        self.timestamp    = try c.decode(Date.self,   forKey: .timestamp)
        self.kind         = try c.decode(String.self, forKey: .kind)
        self.channel      = try c.decodeIfPresent(String.self, forKey: .channel)
        self.detail       = try c.decodeIfPresent(String.self, forKey: .detail)
        self.renamedTo    = try c.decodeIfPresent(String.self, forKey: .renamedTo)
        self.lastUserHost = try c.decodeIfPresent(String.self, forKey: .lastUserHost)
        self.history      = try c.decodeIfPresent([SeenSighting].self, forKey: .history) ?? []
    }
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

    /// Cap on the per-nick history array. 50 covers the typical "did this
    /// nick connect from a different host yesterday" question without
    /// blowing up on heavily-active users.
    static let historyCap = 50

    /// Record an activity event. `kind` must be one of
    /// "msg"/"join"/"part"/"quit"/"nick". `userHost` is the `user@host`
    /// portion of the IRC prefix at observation time — when supplied it
    /// helps the user spot host changes / shared hosts across nicks.
    func record(networkID: UUID,
                networkSlug: String,
                nick: String,
                kind: String,
                channel: String?,
                detail: String?,
                userHost: String? = nil) {
        guard !nick.isEmpty else { return }
        ensureLoaded(networkID: networkID, slug: networkSlug)

        let now = Date()
        let sighting = SeenSighting(
            timestamp: now,
            kind: kind,
            channel: channel,
            detail: detail,
            userHost: userHost
        )

        let key = nick.lowercased()
        var entry = tables[networkID]?[key] ?? SeenEntry(
            nick: nick,
            timestamp: now,
            kind: kind
        )
        // Top-level fields = most recent observation, for fast lookup.
        entry.nick = nick
        entry.timestamp = now
        entry.kind = kind
        entry.channel = channel
        entry.detail = detail
        entry.renamedTo = nil
        if let userHost { entry.lastUserHost = userHost }
        // History gets the new sighting prepended; cap to bound storage.
        entry.history.insert(sighting, at: 0)
        if entry.history.count > Self.historyCap {
            entry.history.removeLast(entry.history.count - Self.historyCap)
        }
        tables[networkID, default: [:]][key] = entry
        scheduleWrite(networkID: networkID, slug: networkSlug)
    }

    /// Record a nick change. The old nick's entry is updated to point at
    /// the new nick (so `/seen <old>` forwards), and the new nick gets a
    /// fresh entry seeded with a "was <old>" detail. Both sides also get
    /// a sighting prepended to their history so the audit trail is complete.
    func recordNickChange(networkID: UUID,
                          networkSlug: String,
                          oldNick: String,
                          newNick: String,
                          userHost: String? = nil) {
        guard !oldNick.isEmpty, !newNick.isEmpty else { return }
        ensureLoaded(networkID: networkID, slug: networkSlug)
        let now = Date()
        let oldKey = oldNick.lowercased()
        let newKey = newNick.lowercased()

        // Old nick: forwarding record.
        var forward = tables[networkID]?[oldKey] ?? SeenEntry(
            nick: oldNick, timestamp: now, kind: "nick"
        )
        forward.nick = oldNick
        forward.timestamp = now
        forward.kind = "nick"
        forward.detail = newNick
        forward.renamedTo = newNick
        if let userHost { forward.lastUserHost = userHost }
        forward.history.insert(SeenSighting(
            timestamp: now,
            kind: "nick",
            channel: forward.channel,
            detail: "→ \(newNick)",
            userHost: userHost
        ), at: 0)
        if forward.history.count > Self.historyCap {
            forward.history.removeLast(forward.history.count - Self.historyCap)
        }
        tables[networkID, default: [:]][oldKey] = forward

        // New nick: fresh-or-updated entry, carries history forward from
        // the old name so the rename doesn't reset the timeline.
        var fresh = tables[networkID]?[newKey] ?? SeenEntry(
            nick: newNick, timestamp: now, kind: "nick"
        )
        fresh.nick = newNick
        fresh.timestamp = now
        fresh.kind = "nick"
        fresh.channel = tables[networkID]?[oldKey]?.channel
        fresh.detail = "was \(oldNick)"
        fresh.renamedTo = nil
        if let userHost { fresh.lastUserHost = userHost }
        fresh.history.insert(SeenSighting(
            timestamp: now,
            kind: "nick",
            channel: fresh.channel,
            detail: "was \(oldNick)",
            userHost: userHost
        ), at: 0)
        // Inherit the old nick's older sightings so the new nick's history
        // gives a continuous picture of activity across rename events.
        if let oldHistory = tables[networkID]?[oldKey]?.history.dropFirst() {
            fresh.history.append(contentsOf: oldHistory)
        }
        if fresh.history.count > Self.historyCap {
            fresh.history.removeLast(fresh.history.count - Self.historyCap)
        }
        tables[networkID, default: [:]][newKey] = fresh

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
