import Foundation
import AppKit
import Vision
import PDFKit

/// On-device OCR via the Vision framework. Reads text out of images (and
/// image-only PDF pages) so the "snap a photo / drop a screenshot → read it
/// aloud" path works without any cloud round-trip.
enum OCRService {

    enum OCRError: Error, LocalizedError {
        case badImage
        case empty
        var errorDescription: String? {
            switch self {
            case .badImage: return "Couldn't read that image."
            case .empty:    return "No text was recognized in the image."
            }
        }
    }

    static let supportedImageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "tiff", "tif", "heic", "gif", "bmp"]

    /// Recognize text from an image file. Returns the joined recognized lines.
    static func recognizeText(imageURL url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.badImage
        }
        let text = try recognize(cgImage: cg)
        guard !text.isEmpty else { throw OCRError.empty }
        return text
    }

    static func recognize(cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return TextExtractionService.normalize(lines.joined(separator: "\n"))
    }

    /// OCR every page of an image-only PDF by rasterizing each page and
    /// recognizing it. Used as a fallback when `PDFDocument.string` comes back
    /// empty (scanned PDFs carry no text layer).
    static func recognizePDF(_ url: URL, scale: CGFloat = 2.0) throws -> String {
        guard let pdf = PDFDocument(url: url) else { throw OCRError.badImage }
        var parts: [String] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelW = Int(bounds.width * scale)
            let pixelH = Int(bounds.height * scale)
            guard pixelW > 0, pixelH > 0,
                  let ctx = CGContext(
                    data: nil, width: pixelW, height: pixelH,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            if let cg = ctx.makeImage(), let text = try? recognize(cgImage: cg), !text.isEmpty {
                parts.append(text)
            }
        }
        let joined = parts.joined(separator: "\n\n")
        guard !joined.isEmpty else { throw OCRError.empty }
        return joined
    }
}
