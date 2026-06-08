import SwiftUI
import AppKit

/// The Markdown (source) editor: an `NSTextView` with markdown syntax
/// highlighting, an optional line-number ruler, and the toolbar/Format-menu
/// commands (bold/italic/link/…). Honors the editor preferences (font, word
/// wrap, line numbers, tab width, spellcheck, auto-close brackets).
struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var settings: AppSettings
    var onScroll: ((Double) -> Void)?
    var scrollTo: Double?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // We build the scroll/text view by hand (rather than
        // `NSTextView.scrollableTextView()`) so the text view is our
        // `EditorTextView` subclass, which opens dropped markdown files instead
        // of inserting their path. (Filtering `registeredDraggedTypes` doesn't
        // stick — NSTextView re-registers its drag types when added to a window.)
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autoresizingMask = [.width, .height]

        let textView = EditorTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        // A dropped markdown file opens as a document instead of inserting its
        // path; any other drop (plain text, non-markdown files) falls back to
        // the standard NSTextView behavior.
        textView.onOpenFiles = { urls in
            Task { @MainActor in AppState.shared.openDroppedFiles(urls) }
        }

        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.backgroundColor = SourcePalette.background
        textView.insertionPointColor = SourcePalette.caret
        textView.string = text

        scroll.drawsBackground = true
        scroll.backgroundColor = SourcePalette.background

        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        context.coordinator.configure(with: settings)
        context.coordinator.highlight()
        context.coordinator.observeScroll()
        context.coordinator.observeActions()
        context.coordinator.observeFind()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selected.clamped(to: textView.string.count))
            context.coordinator.highlight()
        }
        context.coordinator.configure(with: settings)
        if let scrollTo { context.coordinator.scroll(toFraction: scrollTo) }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var actionObserver: NSObjectProtocol?
        private var findObserver: NSObjectProtocol?
        private var highlightWorkItem: DispatchWorkItem?
        private var lastReported: Double = 0
        private var lastApplied: Double?

        init(_ parent: SourceTextView) { self.parent = parent }

        deinit {
            if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
            if let findObserver { NotificationCenter.default.removeObserver(findObserver) }
        }

        // MARK: Configuration

        func configure(with settings: AppSettings) {
            guard let textView else { return }
            let font = settings.editorFont()
            textView.font = font

            // Tab width as a multiple of the space advance.
            let space = (" " as NSString).size(withAttributes: [.font: font]).width
            let style = NSMutableParagraphStyle()
            style.defaultTabInterval = space * CGFloat(settings.tabWidth)
            style.tabStops = []
            textView.defaultParagraphStyle = style

            textView.isContinuousSpellCheckingEnabled = settings.checkSpelling
            textView.isGrammarCheckingEnabled = false

            // Editor contrast — a distinct (darker) editor background vs a softer one.
            let bg = settings.editorContrast ? SourcePalette.background : SourcePalette.backgroundSoft
            textView.backgroundColor = bg
            scrollView?.backgroundColor = bg

            // Word wrap.
            if settings.wordWrap {
                textView.isHorizontallyResizable = false
                textView.textContainer?.widthTracksTextView = true
                if let width = scrollView?.contentSize.width {
                    textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
                }
            } else {
                textView.isHorizontallyResizable = true
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                               height: CGFloat.greatestFiniteMagnitude)
            }

            // Line-number ruler.
            if settings.showLineNumbers {
                if scrollView?.verticalRulerView == nil {
                    let ruler = LineNumberRuler(textView: textView)
                    scrollView?.verticalRulerView = ruler
                }
                scrollView?.hasVerticalRuler = true
                scrollView?.rulersVisible = true
            } else {
                scrollView?.rulersVisible = false
                scrollView?.hasVerticalRuler = false
            }
            highlight()
        }

        // MARK: Delegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            scheduleHighlight()
            centerCaretIfNeeded()
            (scrollView?.verticalRulerView as? LineNumberRuler)?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateFocusMode()
            centerCaretIfNeeded()
        }

        // MARK: Writing modes

        /// Typewriter mode — keep the caret's line vertically centered.
        func centerCaretIfNeeded() {
            guard parent.settings.typewriterMode,
                  let tv = textView, let sv = scrollView,
                  let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: tv.selectedRange(), actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let caretY = rect.midY + tv.textContainerInset.height
            let target = caretY - sv.contentSize.height / 2
            let maxY = max(0, tv.bounds.height - sv.contentSize.height)
            sv.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, target), maxY)))
            sv.reflectScrolledClipView(sv.contentView)
        }

        /// Focus mode — dim everything outside the current paragraph using
        /// display-only temporary attributes (so syntax colors are preserved
        /// when focus mode is turned off).
        func updateFocusMode() {
            guard let tv = textView, let lm = tv.layoutManager else { return }
            let ns = tv.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            guard parent.settings.focusMode else { return }
            let para = ns.paragraphRange(for: tv.selectedRange())
            let dim = SourcePalette.muted.withAlphaComponent(0.45)
            if para.location > 0 {
                lm.addTemporaryAttribute(.foregroundColor, value: dim,
                                         forCharacterRange: NSRange(location: 0, length: para.location))
            }
            let after = para.location + para.length
            if after < full.length {
                lm.addTemporaryAttribute(.foregroundColor, value: dim,
                                         forCharacterRange: NSRange(location: after, length: full.length - after))
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let replacementString,
                  parent.settings.autoCloseBrackets else { return true }
            // Auto-close brackets/quotes when typing a single opening char with
            // an empty selection.
            guard affectedCharRange.length == 0 else { return true }
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "`": "`"]
            guard let close = pairs[replacementString] else {
                // Continue list markers on Enter.
                if replacementString == "\n" { return handleNewline(textView, at: affectedCharRange) }
                return true
            }
            textView.insertText(replacementString + close, replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
            return false
        }

        /// On Enter inside a list item, start the next item automatically.
        private func handleNewline(_ textView: NSTextView, at range: NSRange) -> Bool {
            let ns = textView.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = line.range(of: #"^(\s*)([-*+]|\d+\.)\s+"#, options: .regularExpression) {
                if trimmed.range(of: #"^([-*+]|\d+\.)\s*$"#, options: .regularExpression) != nil {
                    return true // empty item — let Enter end the list
                }
                let prefix = String(line[match])
                    .replacingOccurrences(of: "\n", with: "")
                textView.insertText("\n" + leadingMarker(prefix), replacementRange: range)
                return false
            }
            return true
        }

        private func leadingMarker(_ prefix: String) -> String {
            // Bump numbered markers (1. -> 2.); keep bullet markers as-is.
            if let r = prefix.range(of: #"\d+"#, options: .regularExpression),
               let n = Int(prefix[r]) {
                return prefix.replacingCharacters(in: r, with: String(n + 1))
            }
            return prefix
        }

        // MARK: Scroll sync

        func observeScroll() {
            guard let clip = scrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                guard let self, let tv = self.textView, let sv = self.scrollView else { return }
                let docHeight = tv.bounds.height - sv.contentSize.height
                guard docHeight > 0 else { return }
                let fraction = max(0, min(1, sv.contentView.bounds.origin.y / docHeight))
                self.lastReported = fraction
                self.parent.onScroll?(fraction)
            }
        }

        func scroll(toFraction fraction: Double) {
            guard let tv = textView, let sv = scrollView else { return }
            if abs(fraction - lastReported) < 0.002 { return }
            if let lastApplied, abs(fraction - lastApplied) < 0.002 { return }
            let docHeight = tv.bounds.height - sv.contentSize.height
            guard docHeight > 0 else { return }
            lastApplied = fraction
            sv.contentView.scroll(to: NSPoint(x: 0, y: docHeight * fraction))
            sv.reflectScrolledClipView(sv.contentView)
        }

        // MARK: Format actions

        func observeActions() {
            actionObserver = NotificationCenter.default.addObserver(
                forName: EditorAction.notification, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let raw = note.object as? String,
                      let action = EditorAction(rawValue: raw),
                      let tv = self.textView,
                      tv.window?.isKeyWindow == true else { return }
                self.apply(action, to: tv)
            }
        }

        private func apply(_ action: EditorAction, to tv: NSTextView) {
            switch action {
            case .bold:          wrap(tv, with: "**")
            case .italic:        wrap(tv, with: "_")
            case .strikethrough: wrap(tv, with: "~~")
            case .inlineCode:    wrap(tv, with: "`")
            case .link:          insertLink(tv)
            case .unorderedList: prefixLines(tv, with: "- ")
            case .orderedList:   numberLines(tv)
            case .quote:         prefixLines(tv, with: "> ")
            case .codeBlock:     fence(tv)
            }
            parent.text = tv.string
            highlight()
        }

        private func wrap(_ tv: NSTextView, with marker: String) {
            let range = tv.selectedRange()
            let ns = tv.string as NSString
            let selected = ns.substring(with: range)
            let wrapped = "\(marker)\(selected)\(marker)"
            if tv.shouldChangeText(in: range, replacementString: wrapped) {
                tv.replaceCharacters(in: range, with: wrapped)
                tv.didChangeText()
                let caret = selected.isEmpty
                    ? NSRange(location: range.location + (marker as NSString).length, length: 0)
                    : NSRange(location: range.location, length: (wrapped as NSString).length)
                tv.setSelectedRange(caret)
            }
        }

        private func insertLink(_ tv: NSTextView) {
            let range = tv.selectedRange()
            let ns = tv.string as NSString
            let selected = ns.substring(with: range)
            let text = selected.isEmpty ? "title" : selected
            let replacement = "[\(text)](url)"
            if tv.shouldChangeText(in: range, replacementString: replacement) {
                tv.replaceCharacters(in: range, with: replacement)
                tv.didChangeText()
                // Select the "url" placeholder.
                let urlLoc = range.location + (replacement as NSString).range(of: "url").location
                tv.setSelectedRange(NSRange(location: urlLoc, length: 3))
            }
        }

        private func prefixLines(_ tv: NSTextView, with prefix: String) {
            let ns = tv.string as NSString
            let lineRange = ns.lineRange(for: tv.selectedRange())
            let block = ns.substring(with: lineRange)
            let newBlock = block
                .components(separatedBy: "\n")
                .enumerated()
                .map { (i, line) -> String in
                    (i == block.components(separatedBy: "\n").count - 1 && line.isEmpty) ? line : prefix + line
                }
                .joined(separator: "\n")
            if tv.shouldChangeText(in: lineRange, replacementString: newBlock) {
                tv.replaceCharacters(in: lineRange, with: newBlock)
                tv.didChangeText()
            }
        }

        private func numberLines(_ tv: NSTextView) {
            let ns = tv.string as NSString
            let lineRange = ns.lineRange(for: tv.selectedRange())
            let lines = ns.substring(with: lineRange).components(separatedBy: "\n")
            var n = 0
            let newBlock = lines.map { line -> String in
                if line.isEmpty { return line }
                n += 1; return "\(n). \(line)"
            }.joined(separator: "\n")
            if tv.shouldChangeText(in: lineRange, replacementString: newBlock) {
                tv.replaceCharacters(in: lineRange, with: newBlock)
                tv.didChangeText()
            }
        }

        private func fence(_ tv: NSTextView) {
            let range = tv.selectedRange()
            let ns = tv.string as NSString
            let selected = ns.substring(with: range)
            let replacement = "```\n\(selected)\n```"
            if tv.shouldChangeText(in: range, replacementString: replacement) {
                tv.replaceCharacters(in: range, with: replacement)
                tv.didChangeText()
            }
        }

        // MARK: Find & Replace

        func observeFind() {
            findObserver = NotificationCenter.default.addObserver(
                forName: .pmFind, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let box = note.object as? FindCommandBox,
                      let tv = self.textView,
                      tv.window?.isKeyWindow == true else { return }
                switch box.command {
                case .select(let range):
                    self.findSelect(range, in: tv)
                case .replace(let range, let replacement):
                    self.findReplace(range, with: replacement, in: tv)
                case .replaceAll(let ranges, let replacement):
                    self.findReplaceAll(ranges, with: replacement, in: tv)
                }
            }
        }

        private func findSelect(_ range: NSRange, in tv: NSTextView) {
            guard NSMaxRange(range) <= (tv.string as NSString).length else { return }
            tv.setSelectedRange(range)
            tv.scrollRangeToVisible(range)
            tv.showFindIndicator(for: range)
        }

        private func findReplace(_ range: NSRange, with replacement: String, in tv: NSTextView) {
            guard NSMaxRange(range) <= (tv.string as NSString).length,
                  tv.shouldChangeText(in: range, replacementString: replacement) else { return }
            tv.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            parent.text = tv.string
            highlight()
        }

        private func findReplaceAll(_ ranges: [NSRange], with replacement: String, in tv: NSTextView) {
            guard !ranges.isEmpty else { return }
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
            tv.textStorage?.beginEditing()
            // Replace from the end backwards so earlier ranges stay valid.
            for range in ranges.sorted(by: { $0.location > $1.location }) {
                guard NSMaxRange(range) <= (tv.textStorage?.length ?? 0) else { continue }
                tv.textStorage?.replaceCharacters(in: range, with: replacement)
            }
            tv.textStorage?.endEditing()
            tv.didChangeText()
            parent.text = tv.string
            highlight()
        }

        // MARK: Highlighting

        func scheduleHighlight() {
            highlightWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlight() }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        func highlight() {
            guard let textView,
                  let storage = textView.textStorage else { return }
            MarkdownHighlighter.apply(to: storage, baseFont: parent.settings.editorFont())
            updateFocusMode()
        }
    }
}

