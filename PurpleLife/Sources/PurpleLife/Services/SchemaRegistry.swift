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

    /// Set by `AppState` at launch — fans schema mutations out to
    /// CloudKit (`pushType` / `pushDeleteType`). Optional so tests
    /// that operate on a SchemaRegistry without sync still work; the
    /// schema-sync hook is fire-and-forget Task and never blocks
    /// local writes.
    weak var sync: CloudKitSyncService?

    /// Set by Schema Editor / sidebar views as they appear, threaded
    /// from SwiftUI's `@Environment(\.undoManager)`. Each mutation
    /// registers a snapshot-based inverse so ⌘Z restores the prior
    /// schema state.
    var undoManager: UndoManager?

    /// Sentinel target for NSUndoManager's `withTarget:` parameter.
    /// `self` would work too, but pinning to a private object lets a
    /// future `removeAllActions(withTarget:)` scope cleanup without
    /// touching unrelated managers.
    private let undoTarget = NSObject()

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

        // Backfill the per-type updatedAt for any pre-schema-sync
        // type that's missing it. The epoch default sorts "older
        // than anything," so the first remote update via CloudKit
        // wins LWW and the local copy gets overwritten — exactly
        // the right thing when an unsynced peer starts following a
        // synced one.
        for i in diskTypes.indices where diskTypes[i].updatedAt == nil {
            diskTypes[i].updatedAt = ObjectType.epochTimestamp
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
    /// Stamps `updatedAt = now` so peers' LWW reconciliation picks up
    /// the change.
    func upsertType(_ type: ObjectType) {
        let snapshot = self.snapshot()
        var stamped = type
        stamped.updatedAt = isoNow()
        if let idx = types.firstIndex(where: { $0.id == stamped.id }) {
            types[idx] = stamped
        } else {
            types.append(stamped)
        }
        save()
        if let sync {
            Task { await sync.pushType(stamped) }
        }
        registerUndo(name: "Edit schema") { [weak self] in
            self?.restore(snapshot: snapshot, fanOut: true)
        }
    }

    /// Delete a user-defined type. Built-ins can't be deleted — call
    /// `setHidden(_:hidden:)` to hide them from the sidebar instead.
    /// Returns `true` if the type was removed.
    @discardableResult
    func deleteType(id: String) -> Bool {
        guard let idx = types.firstIndex(where: { $0.id == id }),
              !types[idx].builtIn else { return false }
        let snapshot = self.snapshot()
        types.remove(at: idx)
        save()
        if let sync {
            Task { await sync.pushDeleteType(id: id) }
        }
        registerUndo(name: "Delete type") { [weak self] in
            self?.restore(snapshot: snapshot, fanOut: true)
        }
        return true
    }

    func setHidden(_ id: String, hidden: Bool) {
        guard let t = type(id: id), t.builtIn else { return }
        let snapshot = self.snapshot()
        if hidden {
            hiddenBuiltInIds.insert(id)
        } else {
            hiddenBuiltInIds.remove(id)
        }
        save()
        registerUndo(name: hidden ? "Hide type" : "Show type") { [weak self] in
            // hiddenBuiltInIds is per-device, never synced — undo
            // doesn't need to fan out to CloudKit.
            self?.restore(snapshot: snapshot, fanOut: false)
        }
    }

    // MARK: - Undo helpers

    /// Coarse snapshot — capture the full types array + hidden set
    /// before each mutation. The schema is small (handful of types
    /// each ~KB serialized) so duplicating it for every undoable
    /// action is cheap, and snapshot-restore is bulletproof against
    /// per-mutation invariants we'd otherwise need to think about
    /// (renames vs adds vs option edits, etc.).
    private struct Snapshot {
        let types: [ObjectType]
        let hiddenBuiltInIds: Set<String>
    }

    private func snapshot() -> Snapshot {
        Snapshot(types: types, hiddenBuiltInIds: hiddenBuiltInIds)
    }

    private func restore(snapshot: Snapshot, fanOut: Bool) {
        // Snapshot the *current* state for the redo path before
        // we replace it.
        let inverse = self.snapshot()
        types = snapshot.types
        hiddenBuiltInIds = snapshot.hiddenBuiltInIds
        save()

        if fanOut, let sync {
            // Push the restored types so peers reconcile via LWW.
            // Each restored type carries its prior `updatedAt`; if
            // the user is re-introducing an older state, the LWW on
            // peers might keep the newer remote — that's the right
            // behavior, undo is local intent. We bump the timestamp
            // so the user's undo wins on this device's next push.
            for var type in snapshot.types {
                type.updatedAt = isoNow()
                if let idx = types.firstIndex(where: { $0.id == type.id }) {
                    types[idx] = type
                }
                Task { [type, weak sync] in await sync?.pushType(type) }
            }
            // Types removed by the snapshot restore (i.e. present in
            // `inverse` but not in `snapshot`) should be deleted
            // remotely too.
            let restoredIds = Set(snapshot.types.map(\.id))
            for removed in inverse.types where !restoredIds.contains(removed.id) {
                let id = removed.id
                Task { [weak sync] in await sync?.pushDeleteType(id: id) }
            }
            save()
        }

        registerUndo(name: "Restore schema") { [weak self] in
            self?.restore(snapshot: inverse, fanOut: fanOut)
        }
    }

    /// Synchronous main-actor dispatch — see the same comment on
    /// `ObjectEngine.registerUndo`. NSUndoManager calls the handler
    /// on the calling thread; for the env-injected manager that's
    /// always main, and a `Task` hop would defer past the caller's
    /// next statement.
    private func registerUndo(name: String, _ handler: @escaping @MainActor () -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoTarget) { _ in
            MainActor.assumeIsolated { handler() }
        }
        undoManager.setActionName(name)
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
    /// history if the user intended a rename. Same intent as the
    /// schema-versioning safety net in `ObjectEngine.update` — peers
    /// running different schema versions don't drop each other's data.
    func removeField(fieldId: String, fromTypeId typeId: String) {
        guard var t = type(id: typeId),
              let idx = t.fields.firstIndex(where: { $0.id == fieldId }) else { return }
        t.fields.remove(at: idx)
        upsertType(t)
    }

    /// Reorder a single field by relative offset (`delta = -1` moves
    /// up, `+1` moves down). No-ops at the array bounds. Used by the
    /// Schema Editor's row context menu; goes through `upsertType` so
    /// it gets the same undo + sync treatment as any other schema
    /// mutation.
    func moveField(fieldId: String, onTypeId typeId: String, by delta: Int) {
        guard var t = type(id: typeId),
              let idx = t.fields.firstIndex(where: { $0.id == fieldId }) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0, newIdx < t.fields.count, newIdx != idx else { return }
        let field = t.fields.remove(at: idx)
        t.fields.insert(field, at: newIdx)
        upsertType(t)
    }

    // MARK: - CloudKit-applied changes

    /// Apply a remote type definition. LWW: only overrides the local
    /// copy if the remote `updatedAt` is greater. Called by
    /// `CloudKitSyncService.applyRemoteType` during pull. The hidden
    /// flag is per-device (`hiddenBuiltInIds`) — not touched by sync.
    /// No `sync.pushType` echo since the change came FROM the remote.
    func applyRemote(_ type: ObjectType) {
        let local = self.type(id: type.id)
        let localStamp = local?.updatedAt ?? ObjectType.epochTimestamp
        let remoteStamp = type.updatedAt ?? ObjectType.epochTimestamp
        if let _ = local, localStamp >= remoteStamp {
            return
        }
        if let idx = types.firstIndex(where: { $0.id == type.id }) {
            types[idx] = type
        } else {
            types.append(type)
        }
        save()
    }

    /// Apply a remote deletion. Built-ins can't be deleted — defensive
    /// against a remote that might somehow attempt it (shouldn't
    /// happen since `deleteType` rejects built-ins locally too).
    func applyRemoteDelete(typeId: String) {
        guard let idx = types.firstIndex(where: { $0.id == typeId }),
              !types[idx].builtIn else { return }
        types.remove(at: idx)
        save()
    }

    // MARK: - Helpers

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
