import Foundation
import GRDB

@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("MasterClipper", isDirectory: true)
    }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("masterclipper.sqlite")
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("masterclipper.sqlite")
        dbPool = try! DatabasePool(path: dbURL.path)
        try! migrate()
        try? seedDefaults()
    }

    // MARK: - Migrations

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "personas") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("code", .text).notNull().collate(.nocase)
                t.column("display_name", .text).notNull()
                t.column("color_hex", .text).notNull().defaults(to: "#888888")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("archived", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["code"])
            }

            try db.create(table: "sites") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("code", .text).notNull().collate(.nocase)
                t.column("display_name", .text).notNull()
                t.column("persona_scope", .text).notNull().defaults(to: "")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("archived", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["code"])
            }

            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().collate(.nocase)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("archived", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["name"])
            }

            try db.create(table: "clips") { t in
                t.column("id", .text).primaryKey()
                t.column("external_clip_id", .text)
                t.column("tracking_tag", .text)
                t.column("persona_code", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("description_raw", .text).notNull().defaults(to: "")
                t.column("description_refined", .text).notNull().defaults(to: "")
                t.column("keywords", .text).notNull().defaults(to: "")
                t.column("performers", .text).notNull().defaults(to: "")
                t.column("clip_filename", .text)
                t.column("thumbnail_filename", .text)
                t.column("preview_filename", .text)
                t.column("length_seconds", .integer)
                t.column("price_cents", .integer)
                t.column("sales_count", .integer).notNull().defaults(to: 0)
                t.column("income_cents", .integer).notNull().defaults(to: 0)
                t.column("content_date", .text)
                t.column("go_live_date", .text)
                t.column("status", .text).notNull().defaults(to: "production")
                t.column("archived", .integer).notNull().defaults(to: 0)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_clips_persona",  on: "clips", columns: ["persona_code"])
            try db.create(index: "idx_clips_status",   on: "clips", columns: ["status"])
            try db.create(index: "idx_clips_external", on: "clips", columns: ["external_clip_id"])
            try db.create(index: "idx_clips_golive",   on: "clips", columns: ["go_live_date"])

            try db.create(table: "clip_categories") { t in
                t.column("clip_id", .text).notNull().references("clips", onDelete: .cascade)
                t.column("category_id", .integer).notNull().references("categories", onDelete: .cascade)
                t.primaryKey(["clip_id", "category_id"])
            }

            try db.create(table: "clip_postings") { t in
                t.column("clip_id", .text).notNull().references("clips", onDelete: .cascade)
                t.column("site_id", .integer).notNull().references("sites", onDelete: .cascade)
                t.column("posted_date", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.primaryKey(["clip_id", "site_id"])
            }
            try db.create(index: "idx_postings_site_status", on: "clip_postings",
                          columns: ["site_id", "status"])

            try db.create(table: "id_sequences") { t in
                t.column("date_key", .text).primaryKey()
                t.column("last_seq", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "calendar_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull()
                t.column("persona_code", .text).notNull()
                t.column("clip_id", .text).references("clips", onDelete: .setNull)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_cal_unique", on: "calendar_events",
                          columns: ["date", "persona_code"], options: .unique)
            try db.create(index: "idx_cal_date",    on: "calendar_events", columns: ["date"])
            try db.create(index: "idx_cal_persona", on: "calendar_events", columns: ["persona_code"])

            try db.create(table: "calendar_rules") { t in
                t.column("persona_code", .text).notNull()
                t.column("weekday", .integer).notNull()
                t.column("enabled", .integer).notNull().defaults(to: 0)
                t.primaryKey(["persona_code", "weekday"])
            }

            try db.create(table: "prices") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("label", .text).notNull()
                t.column("price_cents", .integer).notNull()
                t.column("notes", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v2_clip_history") { db in
            try db.create(table: "clip_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("clip_id", .text).notNull().references("clips", onDelete: .cascade)
                t.column("field", .text).notNull()
                t.column("old_value", .text)
                t.column("new_value", .text)
                t.column("changed_at", .text).notNull()
            }
            try db.create(index: "idx_history_clip",    on: "clip_history", columns: ["clip_id"])
            try db.create(index: "idx_history_changed", on: "clip_history", columns: ["changed_at"])
        }

        migrator.registerMigration("v3_editing_pipeline") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "fcp_project_folder", .text)
                t.add(column: "production_folder", .text)
            }
            // Remap legacy status strings to the new pipeline. Any rows whose
            // previous status was 'archived' get their `archived` bool set
            // (since archive is now a separate boolean) and the status reset
            // to 'new'. Order matters: the CASE evaluates row-at-a-time so
            // we can safely rename 'production'→'new' and 'delivered'→
            // 'production' in the same statement.
            try db.execute(sql: """
                UPDATE clips
                   SET archived = CASE WHEN status = 'archived' THEN 1 ELSE archived END,
                       status = CASE status
                           WHEN 'production' THEN 'new'
                           WHEN 'postprod'   THEN 'editing'
                           WHEN 'ready'      THEN 'to_post'
                           WHEN 'delivered'  THEN 'production'
                           WHEN 'archived'   THEN 'new'
                           ELSE status
                       END
                """)
        }

        migrator.registerMigration("v4_persona_color_refresh") { db in
            // Only overwrite the *previous* defaults — leave any user-picked
            // colors alone. Idempotent: a fresh install seeds the new defaults
            // directly, so this UPDATE just no-ops on first launch.
            try db.execute(sql: """
                UPDATE personas SET color_hex = '#FFB6C1'
                 WHERE code = 'CoC' AND color_hex = '#7A4FFF'
                """)
            try db.execute(sql: """
                UPDATE personas SET color_hex = '#B22222'
                 WHERE code = 'PoA' AND color_hex = '#E9508C'
                """)
        }

        migrator.registerMigration("v5_clip_categories_order") { db in
            // Per-clip category order matters: posting platforms each surface
            // categories differently but every one of them respects the order
            // in which the creator listed them. Add a `position` column
            // (default 0) and backfill it from rowid so existing data has a
            // deterministic, stable initial ordering.
            try db.alter(table: "clip_categories") { t in
                t.add(column: "position", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: """
                UPDATE clip_categories
                   SET position = (
                       SELECT COUNT(*) FROM clip_categories cc2
                       WHERE cc2.clip_id = clip_categories.clip_id
                         AND cc2.rowid   < clip_categories.rowid
                   )
                """)
            try db.create(index: "idx_clip_categories_pos",
                          on: "clip_categories",
                          columns: ["clip_id", "position"])
        }

        migrator.registerMigration("v6_clip_transcript") { db in
            // Adds the `transcript` column for whisper-generated transcripts.
            // Stored as plain text; Phase 2 file-handling pipeline writes here
            // after running the sibling transcribe.py against the production
            // MP4. Empty string means "not yet transcribed" — same convention
            // as descriptionRaw / descriptionRefined.
            try db.alter(table: "clips") { t in
                t.add(column: "transcript", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v7_clip_hashes") { db in
            // File-integrity hashes + sizes for the canonical MP4 pair. The
            // user can re-run hashing on demand from the editor; an empty
            // string in any column means "not yet hashed". `bytes` columns
            // stay nullable because we may know the hash before the size
            // (or vice-versa).
            try db.alter(table: "clips") { t in
                t.add(column: "mp4_md5",            .text).notNull().defaults(to: "")
                t.add(column: "mp4_sha1",           .text).notNull().defaults(to: "")
                t.add(column: "mp4_sha256",         .text).notNull().defaults(to: "")
                t.add(column: "mp4_size_bytes",     .integer)
                t.add(column: "reduced_md5",        .text).notNull().defaults(to: "")
                t.add(column: "reduced_sha1",       .text).notNull().defaults(to: "")
                t.add(column: "reduced_sha256",     .text).notNull().defaults(to: "")
                t.add(column: "reduced_size_bytes", .integer)
                t.add(column: "hashes_computed_at", .text).notNull().defaults(to: "")
            }
        }

        try migrator.migrate(dbPool)
    }

    // MARK: - Seed defaults

    private func seedDefaults() throws {
        try dbPool.write { db in
            if try Persona.fetchCount(db) == 0 {
                let defaults: [(code: String, name: String, color: String, order: Int)] = [
                    ("CoC", "Curse Of Curves",       "#FFB6C1", 0),  // light pink
                    ("PoA", "Princess Of Addiction", "#B22222", 1),  // sunset dark red
                    ("Shr", "Sheer Addiction",       "#3CB6C1", 2),
                    ("N/A", "Not Applicable",        "#888888", 3),
                ]
                for (code, name, color, order) in defaults {
                    var p = Persona(id: nil, code: code, displayName: name,
                                    colorHex: color, sortOrder: order, archived: false)
                    try p.insert(db)
                }
            }

            if try Site.fetchCount(db) == 0 {
                let defaults: [(code: String, name: String, scope: String, order: Int)] = [
                    ("c4s", "Clips4Sale", "CoC,PoA", 0),
                    ("mv",  "ManyVids",   "CoC",     1),
                    ("nf",  "NiteFlirt",  "CoC,PoA", 2),
                    ("iwc", "IWantClips", "PoA",     3),
                    ("lf",  "LoyalFans",  "PoA",     4),
                ]
                for (code, name, scope, order) in defaults {
                    var s = Site(id: nil, code: code, displayName: name,
                                 personaScope: scope, sortOrder: order, archived: false)
                    try s.insert(db)
                }
            }

            if try CalendarRule.fetchCount(db) == 0 {
                // Calendar.weekday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
                let enabledByPersona: [String: Set<Int>] = [
                    "CoC": [2, 5],   // Mon + Thu
                    "PoA": [4, 6],   // Wed + Fri
                    "Shr": [],
                    "N/A": [],
                ]
                for (persona, days) in enabledByPersona {
                    for weekday in 1...7 {
                        let rule = CalendarRule(personaCode: persona, weekday: weekday,
                                                enabled: days.contains(weekday))
                        try rule.insert(db)
                    }
                }
            }
        }
    }

    // MARK: - Personas

    func fetchPersonas(includeArchived: Bool = false) throws -> [Persona] {
        try dbPool.read { db in
            var q = Persona.order(Column("sort_order").asc, Column("code").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    func savePersona(_ p: inout Persona) throws {
        try dbPool.write { db in try p.save(db) }
    }

    func deletePersona(id: Int64) throws {
        _ = try dbPool.write { db in try Persona.deleteOne(db, key: id) }
    }

    // MARK: - Sites

    func fetchSites(includeArchived: Bool = false) throws -> [Site] {
        try dbPool.read { db in
            var q = Site.order(Column("sort_order").asc, Column("code").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    func saveSite(_ s: inout Site) throws {
        try dbPool.write { db in try s.save(db) }
    }

    func deleteSite(id: Int64) throws {
        _ = try dbPool.write { db in try Site.deleteOne(db, key: id) }
    }

    // MARK: - Categories

    func fetchCategories(includeArchived: Bool = false) throws -> [Category] {
        try dbPool.read { db in
            var q = Category.order(Column("sort_order").asc, Column("name").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    func saveCategory(_ c: inout Category) throws {
        try dbPool.write { db in try c.save(db) }
    }

    func deleteCategory(id: Int64) throws {
        _ = try dbPool.write { db in try Category.deleteOne(db, key: id) }
    }

    func ensureCategory(named name: String) throws -> Category {
        try dbPool.write { db in
            if let existing = try Category.filter(Column("name") == name).fetchOne(db) {
                return existing
            }
            var c = Category(id: nil, name: name, sortOrder: 0, archived: false)
            try c.insert(db)
            return c
        }
    }

    // MARK: - Clips

    func fetchAllClips(includeArchived: Bool = false) throws -> [Clip] {
        try dbPool.read { db in
            var q = Clip.order(Column("created_at").desc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    func fetchClip(id: String) throws -> Clip? {
        try dbPool.read { db in try Clip.fetchOne(db, key: id) }
    }

    func insertClip(_ clip: Clip) throws {
        try dbPool.write { db in
            var mutated = clip
            mutated.status = try Self.computeStatus(for: mutated, in: db)
            try mutated.insert(db)
        }
    }

    func updateClip(_ newClip: Clip) throws {
        try dbPool.write { db in
            let now = Self.isoNow()
            var mutated = newClip
            if let old = try Clip.fetchOne(db, key: newClip.id) {
                // Title rename: keep the legacy notes-marker behaviour.
                if old.title != newClip.title,
                   !old.title.trimmingCharacters(in: .whitespaces).isEmpty {
                    let marker = "[Renamed \(Self.isoDate(Date())): \"\(old.title)\" → \"\(newClip.title)\"]"
                    mutated.notes = mutated.notes.isEmpty ? marker : mutated.notes + "\n" + marker
                }
            }
            // Recompute the pipeline status from the latest data + postings.
            mutated.status = try Self.computeStatus(for: mutated, in: db)
            mutated.updatedAt = now
            // Record per-field history *after* status has been recomputed so the
            // history captures the auto-transition too.
            if let old = try Clip.fetchOne(db, key: newClip.id) {
                try Self.recordClipHistoryDiff(old: old, new: mutated, in: db, at: now)
            }
            try mutated.update(db)
        }
    }

    /// Auto-derive a clip's pipeline status from its editing fields and posting
    /// state. Called from every insert/update path. Does not modify the clip's
    /// `archived` flag (that's a separate column).
    private static func computeStatus(for clip: Clip, in db: Database) throws -> String {
        // Scoped sites for this clip's persona
        let activeSites = try Site.filter(Column("archived") == false).fetchAll(db)
        let scoped = activeSites.filter { $0.appliesTo(personaCode: clip.personaCode) }
        let scopedIds = Set(scoped.compactMap(\.id))

        // Postings already marked posted to scoped sites
        let postedIds: Set<Int64> = try {
            let rows = try Int64.fetchAll(db,
                sql: "SELECT site_id FROM clip_postings WHERE clip_id = ? AND status = 'posted'",
                arguments: [clip.id])
            return Set(rows)
        }()
        let postedScoped = scopedIds.intersection(postedIds)

        // Editing fields completeness
        let fcpFilled  = !(clip.fcpProjectFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let prodFilled = !(clip.productionFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let durFilled  = clip.lengthSeconds != nil
        let editingFilled = [fcpFilled, prodFilled, durFilled].filter { $0 }.count
        let editingComplete = editingFilled == 3

        if !scopedIds.isEmpty && postedScoped.count == scopedIds.count {
            return ClipStatus.production.rawValue
        }
        if !postedScoped.isEmpty {
            return ClipStatus.posting.rawValue
        }
        if editingComplete {
            return ClipStatus.toPost.rawValue
        }
        if editingFilled > 0 {
            return ClipStatus.editing.rawValue
        }
        return ClipStatus.new.rawValue
    }

    /// Diff every field on the clip and append a `clip_history` row for each change.
    /// Skips `updated_at` (always changes by definition) and the synthetic `notes`
    /// rename marker that we already inserted above.
    private static func recordClipHistoryDiff(old: Clip, new: Clip, in db: Database, at now: String) throws {
        @inline(__always)
        func record(_ field: String, _ a: String?, _ b: String?) throws {
            if (a ?? "") == (b ?? "") { return }
            try db.execute(sql: """
                INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [new.id, field, a, b, now])
        }
        try record("external_clip_id",    old.externalClipId,     new.externalClipId)
        try record("tracking_tag",        old.trackingTag,        new.trackingTag)
        try record("persona_code",        old.personaCode,        new.personaCode)
        try record("title",               old.title,              new.title)
        try record("description_raw",     old.descriptionRaw,     new.descriptionRaw)
        try record("description_refined", old.descriptionRefined, new.descriptionRefined)
        try record("keywords",            old.keywords,           new.keywords)
        try record("performers",          old.performers,         new.performers)
        try record("clip_filename",       old.clipFilename,       new.clipFilename)
        try record("thumbnail_filename",  old.thumbnailFilename,  new.thumbnailFilename)
        try record("preview_filename",    old.previewFilename,    new.previewFilename)
        try record("length_seconds",      old.lengthSeconds.map(String.init),  new.lengthSeconds.map(String.init))
        try record("price_cents",         old.priceCents.map(String.init),     new.priceCents.map(String.init))
        try record("sales_count",         "\(old.salesCount)",    "\(new.salesCount)")
        try record("income_cents",        "\(old.incomeCents)",   "\(new.incomeCents)")
        try record("content_date",        old.contentDate,        new.contentDate)
        try record("go_live_date",        old.goLiveDate,         new.goLiveDate)
        try record("status",              old.status,             new.status)
        try record("archived",            old.archived ? "1" : "0", new.archived ? "1" : "0")
        try record("notes",               old.notes,              new.notes)
    }

    func fetchHistory(forClip id: String) throws -> [ClipHistoryEntry] {
        try dbPool.read { db in
            try ClipHistoryEntry
                .filter(Column("clip_id") == id)
                .order(Column("changed_at").desc, Column("id").desc)
                .fetchAll(db)
        }
    }

    /// Append a history row for an external state change (e.g. a posting toggle,
    /// a category-set update). Use the same `field` keys as ClipHistoryEntry.
    func appendHistory(clipId: String, field: String, oldValue: String?, newValue: String?) throws {
        let now = Self.isoNow()
        try dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [clipId, field, oldValue, newValue, now])
        }
    }

    func deleteClip(id: String) throws {
        _ = try dbPool.write { db in try Clip.deleteOne(db, key: id) }
    }

    func clipCount() throws -> Int {
        try dbPool.read { db in try Clip.fetchCount(db) }
    }

    // MARK: - Clip ↔ category

    /// Returns the clip's category IDs in user-defined order (the `position`
    /// column added in v5). The position-based ordering matters: every
    /// posting site renders the category list in the order we hand it to
    /// them, and the order is meaningful to the creator.
    func categoryIds(forClip clipId: String) throws -> [Int64] {
        try dbPool.read { db in
            try Int64.fetchAll(db,
                sql: """
                    SELECT category_id FROM clip_categories
                     WHERE clip_id = ?
                     ORDER BY position, category_id
                    """,
                arguments: [clipId])
        }
    }

    /// Replace the category set for a clip, preserving the input order. Each
    /// row gets a sequential `position` (0, 1, 2…) so the next read returns
    /// IDs in the same order the caller passed in. Any change — including a
    /// pure reorder — appends a `clip_history` row.
    func setCategories(forClip clipId: String, categoryIds: [Int64]) throws {
        try dbPool.write { db in
            let oldIds = try Int64.fetchAll(db,
                sql: """
                    SELECT category_id FROM clip_categories
                     WHERE clip_id = ?
                     ORDER BY position, category_id
                    """,
                arguments: [clipId])

            try db.execute(sql: "DELETE FROM clip_categories WHERE clip_id = ?", arguments: [clipId])
            for (idx, cid) in categoryIds.enumerated() {
                try db.execute(sql: """
                    INSERT INTO clip_categories (clip_id, category_id, position)
                    VALUES (?, ?, ?)
                    """, arguments: [clipId, cid, idx])
            }

            // Order-aware diff: a reorder is a change.
            if oldIds != categoryIds {
                let oldStr = oldIds.map(String.init).joined(separator: ",")
                let newStr = categoryIds.map(String.init).joined(separator: ",")
                try db.execute(sql: """
                    INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                    VALUES (?, 'categories', ?, ?, ?)
                    """, arguments: [clipId, oldStr, newStr, Self.isoNow()])
            }
        }
    }

    // MARK: - Postings

    func fetchPostings(forClip clipId: String) throws -> [ClipPosting] {
        try dbPool.read { db in
            try ClipPosting.filter(Column("clip_id") == clipId).fetchAll(db)
        }
    }

    /// Mark every active site in the clip's persona scope as posted in one
    /// transaction. Used by the "historical" import path and the per-clip
    /// "Mark as historical" right-click action.
    ///
    /// `postedDate` falls back through go-live date → content date → today
    /// when no override is supplied. Status is recomputed once at the end so
    /// the clip lands directly in `production` (assuming there's at least one
    /// scope site).
    @discardableResult
    func markAllScopedSitesPosted(
        clipId: String,
        postedDate: String? = nil,
        notes: String = "Imported as historical"
    ) throws -> Int {
        try dbPool.write { db in
            guard let originalClip = try Clip.fetchOne(db, key: clipId) else { return 0 }
            let resolvedDate = postedDate
                ?? originalClip.goLiveDate
                ?? originalClip.contentDate
                ?? Self.isoDate(Date())

            let activeSites = try Site.filter(Column("archived") == false).fetchAll(db)
            let scoped = activeSites.filter { $0.appliesTo(personaCode: originalClip.personaCode) }
            let now = Self.isoNow()
            var written = 0

            for site in scoped {
                guard let sid = site.id else { continue }
                let existing = try ClipPosting
                    .filter(Column("clip_id") == clipId && Column("site_id") == sid)
                    .fetchOne(db)
                let row = ClipPosting(
                    clipId: clipId,
                    siteId: sid,
                    postedDate: resolvedDate,
                    status: PostingStatus.posted.rawValue,
                    notes: existing?.notes.isEmpty == false ? existing!.notes : notes,
                    createdAt: existing?.createdAt ?? now,
                    updatedAt: now
                )
                try row.save(db)
                written += 1

                // History entry per site so the change log explains where the
                // bulk action came from.
                let oldVal = existing.map { "\($0.status)@\($0.postedDate ?? "")" } ?? "—"
                let newVal = "\(row.status)@\(row.postedDate ?? "")"
                if oldVal != newVal {
                    try db.execute(sql: """
                        INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                        VALUES (?, ?, ?, ?, ?)
                        """, arguments: [clipId, "posting:\(site.code)", oldVal, newVal, now])
                }
            }

            // One status recompute after all postings inserted.
            if var c = try Clip.fetchOne(db, key: clipId) {
                let newStatus = try Self.computeStatus(for: c, in: db)
                if newStatus != c.status {
                    try db.execute(sql: """
                        INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                        VALUES (?, 'status', ?, ?, ?)
                        """, arguments: [c.id, c.status, newStatus, now])
                    c.status = newStatus
                    c.updatedAt = now
                    try c.update(db)
                }
            }
            return written
        }
    }

    func upsertPosting(_ posting: ClipPosting) throws {
        try dbPool.write { db in
            let old = try ClipPosting
                .filter(Column("clip_id") == posting.clipId && Column("site_id") == posting.siteId)
                .fetchOne(db)
            try posting.save(db)

            // Append history entry when the status or posted_date actually moved.
            let oldVal = old.map { "\($0.status)@\($0.postedDate ?? "")" } ?? "—"
            let newVal = "\(posting.status)@\(posting.postedDate ?? "")"
            if oldVal != newVal {
                let siteCode: String = (try Site.fetchOne(db, key: posting.siteId))?.code ?? "site#\(posting.siteId)"
                let field = "posting:\(siteCode)"
                try db.execute(sql: """
                    INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [posting.clipId, field, oldVal, newVal, Self.isoNow()])
            }

            // Posting state changed → re-derive the clip's pipeline status.
            if var clip = try Clip.fetchOne(db, key: posting.clipId) {
                let newStatus = try Self.computeStatus(for: clip, in: db)
                if newStatus != clip.status {
                    let now = Self.isoNow()
                    try db.execute(sql: """
                        INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                        VALUES (?, 'status', ?, ?, ?)
                        """, arguments: [clip.id, clip.status, newStatus, now])
                    clip.status = newStatus
                    clip.updatedAt = now
                    try clip.update(db)
                }
            }
        }
    }

    // MARK: - Calendar

    func fetchEvents(start: String, end: String) throws -> [CalendarEvent] {
        try dbPool.read { db in
            try CalendarEvent
                .filter(Column("date") >= start && Column("date") <= end)
                .order(Column("date").asc, Column("persona_code").asc)
                .fetchAll(db)
        }
    }

    func saveEvent(_ event: inout CalendarEvent) throws {
        try dbPool.write { db in try event.save(db) }
    }

    func fetchRules() throws -> [CalendarRule] {
        try dbPool.read { db in try CalendarRule.fetchAll(db) }
    }

    func saveRule(_ rule: CalendarRule) throws {
        try dbPool.write { db in try rule.save(db) }
    }

    // MARK: - Reset helpers

    /// Drop and re-open the database pool. Used after a restore replaces the
    /// .sqlite files on disk: ARC releases the old pool when we reassign
    /// (closing the WAL), then we open a fresh handle and re-run migrations
    /// against the now-on-disk database.
    func reopenDatabase() throws {
        let dir = Self.supportDirectory
        let dbURL = dir.appendingPathComponent("masterclipper.sqlite")
        self.dbPool = try DatabasePool(path: dbURL.path)
        try migrate()
        try? seedDefaults()
    }

    /// Wipe every row of clip-related data while preserving configuration:
    /// personas, sites, categories, and calendar_rules stay. Use this before a
    /// fresh re-import. Always run a backup first — this is irreversible.
    func wipeAllClipData() throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM clip_history")
            try db.execute(sql: "DELETE FROM clip_postings")
            try db.execute(sql: "DELETE FROM clip_categories")
            try db.execute(sql: "DELETE FROM calendar_events")
            try db.execute(sql: "DELETE FROM clips")
            try db.execute(sql: "DELETE FROM id_sequences")
            try db.execute(sql: "DELETE FROM prices")
        }
    }

    // MARK: - Helpers

    static func isoNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }

    static func isoDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}
