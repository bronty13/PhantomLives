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

// MARK: - 1. Window field editor injector

/// Custom field editor — same as a stock NSTextView, but with continuous
/// spell-check pre-enabled. Auto-correct stays OFF: IRC nicks and channel
/// names look enough like English words that auto-correct would constantly
/// mangle them, but spelling underlines are still useful for prose.
@MainActor
final class SpellCheckedFieldEditor: NSTextView {
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        isFieldEditor = true
        isContinuousSpellCheckingEnabled = true
        isAutomaticSpellingCorrectionEnabled = false
        isGrammarCheckingEnabled = false
        // IRC users frequently type URLs; let the system make them clickable
        // so command-click works without us re-implementing link detection
        // for every single text field.
        isAutomaticLinkDetectionEnabled = true
        // Smart quotes and dashes ruin nick references like "don't" → "don’t"
        // and rewrite "--" into "—". Off everywhere; if the user wants them
        // they can request via the Edit menu's Substitutions submenu.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
    }
}

/// Window delegate that returns the spell-check field editor while passing
/// every other delegate call through to whatever delegate was set before us
/// (typically nil for SwiftUI hosting windows, but we cooperate either way).
@MainActor
final class SpellCheckingWindowDelegate: NSObject, NSWindowDelegate {
    /// Hold the previous delegate so SwiftUI's bookkeeping continues to work.
    /// Weak — if SwiftUI deallocates its delegate, we don't keep it alive.
    private weak var passthrough: NSWindowDelegate?

    /// Attach to a window. If the window already has *this same delegate
    /// type* installed we no-op (re-attaching would lose the passthrough
    /// chain to a delegate we already wrap).
    func install(on window: NSWindow) {
        if window.delegate is SpellCheckingWindowDelegate { return }
        passthrough = window.delegate
        window.delegate = self
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        // NSTextView has no zero-arg init — synthesize a tiny frame; AppKit
        // will resize the field editor to match the active control before
        // first display.
        SpellCheckedFieldEditor(frame: .zero, textContainer: nil)
    }

    // Forward unrecognized selectors to the previous delegate so SwiftUI
    // window callbacks (windowDidResize:, etc.) keep flowing.
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return passthrough?.responds(to: aSelector) ?? false
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let p = passthrough, p.responds(to: aSelector) { return p }
        return nil
    }
}

/// One-shot installer that walks every existing NSWindow and subscribes for
/// future ones. Idempotent — repeated calls are safe; each window is only
/// wrapped once thanks to the type check in `install(on:)`.
@MainActor
enum SpellCheckBootstrap {
    private static var observer: NSObjectProtocol?
    private static let delegate = SpellCheckingWindowDelegate()

    static func installOnAllWindows() {
        for w in NSApp.windows { delegate.install(on: w) }
        if observer != nil { return }
        // New windows announce themselves via didBecomeKeyNotification
        // (NSWindow has no global "did add" notification on macOS). The
        // first time a SwiftUI scene's window becomes key we install.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main
        ) { note in
            if let w = note.object as? NSWindow {
                Task { @MainActor in delegate.install(on: w) }
            }
        }
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
