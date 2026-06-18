import SwiftUI
import IRCKit

/// The single-window Platinum layout. Evokes the classic Ircle multi-window
/// arrangement consolidated into one resizable window (modern comfort):
/// a horizontal Channelbar of buffer buttons, the channel topic, the message
/// area beside the nick list, then the input line and a status bar.
struct ContentView: View {
    @EnvironmentObject var model: IrcleModel
    @EnvironmentObject var settingsStore: SettingsStore

    private var palette: PlatinumPalette {
        .forAppearance(settingsStore.settings.appearance)
    }

    var body: some View {
        let palette = palette
        VStack(spacing: 0) {
            Channelbar(palette: palette)
            Divider().overlay(palette.hairline)

            if let buffer = model.selectedBuffer {
                TopicBar(buffer: buffer, palette: palette)
                Divider().overlay(palette.hairline)
                HStack(spacing: 0) {
                    MessageListView(buffer: buffer, palette: palette,
                                    fontSize: settingsStore.settings.fontSize,
                                    showTimestamps: settingsStore.settings.showTimestamps)
                    if buffer.kind == .channel {
                        Divider().overlay(palette.hairline)
                        NickListView(buffer: buffer, palette: palette)
                            .frame(width: 184)
                    }
                }
                Divider().overlay(palette.hairline)
                InputBarView(buffer: buffer, palette: palette)
            } else {
                WelcomePane(palette: palette)
            }

            Divider().overlay(palette.hairline)
            StatusBar(palette: palette)
        }
        .background(palette.windowBG)
        .frame(minWidth: 720, minHeight: 460)
    }
}

// MARK: - Channelbar (the signature horizontal buffer strip)

struct Channelbar: View {
    @EnvironmentObject var model: IrcleModel
    let palette: PlatinumPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.buffers) { buffer in
                    ChannelbarButton(buffer: buffer, palette: palette,
                                     selected: buffer.id == model.selectedBufferID)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(palette.paneBG)
    }
}

struct ChannelbarButton: View {
    @EnvironmentObject var model: IrcleModel
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette
    let selected: Bool

    private var glyph: String {
        switch buffer.kind {
        case .server:  return "•"
        case .channel: return buffer.joined ? "#" : "✕"
        case .query:   return "@"
        }
    }

    var body: some View {
        Button(action: { model.select(buffer) }) {
            HStack(spacing: 4) {
                Text(glyph).font(palette.chromeFontBold())
                    .foregroundColor(buffer.mentioned ? palette.errorText : palette.chromeText)
                Text(displayName).font(selected ? palette.chromeFontBold() : palette.chromeFont())
                    .foregroundColor(selected ? .white : palette.chromeText)
                    .lineLimit(1)
                if buffer.unread > 0 {
                    Text("\(buffer.unread)")
                        .font(palette.chromeFont(9))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(buffer.mentioned ? palette.errorText : palette.serverText)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(selected ? palette.selection : palette.paneBG)
            .platinumBevel(palette, raised: !selected,
                           fill: selected ? palette.selection : palette.paneBG)
            .opacity(buffer.kind == .channel && !buffer.joined ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if buffer.kind != .server {
                Button("Close") { model.closeBuffer(buffer) }
            }
        }
    }

    /// Channel buffers drop the leading server label for brevity.
    private var displayName: String { buffer.name }
}

// MARK: - Topic bar

struct TopicBar: View {
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette

    var body: some View {
        HStack(spacing: 6) {
            Text("Topic:").font(palette.chromeFontBold())
                .foregroundColor(palette.chromeText)
            Text(buffer.topic.isEmpty ? topicPlaceholder : IRCText.stripFormatting(buffer.topic))
                .font(palette.chromeFont())
                .foregroundColor(palette.topicText)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .platinumBevel(palette, raised: false, fill: palette.textBG)
    }

    private var topicPlaceholder: String {
        switch buffer.kind {
        case .channel: return "(no topic set)"
        case .query:   return "Private conversation with \(buffer.name)"
        case .server:  return "Server console"
        }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var model: IrcleModel
    let palette: PlatinumPalette

    private var stateText: String {
        guard let s = model.session else { return "Not connected" }
        switch s.state {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .failed(let r): return "Error: \(r)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.session?.isConnected == true ? palette.joinText : palette.partText)
                .frame(width: 8, height: 8)
            Text(stateText).font(palette.chromeFont())
            if let nick = model.session?.nick {
                Text("•").foregroundColor(palette.timestamp)
                Text(nick).font(palette.chromeFontBold())
            }
            Spacer()
            if let host = model.session?.displayName {
                Text(host).font(palette.chromeFont()).foregroundColor(palette.timestamp)
            }
        }
        .foregroundColor(palette.chromeText)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(palette.paneBG)
    }
}

// MARK: - Welcome / disconnected pane

struct WelcomePane: View {
    @EnvironmentObject var model: IrcleModel
    let palette: PlatinumPalette

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Ircle")
                .font(.custom("Geneva", size: 40).bold())
                .foregroundColor(palette.chromeText)
            Text("A nostalgic Mac IRC client")
                .font(palette.chromeFont(13))
                .foregroundColor(palette.timestamp)
            Button("Connect") { model.connectDefault() }
                .font(palette.chromeFontBold())
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Text("⌘K to connect · ⌘, for settings")
                .font(palette.chromeFont(11))
                .foregroundColor(palette.timestamp)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.textBG)
    }
}
