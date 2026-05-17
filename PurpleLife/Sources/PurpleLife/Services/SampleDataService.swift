import AppKit
import Foundation
import GRDB

/// Inserts (or removes) a curated, narrative-shaped slice-of-life
/// dataset for the user to poke at the app with — Today timeline,
/// kanban groupings, calendar entries, charts, etc. all populated
/// from one coherent fictional character ("Sam Reyes") across the
/// last ~90 days.
///
/// **Design contract.** Every record this service writes carries an
/// id prefixed with `sample-`. That gives us a single-query subtractive
/// path (`WHERE id LIKE 'sample-%'`) without any second index table or
/// metadata column on `objects`. Re-running `populate()` is idempotent:
/// existing rows are replaced in place, not duplicated. User-created
/// records (whose ids are UUIDs, never starting with `sample-`) are
/// untouched in both directions.
///
/// **Vault contract.** Sample data never lands in Vault types. This is
/// enforced by construction — the dataset only references built-in
/// non-Vault types. Even if the user later flips a built-in to
/// `isVault = true`, the existing sample records are still recoverable
/// by `clearSampleData()` because the id prefix is the source of truth.
///
/// **Performance.** Bulk inserts bypass `ObjectEngine` (which fires
/// per-record sync push, undo registration, and FTS upsert). We write
/// straight to `DatabaseService.insertObject`/`updateObject`, then
/// trigger a single `SearchService.reindexAll` + `TagService.reindexAll`
/// at the end. The 130-ish records this seeds finish in well under a
/// second.
@MainActor
enum SampleDataService {

    /// Every sample record id starts with this. Source of truth for
    /// both populate (replace-if-present) and clear (subtractive).
    static let idPrefix = "sample-"

    struct Result {
        let inserted: Int
        let replaced: Int
        let total: Int
    }

    // MARK: - Public entry points

    /// Add or refresh the sample dataset. Idempotent: existing sample
    /// records get replaced in-place; user-created records untouched.
    /// Returns counts so the UI can show "Wrote 130 records (45 new,
    /// 85 refreshed)."
    @discardableResult
    static func populate() throws -> Result {
        let records = makeRecords(now: Date())
        var inserted = 0
        var replaced = 0
        for record in records {
            if try DatabaseService.shared.fetchObject(id: record.id) != nil {
                try DatabaseService.shared.updateObject(record)
                replaced += 1
            } else {
                try DatabaseService.shared.insertObject(record)
                inserted += 1
            }
        }
        // One pass for search + tag indexes instead of per-record
        // upserts. The non-sample data already lives in both indexes,
        // so `reindexAll` is the safe shape: it tears down and rebuilds.
        if let schema = ObjectEngine.currentSchema {
            SearchService.reindexAll(schema: schema)
        }
        TagService.reindexAll()
        return Result(inserted: inserted, replaced: replaced, total: records.count)
    }

    /// Remove every record whose id starts with `sample-`. Returns the
    /// count removed. User-created records are matched by UUID and
    /// can never start with the prefix, so they're untouched.
    @discardableResult
    static func clearSampleData() throws -> Int {
        let ids = try DatabaseService.shared.dbPool.read { db in
            try String.fetchAll(db,
                                sql: "SELECT id FROM objects WHERE id LIKE ?",
                                arguments: ["\(idPrefix)%"])
        }
        for id in ids {
            try DatabaseService.shared.deleteObject(id: id)
        }
        if let schema = ObjectEngine.currentSchema {
            SearchService.reindexAll(schema: schema)
        }
        TagService.reindexAll()
        return ids.count
    }

    /// Returns how many sample-prefixed records currently live in the
    /// DB. Powers the UI badge ("3 sample records present" / "no
    /// sample data present").
    static func currentSampleRecordCount() -> Int {
        (try? DatabaseService.shared.dbPool.read { db in
            try Int.fetchOne(db,
                             sql: "SELECT COUNT(*) FROM objects WHERE id LIKE ?",
                             arguments: ["\(idPrefix)%"])
        }) ?? 0
    }

