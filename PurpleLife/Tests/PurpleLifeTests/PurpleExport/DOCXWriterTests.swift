import XCTest
@testable import PurpleLife

/// DOCXWriter tests. The strongest assertion is the round-trip
/// through DOCXReader — we write a fixture with the emitter, feed
/// the bytes back through the reader, and confirm every field value
/// shows up in the extracted body. This pins both writers and
/// readers to the same OOXML contract without needing Word to be
/// installed.
@MainActor
final class DOCXWriterTests: XCTestCase {

    // MARK: - Fixtures

    private func makeFixture() -> (SourceTypeInfo, [SourceFieldInfo], [PurpleExport.FieldSelection], [SourceRecord]) {
        let type = SourceTypeInfo(
            id: "test-type",
            name: "Book",
            pluralName: "Books",
            systemImage: "book",
            isVault: false
        )
        let fields = [
            SourceFieldInfo(key: "title",   name: "Title",   kind: .text,    options: []),
            SourceFieldInfo(key: "pages",   name: "Pages",   kind: .number,  options: []),
            SourceFieldInfo(key: "read",    name: "Read",    kind: .boolean, options: [])
        ]
        let selections = fields.map {
            PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: $0.key, header: $0.name)
        }
        let records: [SourceRecord] = [
            SourceRecord(
                id: "rec-1", typeId: type.id,
                createdAt: "2024-01-15T10:00:00Z", updatedAt: "2024-01-15T10:00:00Z",
                fields: ["title": "Dune", "pages": 412.0, "read": true]
            ),
            SourceRecord(
                id: "rec-2", typeId: type.id,
                createdAt: "2024-01-16T10:00:00Z", updatedAt: "2024-01-16T10:00:00Z",
                fields: ["title": "Children of Time", "pages": 600.0, "read": false]
            )
        ]
        return (type, fields, selections, records)
    }

    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("docx-writer-test-\(UUID().uuidString).docx")
    }

    private let linkResolver: (String) -> String? = { _ in nil }
    private let attachmentResolver: (String) -> String? = { _ in nil }

    // MARK: - Smoke

    func testWriterReportsDOCXFormat() {
        XCTAssertEqual(DOCXWriter().format, .docx)
    }

    func testXMLEscapeHandlesPunctuation() {
        let s = "<b>hi & \"bye\"</b>"
        XCTAssertEqual(
            DOCXWriter.xmlEscape(s),
            "&lt;b&gt;hi &amp; &quot;bye&quot;&lt;/b&gt;"
        )
    }

    // MARK: - Round-trip through DOCXReader

    func testRoundTripThroughDOCXReader() async throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = DOCXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        XCTAssertGreaterThan(bytes, 0)

        // Read it back.
        let reader = DOCXReader()
        let data = try Data(contentsOf: url)
        let body = try await reader.extractText(from: .data(data, filenameHint: "out.docx"))

        // Type header lands as a paragraph.
        XCTAssertTrue(body.contains("Books"), "Type plural name should appear as the document heading.")

        // Per-record heading + per-field label-value paragraphs.
        XCTAssertTrue(body.contains("Record rec-1"))
        XCTAssertTrue(body.contains("Record rec-2"))
        XCTAssertTrue(body.contains("Title: Dune"))
        XCTAssertTrue(body.contains("Title: Children of Time"))
        XCTAssertTrue(body.contains("Pages: 412"))
        XCTAssertTrue(body.contains("Pages: 600"))
        XCTAssertTrue(body.contains("Read: true"))
        XCTAssertTrue(body.contains("Read: false"))

        // created_at / updated_at land too.
        XCTAssertTrue(body.contains("created_at: 2024-01-15T10:00:00Z"))
        XCTAssertTrue(body.contains("updated_at: 2024-01-16T10:00:00Z"))
    }

    func testWriterEscapesXMLSpecialCharsInFieldValues() async throws {
        let type = SourceTypeInfo(id: "t", name: "T", pluralName: "Ts", systemImage: "circle", isVault: false)
        let fields = [SourceFieldInfo(key: "note", name: "Note", kind: .text, options: [])]
        let selections = [PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: "note", header: "Note")]
        let records = [SourceRecord(
            id: "r1", typeId: "t", createdAt: "n", updatedAt: "n",
            fields: ["note": "<b>hi & bye</b>"]
        )]
        let writer = DOCXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let reader = DOCXReader()
        let data = try Data(contentsOf: url)
        let body = try await reader.extractText(from: .data(data, filenameHint: "out.docx"))
        // XMLParser un-escapes the entities back to the original chars
        // when reading — strongest possible test for escape correctness.
        XCTAssertTrue(body.contains("<b>hi & bye</b>"), "Expected un-escaped chars in round-tripped body; got: \(body)")
    }

    func testEmptyRecordSetStillProducesValidDocument() async throws {
        let type = SourceTypeInfo(id: "t", name: "T", pluralName: "Ts", systemImage: "circle", isVault: false)
        let writer = DOCXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try writer.write(
            type: type, fields: [], selections: [], records: [],
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        XCTAssertGreaterThan(bytes, 0)
        let reader = DOCXReader()
        let data = try Data(contentsOf: url)
        let body = try await reader.extractText(from: .data(data, filenameHint: "out.docx"))
        XCTAssertEqual(body, "Ts", "Empty record set should still produce the type-heading paragraph and nothing else.")
    }
}
