import Foundation
import CryptoKit

/// Per-script key-value persistence for PurpleBot scripts. Each script's
/// `irc.store.get` / `.set` / `.delete` / `.keys` calls land in its own
/// JSON file under `<supportDir>/scripts/<scriptID>.store.json` so the
/// scripts cannot collide on key names — a script that uses `count` is
/// completely independent of another script that also uses `count`.
///
/// On-disk format mirrors the rest of the persistence layer: plain
/// `JSONSerialization` output when the keystore is locked or absent,
/// AES-256-GCM-sealed under the per-install DEK once the user has
/// unlocked it. The same `EncryptedJSON.safeWrite` envelope guard that
/// protects every other store applies here — a `set` with no key in
/// hand refuses to clobber an existing encrypted file.
///
/// Synchronous from the caller's perspective: PurpleBot's `irc.store`
/// JS calls block while the file write completes. Stores are small
/// (handful of keys per script in typical use) so write-through latency
/// is in the low-millisecond range; if a script writes in a tight loop
/// we may revisit with a debounced flush.
@MainActor
final class ScriptStore {
    private var caches: [UUID: [String: Any]] = [:]
    private let directory: URL
    /// DEK pushed in by `BotHost.setEncryptionKey`. Mirrors the
    /// `currentKey` plumbing on `BotHost` itself so the script store is
    /// sealed under the same envelope as `index.json` and the script
    /// sources.
    private(set) var currentKey: SymmetricKey?

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)
    }

    func setEncryptionKey(_ key: SymmetricKey?) {
        currentKey = key
    }

    /// Read a key. Returns nil when the key is missing OR when the
    /// value is JS `null` — `irc.store.get('x')` returning `null` in
    /// JS is indistinguishable from "no entry", which matches user
    /// expectations for a key-value store.
    func get(scriptID: UUID, key: String) -> Any? {
        ensureLoaded(scriptID: scriptID)
        let value = caches[scriptID]?[key]
        // Translate the NSNull sentinel back to nil so JS sees `null`.
        if value is NSNull { return nil }
        return value
    }

    /// Write a key. `nil` / `NSNull` are stored as JSON null so a
    /// subsequent `get` returns nil — semantically the same as
    /// `delete`, just without the eviction.
    func set(scriptID: UUID, key: String, value: Any?) {
        ensureLoaded(scriptID: scriptID)
        caches[scriptID, default: [:]][key] = value ?? NSNull()
        persist(scriptID: scriptID)
    }

    /// Drop a key. No-op when the key is absent.
    func delete(scriptID: UUID, key: String) {
        ensureLoaded(scriptID: scriptID)
        guard caches[scriptID]?.removeValue(forKey: key) != nil else { return }
        persist(scriptID: scriptID)
    }

    /// Live list of keys. Order is unspecified — JS's `keys()` doesn't
    /// promise sort order on a plain object either.
    func keys(scriptID: UUID) -> [String] {
        ensureLoaded(scriptID: scriptID)
        return Array(caches[scriptID]?.keys ?? [:].keys)
    }

    /// Forget a script's cache + delete its file. Called from `/nuke`
    /// and when a script is deleted from the Setup → Scripts tab.
    func purge(scriptID: UUID) {
        caches.removeValue(forKey: scriptID)
        let url = fileURL(scriptID: scriptID)
        try? FileManager.default.removeItem(at: url)
    }

    /// Re-encrypt every loaded cache under the current keystore key.
    /// Called by `BotHost` when the keystore unlocks so previously
    /// plaintext writes get re-wrapped at the next mutation. Idempotent.
    func reseal() {
        for id in caches.keys {
            persist(scriptID: id)
        }
    }

    // MARK: - File I/O

    private func ensureLoaded(scriptID: UUID) {
        if caches[scriptID] != nil { return }
        let url = fileURL(scriptID: scriptID)
        guard let data = try? Data(contentsOf: url) else {
            caches[scriptID] = [:]
            return
        }
        guard let jsonData = try? EncryptedJSON.unwrap(data, key: currentKey) else {
            // Locked-encrypted: leave the cache empty for this session.
            // We must NOT mark it loaded with `[:]` because the next
            // `set` would persist `{}` over the encrypted file. Instead,
            // record an empty cache only on a clean miss; on a locked
            // miss, keep `caches[scriptID]` nil so subsequent calls
            // re-attempt the load after the keystore unlocks.
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            caches[scriptID] = obj
        } else {
            caches[scriptID] = [:]
        }
    }

    private func persist(scriptID: UUID) {
        guard let cache = caches[scriptID] else { return }
        let url = fileURL(scriptID: scriptID)
        do {
            // JSONSerialization isn't strict about Foundation-only types
            // beyond the listed set (NSDictionary / NSArray / NSString /
            // NSNumber / NSNull / Bool). We accept Any here because the
            // JS bridge hands us values via NSObject types already.
            // Reject non-serializable values rather than crash.
            guard JSONSerialization.isValidJSONObject(cache) else {
                NSLog("PurpleIRC: script store skipped — value not JSON-serializable for \(scriptID)")
                return
            }
            let jsonData = try JSONSerialization.data(withJSONObject: cache,
                                                      options: [.sortedKeys])
            _ = try EncryptedJSON.safeWrite(jsonData, to: url, key: currentKey)
        } catch {
            NSLog("PurpleIRC: script store save failed for \(scriptID): \(error)")
        }
    }

    private func fileURL(scriptID: UUID) -> URL {
        directory.appendingPathComponent("\(scriptID.uuidString).store.json")
    }
}
