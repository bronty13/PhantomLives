import Foundation
import CryptoKit

/// Per-file persistence for `SavedExportConfig`. Mirror of
/// `MappingStore` for the import side — same design rationale (one
/// malformed file can't poison the others; per-file storage makes
/// Reveal-in-Finder + drag-drop sharing free).
@MainActor
final class ExportConfigStore: ObservableObject {

    @Published private(set) var configs: [SavedExportConfig] = []

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
        DatabaseService.supportDirectory.appendingPathComponent("export-configs", isDirectory: true)
    }

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
            configs = []
            return
        }
        var loaded: [SavedExportConfig] = []
        for url in urls where url.pathExtension == "json" {
            do {
                let raw = try Data(contentsOf: url)
                let plain = try EncryptedJSON.unwrap(raw, key: keyResolver())
                if let c = try? decode(plain) {
                    loaded.append(c)
                }
            } catch {
                NSLog("PurpleLife: ExportConfigStore.reload skipped \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        configs = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(_ config: SavedExportConfig) throws -> SavedExportConfig {
        var stamped = config
        stamped.updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = try encode(stamped)
        let url = fileURL(for: stamped.id)
        _ = try EncryptedJSON.safeWrite(data, to: url, key: keyResolver())
        if let idx = configs.firstIndex(where: { $0.id == stamped.id }) {
            configs[idx] = stamped
        } else {
            configs.append(stamped)
        }
        configs.sort { $0.updatedAt > $1.updatedAt }
        return stamped
    }

    func delete(id: String) {
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
        configs.removeAll { $0.id == id }
    }

    @discardableResult
    func duplicate(id: String) throws -> SavedExportConfig? {
        guard let original = configs.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID().uuidString
        copy.name = "\(original.name) (copy)"
        return try save(copy)
    }

    func fileURL(for configId: String) -> URL {
        directoryURL.appendingPathComponent("\(configId).purpleexport.json")
    }

    static func decodeFile(at url: URL, key: SymmetricKey?) throws -> SavedExportConfig {
        let raw = try Data(contentsOf: url)
        let plain = try EncryptedJSON.unwrap(raw, key: key)
        return try decodeStatic(plain)
    }

    // MARK: - Codec

    private func decode(_ data: Data) throws -> SavedExportConfig {
        try Self.decodeStatic(data)
    }

    private static func decodeStatic(_ data: Data) throws -> SavedExportConfig {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(SavedExportConfigEnvelope.self, from: data) {
            return env.config
        }
        return try decoder.decode(SavedExportConfig.self, from: data)
    }

    private func encode(_ config: SavedExportConfig) throws -> Data {
        let envelope = SavedExportConfigEnvelope(config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}
