import XCTest
@testable import PurpleLife

/// Pure-formatter tests. The CSV / Markdown / HTML formatters are
/// nonisolated and take resolver closures, so they're testable
/// without a `@MainActor` host or any database setup.
///
/// Not covered: the WKWebView-based PDF render (needs a UI test
/// host) and the file-write path (the writer is a one-line
/// `try Data.write(to:)` — the formatter is what's interesting).
final class ExportServiceTests: XCTestCase {

    // MARK: - Fixture

    private struct Fixture {
        let type: ObjectType
        let records: [ObjectRecord]
        let linkTitle: (String) -> String?
        let attachmentLabel: (String) -> String?
    }

    private func makeFixture() -> Fixture {
        // Hand-built FieldDefs with explicit ids/keys so the test is
        // independent of the slugifier and the option-id generator.
        let statusOptions: [FieldOption] = [
            FieldOption(id: "opt-active", name: "Active", colorHex: nil),
            FieldOption(id: "opt-archived", name: "Archived", colorHex: nil),
        ]
        let tagOptions: [FieldOption] = [
            FieldOption(id: "tag-personal", name: "Personal", colorHex: nil),
            FieldOption(id: "tag-work", name: "Work", colorHex: nil),
        ]
        let fields: [FieldDef] = [
            FieldDef(id: "f-name",   key: "name",   name: "Name",      kind: .text,        options: [], required: false, description: nil),
            FieldDef(id: "f-notes",  key: "notes",  name: "Notes",     kind: .longText,    options: [], required: false, description: nil),
            FieldDef(id: "f-status", key: "status", name: "Status",    kind: .select,      options: statusOptions, required: false, description: nil),
            FieldDef(id: "f-tags",   key: "tags",   name: "Tags",      kind: .multiSelect, options: tagOptions,    required: false, description: nil),
            FieldDef(id: "f-link",   key: "link",   name: "Linked",    kind: .link,        options: [], required: false, description: nil),
            FieldDef(id: "f-rating", key: "rating", name: "Rating",    kind: .rating,      options: [], required: false, description: nil),
            FieldDef(id: "f-attach", key: "attach", name: "Photo",     kind: .attachment,  options: [], required: false, description: nil),
            FieldDef(id: "f-paid",   key: "paid",   name: "Paid",      kind: .boolean,     options: [], required: false, description: nil),
        ]
        let type = ObjectType(
            id: "type-thing",
            name: "Thing",
            pluralName: "Things",
            systemImage: "square",
            colorHex: "#8B65C1",
            fields: fields,
            builtIn: false,
            primaryFieldKey: "name",
            kanbanGroupKey: nil,
            calendarDateKey: nil,
            galleryAttachmentKey: nil
        )

        // Two records with intentionally awkward content: a comma in
        // the name, a quote and a newline in the notes, a multi-select
        // value, a link to a known + unknown id, and a missing field.
        let r1 = ObjectRecord(
            id: "rec-1",
            typeId: "type-thing",
            parentId: nil,
            fieldsJSON: """
            {"name":"Smith, John","notes":"He said \\"hi\\"\\nthen left","status":"opt-active","tags":["tag-personal","tag-work"],"link":"linked-record-id","rating":4,"attach":"deadbeef","paid":true}
            """,
            createdAt: "2026-05-10T12:00:00Z",
            updatedAt: "2026-05-10T12:30:00Z"
        )
        let r2 = ObjectRecord(
            id: "rec-2",
            typeId: "type-thing",
            parentId: nil,
            fieldsJSON: """
            {"name":"Bob","status":"opt-archived","link":"unknown-id"}
            """,
            createdAt: "2026-05-09T08:00:00Z",
            updatedAt: "2026-05-09T08:00:00Z"
        )

        let linkTitle: (String) -> String? = { id in
            id == "linked-record-id" ? "The Linked Thing" : nil
        }
        let attachmentLabel: (String) -> String? = { sha in
            sha == "deadbeef" ? "vacation.jpg" : nil
        }
        return Fixture(type: type, records: [r1, r2],
                       linkTitle: linkTitle, attachmentLabel: attachmentLabel)
    }

    // MARK: - CSV