    // MARK: - Dataset assembly

    /// All sample records. Pure function of `now` so unit tests can
    /// pin a deterministic timestamp.
    static func makeRecords(now: Date) -> [ObjectRecord] {
        var out: [ObjectRecord] = []
        out.append(contentsOf: makeWeights(now: now))
        out.append(contentsOf: makePlannerItems(now: now))
        out.append(contentsOf: makePeople(now: now))
        out.append(contentsOf: makeBooks(now: now))
        out.append(contentsOf: makeCameras(now: now))
        out.append(contentsOf: makePhotoShoots(now: now))
        out.append(contentsOf: makePhotos(now: now))
        out.append(contentsOf: makeWoWCharacters(now: now))
        out.append(contentsOf: makeNotes(now: now))
        return out
    }

    // MARK: - Per-type generators

    /// Weight: 50 daily-ish entries over the last 90 days, slow
    /// realistic decline 210 → 198 lb with noise. Most via Smart
    /// scale, occasional Manual. Body fat tracked ~25% of the time.
    private static func makeWeights(now: Date) -> [ObjectRecord] {
        var out: [ObjectRecord] = []
        // Deterministic pseudo-noise: small seeded sequence so repeated
        // populates produce the same chart, not a different one each run.
        let noise: [Double] = [0.4, -0.6, 0.2, 0.8, -0.3, 1.1, -0.5, 0.0, 0.7, -0.4,
                                0.3, -0.9, 0.5, 0.6, -0.2, 1.0, -0.7, 0.1, 0.4, -0.5,
                                0.8, -0.3, 0.0, 0.6, -0.6, 0.9, -0.4, 0.2, 0.5, -0.1,
                                0.7, -0.5, 0.3, 0.4, -0.8, 1.2, -0.2, 0.1, 0.6, -0.4,
                                0.5, -0.7, 0.3, 0.8, -0.1, 0.4, -0.3, 0.0, 0.5, -0.2]
        var bodyFatSamples: [Double?] = []
        bodyFatSamples.reserveCapacity(50)
        for i in 0..<50 {
            if i % 4 == 0 {
                bodyFatSamples.append(22.0 - Double(i) * 0.06)
            } else {
                bodyFatSamples.append(nil)
            }
        }
        let sources = ["Smart scale", "Smart scale", "Smart scale", "Manual", "Smart scale"]
        for i in 0..<50 {
            // i=0 is today, i=49 is 90 days ago (roughly daily, skipping some).
            let daysAgo = i * 90 / 50
            let date = dayStartString(daysAgo: daysAgo, from: now)
            let trend = 210.0 - (Double(50 - i) * 12.0 / 50.0)
            let pounds = (trend + noise[i] * 10).rounded() / 10
            var fields: [String: Any] = [
                "date":   date,
                "pounds": pounds,
                "source": optionId(for: sources[i % sources.count],
                                    inField: "source", ofType: "Weight"),
            ]
            if let bf = bodyFatSamples[i] {
                fields["body_fat"] = (bf * 10).rounded() / 10
            }
            if i == 0 { fields["notes"] = "Cycle complete. Down 12 lb since the start." }
            if i == 25 { fields["notes"] = "After the long weekend — back on the wagon." }
            out.append(makeSampleRecord(
                typeId: "Weight",
                index: i,
                fields: fields,
                daysAgo: daysAgo,
                from: now
            ))
        }
        return out
    }

