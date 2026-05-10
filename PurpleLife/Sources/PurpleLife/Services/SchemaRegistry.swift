import Foundation

/// Authoritative store for `ObjectType` definitions. Persisted to
/// `~/Library/Application Support/PurpleLife/schema.json`. Seeds the
/// built-in types on first launch; subsequent launches read whatever's
/// on disk (and merge in any newly added built-ins). User mutations
/// (rename a type, add a field, hide a built-in) are saved atomically
/// after each change.
@MainActor
final class SchemaRegistry: ObservableObject {

    @Published private(set) var types: [ObjectType] = []

    /// Set of built-in type ids the user has hidden from the sidebar.
    /// Hidden types still exist (records still readable) — they're just
    /// not shown in nav. User-defined types deleted by the user are
    /// removed entirely (no soft-delete equivalent).
    @Published private(set) var hiddenBuiltInIds: Set<String> = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let supportDir = DatabaseService.supportDirectory
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? supportDir.appendingPathComponent("schema.json")
        load()
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var types: [ObjectType]
        var hiddenBuiltInIds: [String]
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            // First launch — seed and persist.
            types = SchemaSeed.allTypes
            hiddenBuiltInIds = []
            save()
            return
        }

        var diskTypes = decoded.types
        // Merge in any newly-added built-ins that weren't on disk yet.
        // Existing built-ins on disk win (they may carry user edits).
        let onDiskIds = Set(diskTypes.map(\.id))
        for seed in SchemaSeed.allTypes where !onDiskIds.contains(seed.id) {
            diskTypes.append(seed)
        }

        types = diskTypes
        hiddenBuiltInIds = Set(decoded.hiddenBuiltInIds)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = Persisted(types: types, hiddenBuiltInIds: Array(hiddenBuiltInIds).sorted())
        guard let data = try? encoder.encode(payload) else {
            NSLog("PurpleLife: schema.save encode failed")
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Lookup

    func type(id: String) -> ObjectType? {
        types.first { $0.id == id }
    }

    /// Visible types in their stored order, minus user-hidden built-ins.
    var visibleTypes: [ObjectType] {
        types.filter { !($0.builtIn && hiddenBuiltInIds.contains($0.id)) }
    }

    // MARK: - Mutation

    /// Add or replace a type (matched by `id`). Use for user-created or
    /// edited types; for hiding a built-in use `setHidden(_:hidden:)`.
    func upsertType(_ type: ObjectType) {
        if let idx = types.firstIndex(where: { $0.id == type.id }) {
            types[idx] = type
        } else {
            types.append(type)
        }
        save()
    }

    /// Delete a user-defined type. Built-ins can't be deleted — call
    /// `setHidden(_:hidden:)` to hide them from the sidebar instead.
    /// Returns `true` if the type was removed.
    @discardableResult
    func deleteType(id: String) -> Bool {
        guard let idx = types.firstIndex(where: { $0.id == id }),
              !types[idx].builtIn else { return false }
        types.remove(at: idx)
        save()
        return true
    }

    func setHidden(_ id: String, hidden: Bool) {
        guard let t = type(id: id), t.builtIn else { return }
        if hidden {
            hiddenBuiltInIds.insert(id)
        } else {
            hiddenBuiltInIds.remove(id)
        }
        save()
    }

    // MARK: - Field mutation

    func addField(_ field: FieldDef, toTypeId typeId: String) {
        guard var t = type(id: typeId) else { return }
        t.fields.append(field)
        upsertType(t)
    }

    func updateField(_ field: FieldDef, onTypeId typeId: String) {
        guard var t = type(id: typeId),
              let idx = t.fields.firstIndex(where: { $0.id == field.id }) else { return }
        t.fields[idx] = field
        upsertType(t)
    }

    /// Removes a field by id. The field's data inside any existing
    /// `ObjectRecord.fieldsJSON` blobs is left in place — old keys are
    /// just unreferenced. A future "compact" pass could prune them, but
    /// keeping them means a re-add of the same field name doesn't lose
    /// history if the user intended a rename.
    func removeField(fieldId: String, fromTypeId typeId: String) {
        guard var t = type(id: typeId),
              let idx = t.fields.firstIndex(where: { $0.id == fieldId }) else { return }
        t.fields.remove(at: idx)
        upsertType(t)
    }
}
