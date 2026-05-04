import Foundation
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Helpers for turning user-supplied images (file URLs, NSImages, raw Data
/// from drag-and-drop) into the base64 JPEG strings Ollama's chat API
/// expects on the `images` field of a user message.
enum ImageAttachment {
    /// Maximum long-edge in pixels before re-encoding. Keeps base64 payloads
    /// reasonable for UserDefaults persistence and for the model's input.
    static let maxDimension: CGFloat = 1024

    /// JPEG compression quality used when re-encoding.
    static let jpegQuality: CGFloat = 0.85

    enum Error: Swift.Error, LocalizedError {
        case unreadable
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not read this image."
            case .encodingFailed: return "Could not encode this image."
            }
        }
    }

    /// Loads an image from a file URL, downscales it, re-encodes as JPEG, and
    /// returns the base64 string ready to be attached to a message.
    static func encode(fileURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: fileURL) else { throw Error.unreadable }
        return try encode(image: image)
    }

    /// Loads an image from raw bytes (e.g. drag-and-drop, paste, file
    /// promise), downscales, re-encodes as JPEG, returns base64.
    static func encode(data: Data) throws -> String {
        guard let image = NSImage(data: data) else { throw Error.unreadable }
        return try encode(image: image)
    }

    static func encode(image: NSImage) throws -> String {
        let downscaled = downscale(image, longEdge: maxDimension)
        guard let tiff = downscaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpegData = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: jpegQuality]
              )
        else { throw Error.encodingFailed }
        return jpegData.base64EncodedString()
    }

    /// Decodes a base64-encoded image back into an NSImage for display in
    /// message bubbles.
    static func decode(base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

    /// Returns a copy of the image whose long edge is at most `longEdge`
    /// points. Images already smaller than the bound are returned as-is.
    private static func downscale(_ image: NSImage, longEdge: CGFloat) -> NSImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > longEdge, maxSide > 0 else { return image }

        let scale = longEdge / maxSide
        let target = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let result = NSImage(size: target)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
