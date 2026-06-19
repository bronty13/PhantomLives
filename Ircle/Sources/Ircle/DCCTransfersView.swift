import SwiftUI
import AppKit

/// The DCC Transfers window — inbound file offers you can accept or decline,
/// with live progress. (DCC chat + initiating transfers come later.)
struct DCCTransfersView: View {
    @EnvironmentObject var dcc: IrcleDCC
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow

    private var palette: PlatinumPalette { settingsStore.palette }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DCC Transfers").font(palette.chromeFontBold())
                Spacer()
                Button("Clear finished") { dcc.clearFinished() }
                    .disabled(!hasFinished)
            }
            .padding(8).background(palette.paneBG)
            Divider().overlay(palette.hairline)

            if dcc.items.isEmpty && dcc.chats.isEmpty {
                VStack(spacing: 6) {
                    Text("No transfers.").font(palette.chromeFontBold())
                    Text("DCC SEND offers (files) and DCC CHAT offers appear here to accept.")
                        .font(palette.chromeFont()).foregroundColor(palette.timestamp)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(dcc.chats) { chat in
                            DCCChatRow(session: chat, palette: palette,
                                       open: { openWindow(id: "dccchat", value: chat.id) })
                            Divider().overlay(palette.hairline)
                        }
                        ForEach(dcc.items) { item in
                            DCCRow(item: item, palette: palette)
                            Divider().overlay(palette.hairline)
                        }
                    }
                }
            }
        }
        .background(palette.windowBG)
    }

    private var hasFinished: Bool {
        dcc.items.contains { $0.state.isTerminal } || dcc.chats.contains { $0.state.isTerminal }
    }
}

private struct DCCChatRow: View {
    @EnvironmentObject var dcc: IrcleDCC
    @ObservedObject var session: DCCChatSession
    let palette: PlatinumPalette
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat with \(session.peer)").font(palette.chromeFontBold())
                Text(statusText).font(palette.chromeFont()).foregroundColor(palette.timestamp)
            }
            Spacer()
            switch session.state {
            case .offered:
                HStack(spacing: 6) {
                    Button("Accept") { dcc.acceptChat(session); open() }
                    Button("Decline") { dcc.declineChat(session) }
                }
            case .connecting, .connected:
                HStack(spacing: 6) {
                    Button("Open") { open() }
                    Button("Close") { dcc.closeChat(session) }
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var statusText: String {
        switch session.state {
        case .offered: return "Chat offered"
        case .connecting: return session.isOutgoing ? "Waiting for \(session.peer)…" : "Connecting…"
        case .connected: return "Connected"
        case .closed: return "Closed"
        case .declined: return "Declined"
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

private struct DCCRow: View {
    @EnvironmentObject var dcc: IrcleDCC
    @ObservedObject var item: DCCItem
    let palette: PlatinumPalette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).font(palette.chromeFontBold()).lineLimit(1)
                Text("\(item.isOutgoing ? "to" : "from") \(item.peer) · \(sizeText)")
                    .font(palette.chromeFont()).foregroundColor(palette.timestamp)
                statusLine
            }
            Spacer()
            controls
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)
    }

    @ViewBuilder private var statusLine: some View {
        switch item.state {
        case .offered:      Text("Offered").font(palette.chromeFont()).foregroundColor(palette.timestamp)
        case .connecting:   Text("Connecting…").font(palette.chromeFont()).foregroundColor(palette.serverText)
        case .transferring:
            VStack(alignment: .leading, spacing: 2) {
                if item.size > 0 {
                    ProgressView(value: Double(item.received), total: Double(item.size))
                        .frame(width: 180)
                }
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.received), countStyle: .file)) received")
                    .font(palette.chromeFont()).foregroundColor(palette.serverText)
            }
        case .completed:    Text("Completed").font(palette.chromeFont()).foregroundColor(palette.joinText)
        case .declined:     Text("Declined").font(palette.chromeFont()).foregroundColor(palette.timestamp)
        case .cancelled:    Text("Cancelled").font(palette.chromeFont()).foregroundColor(palette.timestamp)
        case .failed(let m): Text("Failed: \(m)").font(palette.chromeFont()).foregroundColor(palette.errorText).lineLimit(2)
        }
    }

    @ViewBuilder private var controls: some View {
        switch item.state {
        case .offered:
            HStack(spacing: 6) {
                Button("Accept") { dcc.accept(item) }
                Button("Decline") { dcc.decline(item) }
            }
        case .connecting, .transferring:
            Button("Cancel") { dcc.cancel(item) }
        case .completed:
            Button("Reveal") {
                if let dest = item.destination {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            }
        default:
            EmptyView()
        }
    }
}