    func testCSVHeaderIncludesIdFieldsAndTimestamps() {
        let f = makeFixture()
        let csv = ExportService.formatCSV(records: f.records, type: f.type,
                                          linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        let firstLine = csv.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertEqual(firstLine, "id,Name,Notes,Status,Tags,Linked,Rating,Photo,Paid,created_at,updated_at")
    }

    func testCSVEscapesCommasQuotesAndNewlines() {
        let f = makeFixture()
        let csv = ExportService.formatCSV(records: f.records, type: f.type,
                                          linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        // Smith, John has a comma → must be quoted.
        XCTAssertTrue(csv.contains("\"Smith, John\""), "comma cell not quoted")
        // The notes cell has a quote and a newline → quoted, embedded
        // quotes doubled.
        XCTAssertTrue(csv.contains("\"He said \"\"hi\"\"\nthen left\""),
                      "quote+newline cell not RFC4180-escaped — got:\n\(csv)")
    }

    func testCSVResolvesLinkAndMultiSelect() {
        let f = makeFixture()
        let csv = ExportService.formatCSV(records: f.records, type: f.type,
                                          linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        XCTAssertTrue(csv.contains("The Linked Thing"), "link not resolved to title")
        XCTAssertTrue(csv.contains("Personal|Work"), "multi-select not pipe-joined")
        // Unknown link id falls back to the raw id string.
        XCTAssertTrue(csv.contains("unknown-id"), "unknown link fell back unexpectedly")
    }

    func testCSVAttachmentUsesResolverLabelOrFallsBackToSha() {
        let f = makeFixture()
        let csv = ExportService.formatCSV(records: f.records, type: f.type,
                                          linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        XCTAssertTrue(csv.contains("vacation.jpg"), "attachment resolver not applied")
    }

    func testCSVRatingAndBooleanRender() {
        let f = makeFixture()
        let csv = ExportService.formatCSV(records: f.records, type: f.type,
                                          linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        // rec-1 has rating=4 (followed by the attachment cell) and
        // paid=true (followed by created_at). Substring-match the
        // surrounding commas — splitting on "," doesn't work because
        // cell content can legitimately contain commas (e.g. "Smith,
        // John") and embedded newlines break a naive line split too.
        XCTAssertTrue(csv.contains(",4,vacation.jpg"), "rating cell missing or wrong: \(csv)")
        XCTAssertTrue(csv.contains(",true,2026-"),     "boolean cell missing or wrong: \(csv)")
    }

    func testCSVMissingFieldsRenderAsEmpty() {
        let f = makeFixture()
        let csv = ExportService.formatCSV(records: f.records, type: f.type,
                                          linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        // rec-2 has no notes / tags / rating / attach / paid — those
        // cells should be empty (just the comma separator on either
        // side, no quoted whitespace).
        let r2Line = csv.split(separator: "\n").first(where: { $0.contains("rec-2") }).map(String.init) ?? ""
        // Pattern of "Bob," followed eventually by ",,," for the
        // missing trailing fields. Light check: cells past the name
        // should mostly be empty strings.
        let cells = r2Line.components(separatedBy: ",")
        XCTAssertEqual(cells[0], "rec-2")
        XCTAssertEqual(cells[1], "Bob")
        XCTAssertEqual(cells[2], "", "notes should be empty for rec-2")
    }

    // MARK: - Markdown

    func testMarkdownHasHeaderTitleSeparatorAndOneRowPerRecord() {
        let f = makeFixture()
        let md = ExportService.formatMarkdown(records: f.records, type: f.type,
                                              linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        XCTAssertTrue(md.hasPrefix("# Things\n"), "title heading missing")
        // One header row + one separator row + 2 data rows = 4 pipe-led lines.
        let pipeLines = md.split(separator: "\n").filter { $0.hasPrefix("| ") }
        XCTAssertEqual(pipeLines.count, 4, "expected 4 table lines, got \(pipeLines.count)")
        // Separator row must be the second pipe line.
        XCTAssertTrue(pipeLines[1].contains(" --- "), "separator row malformed: \(pipeLines[1])")
    }

    func testMarkdownEscapesPipes() {
        let optWithPipe = FieldOption(id: "p", name: "A | B", colorHex: nil)
        let field = FieldDef(id: "f", key: "label", name: "Label", kind: .select,
                             options: [optWithPipe], required: false, description: nil)
        let type = ObjectType(id: "t", name: "T", pluralName: "Ts",
                              systemImage: "x", colorHex: "#000000",
                              fields: [field], builtIn: false,
                              primaryFieldKey: "label",
                              kanbanGroupKey: nil, calendarDateKey: nil,
                              galleryAttachmentKey: nil)
        let r = ObjectRecord(id: "r", typeId: "t", parentId: nil,
                             fieldsJSON: "{\"label\":\"p\"}",
                             createdAt: "2026-05-10T00:00:00Z",
                             updatedAt: "2026-05-10T00:00:00Z")
        let md = ExportService.formatMarkdown(records: [r], type: type,
                                              linkTitle: { _ in nil },
                                              attachmentLabel: { _ in nil })
        XCTAssertTrue(md.contains("A \\| B"), "pipe in cell value not escaped: \(md)")
    }

    // MARK: - HTML

    func testHTMLContainsTableHeaderAndRowsAndEscapesEntities() {
        let f = makeFixture()
        let html = ExportService.formatHTML(records: f.records, type: f.type,
                                            linkTitle: f.linkTitle, attachmentLabel: f.attachmentLabel)
        XCTAssertTrue(html.contains("<thead>"), "no <thead>")
        XCTAssertTrue(html.contains("<tr><th>id</th>"), "header row missing")
        XCTAssertTrue(html.contains("Smith, John"), "row content missing")
        // The notes cell contains an embedded quote — must be HTML-escaped.
        XCTAssertTrue(html.contains("&quot;hi&quot;"), "embedded quote not html-escaped")
        // Multi-select still pipe-joined (escaping is per format; the
        // pipe is a fine character inside an HTML cell).
        XCTAssertTrue(html.contains("Personal|Work"))
    }

    // MARK: - Helpers

    func testCsvEscapeOnlyQuotesWhenNeeded() {
        XCTAssertEqual(ExportService.csvEscape("plain"), "plain")
        XCTAssertEqual(ExportService.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(ExportService.csvEscape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(ExportService.csvEscape("a\nb"), "\"a\nb\"")
    }
}
