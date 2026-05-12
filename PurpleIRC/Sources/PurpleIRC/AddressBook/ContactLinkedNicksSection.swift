import SwiftUI

/// Person-model section in the contact detail pane: shows every
/// (network, nick) binding on this contact, lets the user link
/// another or unlink existing ones. The "any-network" sentinel
/// (`networkSlug == ""`) renders as "All networks" so users
/// understand legacy migrated entries at a glance.
struct ContactLinkedNicksSection: View {
    @Binding var entry: AddressEntry
    @EnvironmentObject var model: ChatModel
    @State private var newNetworkSlug: String = ""
    @State private var newNick: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.linkedNicks.isEmpty {
                Text("No bindings yet. Upsert via the store auto-seeds one from the primary nick.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(entry.linkedNicks) { ln in
                    HStack(spacing: 8) {
                        Image(systemName: ln.networkSlug.isEmpty ? "globe" : "network")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ln.nick.isEmpty ? "(no nick)" : ln.nick)
                                .font(.system(.body, design: .monospaced))
                            Text(ln.networkSlug.isEmpty
                                 ? "All networks"
                                 : ln.networkSlug)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        sourceBadge(ln.source)
                        Button {
                            unlink(ln)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(entry.linkedNicks.count <= 1)
                        .help(entry.linkedNicks.count <= 1
                              ? "Can't remove the last binding (delete the contact instead)"
                              : "Unlink this binding")
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor)))
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Link another nick")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    networkPicker
                    TextField("Nick on that network", text: $newNick)
                        .textFieldStyle(.roundedBorder)
                    Button("Link") {
                        let trimmed = newNick.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        model.settings.linkNick(
                            addressID: entry.id,
                            networkSlug: newNetworkSlug,
                            nick: trimmed)
                        // Pull the freshly-updated entry back into the
                        // binding so the section re-renders against
                        // the live store.
                        if let updated = model.settings.settings.addressBook
                            .first(where: { $0.id == entry.id }) {
                            entry = updated
                        }
                        newNick = ""
                    }
                    .disabled(newNick.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var networkPicker: some View {
        Picker("", selection: $newNetworkSlug) {
            Text("All networks").tag("")
            ForEach(model.connections) { conn in
                let slug = SeenStore.slug(for: conn.displayName)
                Text(conn.displayName).tag(slug)
            }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    @ViewBuilder
    private func sourceBadge(_ source: LinkedNick.Source) -> some View {
        let text: String = {
            switch source {
            case .manual:     return "manual"
            case .migrated:   return "auto-migrated"
            case .accountTag: return "account match"
            case .hostmask:   return "host match"
            }
        }()
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }

    private func unlink(_ ln: LinkedNick) {
        guard model.settings.unlinkNick(addressID: entry.id, linkedNickID: ln.id) else {
            return
        }
        if let updated = model.settings.settings.addressBook
            .first(where: { $0.id == entry.id }) {
            entry = updated
        }
    }
}
