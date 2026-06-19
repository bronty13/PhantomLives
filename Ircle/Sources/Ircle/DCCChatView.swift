import SwiftUI

/// A single DCC chat conversation window (one per accepted chat, addressed by
/// the session's UUID). Resolves the live `DCCChatSession` from the DCC store.
struct DCCChatView: View {
    @EnvironmentObject var dcc: IrcleDCC
    @EnvironmentObject var settingsStore: SettingsStore
    let sessionID: UUID

    private var palette: PlatinumPalette { settingsStore.palette }

    var body: some View {
        Group {
            if let session = dcc.chat(id: sessionID) {
                DCCChatBody(session: session, palette: palette)
            } else {
                Text("This DCC chat has closed.")
                    .font(palette.chromeFont()).foregroundColor(palette.timestamp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.windowBG)
    }
}

private struct DCCChatBody: View {
    @EnvironmentObject var dcc: IrcleDCC
    @ObservedObject var session: DCCChatSession
    let palette: PlatinumPalette
    @State private var input = ""

    private var connected: Bool { session.state == .connected }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DCC chat with \(session.peer)").font(palette.chromeFontBold())
                Spacer()
                Text(statusText).font(palette.chromeFont()).foregroundColor(statusColor)
            }
            .padding(8).background(palette.paneBG)
            Divider().overlay(palette.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(session.lines) { line in
                            Text(line.fromSelf ? "› \(line.text)" : "‹ \(line.text)")
                                .font(.custom("Monaco", size: 12))
                                .foregroundColor(line.fromSelf ? palette.ownNick : palette.normalText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .background(palette.textBG)
                .onChange(of: session.lines.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }

            Divider().overlay(palette.hairline)
            HStack(spacing: 6) {
                TextField(connected ? "Message…" : "Not connected", text: $input)
                    .textFieldStyle(.plain).font(.custom("Monaco", size: 12))
                    .onSubmit(send)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .platinumBevel(palette, raised: false, fill: palette.textBG)
                    .disabled(!connected)
                Button("Send", action: send).disabled(!connected || input.isEmpty)
            }
            .padding(6).background(palette.paneBG)
        }
    }

    private func send() {
        dcc.sendChat(session, input)
        input = ""
    }

    private var statusText: String {
        switch session.state {
        case .offered: return "Offered"
        case .connecting: return session.isOutgoing ? "Waiting for \(session.peer)…" : "Connecting…"
        case .connected: return "Connected"
        case .closed: return "Closed"
        case .declined: return "Declined"
        case .failed(let m): return "Failed: \(m)"
        }
    }
    private var statusColor: Color {
        switch session.state {
        case .connected: return palette.joinText
        case .failed: return palette.errorText
        default: return palette.timestamp
        }
    }
}
