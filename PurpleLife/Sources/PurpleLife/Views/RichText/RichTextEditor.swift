import SwiftUI
import AppKit

/// SwiftUI WYSIWYG rich-text editor backed by `NSTextView`. Ported from
/// PurpleTracker's `RichTextEditor` (the v1.5 Notes feature). Adapted
/// for PurpleLife:
///
/// - Image-paste survival via `ensureAttachmentFileWrappers` (the
///   load-bearing fix for pasted screenshots — without it, RTFD encode
///   drops bytes because the `NSTextAttachment` has only `.image` set,
///   not a `fileWrapper`).
/// - **NEW**: incoming images > 1920 px wide are downscaled before they
///   become file wrappers; non-alpha images are encoded as JPEG @ 0.7
///   instead of PNG. Keeps notes under the CloudKit ~1 MB record
///   ceiling without compromising the E2E guarantee (compression isn't
///   confidentiality — the bytes still ride inside `encryptedValues`).
///
/// - Binds a single `NSAttributedString` source-of-truth (`attributed`).
/// - Hosts a formatting toolbar that fires AppKit selector-based actions
///   on the embedded text view (bold/italic/underline, headings,
///   bullet/numbered lists, hyperlink, color, clear formatting).
/// - The *editor* owns its attributed string between user typing events;
///   SwiftUI writes back via the binding on every change so callers can
///   persist on autosave.
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

        /// Augment the right-click menu with image-resize options when the
        /// click landed on an attachment. NSTextView doesn't ship with
        /// interactive corner-drag resize; this context menu is the
        /// standard macOS substitute (same pattern Apple Notes uses).
        ///
        /// `charIndex` can land one position past the attachment when the
        /// user clicks at its trailing edge — check the position itself
        /// AND `charIndex - 1` to be forgiving about hit-testing.
        /// Detection accepts EITHER `attachment.image` (fresh paste path)
        /// OR `attachment.fileWrapper` containing image bytes (the post-
        /// RTFD-roundtrip path — when a note is reloaded from disk, the
        /// `image` property is often nil even though the file wrapper
        /// has the bytes).
        func textView(_ view: NSTextView,
                      menu: NSMenu,
                      for event: NSEvent,
                      at charIndex: Int) -> NSMenu? {
            guard let storage = view.textStorage else { return menu }
            let candidate = Self.locateImageAttachment(in: storage, near: charIndex)
            guard let hit = candidate else {
                NSLog("PurpleLife: rich-text right-click at charIndex=\(charIndex) — no image attachment in scope")
                return menu
            }
            NSLog("PurpleLife: rich-text right-click on image at charIndex=\(hit.charIndex)")

            let imageMenu = NSMenu(title: "Image")

            // The slider popover sits at the top of the submenu — it's
            // the primary path for fine-grained resizing. Discrete
            // presets stay below as quick-jumps for "I just want this
            // image at exactly 400 pt without dragging anything."
            let resizeItem = NSMenuItem(title: "Resize image…",
                                        action: #selector(handleImageResizePopover(_:)),
                                        keyEquivalent: "")
            resizeItem.target = self
            resizeItem.representedObject = ImageResizeContext(charIndex: hit.charIndex)
            imageMenu.addItem(resizeItem)
            imageMenu.addItem(NSMenuItem.separator())

            for option in ImageResizeOption.allCases {
                let item = NSMenuItem(title: option.title,
                                      action: #selector(handleImageResize(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = ImageResizeRequest(charIndex: hit.charIndex, option: option)
                imageMenu.addItem(item)
            }
            let imageHeader = NSMenuItem(title: "Image size", action: nil, keyEquivalent: "")
            imageHeader.submenu = imageMenu
            menu.insertItem(NSMenuItem.separator(), at: 0)
            menu.insertItem(imageHeader, at: 0)
            return menu
        }

        @objc fileprivate func handleImageResizePopover(_ sender: NSMenuItem) {
            guard let ctx = sender.representedObject as? ImageResizeContext,
                  let tv = textView,
                  let storage = tv.textStorage,
                  ctx.charIndex < storage.length,
                  let attachment = storage.attribute(.attachment, at: ctx.charIndex, effectiveRange: nil) as? NSTextAttachment else { return }

            // Source image: prefer the file wrapper's natural bytes so
            // the slider's max width matches the as-pasted natural width
            // even after a prior resize (which mutated attachment.image.size).
            let sourceImage: NSImage? = {
                if let data = attachment.fileWrapper?.regularFileContents,
                   let img = NSImage(data: data) {
                    return img
                }
                return attachment.image
            }()
            guard let image = sourceImage else { return }

            let naturalWidth: CGFloat = {
                if let rep = image.representations.first, rep.pixelsWide > 0 {
                    return CGFloat(rep.pixelsWide)
                }
                return image.size.width
            }()
            let currentWidth = attachment.image?.size.width ?? naturalWidth
            // Clamp the upper bound to the natural width — upscaling
            // past the source pixels just blurs. Clamp the lower bound
            // to 40 so the user can't drag the image to invisibility.
            let maxWidth = max(naturalWidth, currentWidth)
            let minWidth: CGFloat = 40

            // Compute the image's rect in the text view's coordinate
            // space so the popover anchors to the actual image
            // location, not somewhere generic.
            let imageRect = Self.attachmentRect(in: tv, charIndex: ctx.charIndex)

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true

            let resizer = ImageResizeSliderView(
                initialWidth: currentWidth,
                minWidth: minWidth,
                maxWidth: maxWidth,
                naturalWidth: naturalWidth,
                onChange: { [weak self] newWidth in
                    self?.resizeImage(at: ctx.charIndex, toWidth: newWidth)
                }
            )
            popover.contentViewController = NSHostingController(rootView: resizer)
            popover.show(relativeTo: imageRect, of: tv, preferredEdge: .maxY)
        }

        /// Resize the attachment's image to the given width, preserving
        /// aspect ratio. Same write path the preset menu items use —
        /// mutates `attachment.image.size` (the render hint AppKit
        /// honors) and re-attaches.
        fileprivate func resizeImage(at charIndex: Int, toWidth width: CGFloat) {
            guard let tv = textView, let storage = tv.textStorage,
                  charIndex < storage.length,
                  let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment else { return }

            let sourceImage: NSImage? = {
                if let data = attachment.fileWrapper?.regularFileContents,
                   let img = NSImage(data: data) {
                    return img
                }
                return attachment.image
            }()
            guard let image = sourceImage else { return }

            let naturalSize: CGSize = {
                if let rep = image.representations.first, rep.pixelsWide > 0 {
                    return CGSize(width: CGFloat(rep.pixelsWide),
                                  height: CGFloat(rep.pixelsHigh))
                }
                return image.size
            }()
            let aspect = naturalSize.height / max(naturalSize.width, 1)
            let newSize = CGSize(width: width, height: width * aspect)

            image.size = newSize
            attachment.image = image
            attachment.bounds = CGRect(origin: .zero, size: newSize)

            let range = NSRange(location: charIndex, length: 1)
            storage.beginEditing()
            storage.removeAttribute(.attachment, range: range)
            storage.addAttribute(.attachment, value: attachment, range: range)
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
            storage.endEditing()
            tv.didChangeText()
            tv.layoutManager?.invalidateLayout(forCharacterRange: range,
                                                actualCharacterRange: nil)
            tv.needsDisplay = true
        }

        /// Compute the on-screen rect of the attachment at `charIndex`
        /// in the text view's coordinate space, suitable for anchoring
        /// an `NSPopover`. Falls back to a small rect at the text
        /// container origin if layout isn't available.
        private static func attachmentRect(in tv: NSTextView, charIndex: Int) -> NSRect {
            guard let layoutManager = tv.layoutManager,
                  let container = tv.textContainer else {
                return NSRect(origin: tv.textContainerOrigin, size: NSSize(width: 1, height: 1))
            }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: charIndex, length: 1),
                actualCharacterRange: nil
            )
            let containerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            return containerRect.offsetBy(
                dx: tv.textContainerOrigin.x,
                dy: tv.textContainerOrigin.y
            )
        }

        @objc private func handleImageResize(_ sender: NSMenuItem) {
            guard let request = sender.representedObject as? ImageResizeRequest,
                  let tv = textView,
                  let storage = tv.textStorage,
                  request.charIndex < storage.length,
                  let attachment = storage.attribute(.attachment, at: request.charIndex, effectiveRange: nil) as? NSTextAttachment else { return }

            // Always reload the image from the file wrapper bytes when
            // possible. That preserves natural-size pixel data across
            // repeated resizes — we set `image.size` (a render-time
            // hint) without resampling the bitmap, so successive
            // resizes don't progressively degrade quality. If no
            // fileWrapper is in scope (shouldn't happen post-paste),
            // fall back to the existing `attachment.image`.
            let sourceImage: NSImage? = {
                if let data = attachment.fileWrapper?.regularFileContents,
                   let img = NSImage(data: data) {
                    return img
                }
                return attachment.image
            }()
            guard let image = sourceImage else { return }

            // Use the source's pixel-rep size as the natural reference,
            // not whatever `image.size` happens to be after a prior
            // resize. NSImage.size is mutable; the bitmap rep's size
            // is the ground truth.
            let naturalSize: CGSize = {
                if let rep = image.representations.first {
                    let pixelSize = CGSize(width: CGFloat(rep.pixelsWide),
                                           height: CGFloat(rep.pixelsHigh))
                    if pixelSize.width > 0 { return pixelSize }
                }
                return image.size
            }()

            let aspect = naturalSize.height / max(naturalSize.width, 1)
            let target = request.option.targetWidth(naturalWidth: naturalSize.width)
            let newSize: CGSize
            if target <= 0 {
                newSize = naturalSize
            } else {
                newSize = CGSize(width: target, height: target * aspect)
            }

            // The layout manager queries `attachment.image.size` for
            // image attachments — NOT `attachment.bounds`. Setting
            // image.size is the only thing that actually moves the
            // rendered dimensions in the editor. We set bounds too as
            // a belt-and-braces measure; some attachment subclasses
            // do consult it.
            image.size = newSize
            attachment.image = image
            attachment.bounds = CGRect(origin: .zero, size: newSize)

            let range = NSRange(location: request.charIndex, length: 1)
            storage.beginEditing()
            storage.removeAttribute(.attachment, range: range)
            storage.addAttribute(.attachment, value: attachment, range: range)
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
            storage.endEditing()
            tv.didChangeText()
            tv.layoutManager?.invalidateLayout(forCharacterRange: range,
                                                actualCharacterRange: nil)
            tv.needsDisplay = true
        }

        /// Returns the attachment at `charIndex` or `charIndex - 1` when
        /// either renders as an image (has `.image` or a non-empty
        /// `fileWrapper`). nil when no image attachment is in scope.
        private static func locateImageAttachment(in storage: NSTextStorage,
                                                  near charIndex: Int) -> (charIndex: Int, attachment: NSTextAttachment)? {
            for probe in [charIndex, charIndex - 1] where probe >= 0 && probe < storage.length {
                guard let att = storage.attribute(.attachment, at: probe, effectiveRange: nil) as? NSTextAttachment else { continue }
                if att.image != nil { return (probe, att) }
                if let wrapper = att.fileWrapper, wrapper.isRegularFile {
                    return (probe, att)
                }
            }
            return nil
        }
    }
}