    /// Planner: 20 items spread across the last 60 and next 30 days.
    /// Status distribution: 9 Done, 3 Doing, 6 Pending, 2 Cancelled.
    private static func makePlannerItems(now: Date) -> [ObjectRecord] {
        struct Item {
            let title: String
            let dayOffset: Int    // negative = past, positive = future
            let status: String
            let project: String
            let notes: String?
        }
        let items: [Item] = [
            .init(title: "Renew passport",                    dayOffset: -42, status: "Done",      project: "Personal admin",   notes: "Photos taken at CVS — submitted online."),
            .init(title: "Q2 perf review notes",              dayOffset: -35, status: "Done",      project: "Apollo migration", notes: nil),
            .init(title: "Dentist cleaning",                  dayOffset: -28, status: "Done",      project: "Personal admin",   notes: "Next visit in 6 months."),
            .init(title: "Photography portfolio site",        dayOffset: -25, status: "Done",      project: "Photography",      notes: "Live at samreyes.photo."),
            .init(title: "Tax filing",                        dayOffset: -20, status: "Done",      project: "Personal admin",   notes: "Federal + state submitted. Refund expected."),
            .init(title: "Replace kitchen faucet",            dayOffset: -18, status: "Done",      project: "Home repairs",     notes: "Took longer than expected — shutoff valve was corroded."),
            .init(title: "Schedule annual physical",          dayOffset: -14, status: "Done",      project: "Personal admin",   notes: nil),
            .init(title: "Apollo: migrate auth middleware",   dayOffset: -10, status: "Done",      project: "Apollo migration", notes: "Shipped Friday. Caught one regression in staging."),
            .init(title: "Camera sensor cleaning",            dayOffset:  -7, status: "Done",      project: "Photography",      notes: nil),
            .init(title: "Apollo: rollout to prod",           dayOffset:  -3, status: "Doing",     project: "Apollo migration", notes: "Canary at 10%."),
            .init(title: "Pack for Niagara trip",             dayOffset:  -1, status: "Doing",     project: "Travel",           notes: nil),
            .init(title: "Write Q2 retrospective",            dayOffset:   0, status: "Doing",     project: "Apollo migration", notes: "Due tomorrow."),
            .init(title: "Niagara Falls photoshoot",          dayOffset:   2, status: "Pending",   project: "Photography",      notes: "Golden hour at 7:42 PM."),
            .init(title: "Mom's birthday call",               dayOffset:   4, status: "Pending",   project: "Family",           notes: "Don't forget the card."),
            .init(title: "Renew car registration",            dayOffset:   8, status: "Pending",   project: "Personal admin",   notes: nil),
            .init(title: "Apollo: post-migration cleanup",    dayOffset:  10, status: "Pending",   project: "Apollo migration", notes: nil),
            .init(title: "Order new running shoes",           dayOffset:  14, status: "Pending",   project: "Health",           notes: nil),
            .init(title: "Plan Iceland trip",                 dayOffset:  21, status: "Pending",   project: "Travel",           notes: "Northern lights season."),
            .init(title: "Gym free trial",                    dayOffset:  -8, status: "Cancelled", project: "Health",           notes: "Going to keep doing home workouts."),
            .init(title: "Book club: Hail Mary discussion",   dayOffset: -16, status: "Cancelled", project: "Reading",          notes: "Conflict — rescheduled to August."),
        ]
        return items.enumerated().map { (i, item) in
            var fields: [String: Any] = [
                "title":   item.title,
                "date":    dayStartString(daysAgo: -item.dayOffset, from: now),
                "status":  optionId(for: item.status, inField: "status", ofType: "PlannerItem"),
                "project": item.project,
            ]
            if let n = item.notes { fields["notes"] = n }
            return makeSampleRecord(
                typeId: "PlannerItem",
                index: i,
                fields: fields,
                daysAgo: max(0, -item.dayOffset),
                from: now
            )
        }
    }

