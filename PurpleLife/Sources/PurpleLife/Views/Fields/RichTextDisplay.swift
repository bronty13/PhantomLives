import AppKit
import SwiftUI

/// Read-only NSTextView host that renders an `NSAttributedString`
/// faithfully — preserves fonts, colors, inline attachments — without
/// the formatting toolbar of `RichTextEditor`. Used by the NoteLog
/// field to show committed entries.
///
/// Uses `intrinsicContentSize`-flavored sizing: the wrapped NSTextView
/// is told its width by the SwiftUI layout, and reports its own
/// preferred height back via a measurement pass on every update. This
/// keeps each entry's row only as tall as its content needs to be,
/// regardless of how many entries are in the list.
struct RichTextDisplay: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> SizingTextView {
        let tv = SizingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 0
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textColor = NSColor.labelColor
        // Dark-mode adaptation — see RichTextEditor for full rationale.
        // The load-bearing fix is the per-attribute rewrite in
        // `fromRTFData → adaptingDefaultBlackToLabelColor`; these two
        // textview properties are Apple's documented backup paths.
        tv.usesAdaptiveColorMappingForDarkAppearance = true
        tv.textStorage?.setAttributedString(attributed)
        return tv
    }

    func updateNSView(_ tv: SizingTextView, context: Context) {
        if tv.textStorage?.isEqual(to: attributed) != true {
            tv.textStorage?.setAttributedString(attributed)
        }
        tv.invalidateIntrinsicContentSize()
    }

    /// NSTextView subclass that computes intrinsicContentSize from its
    /// laid-out content height. Width is whatever SwiftUI passes
    /// through; height is content-driven.
    final class SizingTextView: NSTextView {
        override var intrinsicContentSize: NSSize {
            guard let lm = layoutManager, let tc = textContainer else {
                return super.intrinsicContentSize
            }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height) + textContainerInset.height * 2)
        }
    }
}
