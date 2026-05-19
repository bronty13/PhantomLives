import Foundation
import CryptoKit

/// Per-file persistence for `SavedImportMapping`. Each mapping lives
/// in its own file under `~/Library/Application Support/PurpleLife/mappings/`
/// so:
///   • A malformed mapping doesn't poison the others or the main
///     `settings.json`.
///   • Per-mapping Reveal-in-Finder and drag-drop import work for free.
///   • The on-disk file is the same shape the user can export via
///     "Export Mapping…" — no separate envelope path.
///
/// All files ride the standard `EncryptedJSON.safeWrite` envelope so
/// the contents stay encrypted-at-rest under the user's DEK when
/// keychain-managed mode is on. A locked store falls back to
/// plaintext (`keyResolver` returns nil) — same contract as
/// `SettingsStore`.
@MainActor
final class MappingStore: ObservableObject {

    @Published private(set) var mappings: [SavedImportMapping] = []

    private let directoryURL: URL
    private var keyResolver: () -> SymmetricKey?

    init(directoryURL: URL? = nil, keyResolver: @escaping () -> SymmetricKey? = { nil }) {
        let dir = directoryURL ?? Self.defaultDirectory()
        self.directoryURL = dir
        self.keyResolver = keyResolver
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    static func defaultDirectory() -> URL {
        DatabaseService.supportDirectory.appendingPathComponent("mappings", isDirectory: true)
    }

    /// Re-point the key resolver after construction. Used the same
    /// way `SettingsStore.setKeyResolver` is — AppState wires this
    /// after KeyStore is built.
    func setKeyResolver(_ resolver: @escaping () -> SymmetricKey?) {
        self.keyResolver = resolver
        reload()
    }

    // MARK: - CRUD

    func reload() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            mappings = []
            return
        }
        var loaded: [SavedImportMapping] = []
        for url in urls where url.pathExtension == "json" {
            do {
                let raw = try Data(contentsOf: url)
                let plain = try EncryptedJSON.unwrap(raw, key: keyResolver())
                if let mapping = try? decode(plain) {
                    loaded.append(mapping)
                }
            } catch {
                // Locked file with no key, or corrupt envelope, or
                // unknown format — log and skip. One bad file does
                // not block the others (the whole point of per-file
                // storage). The user can recover the file via the
                // Reveal-in-Finder action and re-import it.
                NSLog("PurpleLife: MappingStore.reload skipped \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        // Newest first by updatedAt — predictable for users.
        mappings = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Insert or replace a mapping (matched by id). Stamps
    /// `updatedAt = now` so the in-memory list re-sorts to newest-first.
    @discardableResult
    func save(_ mapping: SavedImportMapping) throws -> SavedImportMapping {
        var stamped = mapping
        stamped.updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = try encode(stamped)
        let url = fileURL(for: stamped.id)
        _ = try EncryptedJSON.safeWrite(data, to: url, key: keyResolver())
        if let idx = mappings.firstIndex(where: { $0.id == stamped.id }) {
            mappings[idx] = stamped
        } else {
            mappings.append(stamped)
        }
        mappings.sort { $0.updatedAt > $1.updatedAt }
        return stamped
    }

    /// Delete the file + drop the in-memory entry. Idempotent.
    func delete(id: String) {
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
        mappings.removeAll { $0.id == id }
    }

    /// Duplicate: fresh id + " (copy)" suffix on the name. Returns
    /// the new mapping so the wizard can immediately open it for
    /// editing.
    @discardableResult
    func duplicate(id: String) throws -> SavedImportMapping? {
        guard let original = mappings.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID().uuidString
        copy.name = "\(original.name) (copy)"
        return try save(copy)
    }

    /// File URL for the per-mapping on-disk path. Public so the
    /// settings UI can wire "Reveal in Finder" + "Export Mapping…".
    func fileURL(for mappingId: String) -> URL {
        directoryURL.appendingPathComponent("\(mappingId).purplelifemapping.json")
    }

    /// Decode a file's bytes (envelope-first, bare-payload fallback)
    /// into a mapping. Used by the file-import flow that lets a user
    /// pick a `.purplelifemapping.json` they got from a teammate.
    static func decodeFile(at url: URL, key: SymmetricKey?) throws -> SavedImportMapping {
        let raw = try Data(contentsOf: url)
        let plain = try EncryptedJSON.unwrap(raw, key: key)
        return try decodeStatic(plain)
    }

    // MARK: - Codec

    /// Envelope-first decode. Tries `SavedImportMappingEnvelope`
    /// shape, then a bare `SavedImportMapping` (forward-compat with a
    /// future v2 envelope that drops the wrapper, or older drafts
    /// written before the envelope existed).
    private func decode(_ data: Data) throws -> SavedImportMapping {
        try Self.decodeStatic(data)
    }

    private static func decodeStatic(_ data: Data) throws -> SavedImportMapping {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SavedImportMappingEnvelope.self, from: data) {
            return envelope.mapping
        }
        return try decoder.decode(SavedImportMapping.self, from: data)
    }

    private func encode(_ mapping: SavedImportMapping) throws -> Data {
        let envelope = SavedImportMappingEnvelope(mapping)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}
