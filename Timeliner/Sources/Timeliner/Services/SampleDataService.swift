import Foundation

/// Installs and restores curated true-crime sample timelines that ship with
/// the app.
///
/// Each sample case has a stable `sample-` prefixed `Case.id` so we can
/// detect prior installs (and replace on `restore`) without disturbing
/// user-authored cases. Sample data is bundled as JSON in the app resources;
/// the on-disk parsing pipeline is small (~150 events × 43 people for the
/// Madeline Soto case) so the install runs synchronously inside `AppState`
/// flow without measurable delay.
///
/// Lifecycle:
/// - `installIfFirstRunCompleted` runs once from `AppState.init` when the
///   user has never seen sample data and the cases table is empty. It
///   sets `AppSettings.sampleDataEverInstalled = true` so a later delete
///   isn't silently undone.
/// - `restoreAllSamples` is the explicit "Restore Sample Data" path from
///   the General settings tab. It deletes any existing sample-prefixed
///   case (with cascade) and reinstalls the canonical content.
@MainActor
enum SampleDataService {

    // MARK: - Public catalog

    struct SampleSpec: Hashable {
        /// Stable `Case.id` prefix used to detect prior installs.
        let caseId: String
        /// Bundle resource basename (no extension).
        let resourceName: String
        let displayTitle: String
    }

    static let allSamples: [SampleSpec] = [
        SampleSpec(
            caseId: "sample-madeline-soto",
            resourceName: "madeline_soto_case_data",
            displayTitle: "Murder of Madeline Soto"
        ),
    ]

    static func isSampleCaseId(_ id: String) -> Bool {
        id.hasPrefix("sample-")
    }

    // MARK: - First-run install

    /// Install all sample cases on a brand-new database. Idempotent — only
    /// fires when the user has never seen samples *and* the cases table is
    /// empty. After running it flips
    /// `AppSettings.sampleDataEverInstalled = true` so subsequent launches
    /// (including post-delete ones) won't silently re-add anything.
    ///
    /// Returns `true` if any sample was actually inserted, so the caller
    /// can reload its in-memory slices.
    @discardableResult
    static func installIfFirstRunCompleted(
        cases: [Case],
        settingsStore: SettingsStore
    ) -> Bool {
        guard !settingsStore.settings.sampleDataEverInstalled else { return false }
        defer {
            var s = settingsStore.settings
            s.sampleDataEverInstalled = true
            settingsStore.settings = s
            settingsStore.save()
        }
        // If the user already has data, just stamp the flag (no install) so
        // a later empty state doesn't trigger an unwanted seed.
        guard cases.isEmpty else { return false }

        var installed = false
        for spec in allSamples {
            do { try install(spec); installed = true }
            catch { NSLog("Timeliner: sample install failed for \(spec.caseId) — \(error.localizedDescription)") }
        }
        return installed
    }

    /// Wipe and reinstall every shipped sample. Used by the
    /// "Restore Sample Data" button.
    @discardableResult
    static func restoreAllSamples() throws -> Int {
        var count = 0
        for spec in allSamples {
            try install(spec)
            count += 1
        }
        return count
    }

    // MARK: - Per-sample install

    enum SampleError: Error, LocalizedError {
        case resourceMissing(String)
        case decodeFailed(String)
        var errorDescription: String? {
            switch self {
            case .resourceMissing(let name): return "Sample resource not found: \(name).json"
            case .decodeFailed(let s):       return "Sample decode failed: \(s)"
            }
        }
    }

    /// Delete any prior install of `spec` (cascading to its events / people
    /// / attachments) and write the canonical version into the database.
    static func install(_ spec: SampleSpec) throws {
        let payload = try loadPayload(resource: spec.resourceName)
        try wipeIfPresent(caseId: spec.caseId)
        try insertCase(spec: spec, payload: payload)
    }

    // MARK: - Internals

