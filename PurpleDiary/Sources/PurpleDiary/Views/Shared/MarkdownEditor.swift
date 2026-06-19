import SwiftUI
import AppKit

/// A lean Markdown editor: an Edit/Preview toggle over a native `NSTextView`
/// (with macOS spellcheck + undo) plus a **format toolbar** that wraps the
/// selection in Markdown, and a rendered preview that lays out inline media in
/// place. The editor backend is an `NSViewRepresentable`-wrapped `NSTextView`
/// (not SwiftUI `TextEditor`) specifically because the toolbar needs the
/// selection range, which `TextEditor` doesn't expose. The toolbar pattern is
/// ported from `MusicJournal/Views/MarkdownEditor.swift`.
struct MarkdownEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 240
    /// Show the "Import…" button that merges a text file into the body.
    var allowsTextImport: Bool = true

    @State private var previewing = false
    @State private var importError: String?
    @StateObject private var actions = MarkdownActions()

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

            if !previewing {
                formatToolbar
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
                MarkdownTextView(text: $text, actions: actions)
                    .frame(minHeight: minHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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

    /// The Markdown format bar (Write mode only). Each button wraps the selection
    /// or prefixes the selected line(s). Underline is intentionally omitted —
    /// Markdown has no underline syntax, and emitting `<u>` would show as literal
    /// tags in the preview and exports.
    @ViewBuilder
    private var formatToolbar: some View {
        HStack(spacing: 4) {
            Group {
                toolButton("Bold", systemImage: "bold") { actions.wrap("**") }
                toolButton("Italic", systemImage: "italic") { actions.wrap("*") }
                toolButton("Strikethrough", systemImage: "strikethrough") { actions.wrap("~~") }
                toolButton("Inline code", systemImage: "chevron.left.forwardslash.chevron.right") { actions.wrap("`") }
            }
            sep
            Group {
                toolTextButton("H1") { actions.linePrefix("# ") }
                toolTextButton("H2") { actions.linePrefix("## ") }
                toolTextButton("H3") { actions.linePrefix("### ") }
            }
            sep
            Group {
                toolButton("Bullet list", systemImage: "list.bullet") { actions.linePrefix("- ") }
                toolButton("Numbered list", systemImage: "list.number") { actions.linePrefix("1. ") }
                toolButton("Checklist", systemImage: "checklist") { actions.linePrefix("- [ ] ") }
                toolButton("Quote", systemImage: "text.quote") { actions.linePrefix("> ") }
            }
            sep
            toolButton("Clear formatting", systemImage: "eraser") { actions.clearFormatting() }
            Spacer()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var sep: some View { Divider().frame(height: 14) }

    private func toolButton(_ help: String, systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage) }
            .help(help)
    }

    private func toolTextButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.semibold)).frame(minWidth: 20)
        }
        .help("Heading \(label.dropFirst())")
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

// MARK: - Pure formatting transforms (testable)

/// The string-level Markdown transforms behind the toolbar, factored out of the
/// `NSTextView` plumbing so the (off-by-one-prone) logic is unit-testable. Each
/// returns the replacement string for a region; `MarkdownActions` computes the
/// region and applies it through the text view for proper undo.
enum MarkdownFormat {
    /// `marker` + selection + `marker` (e.g. `**bold**`).
    static func wrapped(_ selected: String, marker: String) -> String {
        "\(marker)\(selected)\(marker)"
    }

    /// `marker` prefixed onto every line of `block`; a trailing empty line (after
    /// a final newline) is left alone so the prefix doesn't dangle past the text.
    static func linePrefixed(_ block: String, marker: String) -> String {
        let lines = block.components(separatedBy: "\n")
        return lines.enumerated().map { i, line in
            (i == lines.count - 1 && line.isEmpty) ? line : marker + line
        }.joined(separator: "\n")
    }

    /// Strips inline emphasis markers and leading line markers (headings, quotes,
    /// bullets, numbered items, checkboxes) from `block`. Best-effort, not a parser.
    static func cleared(_ block: String) -> String {
        var b = block
        for marker in ["**", "~~", "`", "*", "_"] {
            b = b.replacingOccurrences(of: marker, with: "")
        }
        return b.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(
                of: #"^\s*(#{1,6}\s+|>\s+|-\s\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)"#,
                with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }
}

// MARK: - Toolbar bridge

/// Holds the live `NSTextView` so the format toolbar can act on the current
/// selection. Owned by `MarkdownEditor` via `@StateObject`. All edits route
/// through `shouldChangeText`/`didChangeText` so undo and the SwiftUI binding
/// stay correct. Ported/extended from MusicJournal's `MarkdownActions`.
@MainActor
final class MarkdownActions: ObservableObject {
    weak var textView: NSTextView?

    /// Wraps the current selection (or cursor) in `marker` on both sides. With no
    /// selection, leaves the cursor between the markers to type the inner text.
    func wrap(_ marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let nsString = tv.string as NSString
        let selected = nsString.substring(with: range)
        let replacement = MarkdownFormat.wrapped(selected, marker: marker)
        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        let cursor = selected.isEmpty
            ? range.location + (marker as NSString).length
            : range.location + (replacement as NSString).length
        tv.setSelectedRange(NSRange(location: cursor, length: 0))
    }

    /// Prefixes `marker` at the start of every line intersecting the selection
    /// (so bullet/quote/checklist work across a multi-line selection; headings on
    /// the single current line). A trailing empty line isn't prefixed.
    func linePrefix(_ marker: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let replacement = MarkdownFormat.linePrefixed(block, marker: marker)
        guard tv.shouldChangeText(in: lineRange, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: lineRange, with: replacement)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: lineRange.location,
                                    length: (replacement as NSString).length))
    }

    /// Strips common Markdown markers from the selected line(s): inline emphasis
    /// (`**`, `*`, `_`, `~~`, `` ` ``) and leading line markers (headings, quotes,
    /// bullets, numbered items, checkboxes). Best-effort, not a parser.
    func clearFormatting() {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: sel)
        let cleaned = MarkdownFormat.cleared(ns.substring(with: lineRange))
        guard tv.shouldChangeText(in: lineRange, replacementString: cleaned) else { return }
        tv.textStorage?.replaceCharacters(in: lineRange, with: cleaned)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: lineRange.location,
                                    length: (cleaned as NSString).length))
    }
}

// MARK: - NSTextView wrapper

/// `NSViewRepresentable` around `NSTextView`: two-way `String` binding, native
/// spellcheck, undo, plain-text (markdown) storage. Hands its `NSTextView` to
/// `MarkdownActions` so the toolbar can mutate the selection.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var actions: MarkdownActions

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false                    // store plain markdown
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = text
        actions.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only overwrite when the bound text changed by something other than
        // direct typing (entry switch, inline-media insert, import) — avoids a
        // feedback loop and cursor reset.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        actions.textView = textView
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
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
