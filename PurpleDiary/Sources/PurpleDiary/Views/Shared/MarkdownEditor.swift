import SwiftUI
import AppKit

/// A lean Markdown editor: an Edit/Preview toggle over a native `NSTextView`
/// (via `TextEditor`) with macOS spellcheck, plus a rendered preview using
/// SwiftUI's built-in Markdown `AttributedString`. A richer toolbar editor
/// lives in `MusicJournal/Views/MarkdownEditor.swift` — port it here when the
/// formatting toolbar becomes a priority.
struct MarkdownEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 240

    @State private var previewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $previewing) {
                    Text("Write").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Spacer()
                Text("\(Entry.countWords(in: text)) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if previewing {
                ScrollView {
                    Text(rendered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
            } else {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }

    /// Render the markdown to an AttributedString. Falls back to plain text if
    /// the source has malformed markup. `.inlineOnlyPreservingWhitespace`
    /// keeps newlines so multi-paragraph entries read correctly.
    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attr = try? AttributedString(markdown: text, options: options) {
            return attr
        }
        return AttributedString(text)
    }
}
