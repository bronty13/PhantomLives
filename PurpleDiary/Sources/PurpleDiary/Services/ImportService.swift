import Foundation

/// Imports journals from a JSON file into the encrypted database. Fully local —
/// the file is read off disk and nothing is uploaded. Four sources:
///
/// - **PurpleDiary** — our own schema-v4 export, round-tripped faithfully:
///   entries land back in their original journals, with mood + tags. (Trackers,
///   people links, and attachments are not carried in the JSON export, so they
///   don't round-trip — documented.)
/// - **Day One / Journey / Diarium** — parsed from each app's documented JSON
///   entry shape into a single destination journal. Extract any `.zip` first and
///   point at the `.json`. Verify against a real export.
///
/// Parsing is pure (`Data -> ImportBundle`, testable); `apply` does the DB
/// inserts (new ids — import is always additive and never collides; tags are
/// de-duplicated by name).
enum ImportService {

    enum Format: String, CaseIterable, Identifiable {
        case auto, purpleDiary, dayOne, journey, diarium
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Auto-detect"
            case .purpleDiary: return "PurpleDiary JSON"
            case .dayOne: return "Day One JSON"
            case .journey: return "Journey JSON"
            case .diarium: return "Diarium JSON"
            }
        }
    }

    struct Bundle {
        struct Entry { var date: String; var title: String; var body: String; var moodRating: Int; var tags: [String] }
        struct Journal { var name: String; var entries: [Entry] }
        var sourceName: String
        var journals: [Journal]
        var totalEntries: Int { journals.reduce(0) { $0 + $1.entries.count } }
    }

    enum ImportError: LocalizedError {
        case unrecognized
        case empty
        var errorDescription: String? {
            switch self {
            case .unrecognized: return "Couldn't recognize this file's format. Try choosing the format explicitly."
            case .empty: return "No entries were found in that file."
            }
        }
    }

    // MARK: - Parse

    static func parse(_ data: Data, format: Format) throws -> Bundle {
        switch format {
        case .purpleDiary: return try parsePurpleDiary(data)
        case .dayOne:      return try parseDayOne(data)
        case .journey:     return try parseJourney(data)
        case .diarium:     return try parseDiarium(data)
        case .auto:
            for parser in [parsePurpleDiary, parseDayOne, parseJourney, parseDiarium] {
                if let b = try? parser(data), b.totalEntries > 0 { return b }
            }
            throw ImportError.unrecognized
        }
    }

    static func parsePurpleDiary(_ data: Data) throws -> Bundle {
        let export = try JSONDecoder().decode(ExportService.JournalExport.self, from: data)
        guard export.app == "PurpleDiary" else { throw ImportError.unrecognized }
        let journalName: [String: String] = Dictionary(
            uniqueKeysWithValues: export.journals.map { ($0.id, $0.name) })
        var byJournal: [String: [Bundle.Entry]] = [:]
        var order: [String] = []
        for e in export.entries {
            let name = journalName[e.journalId] ?? "Imported"
            if byJournal[name] == nil { order.append(name) }
            byJournal[name, default: []].append(
                Bundle.Entry(date: e.date, title: e.title, body: e.bodyMarkdown,
                             moodRating: e.moodRating, tags: e.tags))
        }
        let journals = order.map { Bundle.Journal(name: $0, entries: byJournal[$0] ?? []) }
        return Bundle(sourceName: "PurpleDiary", journals: journals)
    }

    // Day One: { "entries": [ { "creationDate", "text", "tags"?, "starred"? } ] }
    private struct DayOneFile: Decodable {
        struct Entry: Decodable { var creationDate: String?; var text: String?; var tags: [String]? }
        var entries: [Entry]
    }
    static func parseDayOne(_ data: Data) throws -> Bundle {
        let file = try JSONDecoder().decode(DayOneFile.self, from: data)
        let entries = file.entries.map { e in
            Bundle.Entry(date: e.creationDate ?? "", title: "",
                         body: e.text ?? "", moodRating: 0, tags: e.tags ?? [])
        }
        guard !entries.isEmpty else { throw ImportError.empty }
        return Bundle(sourceName: "Day One", journals: [.init(name: "Day One", entries: entries)])
    }

    // Journey: a single entry object, or an array of them.
    // { "date_journal": <ms>, "text": "...", "tags": [...] }
    private struct JourneyEntry: Decodable {
        var date_journal: Double?; var text: String?; var tags: [String]?
    }
    static func parseJourney(_ data: Data) throws -> Bundle {
        let raw: [JourneyEntry]
        if let arr = try? JSONDecoder().decode([JourneyEntry].self, from: data) {
            raw = arr
        } else {
            raw = [try JSONDecoder().decode(JourneyEntry.self, from: data)]
        }
        let iso = ISO8601DateFormatter()
        let entries: [Bundle.Entry] = raw.compactMap { e in
            guard e.text != nil || e.date_journal != nil else { return nil }
            let date: String
            if let ms = e.date_journal { date = iso.string(from: Date(timeIntervalSince1970: ms / 1000)) }
            else { date = "" }
            return Bundle.Entry(date: date, title: "", body: e.text ?? "", moodRating: 0, tags: e.tags ?? [])
        }
        guard !entries.isEmpty else { throw ImportError.empty }
        return Bundle(sourceName: "Journey", journals: [.init(name: "Journey", entries: entries)])
    }

    // Diarium: { "entries": [ { "date", "title"?, "text"|"body", "tags"? } ] } or a bare array.
    private struct DiariumEntry: Decodable {
        var date: String?; var title: String?; var text: String?; var body: String?; var tags: [String]?
    }
    private struct DiariumFile: Decodable { var entries: [DiariumEntry] }
    static func parseDiarium(_ data: Data) throws -> Bundle {
        let raw: [DiariumEntry]
        if let file = try? JSONDecoder().decode(DiariumFile.self, from: data) { raw = file.entries }
        else { raw = try JSONDecoder().decode([DiariumEntry].self, from: data) }
        let entries: [Bundle.Entry] = raw.compactMap { e in
            let text = e.text ?? e.body
            guard text != nil || e.title != nil else { return nil }
            return Bundle.Entry(date: e.date ?? "", title: e.title ?? "",
                                body: text ?? "", moodRating: 0, tags: e.tags ?? [])
        }
        guard !entries.isEmpty else { throw ImportError.empty }
        return Bundle(sourceName: "Diarium", journals: [.init(name: "Diarium", entries: entries)])
    }

    // MARK: - Apply

    /// Insert a parsed bundle into the database. Creates (or reuses by name) a
    /// destination journal per bundle journal, inserts entries with fresh ids,
    /// and de-duplicates tags by name. Returns the number of entries added.
    /// Operates directly on `DatabaseService` (no `AppState`); the caller
    /// reloads its slices afterward.
    @MainActor
    @discardableResult
    static func apply(_ bundle: Bundle) throws -> Int {
        let db = DatabaseService.shared
        let now = DatabaseService.isoNow()

        // Tag name → id, creating missing tags.
        var tagIdByName: [String: Int64] = [:]
        for t in try db.fetchAllTags() { if let r = t.rowId { tagIdByName[t.name.lowercased()] = r } }
        func tagId(_ name: String) throws -> Int64? {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            if let id = tagIdByName[key.lowercased()] { return id }
            var tag = Tag(rowId: nil, name: key, colorHex: "#888888")
            try db.saveTag(&tag)
            if let id = tag.rowId { tagIdByName[key.lowercased()] = id; return id }
            return nil
        }

        // Journal name → id, creating missing journals (default journal reused).
        var journalIdByName: [String: String] = [:]
        for j in try db.fetchAllJournals() { journalIdByName[j.name.lowercased()] = j.id }

        var added = 0
        for bj in bundle.journals where !bj.entries.isEmpty {
            let jid: String
            if let existing = journalIdByName[bj.name.lowercased()] {
                jid = existing
            } else {
                let journal = Journal.newDraft(name: bj.name)
                try db.insertJournal(journal)
                jid = journal.id
                journalIdByName[bj.name.lowercased()] = jid
            }
            for ie in bj.entries {
                var entry = Entry.newDraft(journalId: jid)
                entry.date = ie.date.isEmpty ? now : ie.date
                entry.title = ie.title
                entry.bodyMarkdown = ie.body
                entry.moodRating = max(0, min(5, ie.moodRating))
                try db.insertEntry(entry)
                let ids = try ie.tags.compactMap { try tagId($0) }
                if !ids.isEmpty { try db.setTags(ids, forEntry: entry.id) }
                added += 1
            }
        }
        return added
    }
}
