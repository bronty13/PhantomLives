import QuickLookThumbnailing
import ArchiveKit
import AppKit

/// Content-aware Finder thumbnail for archives: a purple archive box badged with
/// the file count (so a `.zip` with 3 files looks different from one with 300).
/// Reads the count via the shared ArchiveKit engine.
final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let fileCount = (try? ArchiveService().info(request.fileURL))?.fileCount
        let size = request.maximumSize
        let reply = QLThumbnailReply(contextSize: size) { (ctx: CGContext) -> Bool in
            Self.draw(in: ctx, size: size, fileCount: fileCount)
            return true
        }
        handler(reply, nil)
    }

    static func draw(in ctx: CGContext, size: CGSize, fileCount: Int?) {
        let s = min(size.width, size.height)
        let inset = s * 0.10
        let rect = CGRect(x: inset, y: inset, width: size.width - 2*inset, height: size.height - 2*inset)
        let radius = s * 0.16

        // Purple gradient body.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        let colors = [CGColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1),
                      CGColor(red: 0.36, green: 0.16, blue: 0.78, alpha: 1)]
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size.height),
                                   end: CGPoint(x: 0, y: 0), options: [])
        }
        ctx.restoreGState()

        // A white "lid" line across the box.
        let lidY = rect.minY + rect.height * 0.62
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(max(1, s * 0.02))
        ctx.move(to: CGPoint(x: rect.minX + rect.width*0.12, y: lidY))
        ctx.addLine(to: CGPoint(x: rect.maxX - rect.width*0.12, y: lidY))
        ctx.strokePath()

        // File-count badge text, centered in the lower half.
        let label = fileCount.map { $0 == 1 ? "1 file" : "\($0)" } ?? "ZIP"
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let fontSize = s * (label.count > 4 ? 0.16 : 0.24)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let textSize = str.size()
        let p = CGPoint(x: rect.midX - textSize.width/2,
                        y: rect.minY + rect.height*0.30 - textSize.height/2)
        str.draw(at: p)
        NSGraphicsContext.restoreGraphicsState()
    }
}
