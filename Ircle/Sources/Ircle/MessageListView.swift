import SwiftUI
import IRCKit

/// The central message area — the classic Ircle channel window. Monospaced
/// (Monaco), colored by line kind, auto-scrolls to the newest line.
struct MessageListView: View {
    @ObservedObject var buffer: IrcleBuffer
    let palette: PlatinumPalette
    let fontSize: Double
    let showTimestamps: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(buffer.lines) { line in
                        MessageRow(line: line, palette: palette,
                                   fontSize: fontSize, showTimestamps: showTimestamps)
                            .id(line.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Anchor for auto-scroll.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.textBG)
            .onChange(of: buffer.lines.count) { _, _ in
                withAnimation(.none) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private static let bottomAnchor = "ircle.messages.bottom"
}

struct MessageRow: View {
    let line: IrcleLine
    let palette: PlatinumPalette
    let fontSize: Double
    let showTimestamps: Bool

    private var font: Font { palette.messageFont(fontSize) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if showTimestamps {
                Text(Self.time(line.timestamp))
                    .font(font).foregroundColor(palette.timestamp)
            }
            Text(decorated)
                .font(font)
                .foregroundColor(palette.color(for: line.kind))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 0.5)
        .background(line.isMention ? palette.mentionBG : .clear)
    }

    /// Build the classic line prefix per kind. mIRC codes are stripped for the
    /// MVP plain-text path (full color rendering is a later enhancement).
    private var decorated: String {
        let text = IRCText.stripFormatting(line.text)
        switch line.kind {
        case .message:
            let who = line.sender ?? "?"
            return "<\(who)> \(text)"
        case .action:
            return "* \(line.sender ?? "?") \(text)"
        case .notice:
            return "-\(line.sender ?? "?")- \(text)"
        case .join, .part, .quit, .nickChange, .mode, .topic:
            return "*** \(text)"
        case .motd, .system:
            return text
        case .error:
            return "!!! \(text)"
        }
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
