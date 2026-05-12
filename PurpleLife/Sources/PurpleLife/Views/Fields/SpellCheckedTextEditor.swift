import AppKit
import SwiftUI

/// Drop-in replacement for SwiftUI's `TextEditor` that enables
/// continuous spell-check on the underlying NSTextView. SwiftUI's
/// `TextEditor` wraps NSTextView, but `isContinuousSpellCheckingEnabled`
/// defaults to false and SwiftUI doesn't expose a modifier to flip it.
/// This wrapper exists for the `.longText` field renderer — pure
/// plain-text multi-line, with the spell-check underlines users expect
/// in any prose editor.
///
/// Autocorrect stays OFF for the same reasons as `RichTextEditor` —
/// silent text replacement is hostile to technical content.
struct SpellCheckedTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(binding: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = true
        tv.isAutomaticTextReplacementEnabled = true
        tv.isAutomaticLinkDetectionEnabled = true
        tv.isAutomaticDataDetectionEnabled = true
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.drawsBackground = false
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let selection = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = selection
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let binding: Binding<String>
        init(binding: Binding<String>) { self.binding = binding }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            binding.wrappedValue = tv.string
        }
    }
}
