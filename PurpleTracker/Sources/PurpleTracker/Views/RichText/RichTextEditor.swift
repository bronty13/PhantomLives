import SwiftUI
import AppKit

/// SwiftUI WYSIWYG rich-text editor backed by `NSTextView`.
///
/// - Binds a single `NSAttributedString` source-of-truth (`attributed`).
/// - Hosts a formatting toolbar that fires AppKit selector-based actions on
///   the embedded text view (bold/italic/underline, headings, bullet/numbered
///   lists, hyperlink, color, clear formatting).
/// - Designed so the *editor* owns its attributed string between user typing
///   events; SwiftUI writes back via the binding on every change so callers
///   can persist on autosave.
struct RichTextEditor: View {
    @Binding var attributed: NSAttributedString

    var body: some View {
        VStack(spacing: 0) {
            RichTextToolbar()
            RichTextRepresentable(attributed: $attributed)
                .frame(minHeight: 240)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

// MARK: - NSTextView host

private struct RichTextRepresentable: NSViewRepresentable {
    @Binding var attributed: NSAttributedString

    func makeCoordinator() -> Coordinator { Coordinator(binding: $attributed) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsImageEditing = true
        tv.importsGraphics = true
        tv.usesInspectorBar = false
        tv.usesFontPanel = false
        tv.isAutomaticLinkDetectionEnabled = true
        tv.isAutomaticDataDetectionEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticDashSubstitutionEnabled  = true
        tv.isAutomaticTextReplacementEnabled   = true
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.textStorage?.setAttributedString(attributed)
        context.coordinator.textView = tv
        RichTextRegistry.shared.current = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        RichTextRegistry.shared.current = tv
        if let storage = tv.textStorage,
           !storage.isEqual(to: attributed) {
            let selection = tv.selectedRanges
            storage.setAttributedString(attributed)
            tv.selectedRanges = selection
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let binding: Binding<NSAttributedString>
        weak var textView: NSTextView?
        init(binding: Binding<NSAttributedString>) { self.binding = binding }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            binding.wrappedValue = NSAttributedString(attributedString: storage)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let tv = notification.object as? NSTextView {
                RichTextRegistry.shared.current = tv
            }
        }
    }
}

// MARK: - Registry

/// Bridges the rich-text toolbar (SwiftUI) to whichever `NSTextView` is in
/// focus. Last text view wins — fine while only one editor is on-screen.
final class RichTextRegistry {
    static let shared = RichTextRegistry()
    weak var current: NSTextView?
    func firstResponderTextView() -> NSTextView? {
        if let win = NSApp.keyWindow,
           let tv = win.firstResponder as? NSTextView { return tv }
        return current
    }
}

// MARK: - Toolbar

struct RichTextToolbar: View {
    var body: some View {
        HStack(spacing: 6) {
            Group {
                tButton("Bold (⌘B)",          systemImage: "bold")      { applyTrait(.boldFontMask) }
                    .keyboardShortcut("b", modifiers: .command)
                tButton("Italic (⌘I)",        systemImage: "italic")    { applyTrait(.italicFontMask) }
                    .keyboardShortcut("i", modifiers: .command)
                tButton("Underline (⌘U)",     systemImage: "underline") { underline() }
                    .keyboardShortcut("u", modifiers: .command)
                tButton("Strikethrough (⇧⌘X)", systemImage: "strikethrough") { strikethrough() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
            }
            Divider().frame(height: 18)
            Menu {
                Button("Heading 1") { setHeading(size: 22, weight: .bold) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Heading 2") { setHeading(size: 18, weight: .semibold) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Heading 3") { setHeading(size: 15, weight: .semibold) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Body")      { setHeading(size: 13, weight: .regular) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            } label: { Label("Style", systemImage: "textformat") }
                .menuStyle(.borderlessButton).fixedSize()
            Divider().frame(height: 18)
            tButton("Bullet list (⇧⌘7)",   systemImage: "list.bullet") { makeList(numbered: false) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            tButton("Numbered list (⇧⌘8)", systemImage: "list.number") { makeList(numbered: true) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Divider().frame(height: 18)
            tButton("Link (⌘K)", systemImage: "link") { addLink() }
                .keyboardShortcut("k", modifiers: .command)
            ColorPicker("", selection: Binding(
                get: { Color(currentColor()) },
                set: { setColor(NSColor($0)) }
            ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)
            Divider().frame(height: 18)
            tButton("Clear formatting", systemImage: "paintbrush") { clearFormatting() }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
    }

    private func tButton(_ help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func tv() -> NSTextView? { RichTextRegistry.shared.firstResponderTextView() }

    private func applyTrait(_ mask: NSFontTraitMask) {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else {
            let attrs = tv.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let new = NSFontManager.shared.convert(font, toHaveTrait: mask)
            var newAttrs = attrs
            newAttrs[.font] = new
            tv.typingAttributes = newAttrs
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let new = NSFontManager.shared.convert(font, toHaveTrait: mask)
            storage.addAttribute(.font, value: new, range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private func underline() {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        storage.beginEditing()
        var alreadyAll = true
        storage.enumerateAttribute(.underlineStyle, in: range) { v, _, _ in
            if (v as? Int) ?? 0 == 0 { alreadyAll = false }
        }
        let newVal = alreadyAll ? 0 : NSUnderlineStyle.single.rawValue
        storage.addAttribute(.underlineStyle, value: newVal, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    private func strikethrough() {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        storage.beginEditing()
        var alreadyAll = true
        storage.enumerateAttribute(.strikethroughStyle, in: range) { v, _, _ in
            if (v as? Int) ?? 0 == 0 { alreadyAll = false }
        }
        let newVal = alreadyAll ? 0 : NSUnderlineStyle.single.rawValue
        storage.addAttribute(.strikethroughStyle, value: newVal, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    private func setHeading(size: CGFloat, weight: NSFont.Weight) {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let r = paragraphRange(in: tv)
        guard r.length > 0 else { return }
        storage.beginEditing()
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        storage.addAttribute(.font, value: font, range: r)
        storage.endEditing()
        tv.didChangeText()
    }

    private func makeList(numbered: Bool) {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let r = paragraphRange(in: tv)
        guard r.length > 0 else { return }
        let text = (storage.string as NSString).substring(with: r)
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            if line.isEmpty && i == lines.count - 1 { out.append(line); continue }
            let p = numbered ? "\(i + 1). " : "• "
            if line.hasPrefix("• ") || line.range(of: "^\\d+\\. ", options: .regularExpression) != nil {
                out.append(line)
            } else {
                out.append(p + line)
            }
        }
        storage.beginEditing()
        storage.replaceCharacters(in: r, with: out.joined(separator: "\n"))
        storage.endEditing()
        tv.didChangeText()
    }

    private func addLink() {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "Enter a URL for the selected text."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: field.stringValue), !field.stringValue.isEmpty {
            storage.beginEditing()
            storage.addAttribute(.link, value: url, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            storage.endEditing()
            tv.didChangeText()
        }
    }

    private func currentColor() -> NSColor {
        guard let tv = tv(), let storage = tv.textStorage else { return .labelColor }
        let r = tv.selectedRange()
        let probe = r.length > 0 ? r.location : max(0, r.location - 1)
        guard probe < storage.length else { return .labelColor }
        return (storage.attribute(.foregroundColor, at: probe, effectiveRange: nil) as? NSColor) ?? .labelColor
    }

    private func setColor(_ color: NSColor) {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else {
            var attrs = tv.typingAttributes
            attrs[.foregroundColor] = color
            tv.typingAttributes = attrs
            return
        }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: color, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    private func clearFormatting() {
        guard let tv = tv(), let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        let plain = (storage.string as NSString).substring(with: range)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: NSAttributedString(string: plain, attributes: defaultAttrs))
        storage.endEditing()
        tv.didChangeText()
    }

    private func paragraphRange(in tv: NSTextView) -> NSRange {
        guard let storage = tv.textStorage else { return tv.selectedRange() }
        let sel = tv.selectedRange()
        return (storage.string as NSString).paragraphRange(for: sel)
    }
}

// MARK: - RTF / RTFD <-> NSAttributedString helpers

extension NSAttributedString {
    /// Encode this attributed string for persistence. Uses RTFD when the
    /// string contains any attachments (pasted screenshots, images) so the
    /// image bytes survive the round-trip; falls back to plain RTF otherwise
    /// to stay backward-compatible with existing notes.
    func toRTFData() -> Data? {
        let range = NSRange(location: 0, length: length)
        if attachmentCount > 0 {
            // NSTextView paste may stash images via `attachment.image`
            // without a `fileWrapper`. RTFD persistence reads bytes from
            // the file wrapper, so synthesize one when missing.
            let prepared = NSAttributedString.ensureAttachmentFileWrappers(in: self)
            if let rtfd = try? prepared.data(
                from: NSRange(location: 0, length: prepared.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            ) { return rtfd }
        }
        return try? data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Decode an RTF or RTFD payload back into an attributed string. Tries
    /// RTFD first (it tolerates plain-RTF input on macOS) so embedded images
    /// survive. Returns an empty attributed string if `data` is nil/empty.
    static func fromRTFData(_ data: Data?) -> NSAttributedString {
        guard let data, !data.isEmpty else { return NSAttributedString() }
        if let s = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) { return s }
        if let s = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) { return s }
        return NSAttributedString()
    }

    /// Count of `NSTextAttachment` instances in the string.
    var attachmentCount: Int {
        var n = 0
        enumerateAttribute(.attachment,
                           in: NSRange(location: 0, length: length),
                           options: []) { v, _, _ in
            if v is NSTextAttachment { n += 1 }
        }
        return n
    }

    /// Returns a copy of `src` where every `NSTextAttachment` has a
    /// non-nil `fileWrapper`. When only `attachment.image` is set (the case
    /// after pasting a screenshot in NSTextView), a PNG `FileWrapper` is
    /// synthesized so RTFD persistence can carry the bytes. When neither an
    /// image nor a wrapper is available, falls back to `NSTextAttachmentCell`
    /// rendering.
    fileprivate static func ensureAttachmentFileWrappers(
        in src: NSAttributedString
    ) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: src)
        let full = NSRange(location: 0, length: m.length)
        m.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            guard let att = value as? NSTextAttachment else { return }
            if att.fileWrapper != nil { return }

            // Try `.image` first (NSTextView paste path on 10.11+).
            var image: NSImage? = att.image
            if image == nil, let cell = att.attachmentCell as? NSTextAttachmentCell {
                image = cell.image
            }
            guard let nsImage = image,
                  let tiff = nsImage.tiffRepresentation,
                  let rep  = NSBitmapImageRep(data: tiff),
                  let png  = rep.representation(using: .png, properties: [:]) else {
                return
            }
            let wrapper = FileWrapper(regularFileWithContents: png)
            wrapper.preferredFilename = "image-\(UUID().uuidString.prefix(8)).png"
            att.fileWrapper = wrapper
            // Keep the visible cell consistent.
            if att.attachmentCell == nil {
                att.attachmentCell = NSTextAttachmentCell(imageCell: nsImage)
            }
            m.removeAttribute(.attachment, range: range)
            m.addAttribute(.attachment, value: att, range: range)
        }
        return m
    }
}
