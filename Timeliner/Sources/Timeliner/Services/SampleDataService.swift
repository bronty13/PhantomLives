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
        SampleSpec(
            caseId: "sample-harmony-montgomery",
            resourceName: "harmony_montgomery_case_data",
            displayTitle: "Murder of Harmony Montgomery"
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

    /// Map a JSON `role_category` (when present) or freeform `role` string
    /// to the closest `PersonRole` enum case. Different sample sources use
    /// different shapes — Madeline Soto carries a normalized `role_category`
    /// while Harmony Montgomery only has the freeform `role` — so we check
    /// both fields uniformly. Matching is keyword-based to handle composite
    /// strings like "Biological Mother / Witness / Civil Plaintiff".
    internal static func mapRole(_ category: String?, fallback: String?) -> PersonRole {
        let combined = ((category ?? "") + " | " + (fallback ?? "")).lowercased()
        // "Suspect / Convicted Defendant" should land on .suspect even though
        // it also contains "convicted" — check suspect/defendant first so
        // legitimate suspect rows beat the witness fallback below.
        if combined.contains("suspect") || combined.contains("defendant")
            || combined.contains("convicted offender") { return .suspect }
        // "Biological Mother / Witness" is primarily a witness, so match
        // witness before victim — otherwise composite roles all collapse to
        // the wrong bucket.
        if combined.contains("witness") { return .witness }
        if combined.contains("victim") { return .victim }
        if combined.contains("attorney") || combined.contains("prosecut")
            || combined.contains("legal counsel") { return .attorney }
        if combined.contains("law enforcement") || combined.contains("forensics")
            || combined.contains("detective") || combined.contains("officer")
            || combined.contains("sergeant") || combined.contains("corporal")
            || combined.contains("captain") || combined.contains("special agent")
            || combined.contains("medical examiner") || combined.contains("crime analyst")
            || combined.contains("crime scene") { return .detective }
        return .other
    }

    internal static func mapImportance(_ category: String?) -> Importance {
        switch category ?? "" {
        // Critical — the act, the discovery, the verdict / sentencing
        case "Day of Disappearance", "Body Recovery", "Resolution",
             "Homicide", "Verdict", "Sentencing":
            return .critical
        // High — abuse pattern, body movement, charges, arrests, court
        // proceedings, last-known sightings of the victim
        case "Background - Pattern of Abuse", "Charges", "Charge", "Arrest",
             "Court", "Memorial", "Abuse", "Concealment",
             "Last Sighting", "Last Contact", "Trial",
             "Court / Custody":
            return .high
        // Medium — investigation, civil/probate proceedings, witness statements,
        // government reports, child welfare touchpoints
        case "Pre-Disappearance", "Investigation", "Forensics", "Custody",
             "Legal Action", "Court / Pretrial", "Civil", "Civil / Probate",
             "Government Report", "Witness Account", "Child Welfare",
             "Concern Raised", "Welfare Fraud", "Conviction (Other)":
            return .medium
        default:
            // Background, Tangential, missing — and any future category we
            // forget to tag explicitly defaults to .low rather than crashing.
            return .low
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

        var lifeline: [String] = []
        if let dob = jp.dob, !dob.isEmpty { lifeline.append("**Born:** \(dob)") }
        if let dod = jp.dod, !dod.isEmpty { lifeline.append("**Died:** \(dod)") }
        if !lifeline.isEmpty {
            parts.append(lifeline.joined(separator: "  ·  "))
        }

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

    /// Mirrors the JSON document at the top level. The shape is intentionally
    /// lenient — different curated sample sources use different field names
    /// (Madeline Soto: `name`/`timeline_events`/`people_involved`/`full_name`;
    /// Harmony Montgomery: `title`/`events`/`people`/`name`) — so each
    /// nested struct decodes both variants and ignores catalog sections
    /// (`evidence_log`, `vehicles_of_interest`, …) that don't map to any
    /// model in Timeliner.
    internal struct SamplePayload: Decodable {
        let case_: JSONCase
        let people: [JSONPerson]
        let timeline_events: [JSONEvent]
        let metadata: JSONMetadata?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            self.case_ = try c.decode(JSONCase.self, forKey: AnyKey("case"))
            self.people = try c.decode([JSONPerson].self, forKey: AnyKey("people"))
            // Accept either `timeline_events` (Madeline shape) or `events`
            // (Harmony shape). One of them must be present.
            if let evs = try? c.decode([JSONEvent].self, forKey: AnyKey("timeline_events")) {
                self.timeline_events = evs
            } else {
                self.timeline_events = try c.decode([JSONEvent].self, forKey: AnyKey("events"))
            }
            self.metadata = try? c.decode(JSONMetadata.self, forKey: AnyKey("metadata"))
        }
    }

    internal struct JSONCase: Decodable {
        let id: String
        /// Display title — accepts either `name` or `title` field.
        let name: String
        /// Combined summary + outcome (Harmony shape uses both).
        let summary: String
        let status: String

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            self.id = try c.decode(String.self, forKey: AnyKey("id"))
            if let n = try? c.decode(String.self, forKey: AnyKey("name")) {
                self.name = n
            } else {
                self.name = try c.decode(String.self, forKey: AnyKey("title"))
            }
            self.status = try c.decode(String.self, forKey: AnyKey("status"))
            let summary = (try? c.decode(String.self, forKey: AnyKey("summary"))) ?? ""
            let outcome = (try? c.decode(String.self, forKey: AnyKey("outcome"))) ?? ""
            self.summary = outcome.isEmpty
                ? summary
                : (summary + (summary.isEmpty ? "" : "\n\n") + "**Outcome:** " + outcome)
        }
    }

    internal struct JSONPerson: Decodable {
        let id: String
        /// Display name — accepts either `full_name` or `name`.
        let full_name: String
        let role: String
        let role_category: String?
        let agency: String?
        /// Long-form description — accepts either `description` or `notes`.
        let description: String
        let relationship_to_case: String?
        let dob: String?
        let dod: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            self.id = try c.decode(String.self, forKey: AnyKey("id"))
            if let n = try? c.decode(String.self, forKey: AnyKey("full_name")) {
                self.full_name = n
            } else {
                self.full_name = try c.decode(String.self, forKey: AnyKey("name"))
            }
            self.role = (try? c.decode(String.self, forKey: AnyKey("role"))) ?? ""
            self.role_category = try? c.decode(String.self, forKey: AnyKey("role_category"))
            self.agency = try? c.decode(String.self, forKey: AnyKey("agency"))
            self.description = (try? c.decode(String.self, forKey: AnyKey("description")))
                ?? (try? c.decode(String.self, forKey: AnyKey("notes")))
                ?? ""
            self.relationship_to_case = try? c.decode(String.self, forKey: AnyKey("relationship_to_case"))
            self.dob = try? c.decode(String.self, forKey: AnyKey("dob"))
            self.dod = try? c.decode(String.self, forKey: AnyKey("dod"))
        }
    }

    internal struct JSONEvent: Decodable {
        let id: String
        let date: String
        let time: String?
        let category: String?
        let title: String
        let description: String
        let location: String?
        /// Linked person IDs — accepts either `people_involved` or `people`.
        let people_involved: [String]?
        let source: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            self.id = try c.decode(String.self, forKey: AnyKey("id"))
            self.date = try c.decode(String.self, forKey: AnyKey("date"))
            self.time = try? c.decode(String.self, forKey: AnyKey("time"))
            self.category = try? c.decode(String.self, forKey: AnyKey("category"))
            self.title = try c.decode(String.self, forKey: AnyKey("title"))
            self.description = (try? c.decode(String.self, forKey: AnyKey("description"))) ?? ""
            self.location = try? c.decode(String.self, forKey: AnyKey("location"))
            self.people_involved = (try? c.decode([String].self, forKey: AnyKey("people_involved")))
                ?? (try? c.decode([String].self, forKey: AnyKey("people")))
            self.source = try? c.decode(String.self, forKey: AnyKey("source"))
        }
    }

    internal struct JSONMetadata: Decodable {
        let primary_source: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            self.primary_source = try? c.decode(String.self, forKey: AnyKey("primary_source"))
        }
    }

    /// Ad-hoc CodingKey that accepts any string — used so we can decode the
    /// same field from one of several aliased keys.
    private struct AnyKey: CodingKey {
        var stringValue: String
        init(_ s: String) { self.stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
}
