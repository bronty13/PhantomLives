// MarkdownEditor.swift
// Reusable Markdown text editor with a format toolbar, edit/preview toggle,
// and macOS native spellcheck. Stores plain Markdown in the bound String.
//
// Editor backend is `NSTextView` wrapped via `NSViewRepresentable` so the
// toolbar can mutate the current selection (SwiftUI `TextEditor` does not
// expose its selection range). Spellcheck uses the system `NSSpellChecker`,
// which is local on macOS — no network required.

import SwiftUI
import AppKit

/// Markdown editor with format toolbar and live preview toggle.
struct MarkdownEditor: View {
    @Binding var text: String
    /// Minimum height of the editor area (px). Caller should set this
    /// proportional to the expected content length.
    var minHeight: CGFloat = 120

    @State private var showPreview = false
    @StateObject private var actions = MarkdownActions()

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Picker("", selection: $showPreview) {
                    Image(systemName: "pencil").tag(false)
                    Image(systemName: "eye").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)

                if !showPreview {
                    Divider().frame(height: 16)
                    formatButtons
                }
                Spacer()
            }

            if showPreview {
                preview
            } else {
                MarkdownTextView(text: $text, actions: actions)
                    .frame(minHeight: minHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
        }
    }

    @ViewBuilder
    private var formatButtons: some View {
        Group {
            Button { actions.wrap("**") } label: { Image(systemName: "bold") }
                .help("Bold")
            Button { actions.wrap("*") } label: { Image(systemName: "italic") }
                .help("Italic")
            Button { actions.wrap("`") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                .help("Inline code")
            Divider().frame(height: 16)
            Button { actions.linePrefix("## ") } label: { Image(systemName: "textformat.size") }
                .help("Heading")
            Button { actions.linePrefix("- ") } label: { Image(systemName: "list.bullet") }
                .help("Bullet list")
            Button { actions.linePrefix("1. ") } label: { Image(systemName: "list.number") }
                .help("Numbered list")
            Button { actions.linePrefix("> ") } label: { Image(systemName: "text.quote") }
                .help("Quote")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    @ViewBuilder
    private var preview: some View {
        ScrollView {
            Group {
                if text.isEmpty {
                    Text("_Nothing to preview yet — switch to Edit mode and start typing._")
                        .foregroundStyle(.secondary)
                } else if let attr = try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attr)
                } else {
                    Text(text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .textSelection(.enabled)
        }
        .frame(minHeight: minHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3))
        )
    }
}

// MARK: - Toolbar bridge

/// Holds the live `NSTextView` reference so toolbar buttons can act on
/// the current selection. Owned by `MarkdownEditor` via `@StateObject`.
@MainActor
final class MarkdownActions: ObservableObject {
    weak var textView: NSTextView?

    /// Wraps the current selection (or empty cursor position) in `marker`
    /// on both sides. With no selection, places the cursor between the
    /// markers so the user can immediately type the inner text.
    func wrap(_ marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let nsString = tv.string as NSString
        let selected = nsString.substring(with: range)
        let replacement = "\(marker)\(selected)\(marker)"
        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        // Position cursor between the markers when no text was selected,
        // otherwise after the closing marker.
        let cursor: Int
        if selected.isEmpty {
            cursor = range.location + (marker as NSString).length
        } else {
            cursor = range.location + (replacement as NSString).length
        }
        tv.setSelectedRange(NSRange(location: cursor, length: 0))
    }

    /// Inserts `marker` at the start of the line(s) intersecting the
    /// current selection. Idempotent for already-prefixed lines.
    func linePrefix(_ marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let nsString = tv.string as NSString
        // Walk one character back so an empty cursor at the very start of
        // a line still picks up that line's range.
        let lineRange = nsString.lineRange(for: range)
        let lineStart = NSRange(location: lineRange.location, length: 0)
        guard tv.shouldChangeText(in: lineStart, replacementString: marker) else { return }
        tv.textStorage?.replaceCharacters(in: lineStart, with: marker)
        tv.didChangeText()
        let newCursor = NSRange(
            location: range.location + (marker as NSString).length,
            length: range.length
        )
        tv.setSelectedRange(newCursor)
    }
}

// MARK: - NSTextView wrapper

/// `NSViewRepresentable` wrapper around `NSTextView` providing two-way
/// binding to a Swift `String`, native spellcheck, and undo support.
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
        // Hand the toolbar coordinator a reference to this view's text view.
        actions.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only overwrite when the bound text was changed by something other
        // than direct typing — avoids a feedback loop and cursor reset.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            // Try to keep the cursor where it was if still in range.
            let length = (textView.string as NSString).length
            let safe = NSRange(
                location: min(selection.location, length),
                length: 0
            )
            textView.setSelectedRange(safe)
        }
        actions.textView = textView
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Push back into the SwiftUI binding.
            parent.text = tv.string
        }
    }
}
