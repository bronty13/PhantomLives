import SwiftUI

/// Lightweight markdown renderer for event descriptions. Uses Foundation's
/// `AttributedString(markdown:)` (macOS 12+) for the parse — anything more
/// elaborate (line-by-line block rendering) lands in a Phase 2 upgrade.
struct MarkdownText: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}