    private static func loadPayload(resource: String) throws -> SamplePayload {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "SampleData")
                ?? Bundle.main.url(forResource: resource, withExtension: "json")
        else {
            throw SampleError.resourceMissing(resource)
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(SamplePayload.self, from: data)
        } catch {
            throw SampleError.decodeFailed(error.localizedDescription)
        }
    }

    private static func wipeIfPresent(caseId: String) throws {
        let db = DatabaseService.shared
        guard try db.fetchCase(id: caseId) != nil else { return }
        // Mirror AppState.deleteCase's manual attachment cascade so polymorphic
        // attachment rows for the case + every event + every person are
        // cleared before the cascade-on-FK takes care of the rest.
        let allEvents = try db.fetchEvents(caseId: caseId)
        let allPeople = try db.fetchPeople(caseId: caseId)
        try db.deleteAttachments(parentType: .caseRecord, parentId: caseId)
        for ev in allEvents { try db.deleteAttachments(parentType: .event, parentId: ev.id) }
        for p in allPeople { try db.deleteAttachments(parentType: .person, parentId: p.id) }
        try db.deleteCase(id: caseId)
    }

    private static func insertCase(spec: SampleSpec, payload: SamplePayload) throws {
        let db = DatabaseService.shared
        let now = ISO8601DateFormatter().string(from: Date())

        // Build the case description as the JSON summary, with a small footer
        // pointing at the primary source so users can see where the data
        // came from.
        var description = payload.case_.summary
        if let primary = payload.metadata?.primary_source, !primary.isEmpty {
            description += "\n\n*Primary source: \(primary)*"
        }

        let aCase = Case(
            id: spec.caseId,
            title: payload.case_.name,
            caseDescription: description,
            status: caseStatus(for: payload.case_.status),
            pinned: false,
            createdAt: now,
            updatedAt: now
        )
        try db.insertCase(aCase)

        // People — keyed by JSON `id` so events can resolve their
        // `people_involved` references back to the inserted DB rows.
        var personByJsonId: [String: Person] = [:]
        for jp in payload.people {
            let person = Person(
                id: "\(spec.caseId)-\(jp.id)",
                caseId: spec.caseId,
                name: jp.full_name,
                role: mapRole(jp.role_category, fallback: jp.role).rawValue,
                notes: composePersonNotes(jp)
            )
            try db.savePerson(person)
            personByJsonId[jp.id] = person
        }

        // Events
        for je in payload.timeline_events {
            let dateISO = isoDate(date: je.date, time: je.time) ?? "1970-01-01T00:00:00Z"
            let event = Event(
                id: "\(spec.caseId)-\(je.id)",
                caseId: spec.caseId,
                title: je.title,
                dateStart: dateISO,
                dateEnd: nil,
                descriptionMarkdown: composeEventDescription(je),
                sourceURL: "",
                importance: mapImportance(je.category).rawValue,
                createdAt: now
            )
            try db.insertEvent(event)

            let linkedPersonIds = (je.people_involved ?? [])
                .compactMap { personByJsonId[$0]?.id }
            if !linkedPersonIds.isEmpty {
                try db.setPeople(linkedPersonIds, forEvent: event.id)
            }
        }
    }

    // MARK: - Mappings

    internal static func caseStatus(for raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("conviction") || lower.contains("closed") || lower.contains("resolved") {
            return CaseStatus.closed.rawValue
        }
        if lower.contains("cold") {
            return CaseStatus.cold.rawValue
        }
        return CaseStatus.active.rawValue
    }

    /// Map a JSON `role_category` (with a free-text `role` fallback for
    /// disambiguation) to the closest `PersonRole` enum case.
    internal static func mapRole(_ category: String?, fallback: String?) -> PersonRole {
        let cat = (category ?? "").lowercased()
        let fb  = (fallback ?? "").lowercased()
        if cat.contains("victim")     { return .victim }
        if cat.contains("suspect")    { return .suspect }
        if cat.contains("prosecution") || cat.contains("legal counsel") || fb.contains("attorney") {
            return .attorney
        }
        if cat.contains("law enforcement") || cat.contains("forensics") || fb.contains("detective") {
            return .detective
        }
        if cat.contains("witness") { return .witness }
        return .other
    }

    internal static func mapImportance(_ category: String?) -> Importance {
        switch category ?? "" {
        case "Day of Disappearance", "Body Recovery", "Resolution":
            return .critical
        case "Background - Pattern of Abuse", "Charges", "Arrest", "Court", "Memorial":
            return .high
        case "Pre-Disappearance", "Investigation", "Forensics", "Custody", "Legal Action":
            return .medium
        default:
            return .low   // Background, Tangential, missing
        }
    }

    /// Compose a markdown description from the JSON event fields. We bake the
    /// category, location, and source into the body so the user can read a
    /// single chunk without leaving the timeline row.
    private static func composeEventDescription(_ je: JSONEvent) -> String {
        var parts: [String] = []
        if !je.description.isEmpty { parts.append(je.description) }

        var meta: [String] = []
        if let cat = je.category, !cat.isEmpty { meta.append("**Category:** \(cat)") }
        if let loc = je.location, !loc.isEmpty { meta.append("**Location:** \(loc)") }
        if let src = je.source, !src.isEmpty   { meta.append("**Source:** \(src)") }
        if !meta.isEmpty {
            parts.append(meta.joined(separator: "  ·  "))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func composePersonNotes(_ jp: JSONPerson) -> String {
        var parts: [String] = []
        if !jp.role.isEmpty                         { parts.append("**Role:** \(jp.role)") }
        if let agency = jp.agency, !agency.isEmpty  { parts.append("**Agency:** \(agency)") }
        if !jp.description.isEmpty                  { parts.append(jp.description) }
        if let rel = jp.relationship_to_case, !rel.isEmpty { parts.append("*\(rel)*") }
        return parts.joined(separator: "\n\n")
    }

    /// Lenient date parsing for the sample format. Accepts YYYY,
    /// YYYY-MM, or YYYY-MM-DD; folds an optional `HH:mm` onto the date.
    /// Returns an ISO-8601 (zulu) string suitable for `Event.dateStart`.
    internal static func isoDate(date: String, time: String?) -> String? {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "-").map(String.init)
        let datePortion: String
        switch parts.count {
        case 1:
            // year-only — center the event on Jan 1 so the year-grouped
            // timeline sections sort correctly
            datePortion = "\(parts[0])-01-01"
        case 2:
            datePortion = "\(parts[0])-\(parts[1])-01"
        default:
            datePortion = trimmed
        }

        let timePortion: String
        if let t = time?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            // Accept "HH:mm" or "HH:mm:ss"
            if t.split(separator: ":").count == 2 {
                timePortion = "\(t):00"
            } else {
                timePortion = t
            }
        } else {
            timePortion = "00:00:00"
        }
        return "\(datePortion)T\(timePortion)Z"
    }

    // MARK: - JSON shape

    /// Decode raw JSON bytes into the `SamplePayload` shape — kept on a
    /// separate seam from `loadPayload` so tests can validate parsing
    /// without depending on `Bundle.main`.
    internal static func decodePayload(_ data: Data) throws -> SamplePayload {
        do {
            return try JSONDecoder().decode(SamplePayload.self, from: data)
        } catch {
            throw SampleError.decodeFailed(error.localizedDescription)
        }
    }

    /// Mirrors the JSON document at the top level. We ignore the extra
    /// catalog sections (`evidence_log`, `vehicles_of_interest`, …) for now
    /// — the model doesn't have a place for them, and the timeline + people
    /// alone make for a meaningful sample case.
    internal struct SamplePayload: Decodable {
        let case_: JSONCase
        let people: [JSONPerson]
        let timeline_events: [JSONEvent]
        let metadata: JSONMetadata?

        enum CodingKeys: String, CodingKey {
            case case_ = "case"
            case people, timeline_events, metadata
        }
    }

    internal struct JSONCase: Decodable {
        let id: String
        let name: String
        let summary: String
        let status: String
        let tags: [String]?
    }

    internal struct JSONPerson: Decodable {
        let id: String
        let full_name: String
        let role: String
        let role_category: String?
        let agency: String?
        let description: String
        let relationship_to_case: String?
    }

    internal struct JSONEvent: Decodable {
        let id: String
        let date: String
        let time: String?
        let category: String?
        let title: String
        let description: String
        let location: String?
        let people_involved: [String]?
        let source: String?
    }

    internal struct JSONMetadata: Decodable {
        let primary_source: String?
    }
}