    /// 10 people — mix of family, friends, colleagues. Stable ids so
    /// links from other records (notes, planner items) resolve.
    private static func makePeople(now: Date) -> [ObjectRecord] {
        struct P { let display: String; let first: String; let last: String; let email: String?; let phone: String?; let rel: String; let notes: String? }
        let people: [P] = [
            .init(display: "Mom Reyes",      first: "Elena",   last: "Reyes",    email: "elena.reyes@example.com", phone: "+1 716 555 0188", rel: "Family",       notes: "Birthday May 20. Loves photography prints."),
            .init(display: "Dad Reyes",      first: "Miguel",  last: "Reyes",    email: "miguel.reyes@example.com", phone: "+1 716 555 0144", rel: "Family",      notes: nil),
            .init(display: "Jamie Reyes",    first: "Jamie",   last: "Reyes",    email: "jamie.reyes@example.com", phone: nil, rel: "Family",                     notes: "Younger sibling. Lives in Rochester."),
            .init(display: "Pat Singh",      first: "Pat",     last: "Singh",    email: "pat@patsingh.dev", phone: nil, rel: "Friend",                            notes: "Climbing partner."),
            .init(display: "Morgan Lee",     first: "Morgan",  last: "Lee",      email: nil, phone: "+1 510 555 0167", rel: "Friend",                             notes: nil),
            .init(display: "Dani Owens",     first: "Dani",    last: "Owens",    email: "dani.o@example.com", phone: nil, rel: "Friend",                          notes: "Met at the photo walk."),
            .init(display: "Casey Chen",     first: "Casey",   last: "Chen",     email: "casey.chen@example.com", phone: nil, rel: "Friend",                      notes: nil),
            .init(display: "Riley Patel",    first: "Riley",   last: "Patel",    email: "rpatel@apollo.example", phone: nil, rel: "Colleague",                    notes: "Tech lead, Apollo team."),
            .init(display: "Jordan Wu",      first: "Jordan",  last: "Wu",       email: "jwu@apollo.example", phone: nil, rel: "Colleague",                       notes: nil),
            .init(display: "Avery Goldberg", first: "Avery",   last: "Goldberg", email: "avery@apollo.example", phone: nil, rel: "Colleague",                     notes: "Skip-level. 1:1 every other Wednesday."),
        ]
        return people.enumerated().map { (i, p) in
            var fields: [String: Any] = [
                "display_name":  p.display,
                "first_name":    p.first,
                "last_name":     p.last,
                "relationship":  optionId(for: p.rel, inField: "relationship", ofType: "Person"),
            ]
            if let e = p.email { fields["email"] = e }
            if let ph = p.phone { fields["phone"] = ph }
            if let n = p.notes { fields["notes"] = n }
            return makeSampleRecord(
                typeId: "Person",
                index: i,
                fields: fields,
                daysAgo: 30 + i,
                from: now
            )
        }
    }

    /// Books: 3 Finished (with ratings), 2 Reading, 2 Want-to-read, 1 Abandoned.
    private static func makeBooks(now: Date) -> [ObjectRecord] {
        struct B {
            let title: String; let author: String; let status: String
            let startedDaysAgo: Int?; let finishedDaysAgo: Int?
            let rating: Int?; let notes: String?
        }
        let books: [B] = [
            .init(title: "Project Hail Mary",                author: "Andy Weir",          status: "Finished",     startedDaysAgo: 70, finishedDaysAgo: 55, rating: 5, notes: "Funniest hard sci-fi I've read in years."),
            .init(title: "Recursion",                        author: "Blake Crouch",       status: "Finished",     startedDaysAgo: 50, finishedDaysAgo: 38, rating: 4, notes: "Great hook. Loses steam in the middle."),
            .init(title: "The Anthropocene Reviewed",        author: "John Green",         status: "Finished",     startedDaysAgo: 35, finishedDaysAgo: 22, rating: 5, notes: "Reread some essays already."),
            .init(title: "Klara and the Sun",                author: "Kazuo Ishiguro",     status: "Reading",      startedDaysAgo: 18, finishedDaysAgo: nil, rating: nil, notes: "Quiet, devastating prose."),
            .init(title: "Astrophysics for People in a Hurry", author: "Neil deGrasse Tyson", status: "Reading", startedDaysAgo: 10, finishedDaysAgo: nil, rating: nil, notes: nil),
            .init(title: "Tomorrow, and Tomorrow, and Tomorrow", author: "Gabrielle Zevin", status: "Want to read", startedDaysAgo: nil, finishedDaysAgo: nil, rating: nil, notes: "Recommended by Pat."),
            .init(title: "The Three-Body Problem",           author: "Cixin Liu",          status: "Want to read", startedDaysAgo: nil, finishedDaysAgo: nil, rating: nil, notes: nil),
            .init(title: "Infinite Jest",                    author: "David Foster Wallace", status: "Abandoned", startedDaysAgo: 80, finishedDaysAgo: nil, rating: 2, notes: "Made it through page 200. Maybe one day."),
        ]
        return books.enumerated().map { (i, b) in
            var fields: [String: Any] = [
                "title":  b.title,
                "author": b.author,
                "status": optionId(for: b.status, inField: "status", ofType: "Book"),
            ]
            if let s = b.startedDaysAgo  { fields["started"]  = dayStartString(daysAgo: s, from: now) }
            if let f = b.finishedDaysAgo { fields["finished"] = dayStartString(daysAgo: f, from: now) }
            if let r = b.rating          { fields["rating"]   = r }
            if let n = b.notes           { fields["notes"]    = n }
            return makeSampleRecord(typeId: "Book", index: i, fields: fields, daysAgo: 30, from: now)
        }
    }