// MARK: - Image resize options

private enum ImageResizeOption: CaseIterable {
    case small, medium, large, original

    var title: String {
        switch self {
        case .small:    return "Small"
        case .medium:   return "Medium"
        case .large:    return "Large"
        case .original: return "Original size"
        }
    }

    /// Target render width in points. `.original` returns -1 to signal
    /// "use the image's natural size as-pasted."
    func targetWidth(naturalWidth: CGFloat) -> CGFloat {
        switch self {
        case .small:    return 200
        case .medium:   return 400
        case .large:    return 800
        case .original: return -1
        }
    }
}

private struct ImageResizeRequest {
    let charIndex: Int
    let option: ImageResizeOption
}

/// Carries just the attachment's character index to the popover-open
/// handler. The handler does its own width lookup from the attachment.
private struct ImageResizeContext {
    let charIndex: Int
}

// MARK: - Slider popover

/// SwiftUI content for the image-resize popover. A continuous slider
/// fires `onChange` on every drag tick, so the image resizes in real
/// time as the user drags. Discrete preset buttons below the slider
/// jump to common widths without dragging.
private struct ImageResizeSliderView: View {
    @State var width: Double
    let minWidth: Double
    let maxWidth: Double
    let naturalWidth: Double
    let onChange: (CGFloat) -> Void

