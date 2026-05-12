import AppKit
import SwiftUI

/// Field-level adapter that hosts `RichTextEditor` inside the
/// `Detail.swift` form. Two responsibilities:
///
/// 1. **Read/write the `{rtf, plain}` JSON dictionary** in the record's
///    `fieldsBuffer`. The buffer is a `[String: Any]` mirror of the
///    record's `fields_json` — what `Detail`'s save path serializes.
/// 2. **Capture pasted images cleanly at save**: read `NSTextView.textStorage`
///    directly via `RichTextRegistry` to pick up attachments the SwiftUI
///    binding hasn't propagated yet. Same trick as PurpleTracker's
///    `NoteEditorView.saveNow()`.
///
/// Slice B2 does NOT include the autosave debounce — `Detail.swift`'s
/// existing save-on-Save-button + save-on-sheet-dismiss flow already
/// covers it. When B3 introduces the dedicated `NoteEditorView` (which
/// edits a note in a full-pane workspace without a Save button), the
/// 1.2-second debounce will live there.
struct RichTextField: View {
    let fieldKey: String
    @Binding var fieldsBuffer: [String: Any]
    /// Surfaced to `Detail.swift` via `Binding` so the surrounding form
    /// can render a red over-budget banner; `nil` means within budget.
    @Binding var sizeError: String?

    @State private var attributed = NSAttributedString()
    @State private var loadedFromBuffer = false

    var body: some View {
        RichTextEditor(attributed: $attributed)
            .onAppear { loadFromBuffer() }
            .onChange(of: attributed) { _, newValue in
                writeBack(newValue)
            }
    }

    /// First-render load: lift `{rtf, plain}` out of the buffer and
    /// hydrate the editor. Subsequent edits flow back via onChange.
    private func loadFromBuffer() {
        guard !loadedFromBuffer else { return }
        loadedFromBuffer = true
        guard let dict = fieldsBuffer[fieldKey] as? [String: Any] else {
            attributed = NSAttributedString()
            return
        }
        let value = RichTextValue.from(jsonDictionary: dict)
        attributed = NSAttributedString.fromRTFData(value.rtf)
    }

    /// Write back into the buffer dict on each edit. Reads the live
    /// `NSTextView.textStorage` to capture pasted attachments that may
    /// not have propagated to the SwiftUI binding yet — same approach
    /// PurpleTracker's NoteEditorView uses.
    private func writeBack(_ newValue: NSAttributedString) {
        let live: NSAttributedString = {
            if let tv = RichTextRegistry.shared.firstResponderTextView(),
               let storage = tv.textStorage {
                return NSAttributedString(attributedString: storage)
            }
            return newValue
        }()

        let rtf = live.toRTFData() ?? Data()
        if !RichTextLimits.fits(rtf) {
            sizeError = "This note is too large to sync — reduce image sizes or remove some images. (\(rtf.count.formatted()) bytes; limit \(RichTextLimits.maxBlobBytes.formatted()).)"
            // Don't write back over the in-buffer state when the new
            // value is over budget. The editor still shows what the
            // user typed; the buffer keeps the last-known-good value.
            return
        }
        sizeError = nil
        let plain = live.string
        let value = RichTextValue(rtf: rtf, plain: plain)
        fieldsBuffer[fieldKey] = value.jsonDictionary
    }
}