    /// 3 cameras across kinds. Photo Shoots reference these by id.
    private static func makeCameras(now: Date) -> [ObjectRecord] {
        struct C { let model: String; let brand: String; let kind: String; let purchasedDaysAgo: Int; let serial: String?; let notes: String? }
        let cameras: [C] = [
            .init(model: "α7 IV",   brand: "Sony",     kind: "Mirrorless", purchasedDaysAgo: 420, serial: "SN7421887", notes: "Daily driver."),
            .init(model: "X100V",   brand: "Fujifilm", kind: "Compact",    purchasedDaysAgo: 280, serial: "FX100V-552",   notes: "Pocket / travel."),
            .init(model: "AE-1",    brand: "Canon",    kind: "Film",       purchasedDaysAgo: 90,  serial: nil,            notes: "Estate sale find. Light meter still works."),
        ]
        return cameras.enumerated().map { (i, c) in
            var fields: [String: Any] = [
                "model":     c.model,
                "brand":     optionId(for: c.brand, inField: "brand", ofType: "Camera"),
                "kind":      optionId(for: c.kind,  inField: "kind",  ofType: "Camera"),
                "purchased": dayStartString(daysAgo: c.purchasedDaysAgo, from: now),
            ]
            if let s = c.serial { fields["serial"] = s }
            if let n = c.notes  { fields["notes"]  = n }
            return makeSampleRecord(typeId: "Camera", index: i, fields: fields, daysAgo: c.purchasedDaysAgo, from: now)
        }
    }

    /// 6 photo shoots referencing the cameras above.
    private static func makePhotoShoots(now: Date) -> [ObjectRecord] {
        struct S { let title: String; let daysAgo: Int; let location: String; let cameraIndex: Int; let status: String; let notes: String? }
        let shoots: [S] = [
            .init(title: "Niagara Falls golden hour",  daysAgo: 60, location: "Niagara Falls, NY",   cameraIndex: 0, status: "Published", notes: "Three keepers in the gallery."),
            .init(title: "Downtown Buffalo street",    daysAgo: 45, location: "Elmwood Village",     cameraIndex: 1, status: "Edited",    notes: nil),
            .init(title: "Allegheny weekend",          daysAgo: 28, location: "Allegany State Park", cameraIndex: 0, status: "Published", notes: nil),
            .init(title: "Family portraits",           daysAgo: 14, location: "Mom & Dad's house",   cameraIndex: 0, status: "Shot",      notes: "200+ frames; culling next weekend."),
            .init(title: "Frozen Lake Erie",           daysAgo: 8,  location: "Hamburg Beach",       cameraIndex: 1, status: "Edited",    notes: nil),
            .init(title: "Self-portrait roll (AE-1)",  daysAgo: -7, location: "Home studio",         cameraIndex: 2, status: "Planned",   notes: "First roll through the AE-1."),
        ]
        return shoots.enumerated().map { (i, s) in
            var fields: [String: Any] = [
                "title":    s.title,
                "date":     dayStartDateTimeString(daysAgo: s.daysAgo, from: now),
                "location": s.location,
                "camera":   sampleId(for: "Camera", index: s.cameraIndex),
                "status":   optionId(for: s.status, inField: "status", ofType: "PhotoShoot"),
            ]
            if let n = s.notes { fields["notes"] = n }
            return makeSampleRecord(typeId: "PhotoShoot", index: i, fields: fields, daysAgo: max(0, s.daysAgo), from: now)
        }
    }

