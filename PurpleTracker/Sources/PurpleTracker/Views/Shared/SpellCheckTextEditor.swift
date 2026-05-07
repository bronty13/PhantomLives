import SwiftUI
import AppKit

/// `NSTextView`-backed SwiftUI markdown editor with continuous spellcheck.
/// Spelling underlines are always on; autocorrection follows the user's
/// `autocorrectEnabled` setting.
struct SpellCheckTextEditor: NSViewRepresentable {
    @Binding var text: String
    var autocorrectEnabled: Bool = false
    var minHeight: CGFloat = 100

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = autocorrectEnabled
        tv.isGrammarCheckingEnabled = false
        tv.allowsUndo = true
        tv.string = text
        tv.textContainerInset = NSSize(width: 4, height: 6)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        tv.isAutomaticSpellingCorrectionEnabled = autocorrectEnabled
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SpellCheckTextEditor
        init(_ parent: SpellCheckTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