/// An `NSTextView` that opens dropped markdown files (via `onOpenFiles`) rather
/// than inserting their path/contents. NSTextView is registered for file-URL
/// drags and re-registers them whenever it moves to a window, so the only
/// reliable interception point is the dragging-destination methods themselves.
final class EditorTextView: NSTextView {
    /// Invoked with the markdown/text file URLs from a drop; when set and the
    /// drop contains at least one such file, the text view opens them instead
    /// of performing its default insert.
    var onOpenFiles: (([URL]) -> Void)?

    private func openableFileURLs(_ sender: NSDraggingInfo) -> [URL] {
        guard onOpenFiles != nil,
              let objs = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return [] }
        return objs.filter { FileService.markdownExtensions.contains($0.pathExtension.lowercased()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        openableFileURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        openableFileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        openableFileURLs(sender).isEmpty ? super.prepareForDragOperation(sender) : true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = openableFileURLs(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onOpenFiles?(urls)
        return true
    }
}

/// Fixed dark palette for the source editor, matching the OpenMark screenshots.
enum SourcePalette {
    static let background = NSColor(calibratedRed: 0.118, green: 0.118, blue: 0.122, alpha: 1)
    static let backgroundSoft = NSColor(calibratedRed: 0.145, green: 0.145, blue: 0.151, alpha: 1)
    static let caret      = NSColor(calibratedRed: 0.66, green: 0.52, blue: 0.98, alpha: 1)
    static let text       = NSColor(calibratedRed: 0.84, green: 0.84, blue: 0.86, alpha: 1)
    static let heading    = NSColor(calibratedRed: 0.43, green: 0.66, blue: 0.96, alpha: 1) // blue
    static let emphasis   = NSColor(calibratedRed: 0.93, green: 0.42, blue: 0.62, alpha: 1) // pink
    static let code       = NSColor(calibratedRed: 0.31, green: 0.80, blue: 0.71, alpha: 1) // teal
    static let codeBG     = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.21, alpha: 1)
    static let link       = NSColor(calibratedRed: 0.40, green: 0.76, blue: 1.00, alpha: 1)
    static let listMark   = NSColor(calibratedRed: 0.86, green: 0.62, blue: 0.30, alpha: 1)
    static let muted      = NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)
}