    /// 12 photos linked to shoots + cameras. Mix of keeper/maybe/reject.
    private static func makePhotos(now: Date) -> [ObjectRecord] {
        struct Ph { let title: String; let daysAgo: Int; let cameraIdx: Int; let shootIdx: Int; let rating: Int; let kind: String }
        let photos: [Ph] = [
            .init(title: "Niagara 01 — mist rainbow",        daysAgo: 60, cameraIdx: 0, shootIdx: 0, rating: 5, kind: "Keeper"),
            .init(title: "Niagara 02 — long exposure",       daysAgo: 60, cameraIdx: 0, shootIdx: 0, rating: 4, kind: "Keeper"),
            .init(title: "Niagara 03 — wide vista",          daysAgo: 60, cameraIdx: 0, shootIdx: 0, rating: 3, kind: "Maybe"),
            .init(title: "Elmwood neon — laundromat",        daysAgo: 45, cameraIdx: 1, shootIdx: 1, rating: 5, kind: "Keeper"),
            .init(title: "Elmwood neon — diner sign",        daysAgo: 45, cameraIdx: 1, shootIdx: 1, rating: 4, kind: "Keeper"),
            .init(title: "Allegheny 01 — forest trail",      daysAgo: 28, cameraIdx: 0, shootIdx: 2, rating: 4, kind: "Keeper"),
            .init(title: "Allegheny 02 — campfire smoke",    daysAgo: 28, cameraIdx: 0, shootIdx: 2, rating: 3, kind: "Maybe"),
            .init(title: "Allegheny 03 — out of focus",      daysAgo: 28, cameraIdx: 0, shootIdx: 2, rating: 1, kind: "Reject"),
            .init(title: "Family — Jamie + Mom on porch",    daysAgo: 14, cameraIdx: 0, shootIdx: 3, rating: 4, kind: "Keeper"),
            .init(title: "Family — Dad's gardening hands",   daysAgo: 14, cameraIdx: 0, shootIdx: 3, rating: 5, kind: "Keeper"),
            .init(title: "Lake Erie — ice shards",           daysAgo: 8,  cameraIdx: 1, shootIdx: 4, rating: 4, kind: "Keeper"),
            .init(title: "Lake Erie — sunset blowout",       daysAgo: 8,  cameraIdx: 1, shootIdx: 4, rating: 2, kind: "Reject"),
        ]
        return photos.enumerated().map { (i, p) in
            let fields: [String: Any] = [
                "title":  p.title,
                "taken":  dayStartDateTimeString(daysAgo: p.daysAgo, from: now),
                "camera": sampleId(for: "Camera", index: p.cameraIdx),
                "shoot":  sampleId(for: "PhotoShoot", index: p.shootIdx),
                "rating": p.rating,
                "kind":   optionId(for: p.kind, inField: "kind", ofType: "Photo"),
            ]
            return makeSampleRecord(typeId: "Photo", index: i, fields: fields, daysAgo: p.daysAgo, from: now)
        }
    }

