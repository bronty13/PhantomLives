import Foundation
import PDFKit
import AppKit

/// Pure helpers for PDF attachments: a first-page thumbnail for the strip and a
/// page count. PDFKit is a native macOS framework (no Catalyst needed). The PDF
/// bytes themselves are stored verbatim as an encrypted BLOB; this only renders
/// a preview still.
enum PDFProcessing {

    struct Info {
        var thumbnailJPEG: Data?
        var pageCount: Int
    }

    static func info(from data: Data, thumbEdge: CGFloat = ImageProcessing.thumbnailEdge) -> Info? {
        guard let doc = PDFDocument(data: data) else { return nil }
        let pageCount = doc.pageCount
        guard let page = doc.page(at: 0) else { return Info(thumbnailJPEG: nil, pageCount: pageCount) }

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return Info(thumbnailJPEG: nil, pageCount: pageCount) }
        let scale = min(thumbEdge / bounds.width, thumbEdge / bounds.height, 1.0)
        let size = NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))

        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return Info(thumbnailJPEG: nil, pageCount: pageCount)
        }
        return Info(thumbnailJPEG: jpeg, pageCount: pageCount)
    }
}
