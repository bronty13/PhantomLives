import SwiftUI
import IRCKit
import AppKit
import UniformTypeIdentifiers

// MARK: - Identities

struct IdentitiesSetup: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(settings.settings.identities) { ident in
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading) {
                                Text(ident.name.isEmpty ? "(unnamed)" : ident.name)
                                Text(ident.nick.isEmpty ? "(no nick)" : ident.nick)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(ident.id)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let ident = Identity()
                        settings.upsertIdentity(ident)
                        selection = ident.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selection {
                            settings.removeIdentity(id: id)
                            selection = settings.settings.identities.first?.id
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 240)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let id = selection,
               let i = settings.settings.identities.firstIndex(where: { $0.id == id }) {
                IdentityEditor(identity: Binding(
                    get: { settings.settings.identities[i] },
                    set: { settings.settings.identities[i] = $0 }
                ))
            } else {
                VStack {
                    Spacer()
                    Text("Create an identity with + to share nick, realname, SASL, and NickServ across servers.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }
        }
        .onAppear {
            if selection == nil { selection = settings.settings.identities.first?.id }
        }
    }
}

struct IdentityEditor: View {
    @Binding var identity: Identity
    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name (e.g. Work, Casual)", text: $identity.name)
            }
            Section("User") {
                TextField("Nickname", text: $identity.nick)
                TextField("Username", text: $identity.user)
                TextField("Real name", text: $identity.realName)
            }
            Section("Authentication (SASL)") {
                Picker("Mechanism", selection: $identity.saslMechanism) {
                    ForEach(SASLMechanism.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                if identity.saslMechanism == .plain {
                    TextField("Account (defaults to nick)", text: $identity.saslAccount)
                    SecureField("SASL password", text: $identity.saslPassword)
                }
            }
            Section("NickServ fallback") {
                SecureField("NickServ password (ignored when SASL is set)", text: $identity.nickServPassword)
                Text("Sent as PRIVMSG NickServ :IDENTIFY <password> after welcome, only when SASL is disabled.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

