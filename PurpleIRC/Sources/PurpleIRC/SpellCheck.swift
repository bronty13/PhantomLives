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

// MARK: - 1. Bootstrap (no-op; kept for API compatibility)

/// Was an aggressive global NSWindowDelegate replacement; broke SwiftUI's
/// own window-lifecycle delegate calls and prevented the app from loading.
/// Reverted to a no-op. Spell-check on TextFields now goes through
/// `SpellCheckActivator` (per-field, drops into `.background`) which only
/// configures the existing field editor without touching window delegates.
@MainActor
enum SpellCheckBootstrap {
    static func installOnAllWindows() {}
}

// MARK: - 1b. Per-field activator (safe, additive)

/// Drop-in zero-pixel anchor that, once attached to a window, toggles
/// continuous spell-check on the **window's existing field editor**. AppKit
/// reuses one field editor across every NSTextField (and SwiftUI TextField)
/// in a given window, so we only need to flip its flag once and every
/// TextField in that window inherits the behaviour for the rest of the
/// session.
///
/// Usage:
/// ```
/// TextField("…", text: $input)
///     .background(SpellCheckActivator())
/// ```
///
/// Why this is safe (unlike the previous attempt): we never replace the
/// window's delegate, never substitute a custom field editor, and never
/// monitor `didBecomeKeyNotification`. We only set well-documented
/// instance properties on the field editor AppKit already created.
struct SpellCheckActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SpellCheckAnchorView(frame: .zero)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op: the configuration is one-shot from `viewDidMoveToWindow`.
        // SwiftUI may call `update` repeatedly during layout — bailing out
        // here keeps the configuration cost to "exactly once per window."
    }
}

/// Tiny NSView whose only job is to know when it joins a window so it can
/// configure that window's field editor. Owns no layout, no drawing,
/// no responder chain participation.
final class SpellCheckAnchorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // `fieldEditor(_:for:)` lazily creates a single shared field editor
        // on first call, which is what SwiftUI's TextField uses behind the
        // scenes. Setting flags on it propagates to every TextField in
        // the window for the lifetime of the window.
        guard let editor = window.fieldEditor(true, for: nil) as? NSTextView else { return }
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
