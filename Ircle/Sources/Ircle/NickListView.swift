import SwiftUI

/// The right-hand nick list — the classic Ircle "N users" pane with the member
/// roster and a row of action buttons beneath it.
struct NickListView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette
    @State private var selectedNick: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header: "#chan: N users" + a Faces-window button.
            HStack(spacing: 4) {
                Text("\(buffer.name): \(buffer.users.count) user\(buffer.users.count == 1 ? "" : "s")")
                    .font(palette.chromeFontBold())
                    .foregroundColor(palette.chromeText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: { openWindow(id: "faces") }) {
                    Text("Faces").font(palette.chromeFont())
                        .foregroundColor(palette.chromeText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .platinumBevel(palette, raised: true)
                }
                .buttonStyle(.plain)
                .help("Open the Faces window")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(palette.paneBG)

            Divider().overlay(palette.hairline)

            // Roster
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(buffer.users) { user in
                        NickRow(user: user, palette: palette,
                                selected: user.nick == selectedNick)
                            .onTapGesture { selectedNick = user.nick }
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.textBG)

            Divider().overlay(palette.hairline)

            // Action buttons (classic Op/Msg/Whois/Query row)
            actionButtons
                .padding(6)
                .background(palette.paneBG)
        }
        .background(palette.paneBG)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch settingsStore.settings.interfaceStyle {
        case .clean:   cleanActionButtons
        case .classic: classicActionButtons
        }
    }

    /// Minimal set (the default "Clean" layout).
    private var cleanActionButtons: some View {
        let nick = selectedNick
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                NickActionButton("Query", palette: palette, enabled: nick != nil) {
                    if let n = nick { openQuery(n) }
                }
                NickActionButton("Whois", palette: palette, enabled: nick != nil) {
                    if let n = nick { send("WHOIS \(n)") }
                }
            }
            HStack(spacing: 4) {
                NickActionButton("Op", palette: palette, enabled: nick != nil) {
                    if let n = nick { send("MODE \(buffer.name) +o \(n)") }
                }
                NickActionButton("DeOp", palette: palette, enabled: nick != nil) {
                    if let n = nick { send("MODE \(buffer.name) -o \(n)") }
                }
            }
        }
    }

    /// The full original-Ircle 3×3 cockpit grid (the "Classic" layout):
    ///   Op    Kick     Msg
    ///   DeOp  Ban      Cping
    ///   Whois BanKick  Query
    private var classicActionButtons: some View {
        let nick = selectedNick
        let on = nick != nil
        return VStack(spacing: 4) {
            // One-click channel-mode toggles (lit = active). Channels only.
            if buffer.kind == .channel { modeToggleRow }
            HStack(spacing: 4) {
                NickActionButton("Op", palette: palette, enabled: on) { ifNick { send("MODE \(buffer.name) +o \($0)") } }
                NickActionButton("Kick", palette: palette, enabled: on) { ifNick { send("KICK \(buffer.name) \($0)") } }
                NickActionButton("Msg", palette: palette, enabled: on) { ifNick { openQuery($0) } }
            }
            HStack(spacing: 4) {
                NickActionButton("DeOp", palette: palette, enabled: on) { ifNick { send("MODE \(buffer.name) -o \($0)") } }
                NickActionButton("Ban", palette: palette, enabled: on) { ifNick { send("MODE \(buffer.name) +b \($0)!*@*") } }
                NickActionButton("Cping", palette: palette, enabled: on) { ifNick { send("PRIVMSG \($0) :\u{01}PING\u{01}") } }
            }
            HStack(spacing: 4) {
                NickActionButton("Whois", palette: palette, enabled: on) { ifNick { send("WHOIS \($0)") } }
                NickActionButton("BanKick", palette: palette, enabled: on) { ifNick { send("MODE \(buffer.name) +b \($0)!*@*"); send("KICK \(buffer.name) \($0)") } }
                NickActionButton("Query", palette: palette, enabled: on) { ifNick { openQuery($0) } }
            }
        }
    }

    /// The classic `t n i p s m l k r` one-click channel-mode row. A lit cell =
    /// that mode is active; click toggles it. Parameterless modes can be set or
    /// cleared; `l`/`k` (which need a value) can only be cleared from here.
    private var modeToggleRow: some View {
        HStack(spacing: 2) {
            ForEach(Array("tnipsmlkr"), id: \.self) { m in
                let active = buffer.channelModes.contains(m)
                let needsParam = (m == "l" || m == "k")
                Button { toggleMode(m, active: active) } label: {
                    Text(String(m))
                        .font(palette.chromeFontBold())
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .foregroundColor(active ? .white : palette.chromeText)
                        .platinumBevel(palette, raised: !active,
                                       fill: active ? palette.selection : palette.paneBG)
                }
                .buttonStyle(.plain)
                .disabled(!active && needsParam)   // l/k need a value to set
                .help("Channel mode \(active ? "−" : "+")\(m)")
            }
        }
    }

    private func toggleMode(_ m: Character, active: Bool) {
        if active { send("MODE \(buffer.name) -\(m)") }
        else if m != "l" && m != "k" { send("MODE \(buffer.name) +\(m)") }
    }

    /// Run `body` with the selected nick if there is one.
    private func ifNick(_ body: (String) -> Void) {
        if let n = selectedNick { body(n) }
    }

    private func openQuery(_ nick: String) {
        guard let session = model.session(for: buffer) else { return }
        model.select(session.ensureQuery(nick))
    }

    private func send(_ raw: String) {
        model.session(for: buffer)?.runCommand("/\(raw)", in: buffer)
    }
}

struct NickRow: View {
    let user: IrcleUser
    let palette: PlatinumPalette
    let selected: Bool

    private var prefixColor: Color {
        switch user.prefix.first {
        case "~", "&", "@": return palette.errorText   // ops stand out
        case "%":           return palette.actionText
        case "+":           return palette.joinText
        default:            return palette.chromeText
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(user.prefix.isEmpty ? " " : user.prefix)
                .font(palette.chromeFontBold())
                .foregroundColor(prefixColor)
                .frame(width: 8)
            AvatarView(nick: user.nick, size: 15)
            Text(user.nick)
                .font(palette.chromeFont())
                .foregroundColor(selected ? .white : palette.chromeText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(selected ? palette.selection : .clear)
        .contentShape(Rectangle())
    }
}

struct NickActionButton: View {
    let title: String
    let palette: PlatinumPalette
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, palette: PlatinumPalette, enabled: Bool, action: @escaping () -> Void) {
        self.title = title; self.palette = palette; self.enabled = enabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(palette.chromeFont())
                .foregroundColor(enabled ? palette.chromeText : palette.timestamp)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .platinumBevel(palette, raised: true)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
