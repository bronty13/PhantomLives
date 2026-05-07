import Foundation
import AppKit
import UniformTypeIdentifiers

/// Helpers for adding attachments to the database.
///
/// All file bytes go through this service so the thumbnail-generation,
/// MIME-detection, and size-cap policies live in one place. Storage backend
/// is `DatabaseService` — the actual rows live in the `attachments` table
/// as BLOBs and are auto-included in DB backups.
@MainActor
enum AttachmentService {

    /// Cap each attachment at this many bytes. SQLite handles BLOBs much
    /// larger than this just fine, but Timeliner's "attachment included in
    /// the backup zip" model means a single 50 MB photo could noticeably
    /// inflate every backup. Surfaces a clear error to the user instead of
    /// silently swallowing huge files.
    static let maxBytes: Int64 = 25 * 1024 * 1024  // 25 MB

    /// Edge length of the generated image thumbnail in points (we render
    /// @2x, so the actual pixels are this × 2).
    static let thumbnailEdge: CGFloat = 256

    enum AddError: Error, LocalizedError {
        case fileTooBig(actual: Int64, limit: Int64)
        case unreadable(String)
        case ioFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileTooBig(let a, let l):
                let mb = { (b: Int64) in String(format: "%.1f", Double(b) / 1024 / 1024) }
                return "File is too large: \(mb(a)) MB (limit \(mb(l)) MB)."
            case .unreadable(let s): return "Couldn't read the file: \(s)"
            case .ioFailed(let s):   return "Database write failed: \(s)"
            }
        }
    }

    /// Read `url`, build an Attachment, persist via DatabaseService, and
    /// return the inserted row. Generates a thumbnail when the input is
    /// recognized as an image type.
    @discardableResult
    static func addAttachment(
        from url: URL,
        to parent: AttachmentParent,
        parentId: String,
        position: Int = 0
    ) throws -> Attachment {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: url.path) else {
            throw AddError.unreadable("not readable: \(url.path)")
        }

        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > maxBytes {
            throw AddError.fileTooBig(actual: size, limit: maxBytes)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AddError.unreadable(error.localizedDescription)
        }

        let mimeType = mimeType(for: url)
        let thumbnail: Data? = mimeType.hasPrefix("image/") ? makeThumbnail(from: data) : nil

        let attachment = Attachment(
            id: UUID().uuidString,
            parentType: parent.rawValue,
            parentId: parentId,
            filename: url.lastPathComponent,
            mimeType: mimeType,
            sizeBytes: Int64(data.count),
            data: data,
            thumbnailData: thumbnail,
            position: position,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try DatabaseService.shared.insertAttachment(attachment)
        } catch {
            throw AddError.ioFailed(error.localizedDescription)
        }
        return attachment
    }

    /// Build attachments from a paste / drop — same path, just for raw
    /// `Data` instead of a file URL.
    @discardableResult
    static func addAttachment(
        bytes: Data,
        suggestedName: String,
        mimeType: String,
        to parent: AttachmentParent,
        parentId: String,
        position: Int = 0
    ) throws -> Attachment {
        if Int64(bytes.count) > maxBytes {
            throw AddError.fileTooBig(actual: Int64(bytes.count), limit: maxBytes)
        }
        let thumbnail: Data? = mimeType.hasPrefix("image/") ? makeThumbnail(from: bytes) : nil
        let attachment = Attachment(
            id: UUID().uuidString,
            parentType: parent.rawValue,
            parentId: parentId,
            filename: suggestedName,
            mimeType: mimeType,
            sizeBytes: Int64(bytes.count),
            data: bytes,
            thumbnailData: thumbnail,
            position: position,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try DatabaseService.shared.insertAttachment(attachment)
        return attachment
    }

    // MARK: - Helpers

    /// Mime-type lookup via the file extension.  Falls back to the generic
    /// `application/octet-stream` if the extension isn't recognized.
    private static func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension),
           let mime = utType.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    /// Down-scale + JPEG-encode an image into a small (≤ 256 pt) preview.
    /// Returns nil for inputs that aren't decodable as bitmap images
    /// (e.g., SVG, malformed data).
    private static func makeThumbnail(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let scale = min(thumbnailEdge / originalSize.width,
                        thumbnailEdge / originalSize.height,
                        1.0)
        let target = CGSize(
            width: max(1, originalSize.width * scale),
            height: max(1, originalSize.height * scale)
        )

        // Render at 2x for retina; resulting JPEG is small enough that
        // rendering at 1x isn't worth the loss.
        let pxWidth = Int(target.width * 2)
        let pxHeight = Int(target.height * 2)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxWidth, pixelsHigh: pxHeight,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        image.draw(
            in: CGRect(origin: .zero, size: target),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// Open a file picker and return the chosen URLs. Helper for the
    /// "Add attachment…" button so the views don't carry NSOpenPanel
    /// boilerplate.
    static func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Add attachment"
        panel.prompt = "Add"
        if panel.runModal() == .OK { return panel.urls }
        return []
    }

    /// Write an attachment's bytes to disk so the user can save / reveal /
    /// open it externally. Returns the destination URL on success.
    @discardableResult
    static func saveAttachmentToDisk(_ attachment: Attachment, in directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(attachment.filename)
        try attachment.data.write(to: target, options: .atomic)
        return target
    }
}
