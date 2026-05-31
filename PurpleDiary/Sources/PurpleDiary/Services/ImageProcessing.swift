import Foundation
import AppKit

/// Pure image helpers for the photo-import path: downscale a full-resolution
/// import to a sane archival size and generate a small preview thumbnail. Kept
/// separate from PhotoKit so the resizing logic is testable without a photo
/// library. Adapted from Timeliner's `AttachmentService.makeThumbnail`.
enum ImageProcessing {

    /// Largest edge (points) we keep for the stored full image. Journaling
    /// context doesn't need camera-original resolution, and capping keeps the
    /// SQLCipher database from ballooning.
    static let maxImageEdge: CGFloat = 2048

    /// Edge (points) of the preview thumbnail rendered in the editor strip.
    static let thumbnailEdge: CGFloat = 256

    struct EncodedImage {
        var data: Data
        var width: Int
        var height: Int
    }

    /// Downscale (never upscale) to fit within `maxEdge` and JPEG-encode.
    /// Returns nil for inputs that don't decode as a bitmap.
    static func downscaledJPEG(from data: Data,
                               maxEdge: CGFloat = maxImageEdge,
                               quality: CGFloat = 0.8) -> EncodedImage? {
        guard let rep = renderScaled(from: data, maxEdge: maxEdge) else { return nil }
        guard let out = rep.representation(using: .jpeg,
                                           properties: [.compressionFactor: quality]) else { return nil }
        return EncodedImage(data: out, width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// Small JPEG preview (≤ `edge` points) for list/strip rendering.
    static func thumbnailJPEG(from data: Data, edge: CGFloat = thumbnailEdge) -> Data? {
        renderScaled(from: data, maxEdge: edge)?
            .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    // MARK: - Private

    private static func renderScaled(from data: Data, maxEdge: CGFloat) -> NSBitmapImageRep? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(maxEdge / size.width, maxEdge / size.height, 1.0)
        let pxWidth = max(1, Int((size.width * scale).rounded()))
        let pxHeight = max(1, Int((size.height * scale).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxWidth, pixelsHigh: pxHeight,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pxWidth, height: pxHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        image.draw(in: CGRect(x: 0, y: 0, width: pxWidth, height: pxHeight),
                   from: .zero, operation: .copy, fraction: 1.0)
        return rep
    }
}
