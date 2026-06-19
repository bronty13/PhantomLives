import Foundation
import GRDB

/// A named journal (notebook). Every `Entry` belongs to exactly one journal via
/// `entry.journalId`. There is always a default journal (id `Journal.defaultId`,
/// created in the `v4_journals` migration) that pre-existing entries are
/// back-filled into and that can't be deleted.
///
/// A **hidden** journal is excluded from the Timeline, Calendar, Search, and
/// Insights until the user unlocks it for the session (Touch ID / passphrase via
/// the app-lock gate). At this phase "hidden" is an app-level *visibility* gate
/// only — the bytes are still under the single database DEK, exactly as
/// encrypted as everything else. Per-journal *cryptographic* separation (a
/// journal sealed under its own passphrase, opaque even with the app open) is a
/// later phase; see `SCOPING.md` → Phase 9 (Vault).
struct Journal: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID string
    var name: String
    var colorHex: String            // sidebar dot / accent
    var symbol: String              // SF Symbol name
    var isHidden: Bool
    var sortOrder: Int
    var createdAt: String           // ISO-8601
    /// Phase-9 vault: when true, the journal's text is sealed under a per-journal
    /// content key (see `VaultService`) — opaque even with the DB open until
    /// unlocked for the session.
    var isVault: Bool = false

    // Per-journal settings (v7_journal_settings — the "Journal Settings" sheet).
    // All default to today's behavior so existing journals are unchanged.
    var journalDescription: String = ""          // free-text note shown in the header
    var sortMode: String = JournalSortMode.dateDesc.rawValue
    var showInAllEntries: Bool = true            // appears in the "All Journals" view
    var showInOnThisDay: Bool = true             // appears in On This Day
    var showInCalendar: Bool = true              // appears in the Calendar
    var defaultTemplateId: String? = nil         // auto-applied to new blank entries; nil = None
    var concealContent: Bool = false             // blur entry previews in lists

    static let databaseTableName = "journals"

    /// Stable id of the always-present default journal (seeded by the migration;
    /// pre-existing entries are back-filled into it). Never deletable.
    static let defaultId = "00000000-0000-0000-0000-000000000001"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex = "color_hex"
        case symbol
        case isHidden = "is_hidden"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case isVault = "is_vault"
        case journalDescription = "description"
        case sortMode = "sort_mode"
        case showInAllEntries = "show_in_all_entries"
        case showInOnThisDay = "show_in_on_this_day"
        case showInCalendar = "show_in_calendar"
        case defaultTemplateId = "default_template_id"
        case concealContent = "conceal_content"
    }

    var isDefault: Bool { id == Self.defaultId }

    var sortModeValue: JournalSortMode { JournalSortMode(rawValue: sortMode) ?? .dateDesc }
}

extension Journal {
    static func newDraft(name: String,
                         colorHex: String = "#7C5CFF",
                         symbol: String = "book.closed",
                         isHidden: Bool = false,
                         sortOrder: Int = 0) -> Journal {
        Journal(
            id: UUID().uuidString,
            name: name,
            colorHex: colorHex,
            symbol: symbol,
            isHidden: isHidden,
            sortOrder: sortOrder,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

/// How a journal's entries are ordered in the timeline. The raw values are
/// persisted in `journals.sort_mode`; the comparator works on ISO-8601 strings
/// (which sort chronologically), so no `Date` parsing is needed. Applied only
/// when a single journal is selected — "All Journals" stays newest-first.
enum JournalSortMode: String, CaseIterable, Identifiable {
    case dateDesc = "date_desc"       // entry date, newest first (default)
    case dateAsc  = "date_asc"        // entry date, oldest first
    case edited   = "edited_desc"     // recently edited first
    case created  = "created_desc"    // recently created first

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateDesc: return "Entry Date (newest first)"
        case .dateAsc:  return "Entry Date (oldest first)"
        case .edited:   return "Recently Edited"
        case .created:  return "Recently Added"
        }
    }

    /// Order two entries per this mode.
    func ordered(_ a: Entry, _ b: Entry) -> Bool {
        switch self {
        case .dateDesc: return a.date > b.date
        case .dateAsc:  return a.date < b.date
        case .edited:   return a.updatedAt > b.updatedAt
        case .created:  return a.createdAt > b.createdAt
        }
    }
}
