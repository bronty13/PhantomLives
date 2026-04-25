import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Spell-check support for chat input + the address book Markdown editor.
///
/// SwiftUI's `TextField` and `TextEditor` on macOS don't enable continuous
/// spell-check by default — the underlying NSTextView's
/// `isContinuousSpellCheckingEnabled` flag is OFF. Two pieces here:
///
/// 1. **Field-editor injector** — installs a custom NSWindowDelegate on every
///    window the app creates that returns a spell-check-enabled NSTextView
///    as the field editor. NSTextField (which SwiftUI's TextField wraps)
///    queries the window for its field editor when it becomes first-
///    responder; the same field editor is reused across every TextField in
///    that window. Setting it once means every TextField gets the red
///    underline-while-typing treatment for free.
///
/// 2. **`SpellCheckedTextEditor`** — NSViewRepresentable wrapping a
///    full-fledged NSTextView with spell-check on. Used in place of SwiftUI's
///    TextEditor wherever long-form text is being authored (currently the
///    Address Book entry's Markdown notes).

// MARK: - 1. Global text-field spell-check installer

/// Switches every NSControl-backed text edit (which is what SwiftUI
/// TextField uses on macOS) into spell-checking mode the moment editing
/// begins. The `NSControl.textDidBeginEditingNotification` callback's
/// userInfo carries the live field editor as `"NSFieldEditor"`; we just
/// toggle the relevant flags on it and every keystroke after that gets
/// the red-underline treatment.
///
/// Why this is safer than the previous attempts:
/// - Doesn't replace any window delegate.
/// - Doesn't substitute the field editor — only configures the one AppKit
///   already created.
/// - Fires for every NSTextField (and SwiftUI TextField) in the process,
///   regardless of which window owns it, including sheets and popovers.
@MainActor
enum SpellCheckBootstrap {
    private static var observer: NSObjectProtocol?

    /// Idempotent. Safe to call from `WindowGroup.onAppear` repeatedly —
    /// the NotificationCenter observer is registered exactly once.
    static func installOnAllWindows() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidBeginEditingNotification,
            object: nil, queue: .main
        ) { note in
            guard let editor = note.userInfo?["NSFieldEditor"] as? NSTextView
            else { return }
            editor.isContinuousSpellCheckingEnabled = true
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isGrammarCheckingEnabled = false
            // Off everywhere — IRC nicks and channel names look enough like
            // English to repeatedly trip these.
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
        }
    }
}

/// Compatibility shim — older revisions placed `.background(SpellCheckActivator())`
/// on the chat input. The notification-based bootstrap above handles the
/// configuration globally now, so this view is just an empty pass-through.
struct SpellCheckActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - 2. SpellCheckedTextEditor

/// Drop-in replacement for SwiftUI's `TextEditor` that turns on continuous
/// spell-check (red underline as you type). The wrapped NSTextView is
/// hosted in an NSScrollView so long notes scroll independently of the
/// surrounding form.
struct SpellCheckedTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Font applied to the text view. Defaults to a body-sized monospaced
    /// font (good for code snippets / Markdown source); pass a different
    /// value for prose-y editors.
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    /// Background color for the editor surface. Defaults to the system
    /// `textBackgroundColor` so the field reads correctly on light + dark.
    var background: NSColor = .textBackgroundColor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.string = text
        tv.font = font
        tv.backgroundColor = background
        tv.drawsBackground = true
        tv.allowsUndo = true
        tv.isRichText = false                  // plain UTF-8; Markdown is parsed at preview time
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.textContainerInset = NSSize(width: 4, height: 4)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        if tv.font != font { tv.font = font }
        if tv.backgroundColor != background { tv.backgroundColor = background }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckedTextEditor
        init(parent: SpellCheckedTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Round-trip through the binding so SwiftUI re-renders any
            // dependent views (live Markdown preview, character counts, etc.).
            parent.text = tv.string
        }
    }
}
