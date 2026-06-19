import SwiftUI
import AppKit

/// The DCC Transfers window — inbound file offers you can accept or decline,
/// with live progress. (DCC chat + initiating transfers come later.)
struct DCCTransfersView: View {
    @EnvironmentObject var dcc: IrcleDCC
    @EnvironmentObject var settingsStore: SettingsStore

    private var palette: PlatinumPalette { .forAppearance(settingsStore.settings.appearance) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DCC Transfers").font(palette.chromeFontBold())
                Spacer()
                Button("Clear finished") { dcc.clearFinished() }
                    .disabled(!dcc.items.contains { $0.state.isTerminal })
            }
            .padding(8).background(palette.paneBG)
            Divider().overlay(palette.hairline)

            if dcc.items.isEmpty {
                VStack(spacing: 6) {
                    Text("No transfers.").font(palette.chromeFontBold())
                    Text("When someone offers you a file via DCC SEND, it appears here to accept.")
                        .font(palette.chromeFont()).foregroundColor(palette.timestamp)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
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
}

private struct DCCRow: View {
    @EnvironmentObject var dcc: IrcleDCC
    @ObservedObject var item: DCCItem
    let palette: PlatinumPalette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).font(palette.chromeFontBold()).lineLimit(1)
                Text("from \(item.peer) · \(sizeText)")
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
