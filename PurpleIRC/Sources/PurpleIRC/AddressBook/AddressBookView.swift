import SwiftUI
import AppKit

/// Top-level view of the Address Book workspace window. Three-pane
/// NavigationSplitView: filter sidebar, contact list, contact detail.
/// Owns the selection + filter state. Honors
/// `ChatModel.pendingAddressBookSelection` to deeplink from elsewhere
/// in the app (sidebar context menu, Watchlist sheet, future hooks).
struct AddressBookView: View {
    @EnvironmentObject var model: ChatModel
    @State private var selection: Set<UUID> = []
    @State private var filter = AddressBookFilter()
    @State private var showManageTags: Bool = false
    @State private var showSuggestLinks: Bool = false
    @State private var pendingDeleteConfirmation: Bool = false

    var body: some View {
        NavigationSplitView {
            AddressBookFiltersSidebar(filter: $filter)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            AddressBookContactList(
                selection: $selection,
                filter: filter,
                pendingDeleteConfirmation: $pendingDeleteConfirmation,
                showSuggestLinks: $showSuggestLinks,
                showManageTags: $showManageTags
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            detailPane
        }
        .searchable(text: $filter.searchText,
                    placement: .toolbar,
                    prompt: "Search nicks, notes, hostmasks")
        .onAppear { consumePendingSelection() }
        .onChange(of: model.pendingAddressBookSelection) { _, _ in
            consumePendingSelection()
        }
        .confirmationDialog(
            "Delete \(selection.count > 1 ? "\(selection.count) contacts" : "this contact")?",
            isPresented: $pendingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                for id in selection {
                    model.settings.removeAddress(id: id)
                }
                selection.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showManageTags) {
            ContactTagManagerView(settings: model.settings)
        }
        .sheet(isPresented: $showSuggestLinks) {
            SuggestLinksSheet()
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if selection.count == 1, let id = selection.first,
           let idx = model.settings.settings.addressBook.firstIndex(where: { $0.id == id }) {
            ContactDetailView(entry: detailBinding(for: id, at: idx))
        } else if selection.count > 1 {
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("\(selection.count) contacts selected")
                    .font(.title3)
                Text("Use the bulk-operations menu in the list pane below.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Pick a contact").font(.title3)
                Text("Or click + in the list below to add a new one.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Per-row binding into `settings.addressBook` — id-based safe
    /// lookup so a delete-while-editing doesn't write out of bounds
    /// (same shape that fixed the 1.0.109 crash class).
    private func detailBinding(for id: UUID, at fallbackIndex: Int) -> Binding<AddressEntry> {
        Binding<AddressEntry>(
            get: {
                model.settings.settings.addressBook.first(where: { $0.id == id })
                    ?? model.settings.settings.addressBook[
                        min(fallbackIndex, model.settings.settings.addressBook.count - 1)]
            },
            set: { newValue in
                guard let i = model.settings.settings.addressBook
                    .firstIndex(where: { $0.id == id }) else { return }
                model.settings.settings.addressBook[i] = newValue
            }
        )
    }

    private func consumePendingSelection() {
        guard let id = model.pendingAddressBookSelection else { return }
        selection = [id]
        model.pendingAddressBookSelection = nil
    }
}

/// On-demand "Suggest Links" sheet — runs
/// `ContactLinker.suggestLinks` over the current address book + every
/// connected network's SeenStore + IRCv3 account-tag map and presents
/// the candidate list. Nothing is mutated until the user explicitly
/// accepts.
struct SuggestLinksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: ChatModel
    @State private var suggestions: [ContactLinkSuggestion] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Suggested Links").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()
            if suggestions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No candidates right now").font(.title3)
                    Text("Suggestions appear when a nick on a connected network shares a hostmask or services account with one of your existing contacts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(suggestions) { s in
                    HStack(spacing: 12) {
                        Image(systemName: s.reason == .sharedServicesAccount
                              ? "person.crop.circle.badge.checkmark"
                              : "network")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.nick).font(.system(.body, design: .monospaced))
                                Text("on \(s.networkSlug)").font(.caption).foregroundStyle(.secondary)
                            }
                            if let name = contactName(for: s.addressID) {
                                Text("→ link to \(name)").font(.caption).foregroundStyle(.tertiary)
                            }
                            Text(reasonLabel(s.reason))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Link") {
                            model.settings.linkNick(
                                addressID: s.addressID,
                                networkSlug: s.networkSlug,
                                nick: s.nick,
                                source: s.asLinkedNickSource)
                            reload()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 540, height: 420)
        .onAppear { reload() }
    }

    private func reload() {
        suggestions = ContactLinker.suggestLinks(
            in: model.settings.settings.addressBook,
            seen: model.botEngine.seenStore,
            connections: model.connections)
    }

    private func contactName(for id: UUID) -> String? {
        model.settings.settings.addressBook.first(where: { $0.id == id })?.nick
    }

    private func reasonLabel(_ r: ContactLinkSuggestion.Reason) -> String {
        switch r {
        case .sharedHostmask:        return "Shares a hostmask with this contact"
        case .sharedServicesAccount: return "Shares an IRCv3 services account with this contact"
        }
    }
}