    init(initialWidth: CGFloat,
         minWidth: CGFloat,
         maxWidth: CGFloat,
         naturalWidth: CGFloat,
         onChange: @escaping (CGFloat) -> Void) {
        self._width = State(initialValue: Double(initialWidth))
        self.minWidth = Double(minWidth)
        self.maxWidth = Double(maxWidth)
        self.naturalWidth = Double(naturalWidth)
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Width").font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int(width)) pt")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $width, in: minWidth...maxWidth)
                .onChange(of: width) { _, newValue in
                    onChange(CGFloat(newValue))
                }
            HStack(spacing: 6) {
                preset(label: "Small",    value: 200)
                preset(label: "Medium",   value: 400)
                preset(label: "Large",    value: 800)
                preset(label: "Original", value: naturalWidth)
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder
    private func preset(label: String, value: Double) -> some View {
        Button {
            let clamped = min(max(value, minWidth), maxWidth)
            width = clamped
            onChange(CGFloat(clamped))
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Registry

/// Bridges the rich-text toolbar (SwiftUI) to whichever `NSTextView` is in
/// focus. Last text view wins — fine while only one editor is on-screen.
@MainActor
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
    /// to stay backward-compatible with attachment-free notes.
    func toRTFData() -> Data? {
        let range = NSRange(location: 0, length: length)
        if attachmentCount > 0 {
            // NSTextView paste may stash images via `attachment.image`
            // without a `fileWrapper`. RTFD persistence reads bytes from
            // the file wrapper, so synthesize one when missing — and
            // downscale/compress while we're there, so notes don't blow
            // through the CloudKit record-size budget.
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
    /// after pasting a screenshot in NSTextView), an image is synthesized
    /// — downscaled to `maxImageWidth` if it's wider than that, and
    /// encoded as JPEG @ 0.7 when the image has no alpha channel; PNG
    /// otherwise. When neither an image nor a wrapper is available, falls
    /// back to `NSTextAttachmentCell` rendering.
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
            guard let originalImage = image else { return }

            let (downsized, _) = RichTextImagePolicy.downscaleIfNeeded(originalImage)
            guard let (data, ext) = RichTextImagePolicy.encode(downsized) else { return }
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = "image-\(UUID().uuidString.prefix(8)).\(ext)"
            att.fileWrapper = wrapper
            // Modern NSTextAttachment.image is the path NSTextView uses
            // when `allowsImageEditing == true` to draw the interactive
            // resize handles on click. Legacy `attachmentCell` would
            // route through the cell renderer and disable handles, so
            // clear it explicitly (the paste path may have set it).
            att.image = downsized
            att.attachmentCell = nil
            m.removeAttribute(.attachment, range: range)
            m.addAttribute(.attachment, value: att, range: range)
        }
        return m
    }
}

// MARK: - Image policy

/// Pasted-image sizing + format policy. Caps width at 1920 px and
/// prefers JPEG @ 0.7 for non-alpha images. Keeps RTFD bodies under
/// the CloudKit `encryptedValues` ~1 MB ceiling without changing the
/// E2E guarantee (the encoded bytes still travel inside the
/// `fieldsJSON` envelope).
///
/// Non-isolated — pure operations on `NSImage` byte representations,
/// no actor-local state. Allows the `ensureAttachmentFileWrappers`
/// enumerate-closure (which is non-isolated) to call into it freely.
enum RichTextImagePolicy {

    /// Above this width (in px), incoming images are scaled down.
    /// Chosen high enough to preserve legibility of screenshot text on
    /// retina displays while avoiding multi-MB photo pastes that would
    /// blow through the record budget.
    static let maxImageWidth: CGFloat = 1920

    /// JPEG quality for the non-alpha encode path. 0.7 is the sweet
    /// spot between visible-loss-on-photos (negligible) and bytes-saved
    /// vs PNG (often 5–10× smaller for photographic content).
    static let jpegQuality: CGFloat = 0.7

    /// Downscale `image` to `maxImageWidth` if it's wider, preserving
    /// aspect ratio. Returns `(image, downscaled)` so callers can log
    /// the decision if useful.
    static func downscaleIfNeeded(_ image: NSImage) -> (image: NSImage, downscaled: Bool) {
        let width = image.size.width
        guard width > maxImageWidth else { return (image, false) }
        let scale = maxImageWidth / width
        let newSize = NSSize(width: width * scale, height: image.size.height * scale)
        let smaller = NSImage(size: newSize)
        smaller.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        smaller.unlockFocus()
        return (smaller, true)
    }

    /// Encode `image` to bytes. JPEG when the image has no alpha
    /// (photos, screenshots without transparency); PNG otherwise. The
    /// `ext` is the matching file extension for the wrapper name —
    /// AppKit's RTFD reader infers content type from filename in
    /// addition to bytes.
    static func encode(_ image: NSImage) -> (data: Data, ext: String)? {
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }
        let hasAlpha = rep.hasAlpha
        if hasAlpha {
            guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
            return (png, "png")
        }
        let props: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: jpegQuality
        ]
        guard let jpeg = rep.representation(using: .jpeg, properties: props) else { return nil }
        return (jpeg, "jpg")
    }
}
