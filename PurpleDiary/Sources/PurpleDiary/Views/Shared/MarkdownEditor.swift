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
                    previewBody
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Preview body: if the text has inline media refs, render text/media
    /// segments in order so attachments appear in place; otherwise a single Text.
    @ViewBuilder
    private var previewBody: some View {
        if InlineMedia.hasInlineMedia(text) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(InlineMedia.parse(text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let s):
                        if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(rendered(s))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    case .media(let id, let caption):
                        InlineMediaView(attachmentId: id, caption: caption)
                    }
                }
            }
        } else {
            Text(rendered(text))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// Render a markdown string to an AttributedString. Falls back to plain text
    /// if malformed. `.inlineOnlyPreservingWhitespace` keeps newlines.
    private func rendered(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}

/// Renders one inline attachment (by id) inside the editor preview: a thumbnail
/// appropriate to its kind, with the caption beneath, tappable to open the full
/// viewer. Works for photos, video (poster + ▶), audio, PDF, and generic files.
struct InlineMediaView: View {
    let attachmentId: String
    let caption: String

    @State private var thumb: AttachmentThumb?
    @State private var showingViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { showingViewer = true } label: { tile }
                .buttonStyle(.plain)
            if !caption.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { thumb = try? DatabaseService.shared.attachmentThumb(id: attachmentId) }
        .sheet(isPresented: $showingViewer) {
            AttachmentViewerSheet(attachmentId: attachmentId)
        }
    }

    @ViewBuilder
    private var tile: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = thumb?.thumbnailData, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: glyph).font(.title2)
                    Text(thumb?.filename ?? "attachment").lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            if isPlayable {
                Image(systemName: "play.circle.fill")
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.5))
                    .font(.title).padding(6)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private var isPlayable: Bool { thumb?.isVideo == true || thumb?.isAudio == true }
    private var glyph: String {
        guard let thumb else { return "paperclip" }
        if thumb.isVideo { return "video" }
        if thumb.isAudio { return "music.note" }
        if thumb.isPDF { return "doc.richtext" }
        return "doc"
    }
}
