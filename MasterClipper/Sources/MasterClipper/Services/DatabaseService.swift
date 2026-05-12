import Foundation
import GRDB
import MasterClipperCore

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

        migrator.registerMigration("v8_categories_uppercase_and_exclusions") { db in
            // 1. Categories: collapse case-insensitive duplicates onto the
            //    lowest-id row, re-pointing clip_categories links and
            //    deleting the duplicates, then uppercase what's left.
            //    Going forward the UI enforces uppercase on input.
            let rows = try Row.fetchAll(db, sql: "SELECT id, name FROM categories")
            var byUpper: [String: Int64] = [:]      // upperName → keeperId
            var merges: [(dupId: Int64, keeperId: Int64)] = []
            for r in rows {
                let id: Int64 = r["id"]
                let name: String = r["name"]
                let upper = name.uppercased()
                if let keeper = byUpper[upper] {
                    merges.append((dupId: id, keeperId: keeper))
                } else {
                    byUpper[upper] = id
                }
            }
            for (dupId, keeperId) in merges {
                let clipIds = try String.fetchAll(db, sql:
                    "SELECT clip_id FROM clip_categories WHERE category_id = ?",
                    arguments: [dupId])
                for clipId in clipIds {
                    let exists: Int = try Int.fetchOne(db, sql: """
                        SELECT EXISTS(SELECT 1 FROM clip_categories
                                      WHERE clip_id = ? AND category_id = ?)
                        """, arguments: [clipId, keeperId]) ?? 0
                    if exists == 0 {
                        try db.execute(sql: """
                            UPDATE clip_categories SET category_id = ?
                            WHERE clip_id = ? AND category_id = ?
                            """, arguments: [keeperId, clipId, dupId])
                    } else {
                        try db.execute(sql: """
                            DELETE FROM clip_categories
                            WHERE clip_id = ? AND category_id = ?
                            """, arguments: [clipId, dupId])
                    }
                }
                try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [dupId])
            }
            try db.execute(sql: "UPDATE categories SET name = UPPER(name)")

            // 2. Per-clip "exclude from posting" flag — opt-out reason on
            //    why a particular clip won't be posted (sent individually,
            //    custom commission, …). Filtered out of posting queues
            //    and per-site batches.
            try db.alter(table: "clips") { t in
                t.add(column: "posting_excluded", .integer).notNull().defaults(to: 0)
                t.add(column: "exclusion_reason", .text).notNull().defaults(to: "")
                t.add(column: "exclusion_notes",  .text).notNull().defaults(to: "")
            }

            // 3. Configurable dropdown of exclusion reasons — managed in
            //    Settings → Posting. Seeded with the three standard
            //    reasons; user can add / archive their own.
            try db.create(table: "exclusion_reasons") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("label", .text).notNull().unique()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("archived", .integer).notNull().defaults(to: 0)
            }
            let seeds: [(String, Int)] = [
                ("Custom",                          0),
                ("Not Posted - Sent Individually",  1),
                ("Other - Please specify",          2),
            ]
            for (label, idx) in seeds {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO exclusion_reasons (label, sort_order, archived)
                    VALUES (?, ?, 0)
                    """, arguments: [label, idx])
            }
        }

        migrator.registerMigration("v9_recompute_clip_status") { db in
            // Earlier `PostingService.markPosted` wrote directly via
            // `row.save(db)`, bypassing the clip-status recompute that
            // lives inside `upsertPosting`. Any clip with postings
            // created via the batch flow could stay in `to_post` even
            // after the first site was marked posted. Sweep every
            // active clip and snap its `status` to whatever
            // `computeStatus` says now.
            let clips = try Clip.filter(Column("archived") == false).fetchAll(db)
            for var clip in clips {
                let recomputed = try Self.computeStatus(for: clip, in: db)
                if recomputed != clip.status {
                    let now = Self.isoNow()
                    try db.execute(sql: """
                        INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                        VALUES (?, 'status', ?, ?, ?)
                        """, arguments: [clip.id, clip.status, recomputed, now])
                    clip.status = recomputed
                    clip.updatedAt = now
                    try clip.update(db)
                }
            }
        }

        migrator.registerMigration("v10_status_for_excluded_and_no_scope") { db in
            // `computeStatus` now handles two cases that previously
            // stuck clips at `to_post`:
            //   • postingExcluded → production
            //   • no scoped sites + editing complete → production
            // Sweep every active clip and snap its status accordingly.
            let clips = try Clip.filter(Column("archived") == false).fetchAll(db)
            for var clip in clips {
                let recomputed = try Self.computeStatus(for: clip, in: db)
                if recomputed != clip.status {
                    let now = Self.isoNow()
                    try db.execute(sql: """
                        INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                        VALUES (?, 'status', ?, ?, ?)
                        """, arguments: [clip.id, clip.status, recomputed, now])
                    clip.status = recomputed
                    clip.updatedAt = now
                    try clip.update(db)
                }
            }
        }

        migrator.registerMigration("v11_c4s_historical") { db in
            // Single-table store for on-demand Clips4Sale storefront exports.
            // Each import replaces every row for the chosen `store`
            // (CoC | PoA), so the table is always a current snapshot.
            try db.create(table: "c4s_historical") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("store", .text).notNull()
                t.column("clip_status", .text).notNull().defaults(to: "")
                t.column("clip_id", .text).notNull().defaults(to: "")
                t.column("tracking_tag", .text).notNull().defaults(to: "")
                t.column("title", .text).notNull().defaults(to: "")
                t.column("description_text", .text).notNull().defaults(to: "")
                t.column("categories", .text).notNull().defaults(to: "")
                t.column("keywords", .text).notNull().defaults(to: "")
                t.column("clip_filename", .text).notNull().defaults(to: "")
                t.column("thumbnail_filename", .text).notNull().defaults(to: "")
                t.column("preview_filename", .text).notNull().defaults(to: "")
                t.column("performers", .text).notNull().defaults(to: "")
                t.column("price_cents", .integer)
                t.column("sales_count", .integer)
                t.column("income_cents", .integer)
                t.column("imported_at", .text).notNull()
            }
            try db.create(index: "idx_c4s_hist_store",   on: "c4s_historical", columns: ["store"])
            try db.create(index: "idx_c4s_hist_clip_id", on: "c4s_historical", columns: ["clip_id"])
        }

        migrator.registerMigration("v12_clip_segments") { db in
            // One row per source `.mov` for a clip — captured at New-Clip
            // workflow time so the file's identity (filename + ctime + size +
            // MD5/SHA-1/SHA-256) is memorialised before any further editing
            // touches the source on disk.
            try db.create(table: "clip_segments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("clip_id", .text)
                    .notNull()
                    .references("clips", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("filename", .text).notNull().defaults(to: "")
                t.column("creation_date", .text).notNull().defaults(to: "")
                t.column("size_bytes", .integer)
                t.column("md5", .text).notNull().defaults(to: "")
                t.column("sha1", .text).notNull().defaults(to: "")
                t.column("sha256", .text).notNull().defaults(to: "")
                t.column("hashed_at", .text).notNull().defaults(to: "")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.uniqueKey(["clip_id", "position"])
            }
            try db.create(index: "idx_clip_segments_clip", on: "clip_segments", columns: ["clip_id"])
        }

        migrator.registerMigration("v13_status_override") { db in
            // Optional manual override for the auto-derived pipeline status.
            // When NULL, `computeStatus` runs as usual. When set, it returns the
            // override verbatim — used to pin a clip back to a stage even when
            // the editing/posting heuristics would otherwise move it forward.
            try db.alter(table: "clips") { t in
                t.add(column: "status_override", .text)
            }
        }

        migrator.registerMigration("v14_clip_notes") { db in
            // Structured notes table — replaces the single `clips.notes` blob
            // for hand-written entries. Each note is timestamped and stamped
            // with the operator name from settings at write time. The legacy
            // blob stays put: status / posting / editing markers still write
            // there, and the editor renders both timelines.
            try db.create(table: "clip_notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("clip_id",       .text).notNull()
                    .references("clips", onDelete: .cascade)
                t.column("body",          .text).notNull()
                t.column("operator_name", .text).notNull().defaults(to: "")
                t.column("created_at",    .text).notNull()
                t.column("updated_at",    .text).notNull()
            }
            try db.create(index: "idx_clip_notes_clip",
                          on: "clip_notes",
                          columns: ["clip_id", "created_at"])
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

    // MARK: - Clip notes (structured)

    func fetchClipNotes(clipId: String) throws -> [ClipNote] {
        try dbPool.read { db in
            try ClipNote
                .filter(Column("clip_id") == clipId)
                .order(Column("created_at").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    /// Insert a fresh note. `createdAt` and `updatedAt` are stamped with
    /// `isoNow()`. `operatorName` is echoed as the author of record.
    @discardableResult
    func insertClipNote(clipId: String, body: String, operatorName: String) throws -> ClipNote {
        let now = Self.isoNow()
        var n = ClipNote(
            id: nil,
            clipId: clipId,
            body: body,
            operatorName: operatorName,
            createdAt: now,
            updatedAt: now
        )
        try dbPool.write { db in try n.insert(db) }
        return n
    }

    /// Persist edits to an existing note. Bumps `updatedAt`; leaves
    /// `createdAt` and `operatorName` alone — the original author / time
    /// stays intact even if a different operator runs the edit.
    func updateClipNote(_ note: ClipNote) throws {
        var copy = note
        copy.updatedAt = Self.isoNow()
        try dbPool.write { db in try copy.update(db) }
    }

    func deleteClipNote(id: Int64) throws {
        _ = try dbPool.write { db in try ClipNote.deleteOne(db, key: id) }
    }

    /// In-transaction variant for auto-stamping a note alongside another DB
    /// mutation (status change, category swap, save). The caller already
    /// holds a `dbPool.write` so we can't open another. Body is the
    /// rendered diff text; operator is whoever's signed in (or
    /// `"system"` for unattended import / migration paths).
    private static func insertAutoClipNote(
        clipId: String,
        body: String,
        operatorName: String,
        in db: GRDB.Database
    ) throws {
        let now = Self.isoNow()
        var note = ClipNote(
            id: nil,
            clipId: clipId,
            body: body,
            operatorName: operatorName.trimmingCharacters(in: .whitespaces).isEmpty
                ? "system"
                : operatorName,
            createdAt: now,
            updatedAt: now
        )
        try note.insert(db)
    }

    /// Render an old → new diff line. Empty values → `<empty>` so a note like
    /// `Title: <empty> → "Foo"` reads cleanly when a field gets populated for
    /// the first time.
    private static func diffLine(_ field: String, _ old: String, _ new: String) -> String? {
        guard old != new else { return nil }
        let o = old.isEmpty ? "<empty>" : "\"\(old)\""
        let n = new.isEmpty ? "<empty>" : "\"\(new)\""
        return "\(field): \(o) → \(n)"
    }

    // MARK: - Categories

    func fetchCategories(includeArchived: Bool = false) throws -> [ClipCategory] {
        try dbPool.read { db in
            var q = ClipCategory.order(Column("sort_order").asc, Column("name").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    func saveCategory(_ c: inout ClipCategory) throws {
        try dbPool.write { db in try c.save(db) }
    }

    func deleteCategory(id: Int64) throws {
        _ = try dbPool.write { db in try ClipCategory.deleteOne(db, key: id) }
    }

    func ensureCategory(named name: String) throws -> ClipCategory {
        // Categories are stored uppercase as of v8 — normalise here so
        // every code path (inline picker, import, settings CRUD) lands
        // on the same row regardless of how the user typed it in.
        let upper = name.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return try dbPool.write { db in
            if var existing = try ClipCategory.filter(Column("name") == upper).fetchOne(db) {
                // Un-archive on re-use. The "Archive unused" cleanup
                // hides categories that aren't currently attached to a
                // clip; re-attaching one (via import, backfill, or the
                // inline picker) should bring it back into the picker.
                if existing.archived {
                    existing.archived = false
                    try existing.update(db)
                }
                return existing
            }
            var c = ClipCategory(id: nil, name: upper, sortOrder: 0, archived: false)
            try c.insert(db)
            return c
        }
    }

    /// Archive every category that isn't currently referenced by any
    /// `clip_categories` row. Returns the number of categories
    /// archived. Reversible — flip the row's `archived` toggle in
    /// **Settings → Categories** to bring it back, or just attach it
    /// to a clip (`ensureCategory` un-archives on re-use).
    @discardableResult
    func archiveUnusedCategories() throws -> Int {
        try dbPool.write { db in
            // Count first so we can return how many flipped.
            let n = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM categories
                 WHERE archived = 0
                   AND id NOT IN (SELECT category_id FROM clip_categories)
                """) ?? 0
            try db.execute(sql: """
                UPDATE categories
                   SET archived = 1
                 WHERE archived = 0
                   AND id NOT IN (SELECT category_id FROM clip_categories)
                """)
            return n
        }
    }

    /// How many active categories aren't currently attached to any
    /// clip. Drives the "Clean up unused" button label so the user
    /// knows what they're committing to.
    func unusedActiveCategoryCount() throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM categories
                 WHERE archived = 0
                   AND id NOT IN (SELECT category_id FROM clip_categories)
                """) ?? 0
        }
    }

    // MARK: - Exclusion reasons

    func fetchExclusionReasons(includeArchived: Bool = false) throws -> [ExclusionReason] {
        try dbPool.read { db in
            var q = ExclusionReason.order(Column("sort_order").asc, Column("label").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    func saveExclusionReason(_ r: inout ExclusionReason) throws {
        try dbPool.write { db in try r.save(db) }
    }

    func deleteExclusionReason(id: Int64) throws {
        _ = try dbPool.write { db in try ExclusionReason.deleteOne(db, key: id) }
    }

    // MARK: - C4S historical

    func fetchC4SHistorical(store: String? = nil) throws -> [C4SHistoricalRecord] {
        try dbPool.read { db in
            var q = C4SHistoricalRecord
                .order(Column("store").asc, Column("title").collating(.localizedCaseInsensitiveCompare).asc)
            if let store = store, !store.isEmpty {
                q = q.filter(Column("store") == store)
            }
            return try q.fetchAll(db)
        }
    }

    func c4sHistoricalCount(store: String? = nil) throws -> Int {
        try dbPool.read { db in
            if let store = store, !store.isEmpty {
                return try C4SHistoricalRecord.filter(Column("store") == store).fetchCount(db)
            }
            return try C4SHistoricalRecord.fetchCount(db)
        }
    }

    /// Wholesale replace: every row whose `store` matches is deleted, then
    /// the supplied rows are inserted with a single `imported_at` stamp.
    /// Whole thing happens in one transaction so the table is never half
    /// in/half out of date for that store. Returns the number of inserted rows.
    @discardableResult
    func replaceC4SHistorical(store: String, with rows: [C4SHistoricalRecord]) throws -> Int {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM c4s_historical WHERE store = ?", arguments: [store])
            for var row in rows {
                row.id = nil
                row.store = store
                try row.insert(db)
            }
            return rows.count
        }
    }

    // MARK: - Historical category backfill

    /// Targets for `HistoricalCategoryBackfillService`: production-status
    /// clips with no categories assigned. We use this filter (rather
    /// than a "is_historical" flag) because there isn't one — clips
    /// that came in via `Mark as historical` look identical to clips
    /// that worked through the pipeline normally, except for the
    /// missing categories.
    func fetchProductionClipsWithoutCategories() throws -> [Clip] {
        try dbPool.read { db in
            try Clip.fetchAll(db, sql: """
                SELECT c.* FROM clips c
                 WHERE c.archived = 0
                   AND c.status = 'production'
                   AND NOT EXISTS (
                       SELECT 1 FROM clip_categories cc
                        WHERE cc.clip_id = c.id
                   )
                 ORDER BY c.persona_code, c.title
                """)
        }
    }

    /// Apply the user-confirmed subset of a backfill plan. For each
    /// candidate: ensure each Category exists (uppercased), then insert
    /// `clip_categories` rows with the supplied positional order. The
    /// whole batch happens in one transaction so the operation is
    /// all-or-nothing. Skips any clip that gained categories between
    /// plan-time and commit-time.
    @discardableResult
    func applyHistoricalCategoryBackfill(
        _ candidates: [HistoricalCategoryBackfillService.Candidate]
    ) throws -> Int {
        try dbPool.write { db in
            var assigned = 0
            for cand in candidates {
                let existing = try Int.fetchOne(db, sql:
                    "SELECT COUNT(*) FROM clip_categories WHERE clip_id = ?",
                    arguments: [cand.clipId]) ?? 0
                guard existing == 0 else { continue }

                for (pos, name) in cand.categories.enumerated() {
                    let category = try Self.ensureCategoryInTransaction(named: name, db: db)
                    guard let categoryId = category.id else { continue }
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO clip_categories (clip_id, category_id, position)
                        VALUES (?, ?, ?)
                        """, arguments: [cand.clipId, categoryId, pos])
                }
                assigned += 1
            }
            return assigned
        }
    }

    /// In-transaction variant of `ensureCategory`. The public
    /// `ensureCategory(named:)` opens its own write block, which would
    /// deadlock if called from inside another `dbPool.write`.
    private static func ensureCategoryInTransaction(named name: String, db: GRDB.Database) throws -> ClipCategory {
        let upper = name.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try ClipCategory.filter(Column("name") == upper).fetchOne(db) {
            return existing
        }
        var c = ClipCategory(id: nil, name: upper, sortOrder: 0, archived: false)
        try c.insert(db)
        return c
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

    func updateClip(_ newClip: Clip, operatorName: String = "") throws {
        try dbPool.write { db in
            let now = Self.isoNow()
            var mutated = newClip
            let old = try Clip.fetchOne(db, key: newClip.id)
            if let old {
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
            if let old {
                try Self.recordClipHistoryDiff(old: old, new: mutated, in: db, at: now)

                // Auto-stamp a structured note for the user-visible fields the
                // editor exposes (title, raw description, go-live date, status).
                // Bundled into one note so a save doesn't spam the timeline.
                let lines = [
                    Self.diffLine("Title",        old.title,           mutated.title),
                    Self.diffLine("Description",  old.descriptionRaw,  mutated.descriptionRaw),
                    Self.diffLine("Go-Live",      old.goLiveDate ?? "", mutated.goLiveDate ?? ""),
                    Self.diffLine("Status",       old.status,          mutated.status),
                ].compactMap { $0 }
                if !lines.isEmpty {
                    try Self.insertAutoClipNote(
                        clipId: mutated.id,
                        body: lines.joined(separator: "\n"),
                        operatorName: operatorName,
                        in: db
                    )
                }
            }
            try mutated.update(db)
        }
    }

    /// Auto-derive a clip's pipeline status from its editing fields and posting
    /// state. Called from every insert/update path. Does not modify the clip's
    /// `archived` flag (that's a separate column).
    private static func computeStatus(for clip: Clip, in db: Database) throws -> String {
        // Manual override pins the status — bypasses the heuristic entirely.
        // Clearing the override (setStatusOverride(..., to: nil)) restores the
        // auto-derivation on the next write.
        if let override = clip.statusOverride,
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }

        // Excluded-from-posting clips are "done" from the pipeline POV
        // — there's nothing to post, so promote straight to production
        // so they don't sit forever in `to_post` / `posting`.
        if clip.postingExcluded {
            return ClipStatus.production.rawValue
        }

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

        // No scoped sites for this persona (e.g. Shr / N/A clips when
        // no site is configured for them) — nothing to post, so once
        // editing is complete the clip graduates straight to
        // production. Without this branch such clips would stick at
        // `to_post` forever.
        if scopedIds.isEmpty {
            if editingComplete   { return ClipStatus.production.rawValue }
            if editingFilled > 0 { return ClipStatus.editing.rawValue }
            return ClipStatus.new.rawValue
        }

        if postedScoped.count == scopedIds.count {
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
        try record("status_override",     old.statusOverride,     new.statusOverride)
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

    /// Pin (`override` = some status) or unpin (`override` = nil) a clip's
    /// pipeline status. Writes the column directly, recomputes `status` from
    /// the override, stamps a `[Status YYYY-MM-DD: old → new (manual)]`
    /// marker into `notes`, and records two `clip_history` rows so the
    /// transition shows up in the per-clip change log.
    func setStatusOverride(clipId: String, override: String?) throws {
        try dbPool.write { db in
            guard var clip = try Clip.fetchOne(db, key: clipId) else { return }
            let oldStatus = clip.status
            let oldOverride = clip.statusOverride
            let now = Self.isoNow()

            clip.statusOverride = (override?.trimmingCharacters(in: .whitespaces).isEmpty == true) ? nil : override
            clip.status = try Self.computeStatus(for: clip, in: db)
            clip.updatedAt = now

            let label: String = {
                if let o = clip.statusOverride, let s = ClipStatus(rawValue: o) {
                    return s.label
                }
                return clip.statusOverride ?? "auto"
            }()
            let oldLabel = ClipStatus(rawValue: oldStatus)?.label ?? oldStatus
            let marker: String = override == nil
                ? "[Status \(Self.isoDate(Date())): cleared override (was \(oldLabel))]"
                : "[Status \(Self.isoDate(Date())): \(oldLabel) → \(label) (manual)]"
            clip.notes = clip.notes.isEmpty ? marker : clip.notes + "\n" + marker

            try clip.update(db)

            try db.execute(sql: """
                INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [clipId, "status_override", oldOverride, clip.statusOverride, now])
            if oldStatus != clip.status {
                try db.execute(sql: """
                    INSERT INTO clip_history (clip_id, field, old_value, new_value, changed_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [clipId, "status", oldStatus, clip.status, now])
            }
        }
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
    /// pure reorder — appends a `clip_history` row and a structured note.
    func setCategories(forClip clipId: String, categoryIds: [Int64], operatorName: String = "") throws {
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

                // Resolve names for the structured note. Look up *all* ids in
                // one shot — covers both old and new sets.
                let allIds = Array(Set(oldIds + categoryIds))
                var nameById: [Int64: String] = [:]
                if !allIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: allIds.count).joined(separator: ",")
                    let rows = try Row.fetchAll(db,
                        sql: "SELECT id, name FROM categories WHERE id IN (\(placeholders))",
                        arguments: StatementArguments(allIds))
                    for r in rows { nameById[r["id"]] = r["name"] }
                }
                func render(_ ids: [Int64]) -> String {
                    if ids.isEmpty { return "<none>" }
                    return ids.map { nameById[$0] ?? "id:\($0)" }.joined(separator: ", ")
                }
                try Self.insertAutoClipNote(
                    clipId: clipId,
                    body: "Categories: \(render(oldIds)) → \(render(categoryIds))",
                    operatorName: operatorName,
                    in: db
                )
            }
        }
    }

    // MARK: - Segments

    /// Returns the segments belonging to a clip ordered by 1-based `position`.
    func fetchSegments(forClip clipId: String) throws -> [ClipSegment] {
        try dbPool.read { db in
            try ClipSegment
                .filter(Column("clip_id") == clipId)
                .order(Column("position"))
                .fetchAll(db)
        }
    }

    /// Replace the entire segment set for a clip in one transaction. The
    /// caller hands in `[ClipSegment]` already populated with hashes and
    /// metadata; we DELETE the existing rows and INSERT the new ones so
    /// stale segments from a previous (larger) folder snapshot don't linger.
    /// `clip_id` is overwritten on each row to guarantee they all belong to
    /// `clipId` regardless of what the caller put there.
    func replaceSegments(forClip clipId: String, with segments: [ClipSegment]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM clip_segments WHERE clip_id = ?", arguments: [clipId])
            for segment in segments {
                var row = segment
                row.clipId = clipId
                row.id = nil   // force INSERT — autoincrement PK
                try row.insert(db)
            }
        }
    }

    /// Drop every segment row for a clip. Cascades automatically when the
    /// clip itself is deleted (FK ON DELETE CASCADE), but available
    /// explicitly so a "rebuild segments from scratch" flow can clear the
    /// table without recreating the clip row.
    func deleteSegments(forClip clipId: String) throws {
        _ = try dbPool.write { db in
            try db.execute(sql: "DELETE FROM clip_segments WHERE clip_id = ?", arguments: [clipId])
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
            try db.execute(sql: "DELETE FROM clip_segments")
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