    /// 5 WoW characters across factions / classes / statuses.
    private static func makeWoWCharacters(now: Date) -> [ObjectRecord] {
        struct W { let name: String; let cls: String; let level: Int; let realm: String; let faction: String; let status: String; let notes: String? }
        let chars: [W] = [
            .init(name: "Threadweaver", cls: "Mage",        level: 80, realm: "Stormrage",    faction: "Alliance", status: "Main",   notes: "Main raider — fire spec."),
            .init(name: "Stoneheart",   cls: "Paladin",     level: 80, realm: "Stormrage",    faction: "Alliance", status: "Alt",    notes: "Tank alt for M+."),
            .init(name: "Velgrym",      cls: "Death Knight", level: 75, realm: "Tichondrius", faction: "Horde",    status: "Banked", notes: "Levelling project on the back burner."),
            .init(name: "Daerthe",      cls: "Druid",       level: 64, realm: "Stormrage",    faction: "Alliance", status: "Banked", notes: nil),
            .init(name: "Phant",        cls: "Warlock",     level: 80, realm: "Stormrage",    faction: "Alliance", status: "Alt",    notes: "Affliction lock — slow but inevitable."),
        ]
        return chars.enumerated().map { (i, w) in
            var fields: [String: Any] = [
                "name":    w.name,
                "class":   optionId(for: w.cls,     inField: "class",   ofType: "WoWCharacter"),
                "level":   w.level,
                "realm":   w.realm,
                "faction": optionId(for: w.faction, inField: "faction", ofType: "WoWCharacter"),
                "status":  optionId(for: w.status,  inField: "status",  ofType: "WoWCharacter"),
            ]
            if let n = w.notes { fields["notes"] = n }
            return makeSampleRecord(typeId: "WoWCharacter", index: i, fields: fields, daysAgo: 5 + i * 3, from: now)
        }
    }

