import SwiftUI

/// The right-hand nick list — the classic Ircle "N users" pane with the member
/// roster and a row of action buttons beneath it.
struct NickListView: View {
    @EnvironmentObject var model: IrcleModel
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette
    @State private var selectedNick: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header: "#chan: N users"
            Text("\(buffer.name): \(buffer.users.count) user\(buffer.users.count == 1 ? "" : "s")")
                .font(palette.chromeFontBold())
                .foregroundColor(palette.chromeText)
                .lineLimit(1)
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

    private var actionButtons: some View {
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

    private func openQuery(_ nick: String) {
        guard let session = model.session else { return }
        let buf = session.ensureQuery(nick)
        model.select(buf)
    }

    private func send(_ raw: String) {
        model.session?.runCommand("/\(raw)", in: buffer)
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
        HStack(spacing: 2) {
            Text(user.prefix.isEmpty ? " " : user.prefix)
                .font(palette.chromeFontBold())
                .foregroundColor(prefixColor)
                .frame(width: 10)
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
