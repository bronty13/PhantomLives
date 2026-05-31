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
    }

    var isDefault: Bool { id == Self.defaultId }
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
