import SwiftUI
import IRCKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem { Label("Connection", systemImage: "network") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
        }
        .frame(width: 460, height: 420)
    }
}

// MARK: - Connection

struct ConnectionSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var model: IrcleModel

    private var profileBinding: Binding<ServerProfile> {
        Binding(
            get: { settingsStore.settings.servers.first ?? ServerProfile() },
            set: { newValue in
                if settingsStore.settings.servers.isEmpty {
                    settingsStore.settings.servers = [newValue]
                } else {
                    settingsStore.settings.servers[0] = newValue
                }
            }
        )
    }

    var body: some View {
        let profile = profileBinding
        Form {
            Section("Server") {
                TextField("Name", text: profile.name)
                TextField("Host", text: profile.host)
                TextField("Port", value: profile.port, format: .number)
                Toggle("Use TLS (SSL)", isOn: profile.useTLS)
            }
            Section("Identity") {
                TextField("Nickname", text: profile.nick)
                TextField("Username", text: profile.user)
                TextField("Real name", text: profile.realName)
            }
            Section("Authentication") {
                Picker("SASL", selection: profile.saslMechanism) {
                    ForEach(SASLMechanism.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                if profile.wrappedValue.saslMechanism == .plain {
                    TextField("Account", text: profile.saslAccount)
                    SecureField("Password", text: profile.saslPassword)
                }
                SecureField("Server password (optional)", text: profile.serverPassword)
            }
            Section("Auto-join") {
                TextField("Channels (space-separated)", text: Binding(
                    get: { profile.wrappedValue.autoJoin.joined(separator: " ") },
                    set: { profile.wrappedValue.autoJoin = $0.split(separator: " ").map(String.init) }
                ))
            }
            Section {
                HStack {
                    Button("Connect") { model.connect(to: profile.wrappedValue) }
                    Button("Disconnect") { model.disconnect() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settingsStore.settings.appearance) {
                    ForEach(IrcleAppearance.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Messages") {
                Toggle("Show timestamps", isOn: $settingsStore.settings.showTimestamps)
                HStack {
                    Text("Font size")
                    Slider(value: $settingsStore.settings.fontSize, in: 9...18, step: 1)
                    Text("\(Int(settingsStore.settings.fontSize)) pt")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}
