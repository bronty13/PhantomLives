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
            // Per-run fonts/colors live inside the AttributedString (mIRC
            // rendering), so no outer .font/.foregroundColor here.
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 0.5)
        .background(line.isMention ? palette.mentionBG : .clear)
    }

    /// Classic line prefix per kind + the body rendered with mIRC colors. The
    /// prefix is client-generated (plain); only the body carries mIRC codes.
    private var attributed: AttributedString {
        var out = AttributedString()
        switch line.kind {
        case .message:
            out += MircRenderer.plain("<\(line.sender ?? "?")> ", size: fontSize,
                                      color: line.isSelf ? palette.ownNick : palette.otherNick)
        case .action:
            out += MircRenderer.plain("* \(line.sender ?? "?") ", size: fontSize, color: palette.actionText)
        case .notice:
            out += MircRenderer.plain("-\(line.sender ?? "?")- ", size: fontSize, color: palette.noticeText)
        case .join, .part, .quit, .nickChange, .mode, .topic:
            out += MircRenderer.plain("*** ", size: fontSize, color: palette.color(for: line.kind))
        case .error:
            out += MircRenderer.plain("!!! ", size: fontSize, color: palette.errorText)
        case .motd, .system:
            break
        }
        out += MircRenderer.attributed(line.text, size: fontSize,
                                       baseColor: palette.color(for: line.kind))
        return out
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
