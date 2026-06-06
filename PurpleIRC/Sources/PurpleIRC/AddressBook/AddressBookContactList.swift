import SwiftUI

/// Middle pane of the Address Book workspace — the contact list with
/// multi-select, +/− bar, bulk-tag menu, and the Suggest Links
/// entry-point. Honors the filter from the sidebar; selection updates
/// the detail pane on the right.
struct AddressBookContactList: View {
    @EnvironmentObject var model: ChatModel
    @Binding var selection: Set<UUID>
    let filter: AddressBookFilter
    @Binding var pendingDeleteConfirmation: Bool
    @Binding var showSuggestLinks: Bool
    @Binding var showManageTags: Bool

    /// One filtered, presence-resolved row. Caching the resolved presence
    /// alongside the entry means the row doesn't recompute it (and the filter
    /// + row don't fold presence twice).
    private struct VisibleRow: Identifiable {
        let entry: AddressEntry
        let presence: WatchPresence
        var id: UUID { entry.id }
    }

    /// Cached filtered + sorted contact rows. The filter folds a cross-network
    /// sighting timeline (recency) and a presence lookup per contact — work
    /// that, as a computed property read by `body`, re-ran on *every* model
    /// change, including every incoming IRC line while connected. Now it's
    /// recomputed only when the address book, filter, or watch presence
    /// actually changes (see `refreshVisibleRows()` + the `.onChange` cluster).
    @State private var visibleRows: [VisibleRow] = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(visibleRows) { row in
                    AddressBookContactListRow(
                        entry: row.entry,
                        presence: row.presence
                    )
                    .tag(row.entry.id)
                    .contextMenu { rowMenu(for: row.entry) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 10) {
                Button(action: addContact) {
                    Image(systemName: "plus")
                }
                .help("Add a new contact")

                Button(action: { pendingDeleteConfirmation = true }) {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help(selection.count > 1
                      ? "Delete \(selection.count) contacts"
                      : "Delete contact")

                Menu {
                    Section("Tag selected") {
                        ForEach(model.settings.settings.contactTags) { tag in
                            Button(tag.name) { tagSelected(tag.id) }
                        }
                    }
                    Divider()
                    Button("Set watch on for selected") {
                        setWatchOn(true)
                    }
                    Button("Set watch off for selected") {
                        setWatchOn(false)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .disabled(selection.isEmpty)
                .frame(width: 26)
                .help("Bulk operations on selected contacts")

                Spacer()

                Button {
                    showSuggestLinks = true
                } label: {
                    Label("Suggest Links", systemImage: "link.badge.plus")
                }
                .help("Find candidate nicks to link under existing contacts (uses shared hostmask + IRCv3 account-tag heuristics)")

                Button {
                    showManageTags = true
                } label: {
                    Label("Tags", systemImage: "tag")
                }
                .help("Manage the global tag list")

                Text("\(visibleRows.count) / \(model.settings.settings.addressBook.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .onAppear { refreshVisibleRows() }
        .onChange(of: model.settings.settings.addressBook) { _, _ in refreshVisibleRows() }
        .onChange(of: filter) { _, _ in refreshVisibleRows() }
        .onChange(of: model.watchlist.presence) { _, _ in refreshVisibleRows() }
    }

    // MARK: - Derived data

    /// Recompute the cached, filtered + sorted contact rows. Folds the
    /// cross-network sighting timeline (only when the recency filter needs it)
    /// and the presence lookup once per contact. Decoupled from raw IRC
    /// traffic: recency buckets are coarse (24h/7d), so a few seconds of
    /// staleness between presence ticks is invisible and well worth not
    /// re-folding the whole address book on every incoming line.
    private func refreshVisibleRows() {
        let needsActivity = filter.recency != .any
        visibleRows = model.settings.settings.addressBook
            .compactMap { entry -> VisibleRow? in
                let p = presence(for: entry)
                let lastMsg = needsActivity ? lastMessageAt(for: entry) : nil
                guard filter.matches(entry: entry, presence: p, lastMessageAt: lastMsg) else {
                    return nil
                }
                return VisibleRow(entry: entry, presence: p)
            }
            .sorted { $0.entry.nick.lowercased() < $1.entry.nick.lowercased() }
    }

    private func presence(for entry: AddressEntry) -> WatchPresence {
        // First linked-nick that resolves to a known presence wins;
        // otherwise unknown.
        let nicks = entry.allLinkedNicksLowercased()
        for n in nicks {
            if let p = model.watchlist.presence[n] {
                return p
            }
        }
        return .unknown
    }

    private func lastMessageAt(for entry: AddressEntry) -> Date? {
        let sightings = entry.allSightings(
            across: model.connections,
            store: model.botEngine.seenStore)
        return sightings.first { $0.sighting.kind == "msg" }?.sighting.timestamp
    }

    // MARK: - Mutators

    private func addContact() {
        let existingNicks = Set(model.settings.settings.addressBook.map { $0.nick })
        var i = 1
        while existingNicks.contains("New Contact \(i)") { i += 1 }
        let entry = AddressEntry(nick: "New Contact \(i)", watch: false)
        model.settings.upsertAddress(entry)
        // Auto-select the new row so the detail pane snaps to it.
        selection = [entry.id]
    }

    private func tagSelected(_ tagID: UUID) {
        for id in selection {
            guard var entry = model.settings.settings.addressBook
                .first(where: { $0.id == id }) else { continue }
            if !entry.tagIDs.contains(tagID) {
                entry.tagIDs.append(tagID)
                model.settings.upsertAddress(entry)
            }
        }
    }

    private func setWatchOn(_ on: Bool) {
        for id in selection {
            guard var entry = model.settings.settings.addressBook
                .first(where: { $0.id == id }) else { continue }
            entry.watch = on
            model.settings.upsertAddress(entry)
        }
    }

    // MARK: - Row context menu

    @ViewBuilder
    private func rowMenu(for entry: AddressEntry) -> some View {
        Button("Open query with \(entry.nick)") {
            model.sendInput("/query \(entry.nick)")
        }
        Button("WHOIS \(entry.nick)") {
            model.sendInput("/whois \(entry.nick)")
        }
        Divider()
        if entry.watch {
            Button("Stop notifying when online") {
                var copy = entry
                copy.watch = false
                model.settings.upsertAddress(copy)
            }
        } else {
            Button("Notify when online") {
                var copy = entry
                copy.watch = true
                model.settings.upsertAddress(copy)
            }
        }
        Divider()
        Button("Remove contact", role: .destructive) {
            model.settings.removeAddress(id: entry.id)
            selection.remove(entry.id)
        }
    }
}
