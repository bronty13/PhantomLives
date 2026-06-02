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

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(visibleEntries) { entry in
                    AddressBookContactListRow(
                        entry: entry,
                        presence: presence(for: entry)
                    )
                    .tag(entry.id)
                    .contextMenu { rowMenu(for: entry) }
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

                Text("\(visibleEntries.count) / \(model.settings.settings.addressBook.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Derived data

    /// Address book filtered through the active filter, sorted by
    /// case-insensitive primary nick. Precomputes the cross-network
    /// fold (presence + last-msg time) per entry so the filter doesn't
    /// redo the work for every predicate evaluation.
    private var visibleEntries: [AddressEntry] {
        // The last-message time needs a cross-network sighting fold per
        // entry, so only pay for it when the recency filter actually uses
        // it (it's `.any` by default). Otherwise `matches` ignores the
        // value entirely.
        let needsActivity = filter.recency != .any
        return model.settings.settings.addressBook
            .filter { entry in
                filter.matches(
                    entry: entry,
                    presence: presence(for: entry),
                    lastMessageAt: needsActivity ? lastMessageAt(for: entry) : nil)
            }
            .sorted { lhs, rhs in
                lhs.nick.lowercased() < rhs.nick.lowercased()
            }
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
