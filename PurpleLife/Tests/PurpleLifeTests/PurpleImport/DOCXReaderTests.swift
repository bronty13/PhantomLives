import XCTest
import ZIPFoundation
@testable import PurpleLife

/// DOCXReader tests. We hand-roll a minimum-viable .docx fixture
/// in-memory rather than shipping a binary. The fixture covers:
///   • Two paragraphs (`<w:p>` blocks).
///   • Soft line-break (`<w:br/>`) mid-paragraph.
///   • Tab mark (`<w:tab/>`).
///   • A `<w:tbl>` block whose text MUST be skipped per the locked
///     v1 contract.
@MainActor
final class DOCXReaderTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeDocx(documentXML: String) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        </Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        </Relationships>
        """
        let parts: [(String, String)] = [
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", rootRels),
            ("word/document.xml", documentXML)
        ]
        for (path, body) in parts {
            let bytes = Data(body.utf8)
            try archive.addEntry(
                with: path, type: .file,
                uncompressedSize: Int64(bytes.count),
                compressionMethod: .deflate,
                provider: { pos, size in
                    let start = Int(pos); let end = min(start + size, bytes.count)
                    return bytes.subdata(in: start..<end)
                }
            )
        }
        return archive.data ?? Data()
    }

    private func source(_ data: Data) -> PurpleImport.SourceInput {
        .data(data, filenameHint: "test.docx")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    // MARK: - Tests

    func testTwoParagraphsConcatenatedWithBlankLine() async throws {
        let docXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>First paragraph</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second paragraph</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """#
        let data = try makeDocx(documentXML: docXML)
        let reader = DOCXReader()
        let rows = try await collect(reader.read(source(data)))
        XCTAssertEqual(rows.count, 1)
        let body = try XCTUnwrap(rows[0].cell(at: .path("$._body")) as? String)
        XCTAssertEqual(body, "First paragraph\n\nSecond paragraph")
    }

    func testSoftBreakWithinParagraphBecomesNewline() async throws {
        let docXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>Line one</w:t></w:r>
              <w:r><w:br/><w:t>Line two</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """#
        let data = try makeDocx(documentXML: docXML)
        let reader = DOCXReader()
        let body = try await reader.extractText(from: source(data))
        XCTAssertEqual(body, "Line one\nLine two")
    }

    func testTabMarkBecomesLiteralTab() async throws {
        let docXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>Column1</w:t><w:tab/><w:t>Column2</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """#
        let data = try makeDocx(documentXML: docXML)
        let reader = DOCXReader()
        let body = try await reader.extractText(from: source(data))
        XCTAssertEqual(body, "Column1\tColumn2")
    }

    /// **Locked v1 scope contract.** Table contents must NOT appear in
    /// the extracted body. This is the single most-important
    /// assertion in the suite — if it ever flips we've started
    /// implementing table extraction and the HANDOFF note needs an
    /// update first.
    func testTableContentIsSkipped() async throws {
        let docXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Body before table</w:t></w:r></w:p>
            <w:tbl>
              <w:tr>
                <w:tc><w:p><w:r><w:t>Cell A1</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Cell B1</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:p><w:r><w:t>Cell A2</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Cell B2</w:t></w:r></w:p></w:tc>
              </w:tr>
            </w:tbl>
            <w:p><w:r><w:t>Body after table</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """#
        let data = try makeDocx(documentXML: docXML)
        let reader = DOCXReader()
        let body = try await reader.extractText(from: source(data))
        XCTAssertFalse(body.contains("Cell A1"), "Table cell text leaked into body — v1 scope violated.")
        XCTAssertFalse(body.contains("Cell B2"), "Table cell text leaked into body — v1 scope violated.")
        XCTAssertTrue(body.contains("Body before table"))
        XCTAssertTrue(body.contains("Body after table"))
    }

    func testCustomParagraphSeparatorOption() async throws {
        let docXML = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>A</w:t></w:r></w:p>
            <w:p><w:r><w:t>B</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """#
        let data = try makeDocx(documentXML: docXML)
        let reader = DOCXReader()
        reader.setOptions(["paragraphSeparator": " | "])
        let body = try await reader.extractText(from: source(data))
        XCTAssertEqual(body, "A | B")
    }

    func testMissingDocumentXMLThrows() async throws {
        // Build a zip whose only content is a stray file — no
        // word/document.xml. Mirrors a renamed .zip masquerading as
        // .docx.
        let archive = try Archive(data: Data(), accessMode: .create)
        let stub = Data("not a docx".utf8)
        try archive.addEntry(
            with: "junk.txt", type: .file,
            uncompressedSize: Int64(stub.count),
            compressionMethod: .deflate,
            provider: { pos, size in
                let start = Int(pos); let end = min(start + size, stub.count)
                return stub.subdata(in: start..<end)
            }
        )
        let data = archive.data ?? Data()
        let reader = DOCXReader()
        do {
            _ = try await reader.probe(source(data))
            XCTFail("Expected DOCXReaderError.missingDocumentXML.")
        } catch DOCXReaderError.missingDocumentXML {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
