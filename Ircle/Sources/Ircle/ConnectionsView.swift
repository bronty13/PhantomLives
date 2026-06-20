import SwiftUI
import AppKit

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
            headerRow(palette)
            Divider().overlay(palette.hairline)
            List(selection: $selectedID) {
                ForEach(Array(servers.enumerated()), id: \.element.id) { idx, server in
                    row(idx + 1, server, palette).tag(server.id)
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

    // MARK: Rows

    private func headerRow(_ palette: PlatinumPalette) -> some View {
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

    private func row(_ nbr: Int, _ server: ServerProfile, _ palette: PlatinumPalette) -> some View {
        let s = session(for: server)
        return HStack(spacing: 6) {
            Text("\(nbr)").frame(width: 30, alignment: .leading)
                .foregroundColor(palette.timestamp)
            HStack(spacing: 5) {
                Circle().fill(statusColor(s, palette)).frame(width: 8, height: 8)
                Text(statusText(s)).foregroundColor(palette.chromeText)
            }
            .frame(width: 92, alignment: .leading)
            Text(s?.nick ?? server.nick).frame(width: 110, alignment: .leading)
                .foregroundColor(palette.chromeText).lineLimit(1)
            Text(server.host).foregroundColor(palette.timestamp).lineLimit(1)
            Spacer()
        }
        .font(palette.chromeFont())
        .contentShape(Rectangle())
        // Double-click connects, like the classic window.
        .onTapGesture(count: 2) { model.connect(to: server) }
    }

    private func statusText(_ s: IrcleSession?) -> String {
        switch s?.state {
        case .connected:    return "online"
        case .connecting:   return "connecting…"
        case .failed:       return "error"
        case .disconnected: return "offline"
        case nil:           return "—"
        }
    }

    private func statusColor(_ s: IrcleSession?, _ palette: PlatinumPalette) -> Color {
        switch s?.state {
        case .connected:  return palette.joinText
        case .connecting: return palette.partText
        case .failed:     return palette.errorText
        default:          return palette.timestamp.opacity(0.5)
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
            .disabled(session(forSelected: true)?.isConnected != true)
            Button("Edit…") { ConnectionsView.openSettings() }
                .disabled(selectedProfile == nil)
            Button("Nick…") {
                if let p = selectedProfile {
                    nickDraft = session(for: p)?.nick ?? p.nick
                    nickTarget = p
                }
            }
            .disabled(selectedProfile == nil)
            Spacer()
            Button("Server…") { ConnectionsView.openSettings() }
                .help("Add or edit servers in Settings")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.paneBG)
    }

    /// Session for the selected profile (helper for the Disconnect enable check).
    private func session(forSelected: Bool) -> IrcleSession? {
        guard let p = selectedProfile else { return nil }
        return session(for: p)
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
        guard !nick.isEmpty, let s = session(for: profile) else { nickTarget = nil; return }
        // Live session → send /NICK; the change reflects when the server confirms.
        model.submitInput("/nick \(nick)", in: s.serverBuffer)
        nickTarget = nil
    }

    /// Bring the Settings window forward (macOS 14 selector).
    static func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
