import XCTest
@testable import PurpleLife

@MainActor
final class NoteLogValueTests: XCTestCase {

    // MARK: - Storage shape

    func test_jsonDictionaryRoundtrip() throws {
        let ref = NoteLogAttachmentRef(
            id: "att-1",
            sha256: "deadbeef",
            filename: "receipt.pdf",
            mimeType: "application/pdf",
            sizeBytes: 12345
        )
        let entry = NoteLogEntry(
            id: "e-1",
            createdAt: "2026-05-12T08:30:00Z",
            updatedAt: "2026-05-12T08:30:00Z",
            rtf: Data([0xDE, 0xAD]).base64EncodedString(),
            plain: "Met with vendor",
            attachments: [ref]
        )
        let value = NoteLogValue(entries: [entry])

        let dict = value.jsonDictionary
        XCTAssertNotNil(dict["entries"])
        let decoded = NoteLogValue.from(jsonDictionary: dict)
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries.first?.plain, "Met with vendor")
        XCTAssertEqual(decoded.entries.first?.attachments.first?.filename, "receipt.pdf")
        XCTAssertEqual(decoded.entries.first?.rtfData, Data([0xDE, 0xAD]))
    }

    func test_jsonDecodeTolerantOfMissingKeys() {
        XCTAssertEqual(NoteLogValue.from(jsonDictionary: [:]).entries, [])
        XCTAssertEqual(NoteLogValue.from(jsonDictionary: ["entries": []]).entries, [])
    }

    func test_limitsFitsBoundary() {
        XCTAssertTrue(NoteLogLimits.fits(Data(count: NoteLogLimits.maxEntryRTFBytes)))
        XCTAssertFalse(NoteLogLimits.fits(Data(count: NoteLogLimits.maxEntryRTFBytes + 1)))
    }

    // MARK: - SearchService integration

    func test_searchableTextIncludesEntryPlainAndAttachmentFilenames() throws {
        let body = FieldDef.make(name: "Log", kind: .noteLog)
        let type = ObjectType.builtIn(
            id: "TestLog",
            name: "Test Log",
            pluralName: "Logs",
            systemImage: "doc.text",
            colorHex: "#888888",
            fields: [body],
            primaryFieldKey: nil
        )
        let dict: [String: Any] = [
            "entries": [
                [
                    "id": "e-1",
                    "createdAt": "2026-05-12T08:30:00Z",
                    "updatedAt": "2026-05-12T08:30:00Z",
                    "rtf": "",
                    "plain": "alpha beta gamma",
                    "attachments": [
                        [
                            "id": "att-1",
                            "sha256": "deadbeef",
                            "filename": "receipt.pdf",
                            "mimeType": "application/pdf",
                            "sizeBytes": 12345
                        ]
                    ]
                ]
            ]
        ]
        let record = ObjectRecord.make(typeId: type.id, fields: [body.key: dict])
        let (_, indexed) = SearchService.searchableText(for: record, type: type)
        XCTAssertTrue(indexed.contains("alpha beta gamma"),
                      "Entry plain text must be in FTS body; got: '\(indexed)'")
        XCTAssertTrue(indexed.contains("receipt.pdf"),
                      "Attachment filename must be in FTS body; got: '\(indexed)'")
    }

    // MARK: - ExportService integration

    func test_exportRendersEntryWithAttachmentNames() {
        let body = FieldDef.make(name: "Log", kind: .noteLog)
        let value: [String: Any] = [
            "entries": [
                [
                    "id": "e-1",
                    "createdAt": "2026-05-12T08:30:00Z",
                    "updatedAt": "2026-05-12T08:30:00Z",
                    "rtf": "",
                    "plain": "Phone call",
                    "attachments": [
                        ["id": "a", "sha256": "x", "filename": "notes.txt",
                         "mimeType": "text/plain", "sizeBytes": 42]
                    ]
                ],
                [
                    "id": "e-2",
                    "createdAt": "2026-05-11T08:00:00Z",
                    "updatedAt": "2026-05-11T08:00:00Z",
                    "rtf": "",
                    "plain": "Earlier note",
                    "attachments": []
                ]
            ]
        ]
        let rendered = ExportService.renderCell(
            value,
            kind: body.kind,
            options: [],
            linkTitle: { _ in nil },
            attachmentLabel: { _ in nil }
        )
        // Newest first.
        let lines = rendered.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("Phone call"))
        XCTAssertTrue(lines[0].contains("notes.txt"))
        XCTAssertTrue(lines[1].contains("Earlier note"))
        XCTAssertFalse(lines[1].contains("attachments:"))
    }
}
