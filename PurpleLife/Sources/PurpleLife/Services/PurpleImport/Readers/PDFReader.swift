import Foundation
import PDFKit

/// PDF reader for Purple Import — Phase 5, text-only single-record.
///
/// Locked v1 scope (see HANDOFF 2026-05-19): one record per document,
/// the entire extracted text under `.path("$._body")`. No table
/// extraction (PDFKit has no per-glyph x/y positioning suitable for
/// column reconstruction); no per-page split (a future option, gated
/// behind a real motivating document); no images / annotations.
///
/// Pages are joined with form-feed (`\u{000C}`) separators so a
/// downstream consumer that wants per-page chunks can split on that
/// boundary without losing information. The default presentation
/// inside PurpleLife just maps `$._body` to a `.richText` / `.longText`
/// field on the chosen type.
///
/// Options:
///   • `pageSeparator` (String) — overrides the default form-feed
///     separator. Useful for users who want "\n\n--- page break ---\n\n"
///     in the imported body.
final class PDFReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .pdf }

    private var pageSeparator: String = "\u{000C}"

    func setOptions(_ options: [String: Any]) {
        if let s = options["pageSeparator"] as? String, !s.isEmpty {
            self.pageSeparator = s
        }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let body = try extractText(from: source)
        return .document(richText: body)
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize _: Int) async throws -> PurpleImport.SourcePreview {
        let body = try extractText(from: source)
        let row = PurpleImport.SourceRow(
            cells: [.path("$._body"): body],
            rowIndex: 0
        )
        return PurpleImport.SourcePreview(
            shape: .document(richText: body),
            sampleRows: [row],
            totalRows: 1
        )
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            do {
                let body = try self.extractText(from: source)
                continuation.yield(PurpleImport.SourceRow(
                    cells: [.path("$._body"): body],
                    rowIndex: 0
                ))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Text extraction

    /// Pull every page's text out of the PDF and join with the
    /// configured page separator. `PDFDocument.string` exists, but it
    /// drops page boundaries entirely — the per-page walk preserves
    /// them so a downstream consumer can re-split if useful.
    func extractText(from source: PurpleImport.SourceInput) throws -> String {
        let document: PDFDocument
        switch source {
        case .url(let url):
            guard let d = PDFDocument(url: url) else {
                throw PDFReaderError.openFailed(url.lastPathComponent)
            }
            document = d
        case .data(let data, let hint):
            guard let d = PDFDocument(data: data) else {
                throw PDFReaderError.openFailed(hint ?? "(in-memory)")
            }
            document = d
        }
        var pages: [String] = []
        for i in 0 ..< document.pageCount {
            guard let page = document.page(at: i) else { continue }
            pages.append(page.string ?? "")
        }
        return pages.joined(separator: pageSeparator)
    }
}

// MARK: - Errors

enum PDFReaderError: LocalizedError {
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let name):
            return "Couldn't open PDF ‘\(name)’. The file may be encrypted, corrupt, or scanned-image-only (no embedded text)."
        }
    }
}
