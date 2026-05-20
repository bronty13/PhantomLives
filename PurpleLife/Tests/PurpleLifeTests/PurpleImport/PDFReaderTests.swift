import XCTest
import PDFKit
@testable import PurpleLife

/// PDFReader tests. We generate a small PDF in-test rather than
/// shipping a base64 fixture — PDFKit's writer is round-trip-stable
/// enough to give us a deterministic input for the reader to chew on.
@MainActor
final class PDFReaderTests: XCTestCase {

    // MARK: - Fixture generation

    /// Build a PDF whose pages contain the given strings. Uses a
    /// CGPDFContext to render each string with Core Text so PDFKit's
    /// extractor can pull it back out verbatim.
    private func makePDF(pages: [String]) -> Data {
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        for body in pages {
            context.beginPDFPage(nil)
            let font = NSFont.systemFont(ofSize: 12)
            let attributed = NSAttributedString(string: body, attributes: [.font: font])
            // Set up Core Text frame at top-left-ish of the page.
            let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            let path = CGPath(rect: CGRect(x: 72, y: 72, width: 468, height: 648), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()
        return mutableData as Data
    }

    private func dataSource(_ data: Data) -> PurpleImport.SourceInput {
        .data(data, filenameHint: "test.pdf")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    // MARK: - Tests

    func testProbeReturnsDocumentShape() async throws {
        let pdf = makePDF(pages: ["Hello world"])
        let reader = PDFReader()
        let shape = try await reader.probe(dataSource(pdf))
        if case .document(let body) = shape {
            XCTAssertTrue(body.contains("Hello"), "Expected extracted body to contain 'Hello'; got: \(body)")
        } else {
            XCTFail("Expected .document shape; got \(shape)")
        }
    }

    func testPreviewProducesSingleRowWithBodyPath() async throws {
        let pdf = makePDF(pages: ["Line one"])
        let reader = PDFReader()
        let preview = try await reader.preview(dataSource(pdf), sampleSize: 10)
        XCTAssertEqual(preview.sampleRows.count, 1)
        XCTAssertEqual(preview.totalRows, 1)
        let body = preview.sampleRows[0].cell(at: .path("$._body")) as? String
        XCTAssertNotNil(body)
        XCTAssertTrue(body!.contains("Line"))
    }

    func testReadStreamsExactlyOneRow() async throws {
        let pdf = makePDF(pages: ["Only one record per PDF in v1."])
        let reader = PDFReader()
        let rows = try await collect(reader.read(dataSource(pdf)))
        XCTAssertEqual(rows.count, 1, "Locked v1 scope: text-only PDF reader yields exactly one record per document.")
    }

    func testMultiplePagesJoinedWithFormFeedByDefault() async throws {
        let pdf = makePDF(pages: ["Page A", "Page B"])
        let reader = PDFReader()
        let rows = try await collect(reader.read(dataSource(pdf)))
        let body = try XCTUnwrap(rows.first?.cell(at: .path("$._body")) as? String)
        // PDFKit's extraction varies in whitespace — assert the
        // separator landed, not the surrounding text.
        XCTAssertTrue(body.contains("\u{000C}"), "Default page separator is form-feed (\\u{000C}); body was: \(body)")
    }

    func testCustomPageSeparatorOption() async throws {
        let pdf = makePDF(pages: ["A", "B"])
        let reader = PDFReader()
        reader.setOptions(["pageSeparator": "\n\n--- BREAK ---\n\n"])
        let rows = try await collect(reader.read(dataSource(pdf)))
        let body = try XCTUnwrap(rows.first?.cell(at: .path("$._body")) as? String)
        XCTAssertTrue(body.contains("--- BREAK ---"), "Custom page separator should land in the joined body; got: \(body)")
    }

    func testCorruptDataThrowsOpenFailed() async throws {
        let reader = PDFReader()
        do {
            _ = try await reader.probe(.data(Data("not a pdf".utf8), filenameHint: "garbage.pdf"))
            XCTFail("Expected PDFReaderError.openFailed for non-PDF bytes.")
        } catch PDFReaderError.openFailed {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
