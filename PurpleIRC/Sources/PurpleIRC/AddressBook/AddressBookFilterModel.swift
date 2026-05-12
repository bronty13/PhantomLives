import Foundation

/// Filter state for the Address Book workspace's contact list. Value
/// type — bound from `AddressBookView` and consulted by the contact
/// list when deciding whether to render a row.
///
/// Filters are AND-combined: a contact must match every active filter
/// to appear in the list. The "all" / nil cases are no-ops, so a
/// freshly-constructed filter shows every contact.
struct AddressBookFilter: Equatable {
    var presence: PresenceFilter = .any
    var coverage: CoverageFilter = .any
    /// Only contacts tagged with this id appear. Nil = no tag filter.
    var tagID: UUID? = nil
    var recency: RecencyFilter = .any
    /// Substring (lower-cased) the user typed into the workspace
    /// search field. Matched against nick, every linked-nick string,
    /// note, richNotes, and the contact's hostmask history (current
    /// + recent). Empty = no search filter.
    var searchText: String = ""

    enum PresenceFilter: String, CaseIterable, Identifiable {
        case any, online, offline, unknown
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any:     return "All"
            case .online:  return "Online"
            case .offline: return "Offline"
            case .unknown: return "Unknown"
            }
        }
    }

    /// Network-coverage filter: how many distinct networks the contact
    /// is linked to. Power-user view; surfaces the multi-network
    /// contacts that justify the Person model.
    enum CoverageFilter: String, CaseIterable, Identifiable {
        case any
        case single        // one specific network
        case multi         // two or more
        case unlinked      // empty linkedNicks (transitional state)
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any:      return "Any coverage"
            case .single:   return "Single network"
            case .multi:    return "Multiple networks"
            case .unlinked: return "Unlinked (legacy)"
            }
        }
    }

    /// Recently-active filter sourced from the cross-network
    /// `allSightings` fold. "Active" means "saw a msg-kind sighting
    /// within the window."
    enum RecencyFilter: String, CaseIterable, Identifiable {
        case any
        case last24h
        case last7d
        case last30d
        case quiet      // no msg-kind sighting in 30+ days
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any:     return "All"
            case .last24h: return "Active in last 24h"
            case .last7d:  return "Active in last 7d"
            case .last30d: return "Active in last 30d"
            case .quiet:   return "Quiet 30d+"
            }
        }
    }

    /// True iff every active filter passes for the given contact.
    /// Caller supplies precomputed values for the cross-cutting facts
    /// (presence, last-msg sighting timestamp) so the filter doesn't
    /// have to redo the fold per row.
    func matches(entry: AddressEntry,
                 presence: WatchPresence,
                 lastMessageAt: Date?) -> Bool {
        switch self.presence {
        case .any: break
        case .online: if presence != .online { return false }
        case .offline: if presence != .offline { return false }
        case .unknown: if presence != .unknown { return false }
        }

        switch coverage {
        case .any: break
        case .single:
            // Exactly one distinct network. Treat "" (any-network
            // sentinel) as a single bucket so a migrated entry without
            // explicit links shows as "single."
            let nets = Set(entry.linkedNicks.map(\.networkSlug))
            if nets.count != 1 { return false }
        case .multi:
            let nets = Set(entry.linkedNicks.map(\.networkSlug))
            if nets.count < 2 { return false }
        case .unlinked:
            if !entry.linkedNicks.isEmpty { return false }
        }

        if let tagID, !entry.tagIDs.contains(tagID) { return false }

        switch recency {
        case .any: break
        case .last24h: if !inLast(seconds: 24 * 3600, lastMessageAt) { return false }
        case .last7d:  if !inLast(seconds: 7 * 24 * 3600, lastMessageAt) { return false }
        case .last30d: if !inLast(seconds: 30 * 24 * 3600, lastMessageAt) { return false }
        case .quiet:
            // "No msg in 30d+." If there's no record at all, also
            // counts as quiet (per the spec) — these are the people
            // you've gone silent with that this filter surfaces.
            if let lastMessageAt {
                if Date().timeIntervalSince(lastMessageAt) <= 30 * 24 * 3600 { return false }
            }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            let nickHit = entry.nick.lowercased().contains(q)
                || entry.linkedNicks.contains { $0.nick.lowercased().contains(q) }
            let noteHit = entry.note.lowercased().contains(q)
                || entry.richNotes.lowercased().contains(q)
            if !nickHit && !noteHit { return false }
        }
        return true
    }

    private func inLast(seconds: TimeInterval, _ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= seconds
    }

    /// True iff any non-default filter is active. Drives the workspace
    /// toolbar's "Clear filters" affordance.
    var isActive: Bool {
        presence != .any || coverage != .any || tagID != nil
            || recency != .any || !searchText.isEmpty
    }
}
