import AppKit

/// Renders a lightweight "page preview" thumbnail for a markdown file — a white
/// document card with a purple accent and the first lines of the file, lightly
/// styled (headings bold, bullets dotted). Fast and synchronous (Core Text), so
/// it's safe inside a Quick Look thumbnail extension's tight time/memory budget.
/// Shared by `PurpleMarkThumbnail` and unit-testable via `previewLines`.
public enum MarkdownThumbnail {

    public enum LineKind: Equatable {
        case h1, h2, heading, bullet, quote, code, normal
    }

    public struct Line: Equatable {
        public let kind: LineKind
        public let text: String
        public init(kind: LineKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Classifies the first `max` meaningful lines for display. Strips markdown
    /// markers (so `# Title` → `Title`, `- item` → `item`). Skips leading blank
    /// lines and the contents of fenced code blocks beyond their first line.
    public static func previewLines(from markdown: String, max: Int = 14) -> [Line] {
        var out: [Line] = []
        var inFence = false
        var fence = ""
        var started = false
        for raw in markdown.components(separatedBy: "\n") {
            if out.count >= max { break }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if !inFence { inFence = true; fence = marker; out.append(Line(kind: .code, text: trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))) }
                else if trimmed.hasPrefix(fence) { inFence = false }
                started = true
                continue
            }
            if inFence {
                out.append(Line(kind: .code, text: raw))
                started = true
                continue
            }
            if trimmed.isEmpty {
                if started, let last = out.last, last.text.isEmpty == false { /* allow a single gap implicitly */ }
                continue
            }
            started = true
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed { if ch == "#" { level += 1 } else { break } }
                let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                let kind: LineKind = level == 1 ? .h1 : (level == 2 ? .h2 : .heading)
                out.append(Line(kind: kind, text: String(title)))
            } else if let r = trimmed.range(of: #"^([-*+]|\d+\.)\s+"#, options: .regularExpression) {
                out.append(Line(kind: .bullet, text: String(trimmed[r.upperBound...])))
            } else if trimmed.hasPrefix(">") {
                out.append(Line(kind: .quote, text: trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else {
                out.append(Line(kind: .normal, text: stripInline(trimmed)))
            }
        }
        return out
    }

    /// Removes the most common inline markers for a cleaner thumbnail.
    private static func stripInline(_ s: String) -> String {
        var t = s
        for token in ["**", "__", "`", "~~"] { t = t.replacingOccurrences(of: token, with: "") }
        return t
    }

    /// Draws the thumbnail into the current `NSGraphicsContext` at `size`.
    public static func draw(markdown: String, size: CGSize) {
        let pageColor = NSColor.white
        let accent = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.92, alpha: 1)
        let headingColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        let bodyColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        let mutedColor = NSColor(calibratedWhite: 0.62, alpha: 1)

        let inset = size.width * 0.06
        let page = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        let radius = size.width * 0.05

        // Drop shadow + page.
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = size.width * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -size.width * 0.012)
        shadow.set()
        let pagePath = NSBezierPath(roundedRect: page, xRadius: radius, yRadius: radius)
        pageColor.setFill()
        pagePath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Clip subsequent text to the page.
        NSGraphicsContext.current?.saveGraphicsState()
        pagePath.addClip()

        // Purple accent bar across the top of the page.
        let barHeight = page.height * 0.045
        accent.setFill()
        NSBezierPath(rect: NSRect(x: page.minX, y: page.maxY - barHeight, width: page.width, height: barHeight)).fill()

        // Lay out the preview lines top-down.
        let padX = page.width * 0.1
        let contentX = page.minX + padX
        let contentW = page.width - padX * 2
        let base = size.width * 0.058         // base font size scales with thumbnail
        var y = page.maxY - barHeight - page.height * 0.06

        for line in previewLines(from: markdown, max: 16) {
            if y < page.minY + base { break }
            let (font, color, indent, size2): (NSFont, NSColor, CGFloat, CGFloat)
            switch line.kind {
            case .h1:      (font, color, indent, size2) = (.systemFont(ofSize: base * 1.7, weight: .bold), headingColor, 0, base * 1.7)
            case .h2:      (font, color, indent, size2) = (.systemFont(ofSize: base * 1.35, weight: .bold), headingColor, 0, base * 1.35)
            case .heading: (font, color, indent, size2) = (.systemFont(ofSize: base * 1.15, weight: .semibold), headingColor, 0, base * 1.15)
            case .bullet:  (font, color, indent, size2) = (.systemFont(ofSize: base, weight: .regular), bodyColor, base * 1.1, base)
            case .quote:   (font, color, indent, size2) = (.systemFont(ofSize: base, weight: .regular), mutedColor, base * 0.8, base)
            case .code:    (font, color, indent, size2) = (.monospacedSystemFont(ofSize: base * 0.92, weight: .regular), mutedColor, 0, base)
            case .normal:  (font, color, indent, size2) = (.systemFont(ofSize: base, weight: .regular), bodyColor, 0, base)
            }

            // Bullet dot / quote bar.
            if line.kind == .bullet {
                bodyColor.setFill()
                let r = base * 0.16
                NSBezierPath(ovalIn: NSRect(x: contentX + indent * 0.35, y: y - size2 * 0.55, width: r * 2, height: r * 2)).fill()
            } else if line.kind == .quote {
                accent.withAlphaComponent(0.5).setFill()
                NSBezierPath(rect: NSRect(x: contentX, y: y - size2, width: base * 0.18, height: size2 * 1.2)).fill()
            }

            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
            let textRect = NSRect(x: contentX + indent, y: y - size2 * 1.15, width: contentW - indent, height: size2 * 1.3)
            (line.text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)

            let gap: CGFloat
            switch line.kind {
            case .h1: gap = size2 * 1.7
            case .h2, .heading: gap = size2 * 1.5
            default: gap = size2 * 1.45
            }
            y -= gap
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
