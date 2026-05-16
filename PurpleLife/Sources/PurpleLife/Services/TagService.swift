import Foundation
import GRDB

/// Owns the cross-cutting tag vocabulary and the per-record tag list.
///
/// The vocabulary lives in `AppSettings.tagVocabulary`; the per-record
/// list lives inside `ObjectRecord.fieldsJSON` under the reserved
/// `TagDef.recordKey` ("_tags") as an array of tag ids. A derived
/// `record_tags` table (migration v4) mirrors the fields-blob source
/// of truth for fast SQL filtering; it is maintained by `ObjectEngine`
/// on every create / update / delete — same pattern as the FTS index.
///
/// Per-record attach/detach goes through `ObjectEngine.update`, which
/// already registers undo, fans out to FTS + sync, and bumps
/// `updated_at`. Vocabulary-level mutations (rename, merge, delete)
/// fan their per-record rewrites through the same `update` path so the
/// same guarantees hold.
@MainActor
enum TagService {

    /// Injected by `AppState` at launch so the service can read & write
    /// the vocabulary without a direct dependency on the SettingsStore
    /// at the type level. Tests construct a SettingsStore and wire
    /// this directly.
    static var settings: SettingsStore?

    // MARK: - Vocabulary

    /// All tags, sorted by name (case-insensitive).
    static var allTags: [TagDef] {
        (settings?.settings.tagVocabulary ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Look up by id.
    static func tag(id: String) -> TagDef? {
        settings?.settings.tagVocabulary.first { $0.id == id }
    }

    /// Look up by name (case-insensitive, whitespace-trimmed).
    static func tag(name: String) -> TagDef? {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        return settings?.settings.tagVocabulary.first {
            $0.name.lowercased() == lower
        }
    }

    /// Create a tag if one with the same name (case-insensitive)
    /// doesn't already exist; otherwise return the existing one.
    /// Empty / whitespace-only names are rejected (returns nil).
    @discardableResult
    static func add(name: String, colorHex: String? = nil) -> TagDef? {
        guard let settings else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = tag(name: trimmed) { return existing }
        let new = TagDef.make(name: trimmed, colorHex: colorHex)
        settings.settings.tagVocabulary.append(new)
        settings.save()
        return new
    }

    /// Rename in place. Silent no-op when the id doesn't exist, the
    /// new name is empty, or a *different* tag already carries the
    /// new name (the caller should detect the collision and offer
    /// `merge(sourceId:into:)` instead).
    static func rename(id: String, to newName: String) {
        guard let settings else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let collide = tag(name: trimmed), collide.id != id { return }
        guard let idx = settings.settings.tagVocabulary.firstIndex(where: { $0.id == id }) else { return }
        settings.settings.tagVocabulary[idx].name = trimmed
        settings.settings.tagVocabulary[idx].updatedAt = isoNow()
        settings.save()
    }

    /// Recolor. Pass nil to clear the color back to the neutral fallback.
    static func recolor(id: String, colorHex: String?) {
        guard let settings else { return }
        guard let idx = settings.settings.tagVocabulary.firstIndex(where: { $0.id == id }) else { return }
        settings.settings.tagVocabulary[idx].colorHex = colorHex
        settings.settings.tagVocabulary[idx].updatedAt = isoNow()
        settings.save()
    }

    /// Merge `source` into `destination`. Every record carrying
    /// `source` ends up carrying `destination` (deduped) instead;
    /// `source` is removed from the vocabulary. Per-record rewrites
    /// fan through `ObjectEngine.update`, so FTS + sync + undo +
    /// `record_tags` index all stay consistent.
    static func merge(sourceId: String, into destinationId: String) {
        guard sourceId != destinationId else { return }
        guard let settings else { return }
        guard settings.settings.tagVocabulary.contains(where: { $0.id == sourceId }),
              settings.settings.tagVocabulary.contains(where: { $0.id == destinationId }) else { return }

        rewriteTagsOnEveryRecord { ids in
            guard ids.contains(sourceId) else { return nil }
            var next = ids.filter { $0 != sourceId }
            if !next.contains(destinationId) { next.append(destinationId) }
            return next
        }

        settings.settings.tagVocabulary.removeAll { $0.id == sourceId }
        settings.save()
    }

    /// Remove a tag from the vocabulary; strip it from every record
    /// that referenced it. The records themselves remain.
    static func delete(id: String) {
        guard let settings else { return }
        rewriteTagsOnEveryRecord { ids in
            ids.contains(id) ? ids.filter { $0 != id } : nil
        }
        settings.settings.tagVocabulary.removeAll { $0.id == id }
        settings.save()
    }

    // MARK: - Per-record

    /// Raw tag ids attached to a record (from its `_tags` field).
    static func tagIds(on record: ObjectRecord) -> [String] {
        record.fields()[TagDef.recordKey] as? [String] ?? []
    }

    /// Tags attached to a record, resolved against the vocabulary.
    /// Orphaned ids (e.g. a tag deleted on this Mac but still
    /// referenced by a record that hasn't yet been rewritten) are
    /// silently dropped.
    static func tags(on record: ObjectRecord) -> [TagDef] {
        let ids = Set(tagIds(on: record))
        return allTags.filter { ids.contains($0.id) }
    }

    /// Replace the tag list on a record. Routes through
    /// `ObjectEngine.update` so FTS, sync, undo, and the
    /// `record_tags` index all stay consistent. Duplicates in the
    /// input are removed while preserving order.
    @discardableResult
    static func setTags(_ ids: [String], on record: ObjectRecord) throws -> ObjectRecord {
        var seen: Set<String> = []
        let unique = ids.filter { seen.insert($0).inserted }
        return try ObjectEngine.update(record, fields: [TagDef.recordKey: unique])
    }

    // MARK: - `record_tags` index maintenance

    /// Replace the index rows for a single record. Called from
    /// `ObjectEngine.create` / `update` / `restore` after the JSON
    /// write succeeds.
    static func indexUpsert(record: ObjectRecord) {
        let tagIds = (record.fields()[TagDef.recordKey] as? [String]) ?? []
        do {
            try DatabaseService.shared.dbPool.write { db in
                try db.execute(
                    sql: "DELETE FROM record_tags WHERE record_id = ?",
                    arguments: [record.id]
                )
                for tagId in tagIds {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO record_tags (record_id, tag_id) VALUES (?, ?)",
                        arguments: [record.id, tagId]
                    )
                }
            }
        } catch {
            NSLog("PurpleLife: TagService.indexUpsert failed — \(error.localizedDescription)")
        }
    }

    /// Remove all index rows for a record. The migration's
    /// `ON DELETE CASCADE` from `objects` covers production deletes
    /// automatically; this method exists for symmetry with
    /// `SearchService.delete` so the engine has an explicit hook to
    /// call, and for `reindexAll` semantics.
    static func indexDelete(recordId: String) {
        do {
            try DatabaseService.shared.dbPool.write { db in
                try db.execute(
                    sql: "DELETE FROM record_tags WHERE record_id = ?",
                    arguments: [recordId]
                )
            }
        } catch {
            NSLog("PurpleLife: TagService.indexDelete failed — \(error.localizedDescription)")
        }
    }

    /// Wipe and rebuild the `record_tags` table from every record's
    /// `_tags` field. Called from `AppState` at launch alongside
    /// `SearchService.reindexAll(schema:)`. Cheap for personal-scale
    /// row counts.
    static func reindexAll() {
        do {
            let db = DatabaseService.shared
            let all = try db.fetchAllObjects()
            try db.dbPool.write { dbq in
                try dbq.execute(sql: "DELETE FROM record_tags")
                for obj in all {
                    let tagIds = (obj.fields()[TagDef.recordKey] as? [String]) ?? []
                    for tagId in tagIds {
                        try dbq.execute(
                            sql: "INSERT OR IGNORE INTO record_tags (record_id, tag_id) VALUES (?, ?)",
                            arguments: [obj.id, tagId]
                        )
                    }
                }
            }
        } catch {
            NSLog("PurpleLife: TagService.reindexAll failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Internal helpers

    /// Delegated to `TagDef.isoNow()` so every timestamp in the
    /// vocabulary — `make()`'s initial stamp and every later
    /// mutation — uses the same fractional-second format.
    private static func isoNow() -> String {
        TagDef.isoNow()
    }

    /// Walk every record; for each, call `transform(currentTagIds)`.
    /// If the transform returns non-nil, fan the new array back
    /// through `ObjectEngine.update` so FTS + sync + undo + the
    /// `record_tags` index all stay coherent. Used by `merge` and
    /// `delete` to apply a vocabulary-level edit across records.
    private static func rewriteTagsOnEveryRecord(_ transform: ([String]) -> [String]?) {
        guard let all = try? ObjectEngine.fetchAll() else { return }
        for record in all {
            let current = (record.fields()[TagDef.recordKey] as? [String]) ?? []
            guard let next = transform(current) else { continue }
            _ = try? ObjectEngine.update(record, fields: [TagDef.recordKey: next])
        }
    }
}
