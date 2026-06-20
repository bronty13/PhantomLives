import SwiftUI
import AppKit
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
                                   fontSize: fontSize, showTimestamps: showTimestamps,
                                   copyAll: copyAll)
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

    /// Copy the whole buffer (timestamps + plain text) to the clipboard.
    private func copyAll() {
        let text = buffer.lines
            .map { MessageRow.plain($0, showTimestamps: showTimestamps) }
            .joined(separator: "\n")
        Pasteboard.copy(text)
    }
}

struct MessageRow: View {
    let line: IrcleLine
    let palette: PlatinumPalette
    let fontSize: Double
    let showTimestamps: Bool
    var copyAll: (() -> Void)? = nil

    // Per-element fonts. In the classic look every slot resolves to Monaco at
    // `fontSize`, so retro renders byte-identical; a Modern theme can give each
    // its own family/size/weight/italic/tracking.
    private var bodyFont: ResolvedFont {
        switch line.kind {
        case .join, .part, .quit, .nickChange, .mode, .topic, .motd, .system, .error:
            return palette.font(.systemLine, fallbackSize: fontSize)
        default:
            return palette.font(.messageBody, fallbackSize: fontSize)
        }
    }
    private var nickFont: ResolvedFont { palette.font(.nick, fallbackSize: fontSize) }
    private var stampFont: ResolvedFont { palette.font(.timestamp, fallbackSize: fontSize) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if showTimestamps {
                Text(Self.time(line.timestamp))
                    .ircleFont(stampFont).foregroundColor(palette.timestamp)
            }
            // Per-run fonts/colors live inside the AttributedString (mIRC
            // rendering), so no outer .font/.foregroundColor here.
            Text(attributed)
                .tracking(bodyFont.tracking)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 0.5)
        .background(line.isMention ? palette.mentionBG : .clear)
        // Drag-select doesn't always work across rows in a LazyVStack, so give
        // every line an explicit Copy (and Copy All) — the reliable way to grab
        // an error message out of the console.
        .contextMenu {
            Button("Copy") { Pasteboard.copy(MessageRow.plain(line, showTimestamps: showTimestamps)) }
            if let copyAll { Button("Copy All") { copyAll() } }
        }
    }

    /// Plain-text form of a line (the copyable representation), mirroring the
    /// on-screen prefix but with mIRC codes stripped.
    static func plain(_ line: IrcleLine, showTimestamps: Bool) -> String {
        let body = IRCText.stripFormatting(line.text)
        let core: String
        switch line.kind {
        case .message:    core = "<\(line.sender ?? "?")> \(body)"
        case .action:     core = "* \(line.sender ?? "?") \(body)"
        case .notice:     core = "-\(line.sender ?? "?")- \(body)"
        case .join, .part, .quit, .nickChange, .mode, .topic: core = "*** \(body)"
        case .error:      core = "!!! \(body)"
        case .motd, .system: core = body
        }
        guard showTimestamps else { return core }
        return "[\(time(line.timestamp))] \(core)"
    }

    /// Classic line prefix per kind + the body rendered with mIRC colors. The
    /// prefix is client-generated (plain); only the body carries mIRC codes.
    private var attributed: AttributedString {
        let body = bodyFont
        let nick = nickFont
        var out = AttributedString()
        switch line.kind {
        case .message:
            out += MircRenderer.plain("<\(line.sender ?? "?")> ", family: nick.family,
                                      size: Double(nick.size), weight: nick.weight, italic: nick.italic,
                                      color: line.isSelf ? palette.ownNick : palette.otherNick)
        case .action:
            out += MircRenderer.plain("* \(line.sender ?? "?") ", family: body.family,
                                      size: Double(body.size), weight: body.weight, italic: body.italic,
                                      color: palette.actionText)
        case .notice:
            out += MircRenderer.plain("-\(line.sender ?? "?")- ", family: body.family,
                                      size: Double(body.size), weight: body.weight, italic: body.italic,
                                      color: palette.noticeText)
        case .join, .part, .quit, .nickChange, .mode, .topic:
            out += MircRenderer.plain("*** ", family: body.family,
                                      size: Double(body.size), weight: body.weight, italic: body.italic,
                                      color: palette.color(for: line.kind))
        case .error:
            out += MircRenderer.plain("!!! ", family: body.family,
                                      size: Double(body.size), weight: body.weight, italic: body.italic,
                                      color: palette.errorText)
        case .motd, .system:
            break
        }
        out += MircRenderer.attributed(line.text, family: body.family, size: Double(body.size),
                                       baseWeight: body.weight, baseItalic: body.italic,
                                       baseColor: palette.color(for: line.kind),
                                       backgroundLuminance: palette.messageBackgroundLuminance)
        return out
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
