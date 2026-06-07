import SwiftUI
import AppKit

/// The reading surface, backed by `NSTextView` (TextKit) rather than SwiftUI
/// `Text`. This is what makes **word-precise click-to-start** possible: SwiftUI
/// `Text` can't map a click to a character index, but TextKit's layout manager
/// can (`characterIndex(for:)`). It also keeps native text selection and stays
/// efficient on large documents.
///
/// Highlighting (current word + enclosing sentence) and line-focus dimming are
/// applied as attribute edits on the text storage — never rebuilding the string
/// per spoken word — and the view auto-scrolls to keep the spoken word visible.
struct ReaderTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let wordRange: NSRange?
    let sentenceRange: NSRange?
    let lineFocus: Bool
    let isSpeaking: Bool
    /// Called with the absolute character offset (snapped to the start of the
    /// clicked word) when the user clicks in the text.
    let onClickOffset: (Int) -> Void

    // MARK: Colors
    private static let wordBG = NSColor.systemYellow.withAlphaComponent(0.92)
    private static let wordFG = NSColor.black
    private static let sentenceBG = NSColor.systemPurple.withAlphaComponent(0.16)
    private static let dimFG = NSColor.tertiaryLabelColor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = CenteringTextView()
        tv.onClickOffset = { idx in
            context.coordinator.handleClick(idx)
        }
        context.coordinator.onClickOffset = onClickOffset
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.allowsUndo = false
        tv.isRichText = true
        tv.textContainerInset = NSSize(width: 40, height: 28)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.rebuild(text: text, fontSize: fontSize, lineSpacing: lineSpacing,
                                    lineFocus: lineFocus)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.onClickOffset = onClickOffset

        // Rebuild the whole string only when the content or typography changes.
        if c.appliedText != text || c.appliedFontSize != fontSize || c.appliedLineSpacing != lineSpacing {
            c.rebuild(text: text, fontSize: fontSize, lineSpacing: lineSpacing, lineFocus: lineFocus)
        }
        if c.appliedLineFocus != lineFocus {
            c.applyLineFocus(lineFocus)
        }
        c.applyHighlight(word: wordRange, sentence: sentenceRange, speaking: isSpeaking,
                         word_bg: Self.wordBG, word_fg: Self.wordFG,
                         sentence_bg: Self.sentenceBG, dim_fg: Self.dimFG)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator (owns the mutable AppKit state)

    final class Coordinator {
        weak var textView: NSTextView?
        var onClickOffset: ((Int) -> Void)?

        var appliedText: String?
        var appliedFontSize: CGFloat = 0
        var appliedLineSpacing: CGFloat = 0
        var appliedLineFocus = false

        private var curWord: NSRange?
        private var curSentence: NSRange?

        func handleClick(_ characterIndex: Int) {
            guard let s = appliedText else { return }
            onClickOffset?(ReaderTextView.wordStart(in: s, at: characterIndex))
        }

        /// Rebuild the text storage from scratch with base typography.
        func rebuild(text: String, fontSize: CGFloat, lineSpacing: CGFloat, lineFocus: Bool) {
            guard let storage = textView?.textStorage else { return }
            let para = NSMutableParagraphStyle()
            para.lineSpacing = lineSpacing
            para.paragraphSpacing = lineSpacing + 6
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
            storage.setAttributedString(NSAttributedString(string: text, attributes: attrs))
            appliedText = text
            appliedFontSize = fontSize
            appliedLineSpacing = lineSpacing
            appliedLineFocus = false
            curWord = nil
            curSentence = nil
            if lineFocus { applyLineFocus(true) }
        }

        /// Dim the whole document (or restore it) for line-focus mode.
        func applyLineFocus(_ on: Bool) {
            guard let storage = textView?.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor,
                                 value: on ? NSColor.tertiaryLabelColor : NSColor.labelColor,
                                 range: full)
            storage.endEditing()
            appliedLineFocus = on
            // Re-light the active sentence if we have one.
            if on, let s = curSentence, let st = textView?.textStorage,
               NSMaxRange(s) <= st.length {
                st.addAttribute(.foregroundColor, value: NSColor.labelColor, range: s)
            }
        }

        /// Minimal-diff highlight: only the changed word / sentence ranges are
        /// touched per spoken step, so this is cheap even on long documents.
        func applyHighlight(word: NSRange?, sentence: NSRange?, speaking: Bool,
                            word_bg: NSColor, word_fg: NSColor,
                            sentence_bg: NSColor, dim_fg: NSColor) {
            guard let storage = textView?.textStorage else { return }
            let len = storage.length
            func valid(_ r: NSRange?) -> NSRange? {
                guard let r, r.location >= 0, r.length > 0, NSMaxRange(r) <= len else { return nil }
                return r
            }
            let newWord = speaking ? valid(word) : nil
            let newSentence = speaking ? valid(sentence) : nil
            guard newWord != curWord || newSentence != curSentence else { return }

            storage.beginEditing()

            // Sentence background transition.
            if newSentence != curSentence {
                if let old = curSentence, NSMaxRange(old) <= len {
                    storage.removeAttribute(.backgroundColor, range: old)
                    if appliedLineFocus {
                        storage.addAttribute(.foregroundColor, value: dim_fg, range: old)
                    }
                }
                if let new = newSentence {
                    storage.addAttribute(.backgroundColor, value: sentence_bg, range: new)
                    if appliedLineFocus {
                        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: new)
                    }
                }
            }

            // Word background + contrast foreground transition.
            if newWord != curWord {
                if let old = curWord, NSMaxRange(old) <= len {
                    storage.removeAttribute(.backgroundColor, range: old)
                    // Restore the word's foreground to its sentence context.
                    let inLitSentence = newSentence.map { NSIntersectionRange($0, old).length > 0 } ?? false
                    let restore = (appliedLineFocus && !inLitSentence) ? dim_fg : NSColor.labelColor
                    storage.addAttribute(.foregroundColor, value: restore, range: old)
                }
                if let new = newWord {
                    storage.addAttribute(.backgroundColor, value: word_bg, range: new)
                    storage.addAttribute(.foregroundColor, value: word_fg, range: new)
                }
            }

            storage.endEditing()
            curWord = newWord
            curSentence = newSentence

            if let w = newWord { textView?.scrollRangeToVisible(w) }
        }
    }

    /// Snap a character index to the start of the word that contains it (or the
    /// next word, if the click landed in whitespace). Pure + static for tests.
    static func wordStart(in text: String, at index: Int) -> Int {
        let ns = text as NSString
        let clamped = max(0, min(index, ns.length))
        var chosen = clamped
        var found = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .byWords) { _, range, _, stop in
            if NSLocationInRange(clamped, range) {
                chosen = range.location; found = true; stop.pointee = true
            } else if range.location >= clamped {
                chosen = range.location; found = true; stop.pointee = true
            }
        }
        return found ? chosen : clamped
    }
}

/// NSTextView that (a) centers a fixed-width reading column and (b) reports the
/// character index the user clicked so the reader can start speaking there.
final class CenteringTextView: NSTextView {
    var onClickOffset: ((Int) -> Void)?
    private let columnWidth: CGFloat = 720

    override func layout() {
        // Center a comfortable reading column by padding the text container.
        let avail = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        let inset = max(40, (avail - columnWidth) / 2)
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: textContainerInset.height)
        }
        super.layout()
    }

    override func mouseDown(with event: NSEvent) {
        if let idx = characterIndex(forClick: event) {
            onClickOffset?(idx)
        }
        super.mouseDown(with: event)   // preserve caret/selection behavior
    }

    private func characterIndex(forClick event: NSEvent) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let idx = lm.characterIndex(for: point, in: tc,
                                    fractionOfDistanceBetweenInsertionPoints: &frac)
        return idx
    }
}
