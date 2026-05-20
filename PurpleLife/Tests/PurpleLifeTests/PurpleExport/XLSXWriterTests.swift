import XCTest
import CoreXLSX
@testable import PurpleLife

/// End-to-end smoke tests for the Phase 4.5 XLSX writer. The strongest
/// assertion is the **round-trip**: we write a fixture with the
/// emitter, open the resulting bytes with CoreXLSX (the same engine
/// the import path uses), and confirm the cell shapes and styles
/// decode the way our writer intended.
@MainActor
final class XLSXWriterTests: XCTestCase {

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
            SourceFieldInfo(key: "read",    name: "Read",    kind: .boolean, options: []),
            SourceFieldInfo(key: "started", name: "Started", kind: .date,    options: [])
        ]
        let selections = fields.map {
            PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: $0.key, header: $0.name)
        }
        let records: [SourceRecord] = [
            SourceRecord(
                id: "rec-1", typeId: type.id,
                createdAt: "2024-01-15T10:00:00Z", updatedAt: "2024-01-15T10:00:00Z",
                fields: [
                    "title": "Dune",
                    "pages": 412.0,
                    "read":  true,
                    "started": "1965-08-01"
                ]
            ),
            SourceRecord(
                id: "rec-2", typeId: type.id,
                createdAt: "2024-01-16T10:00:00Z", updatedAt: "2024-01-16T10:00:00Z",
                fields: [
                    "title": "Children of Time",
                    "pages": 600.0,
                    "read":  false,
                    "started": "2015-06-04"
                ]
            )
        ]
        return (type, fields, selections, records)
    }

    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xlsx-writer-test-\(UUID().uuidString).xlsx")
    }

    private let linkResolver: (String) -> String? = { _ in nil }
    private let attachmentResolver: (String) -> String? = { _ in nil }

    // MARK: - Format-level smoke

    func testWriterReportsXLSXFormat() {
        XCTAssertEqual(XLSXWriter().format, .xlsx)
    }

    func testColumnLetterMatchesExcelConvention() {
        XCTAssertEqual(XLSXWriter.columnLetter(for: 0), "A")
        XCTAssertEqual(XLSXWriter.columnLetter(for: 25), "Z")
        XCTAssertEqual(XLSXWriter.columnLetter(for: 26), "AA")
        XCTAssertEqual(XLSXWriter.columnLetter(for: 51), "AZ")
        XCTAssertEqual(XLSXWriter.columnLetter(for: 52), "BA")
    }

    func testXMLEscapeHandlesAllSpecialChars() {
        let s = "<b>hi & \"bye\" 'now'</b>"
        let escaped = XLSXWriter.xmlEscape(s)
        XCTAssertEqual(escaped, "&lt;b&gt;hi &amp; &quot;bye&quot; &apos;now&apos;&lt;/b&gt;")
    }

    // MARK: - End-to-end round-trip via CoreXLSX

    func testRoundTripThroughCoreXLSX() throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = XLSXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        XCTAssertGreaterThan(bytes, 0)

        // Reopen via CoreXLSX (the same engine the import side uses).
        guard let file = XLSXFile(filepath: url.path) else {
            XCTFail("CoreXLSX could not open the emitter's output — file isn't a valid .xlsx package.")
            return
        }
        let workbook = try XCTUnwrap(file.parseWorkbooks().first)
        let pairs = try file.parseWorksheetPathsAndNames(workbook: workbook)
        XCTAssertEqual(pairs.count, 1, "Workbook should have exactly one sheet.")
        XCTAssertEqual(pairs.first?.name, "Books", "Sheet tab name should match the type's plural name.")

        let worksheet = try file.parseWorksheet(at: pairs[0].path)
        let rows = worksheet.data?.rows ?? []
        // 1 header row + 2 data rows.
        XCTAssertEqual(rows.count, 3)

        // Header row: id, Title, Pages, Read, Started, created_at, updated_at.
        let headerRow = rows.first(where: { $0.reference == 1 })
        let headerCells = headerRow?.cells ?? []
        XCTAssertEqual(headerCells.count, 7)
        let headerLabels = headerCells.map { cell -> String in
            // Inline strings store text in `inlineString.text`.
            cell.inlineString?.text ?? cell.value ?? ""
        }
        XCTAssertEqual(headerLabels, ["id", "Title", "Pages", "Read", "Started", "created_at", "updated_at"])

        // First data row at reference 2.
        let dataRow1 = try XCTUnwrap(rows.first(where: { $0.reference == 2 }))
        let cellsByCol: [String: Cell] = Dictionary(uniqueKeysWithValues: dataRow1.cells.map {
            ($0.reference.column.value, $0)
        })

        // Title — inline string.
        XCTAssertEqual(cellsByCol["B"]?.inlineString?.text, "Dune")

        // Pages — numeric, no t attribute.
        XCTAssertEqual(Double(cellsByCol["C"]?.value ?? ""), 412.0)
        XCTAssertNil(cellsByCol["C"]?.type)

        // Read — boolean (t="b", value "1").
        XCTAssertEqual(cellsByCol["D"]?.type, .bool)
        XCTAssertEqual(cellsByCol["D"]?.value, "1")

        // Started — Excel serial, styled with the date format.
        // 1965-08-01 = 23955 days after 1899-12-30 (the epoch
        // XLSXReader.isoStringFromExcelSerial uses). openpyxl agrees.
        let startedSerial = Double(cellsByCol["E"]?.value ?? "")
        XCTAssertEqual(startedSerial, 23955.0, "1965-08-01 should be Excel serial 23955 (days since 1899-12-30).")
        let styleIndex = cellsByCol["E"]?.styleIndex
        XCTAssertEqual(styleIndex, 1, "Date cells must reference cellXfs index 1 (numFmtId 14).")

        // Closes the loop: feeding our emitted serial back through
        // the reader's inverse function must produce the input date
        // string we wrote.
        let isoBack = XLSXReader.isoStringFromExcelSerial(startedSerial ?? 0)
        XCTAssertEqual(isoBack, "1965-08-01", "Writer→Reader date round-trip should land on the same calendar day.")
    }

    func testDateStyleIndicesAreRecognizedAsDateByReader() throws {
        let (type, fields, selections, records) = makeFixture()
        let writer = XLSXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let file = try XCTUnwrap(XLSXFile(filepath: url.path))
        let styles = try XCTUnwrap(file.parseStyles())
        let dateIndices = XLSXReader.detectDateStyleIndices(in: styles)
        // We declare cellXfs entries at indices 1 (numFmtId 14) and 2 (numFmtId 22)
        // as date-bearing styles. Both should be picked up by the same
        // detector the importer uses.
        XCTAssertTrue(dateIndices.contains(1), "Date cellXf (numFmtId 14) should be detected as a date style.")
        XCTAssertTrue(dateIndices.contains(2), "Date+time cellXf (numFmtId 22) should be detected as a date+time style.")
    }

    // MARK: - DateTime + null-value handling

    func testDateTimeCellEmitsFractionalSerialWithStyle2() throws {
        let type = SourceTypeInfo(id: "t", name: "Event", pluralName: "Events", systemImage: "calendar", isVault: false)
        let fields = [SourceFieldInfo(key: "when", name: "When", kind: .dateTime, options: [])]
        let selections = [PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: "when", header: "When")]
        // Noon UTC on 2024-01-15 → 45306.5 (serial 45306 plus half a day).
        let records = [SourceRecord(
            id: "r1", typeId: "t", createdAt: "n", updatedAt: "n",
            fields: ["when": "2024-01-15T12:00:00Z"]
        )]
        let writer = XLSXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let file = try XCTUnwrap(XLSXFile(filepath: url.path))
        let workbook = try XCTUnwrap(file.parseWorkbooks().first)
        let pairs = try file.parseWorksheetPathsAndNames(workbook: workbook)
        let worksheet = try file.parseWorksheet(at: pairs[0].path)
        let dataRow = try XCTUnwrap((worksheet.data?.rows ?? []).first { $0.reference == 2 })
        let whenCell = try XCTUnwrap(dataRow.cells.first { $0.reference.column.value == "B" })
        let serial = try XCTUnwrap(Double(whenCell.value ?? ""))
        XCTAssertEqual(serial, 45306.5, accuracy: 0.0001,
                       "2024-01-15T12:00:00Z should be Excel serial 45306.5.")
        XCTAssertEqual(whenCell.styleIndex, 2, "Date+time cells reference cellXfs index 2.")
    }

    func testMissingFieldEmitsEmptyCell() throws {
        let type = SourceTypeInfo(id: "t", name: "T", pluralName: "Ts", systemImage: "circle", isVault: false)
        let fields = [SourceFieldInfo(key: "name", name: "Name", kind: .text, options: [])]
        let selections = [PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: "name", header: "Name")]
        let records = [SourceRecord(
            id: "r1", typeId: "t", createdAt: "n", updatedAt: "n",
            fields: [:]   // intentionally missing "name"
        )]
        let writer = XLSXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let file = try XCTUnwrap(XLSXFile(filepath: url.path))
        let workbook = try XCTUnwrap(file.parseWorkbooks().first)
        let pairs = try file.parseWorksheetPathsAndNames(workbook: workbook)
        let worksheet = try file.parseWorksheet(at: pairs[0].path)
        let dataRow = try XCTUnwrap((worksheet.data?.rows ?? []).first { $0.reference == 2 })
        // The Name column (B) should be the empty-cell shape: no
        // `inlineString`, no `value`, no `type` set.
        let nameCell = dataRow.cells.first { $0.reference.column.value == "B" }
        XCTAssertNotNil(nameCell)
        XCTAssertNil(nameCell?.value)
        XCTAssertNil(nameCell?.inlineString)
    }

    func testInlineStringsEscapeXMLPunctuation() throws {
        let type = SourceTypeInfo(id: "t", name: "T", pluralName: "Ts", systemImage: "circle", isVault: false)
        let fields = [SourceFieldInfo(key: "note", name: "Note", kind: .text, options: [])]
        let selections = [PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: "note", header: "Note")]
        let records = [SourceRecord(
            id: "r1", typeId: "t", createdAt: "n", updatedAt: "n",
            fields: ["note": "<b>hi & bye</b>"]
        )]
        let writer = XLSXWriter()
        writer.setOptions(PurpleExport.FormatOptions())
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try writer.write(
            type: type, fields: fields, selections: selections, records: records,
            linkResolver: linkResolver, attachmentResolver: attachmentResolver,
            to: url
        )
        let file = try XCTUnwrap(XLSXFile(filepath: url.path))
        let workbook = try XCTUnwrap(file.parseWorkbooks().first)
        let pairs = try file.parseWorksheetPathsAndNames(workbook: workbook)
        let worksheet = try file.parseWorksheet(at: pairs[0].path)
        let dataRow = try XCTUnwrap((worksheet.data?.rows ?? []).first { $0.reference == 2 })
        let noteCell = try XCTUnwrap(dataRow.cells.first { $0.reference.column.value == "B" })
        // CoreXLSX's parser un-escapes the entities back to the
        // original characters — this is the strongest possible
        // round-trip assertion for XML escaping.
        XCTAssertEqual(noteCell.inlineString?.text, "<b>hi & bye</b>")
    }
}
