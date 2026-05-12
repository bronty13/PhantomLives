import SwiftUI
import AppKit

/// `TextField`-shaped wrapper around an `NSTextField` that enables
/// continuous spell-checking + grammar-checking on the shared field
/// editor when the field gains focus. SwiftUI doesn't expose these
/// flags on macOS `TextField`, so we drop into AppKit.
///
/// API mirrors `TextField(_:text:)` so call sites can swap in place.
/// Use only for free-text user content (note titles, record-level
/// short-text field values, theme names, type names, …). Skip for
/// search boxes, file paths, and numeric inputs — silent red
/// underlines on those are noise, not signal.
struct SpellCheckedTextField: NSViewRepresentable {
    private let placeholder: String
    @Binding private var text: String
    private let onSubmit: (() -> Void)?

    init(_ placeholder: String, text: Binding<String>, onSubmit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.isBordered = true
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.sendsActionOnEndEditing = false
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Only re-stamp when the model differs from the field's current
        // value — otherwise typing the same character twice triggers a
        // re-set that nudges the insertion point to the end mid-edit.
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        context.coordinator.onSubmit = onSubmit
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: SpellCheckedTextField
        fileprivate var onSubmit: (() -> Void)?

        init(_ parent: SpellCheckedTextField) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Configure the field editor when this control becomes the first
        /// responder. The field editor is a shared `NSTextView` that
        /// AppKit reuses across every `NSTextField` in the window, so
        /// the flags have to be (re-)applied per focus rather than once
        /// at construction.
        func control(_ control: NSControl,
                     textShouldBeginEditing fieldEditor: NSText) -> Bool {
            if let tv = fieldEditor as? NSTextView {
                tv.isContinuousSpellCheckingEnabled = true
                tv.isGrammarCheckingEnabled = true
                tv.isAutomaticSpellingCorrectionEnabled = false
            }
            return true
        }

        /// Forward Return-key commit through `onSubmit` so call sites can
        /// chain the standard SwiftUI `.onSubmit` behavior they had
        /// before swapping over.
        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return onSubmit != nil
            }
            return false
        }
    }
}
