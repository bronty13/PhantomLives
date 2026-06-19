import SwiftUI

/// The in-app manual: loads the bundled `Manual.md` and renders it with the
/// lightweight `MarkdownParser`, themed to match the app.
struct ManualView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    private var palette: PlatinumPalette { settingsStore.palette }
    private var blocks: [MarkdownBlock] { MarkdownParser.parse(Self.manualText) }

    /// The bundled manual text (falls back to a friendly message if missing).
    static var manualText: String {
        if let url = Bundle.main.url(forResource: "Manual", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        return "# Manual unavailable\n\nThe manual resource couldn't be loaded."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block, palette: palette)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.textBG)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let palette: PlatinumPalette

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundColor(palette.normalText)
                .padding(.top, level <= 2 ? 10 : 3)
        case .paragraph(let t):
            inline(t).foregroundColor(palette.normalText)
        case .bullet(let t):
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundColor(palette.timestamp)
                inline(t).foregroundColor(palette.normalText)
            }.padding(.leading, 10)
        case .numbered(let t):
            HStack(alignment: .top, spacing: 6) {
                Text("–").foregroundColor(palette.timestamp)
                inline(t).foregroundColor(palette.normalText)
            }.padding(.leading, 10)
        case .quote(let t):
            inline(t).foregroundColor(palette.timestamp).italic()
                .padding(.leading, 12)
                .overlay(Rectangle().fill(palette.hairline).frame(width: 2), alignment: .leading)
        case .code(let t):
            Text(t)
                .font(.custom("Monaco", size: 11))
                .foregroundColor(palette.normalText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(palette.paneBG)
        case .rule:
            Rectangle().fill(palette.hairline).frame(height: 1).padding(.vertical, 4)
        }
    }

    /// Render inline Markdown spans (bold/italic/code/links) without imposing
    /// block structure.
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 19
        case 3: return 16
        default: return 14
        }
    }
}
