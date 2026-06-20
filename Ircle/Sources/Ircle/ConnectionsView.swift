import SwiftUI
import AppKit
import IRCKit

/// The classic Ircle **Connections** window: every saved server in one place
/// with live status and Connect / Disconnect / Edit / Nick buttons. This is the
/// intuitive multi-server hub — connect to several networks without opening
/// Settings. Available in every interface style (⌘⇧K).
struct ConnectionsView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedID: UUID?
    @State private var nickTarget: ServerProfile?
    @State private var nickDraft: String = ""

    private var servers: [ServerProfile] { settingsStore.settings.servers }
    private var palette: PlatinumPalette { settingsStore.palette }

    /// The live session backing a profile, if one exists.
    private func session(for profile: ServerProfile) -> IrcleSession? {
        model.sessions.first { $0.profileID == profile.id }
    }

    var body: some View {
        let palette = palette
        VStack(spacing: 0) {
            ConnectionsRow.header(palette)
            Divider().overlay(palette.hairline)
            List(selection: $selectedID) {
                ForEach(Array(servers.enumerated()), id: \.element.id) { idx, server in
                    rowView(idx + 1, server, palette).tag(server.id)
                }
            }
            .listStyle(.plain)
            Divider().overlay(palette.hairline)
            footer(palette)
        }
        .background(palette.windowBG)
        .frame(minWidth: 380, minHeight: 260)
        .onAppear { if selectedID == nil { selectedID = servers.first?.id } }
        .sheet(item: $nickTarget) { profile in nickSheet(profile, palette) }
    }

    /// A connected server gets a row that observes its session (so the nick and
    /// status update live); a disconnected server gets a static row.
    @ViewBuilder
    private func rowView(_ nbr: Int, _ server: ServerProfile, _ palette: PlatinumPalette) -> some View {
        if let s = session(for: server) {
            ConnectionsRow(nbr: nbr, host: server.host, session: s, palette: palette)
                .onTapGesture(count: 2) { model.connect(to: server) }
        } else {
            ConnectionsRow.content(nbr: nbr, host: server.host, nick: server.nick,
                                   state: nil, palette: palette)
                .onTapGesture(count: 2) { model.connect(to: server) }
        }
    }

    // MARK: Footer

    private var selectedProfile: ServerProfile? {
        guard let id = selectedID else { return nil }
        return servers.first { $0.id == id }
    }

    private func footer(_ palette: PlatinumPalette) -> some View {
        HStack(spacing: 8) {
            Button("Connect") { if let p = selectedProfile { model.connect(to: p) } }
                .disabled(selectedProfile == nil)
            Button("Disconn.") {
                if let p = selectedProfile { session(for: p)?.disconnect() }
            }
            .disabled(selectedProfile.flatMap(session(for:))?.isConnected != true)
            // SettingsLink opens the Settings scene reliably (macOS 14); the tap
            // also tells the Servers tab which profile to pre-select.
            SettingsLink { Text("Edit…") }
                .simultaneousGesture(TapGesture().onEnded { model.pendingEditServerID = selectedID })
                .disabled(selectedProfile == nil)
            Button("Nick…") {
                if let p = selectedProfile {
                    nickDraft = session(for: p)?.nick ?? p.nick
                    nickTarget = p
                }
            }
            .disabled(selectedProfile == nil)
            Spacer()
            SettingsLink { Text("Server…") }
                .help("Add or edit servers in Settings")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.paneBG)
    }

    // MARK: Nick sheet

    private func nickSheet(_ profile: ServerProfile, _ palette: PlatinumPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change nickname on \(profile.name)")
                .font(palette.chromeFontBold())
            TextField("Nickname", text: $nickDraft)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { applyNick(profile) }
            HStack {
                Spacer()
                Button("Cancel") { nickTarget = nil }.keyboardShortcut(.cancelAction)
                Button("Change") { applyNick(profile) }.keyboardShortcut(.defaultAction)
                    .disabled(nickDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func applyNick(_ profile: ServerProfile) {
        let nick = nickDraft.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else { nickTarget = nil; return }
        // Set the nickname for this connection: update the saved profile (used
        // on the next connect, shown in the list, and what the sheet pre-fills),
        // and — if it's connected right now — change it live with /NICK too.
        if let idx = settingsStore.settings.servers.firstIndex(where: { $0.id == profile.id }) {
            settingsStore.settings.servers[idx].nick = nick
        }
        if let s = session(for: profile) {
            s.runCommand("/nick \(nick)", in: s.serverBuffer)
        }
        nickTarget = nil
    }
}

/// A single Connections row. When backed by a live session it's an
/// `@ObservedObject` so the nick + status update the instant they change.
struct ConnectionsRow: View {
    let nbr: Int
    let host: String
    @ObservedObject var session: IrcleSession
    let palette: PlatinumPalette

    var body: some View {
        ConnectionsRow.content(nbr: nbr, host: host, nick: session.nick,
                               state: session.state, palette: palette)
    }

    // MARK: Shared layout (used by both the live and static rows)

    static func header(_ palette: PlatinumPalette) -> some View {
        HStack(spacing: 6) {
            Text("Nbr").frame(width: 30, alignment: .leading)
            Text("Status").frame(width: 92, alignment: .leading)
            Text("Nickname").frame(width: 110, alignment: .leading)
            Text("Server")
            Spacer()
        }
        .font(palette.chromeFontBold())
        .foregroundColor(palette.chromeText)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(palette.paneBG)
    }

    @ViewBuilder
    static func content(nbr: Int, host: String, nick: String,
                        state: IRCConnectionState?, palette: PlatinumPalette) -> some View {
        HStack(spacing: 6) {
            Text("\(nbr)").frame(width: 30, alignment: .leading)
                .foregroundColor(palette.timestamp)
            HStack(spacing: 5) {
                Circle().fill(statusColor(state, palette)).frame(width: 8, height: 8)
                Text(statusText(state)).foregroundColor(palette.chromeText)
            }
            .frame(width: 92, alignment: .leading)
            Text(nick).frame(width: 110, alignment: .leading)
                .foregroundColor(palette.chromeText).lineLimit(1)
            Text(host).foregroundColor(palette.timestamp).lineLimit(1)
            Spacer()
        }
        .font(palette.chromeFont())
        .contentShape(Rectangle())
    }

    static func statusText(_ state: IRCConnectionState?) -> String {
        switch state {
        case .connected:    return "online"
        case .connecting:   return "connecting…"
        case .failed:       return "error"
        case .disconnected: return "offline"
        case nil:           return "—"
        }
    }

    static func statusColor(_ state: IRCConnectionState?, _ palette: PlatinumPalette) -> Color {
        switch state {
        case .connected:  return palette.joinText
        case .connecting: return palette.partText
        case .failed:     return palette.errorText
        default:          return palette.timestamp.opacity(0.5)
        }
    }
}