/// Applies markdown syntax colors to an `NSTextStorage` in a single pass.
enum MarkdownHighlighter {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants — force-try is safe.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let headingRE   = regex(#"^(#{1,6})\s.*$"#)
    private static let boldRE       = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicRE     = regex(#"(?<![\*_])([\*_])(?=\S)(.+?)(?<=\S)\1(?![\*_])"#)
    private static let strikeRE     = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let inlineCodeRE = regex(#"`[^`\n]+`"#)
    private static let fenceRE      = regex(#"^```[\s\S]*?^```"#)
    private static let linkRE       = regex(#"\[[^\]]*\]\([^\)]*\)"#)
    private static let listRE       = regex(#"^\s*([-*+]|\d+\.)\s"#)
    private static let quoteRE      = regex(#"^\s*>.*$"#)

    static func apply(to storage: NSTextStorage, baseFont: NSFont) {
        let full = NSRange(location: 0, length: storage.length)
        let text = storage.string as NSString

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: SourcePalette.text], range: full)

        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)

        func color(_ re: NSRegularExpression, _ c: NSColor, font: NSFont? = nil, bg: NSColor? = nil) {
            re.enumerateMatches(in: storage.string, options: [], range: full) { match, _, _ in
                guard let r = match?.range else { return }
                var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: c]
                if let font { attrs[.font] = font }
                if let bg { attrs[.backgroundColor] = bg }
                storage.addAttributes(attrs, range: r)
            }
        }

        color(quoteRE, SourcePalette.muted)
        color(listRE, SourcePalette.listMark)
        color(headingRE, SourcePalette.heading, font: boldFont)
        color(linkRE, SourcePalette.link)
        color(boldRE, SourcePalette.emphasis, font: boldFont)
        color(strikeRE, SourcePalette.emphasis)
        color(inlineCodeRE, SourcePalette.code, bg: SourcePalette.codeBG)
        color(fenceRE, SourcePalette.code)
        _ = text
        storage.endEditing()
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let loc = Swift.min(location, length)
        let len = Swift.min(self.length, length - loc)
        return NSRange(location: Swift.max(0, loc), length: Swift.max(0, len))
    }
}
