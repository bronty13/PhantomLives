import AppKit

/// A vertical ruler that draws 1-based line numbers next to an `NSTextView`,
/// matching the source view in the OpenMark screenshots.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    /// Fast path for large documents: returns the 0-based line index for a
    /// UTF-16 offset (a `DocumentIndex` binary search), or nil to fall back to
    /// counting. Counting from offset 0 is O(n) per scroll frame — the single
    /// hottest path when scrolling a 100MB file.
    var lineIndexProvider: ((Int) -> Int?)?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        // Gutter background.
        SourcePalette.background.setFill()
        bounds.fill()
        NSColor(white: 1, alpha: 0.06).setStroke()
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        edge.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        edge.stroke()

        let text = textView.string as NSString
        let visibleRect = textView.visibleRect
        let inset = textView.textContainerInset.height
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (textView.font?.pointSize ?? 13) - 2),
                                                    weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: SourcePalette.muted,
        ]

        // Line number of the first visible character: indexed lookup when
        // available, else count (fine for normal-sized files).
        var lineNumber = 1
        if charRange.location > 0 {
            if let indexed = lineIndexProvider?(charRange.location) {
                lineNumber = indexed + 1
            } else {
                text.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                         options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                    lineNumber += 1
                }
            }
        }

        text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) {
            _, lineRangeInText, _, _ in
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRangeInText.location)
            var effective = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &effective)
            let y = lineRect.minY + inset - visibleRect.minY
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: self.bounds.maxX - size.width - 6, y: y + (lineRect.height - size.height) / 2),
                       withAttributes: attrs)
            lineNumber += 1
        }
    }
}
