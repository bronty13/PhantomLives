import XCTest
@testable import PurpleLife

/// End-to-end smoke tests for the Phase 4 writers. Drives each
/// writer against a small in-memory record set, writes to a tempfile,
/// and asserts on the bytes (round-trip via the matching reader
/// where one exists).
@MainActor
final class ExportWritersTests: XCTestCase {

    private func makeFixture() -> (SourceTypeInfo, [SourceFieldInfo], [PurpleExport.FieldSelection], [SourceRecord]) {
        let type = SourceTypeInfo(
            id: "test-type",
            name: "Person",
            pluralName: "People",
            systemImage: "person",
            isVault: false
        )
        let fields = [
            SourceFieldInfo(key: "name", name: "Name", kind: .text, options: []),
            SourceFieldInfo(key: "age", name: "Age", kind: .number, options: []),
            SourceFieldInfo(key: "active", name: "Active", kind: .boolean, options: [])
        ]
        let selections = fields.map {
            PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: $0.key, header: $0.name)
        }
        let records: [SourceRecord] = [
            SourceRecord(
                id: "rec-1", typeId: type.id,
                createdAt: "2024-01-15T10:00:00Z", updatedAt: "2024-01-15T10:00:00Z",
                fields: ["name": "Ada", "age": 36.0, "active": true]
            ),
            SourceRecord(
                id: "rec-2", typeId: type.id,
                createdAt: "2024-01-16T10:00:00Z", updatedAt: "2024-01-16T10:00:00Z",
                fields: ["name": "Grace", "age": 72.0, "active": false]
            )
        ]
        return (type, fields, selections, records)
    }

    private func tempURL(ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-test-\(UUID().uuidString).\(ext)")
    }

    private let linkResolver: (String) -> String? = { _ in nil }
    private let attachmentResolver: (String) -> String? = { _ in nil }

    // MARK: - CSV

    func testCSVWriterShapesHeaderAndRows() throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = CSVWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL(ext: "csv")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)  // header + 2 data
        XCTAssertEqual(String(lines[0]), "id,Name,Age,Active,created_at,updated_at")
        XCTAssertTrue(String(lines[1]).contains("Ada"))
        XCTAssertTrue(String(lines[2]).contains("Grace"))
    }

    func testCSVHeaderOverridesApplied() throws {
        let (type, fields, _, records) = makeFixture()
        var selections = fields.map {
            PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: $0.key, header: $0.name)
        }
        selections[0].header = "Full Name"
        let writer = CSVWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL(ext: "csv")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Full Name"))
        XCTAssertFalse(text.split(separator: "\n").first.map(String.init)?.contains(",Name,") ?? true)
    }

    // MARK: - JSON

    func testJSONWriterArrayOfObjects() throws {
        let (type, fields, selections, records) = makeFixture()
        var opts = PurpleExport.FormatOptions()
        opts.jsonShape = .arrayOfObjects
        opts.jsonPrettyPrint = false
        let writer = JSONWriter()
        writer.setOptions(opts)
        let url = tempURL(ext: "json")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?[0]["Name"] as? String, "Ada")
        XCTAssertEqual(parsed?[0]["Age"] as? Double, 36.0)
        XCTAssertEqual(parsed?[0]["Active"] as? Bool, true)
    }

    func testJSONWriterNDJSON() throws {
        let (type, fields, selections, records) = makeFixture()
        var opts = PurpleExport.FormatOptions()
        opts.jsonShape = .ndjson
        let writer = JSONWriter()
        writer.setOptions(opts)
        let url = tempURL(ext: "ndjson")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
            XCTAssertNotNil(obj as? [String: Any])
        }
    }

    func testJSONNestedEnvelopeCarriesSchema() throws {
        let (type, fields, selections, records) = makeFixture()
        var opts = PurpleExport.FormatOptions()
        opts.jsonShape = .nested
        let writer = JSONWriter()
        writer.setOptions(opts)
        let url = tempURL(ext: "json")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(parsed?["format"] as? String, "purplelife.per-type-export.v1")
        let typeInfo = parsed?["type"] as? [String: Any]
        XCTAssertEqual(typeInfo?["name"] as? String, "Person")
        let recs = parsed?["records"] as? [[String: Any]]
        XCTAssertEqual(recs?.count, 2)
    }

    // MARK: - XML

    func testXMLWriterEmitsRootAndRecords() throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = XMLWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL(ext: "xml")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("<?xml"))
        XCTAssertTrue(text.contains("<records"))
        XCTAssertTrue(text.contains("<record"))
        XCTAssertTrue(text.contains("<Name>Ada</Name>"))
        XCTAssertTrue(text.contains("<Age>36</Age>"))
    }

    func testXMLEscapesSpecialChars() throws {
        let type = SourceTypeInfo(id: "t", name: "T", pluralName: "Ts", systemImage: "circle", isVault: false)
        let fields = [SourceFieldInfo(key: "note", name: "Note", kind: .text, options: [])]
        let selections = [PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: "note", header: "Note")]
        let records = [SourceRecord(
            id: "r1", typeId: "t",
            createdAt: "n", updatedAt: "n",
            fields: ["note": "<b>hi & bye</b>"]
        )]
        let writer = XMLWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL(ext: "xml")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("&lt;b&gt;hi &amp; bye&lt;/b&gt;"))
    }

    // MARK: - Markdown

    func testMarkdownTableShape() throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = MarkdownWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL(ext: "md")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("# People"))
        XCTAssertTrue(text.contains("| id | Name | Age | Active | created_at | updated_at |"))
        XCTAssertTrue(text.contains("| --- |"))
    }

    func testMarkdownListPerRecord() throws {
        let (type, fields, selections, records) = makeFixture()
        var opts = PurpleExport.FormatOptions()
        opts.markdownShape = .listPerRecord
        let writer = MarkdownWriter()
        writer.setOptions(opts)
        let url = tempURL(ext: "md")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("## Record rec-1"))
        XCTAssertTrue(text.contains("- **Name:** Ada"))
    }

    // MARK: - HTML

    func testHTMLWriterStandaloneDocument() throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = HTMLWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL(ext: "html")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("<!doctype html>"))
        XCTAssertTrue(text.contains("<title>People — PurpleLife</title>"))
        XCTAssertTrue(text.contains("<th>Name</th>"))
        XCTAssertTrue(text.contains("<td>Ada</td>"))
    }
}