    /// 12 notes across the three categories (Journal, Idea, Reference).
    /// Bodies are rich-text dictionaries with plain + empty-rtf shape
    /// so they round-trip through the FieldDisplay / editor paths
    /// without special-casing.
    private static func makeNotes(now: Date) -> [ObjectRecord] {
        struct N { let title: String; let daysAgo: Int; let category: String; let body: String }
        let notes: [N] = [
            .init(title: "Q2 retrospective",            daysAgo: 1,  category: "Journal",   body: "Apollo migration was the big win. Photography portfolio finally shipped. Health steady — down 12 lb. Next quarter: Iceland."),
            .init(title: "Iceland trip — first thoughts", daysAgo: 3, category: "Ideas",      body: "Northern lights season is Sept-Mar. Reykjavik + Vík + glacier hike. Renting a 4x4 for the south coast."),
            .init(title: "Sourdough — kitchen notes",   daysAgo: 5,  category: "Reference", body: "Starter feeds: 1:1:1 by weight. Bulk ferment 4-5 hours @ 75°F. Shape, cold retard overnight."),
            .init(title: "Apollo migration learnings",  daysAgo: 8,  category: "Reference", body: "Auth middleware swap was the load-bearing change. Canary rollouts saved us once already — staging didn't catch the session-fixation regression."),
            .init(title: "Photo edit — Niagara batch",  daysAgo: 10, category: "Journal",   body: "Three keepers from the golden hour walk. Long exposure with ND filter worked. Need a sturdier tripod for the wide vista."),
            .init(title: "Recipe — beef shawarma",      daysAgo: 14, category: "Reference", body: "Marinade overnight. Garlic-tahini sauce: 2 cloves garlic, juice of 1 lemon, 1/2 cup tahini, water to thin."),
            .init(title: "Climbing — V4 goals",         daysAgo: 16, category: "Ideas",      body: "Want to send a V4 by end of summer. Currently flashing V2, projecting V3. Plan: bouldering 2x/week + finger strength."),
            .init(title: "Tax filing notes",            daysAgo: 20, category: "Reference", body: "Filed federal + state through CPA. Refund $1.2k expected late June. Quarterly estimates set for next year."),
            .init(title: "Book club — Hail Mary debrief", daysAgo: 25, category: "Journal", body: "Group loved it. Casey ranked Andy Weir's three: Hail Mary > Martian > Artemis. Next pick: Klara and the Sun."),
            .init(title: "Niagara trip planning",       daysAgo: 30, category: "Ideas",      body: "Golden hour at the Falls. Park at Goat Island. Tripod, ND filter, polarizer. Backup rain gear."),
            .init(title: "Coffee roast log — Yirgacheffe", daysAgo: 36, category: "Reference", body: "Light roast, 11 min total, first crack at 8:45, dropped at 11:15. Floral, citrus, bright."),
            .init(title: "Welcome to PurpleLife",       daysAgo: 45, category: "Journal",   body: "Trying this Life OS thing. Hobbies + planner + reading log + weight + photography + WoW all in one place. Worth a quarter to evaluate."),
        ]
        return notes.enumerated().map { (i, n) in
            // Generate a real RTF blob so the Notes editor's load path
            // (which decodes the rtf field, not the plain mirror)
            // renders the body. Plain-only-no-rtf bodies tripped a bug
            // where the editor showed blank then autosaved an empty
            // value back over the plain string — see the editor fix
            // in NoteEditorView.loadIfNeeded for the load-side guard.
            let attr = NSAttributedString(string: n.body)
            let rtf  = (try? attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )) ?? Data()
            let body: [String: Any] = [
                "plain": n.body,
                "rtf":   rtf.base64EncodedString()
            ]
            let fields: [String: Any] = [
                "date":     dayStartString(daysAgo: n.daysAgo, from: now),
                "title":    n.title,
                "category": optionId(for: n.category, inField: "category", ofType: "Note"),
                "body":     body,
            ]
            return makeSampleRecord(typeId: "Note", index: i, fields: fields, daysAgo: n.daysAgo, from: now)
        }
    }

    // MARK: - Helpers

    /// Build one sample record with a stable, prefix-matched id. The
    /// `daysAgo` parameter lets us set createdAt / updatedAt back in
    /// time so the dataset looks lived-in rather than all-stamped-now.
    private static func makeSampleRecord(
        typeId: String,
        index: Int,
        fields: [String: Any],
        daysAgo: Int,
        from now: Date
    ) -> ObjectRecord {
        let id = sampleId(for: typeId, index: index)
        let stamp = isoString(daysAgo: daysAgo, from: now)
        let json = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ObjectRecord(
            id: id,
            typeId: typeId,
            parentId: nil,
            fieldsJSON: json,
            createdAt: stamp,
            updatedAt: stamp
        )
    }

    static func sampleId(for typeId: String, index: Int) -> String {
        "\(idPrefix)\(typeId)-\(index)"
    }

    /// Resolve a built-in field-option label like "Doing" to the
    /// underlying option UUID by walking the seed schema. Returns the
    /// raw label if no match found — leaves a recoverable trail rather
    /// than silently dropping the value. Same pattern the export
    /// pipeline uses, inverted.
    private static func optionId(for label: String, inField key: String, ofType typeId: String) -> String {
        guard let type = SchemaSeed.allTypes.first(where: { $0.id == typeId }),
              let field = type.fields.first(where: { $0.key == key }),
              let option = field.options.first(where: { $0.name == label })
        else {
            return label
        }
        return option.id
    }

    /// ISO date string for "<daysAgo> days before <now>, midnight UTC".
    private static func dayStartString(daysAgo: Int, from now: Date) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// ISO datetime string for "<daysAgo> days before <now>".
    private static func dayStartDateTimeString(daysAgo: Int, from now: Date) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: now) ?? now
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }

    private static func isoString(daysAgo: Int, from now: Date) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return ISO8601DateFormatter().string(from: date)
    }
}
