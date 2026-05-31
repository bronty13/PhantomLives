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
    /// Show the "Import…" button that merges a text file into the body.
    var allowsTextImport: Bool = true

    @State private var previewing = false
    @State private var importError: String?

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
                if allowsTextImport {
                    Button(action: importTextFile) {
                        Label("Import…", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Import a Markdown, text, or RTF file into this entry")
                }
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
        .alert("Couldn’t import that file", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    /// Pick a Markdown/text/RTF file and merge its contents into the body
    /// (smart: set when empty, append after a `---` separator otherwise).
    private func importTextFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = TextImportService.allowedContentTypes
        panel.message = "Import a text file into this entry"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = TextImportService.readText(from: url) else {
            importError = "“\(url.lastPathComponent)” couldn’t be read as text."
            return
        }
        text = TextImportService.mergedBody(existing: text, imported: imported)
        if previewing { previewing = false }   // jump back to Write so the merge is visible
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
