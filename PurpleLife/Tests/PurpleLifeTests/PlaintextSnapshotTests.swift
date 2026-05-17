import XCTest
import GRDB
@testable import PurpleLife

/// Tier 5 — plaintext snapshot export. Covers:
/// - envelope structure (format tag, schema embedded, records decoded)
/// - Vault exclusion via excludingTypeIds
/// - ZIP shape: snapshot.json + attachments/<sha>.<ext> + README.txt
/// - single-JSON shape: attachments inlined as base64
/// - sha256 of inline base64 bytes matches the metadata sha256
/// - readme contains the counts and the format tag
final class PlaintextSnapshotTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func wipe() throws {
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM attachments")
            try db.execute(sql: "DELETE FROM objects_fts")
            try db.execute(sql: "DELETE FROM objects")
        }
    }

    private func writeTempFile(_ contents: String, ext: String = "txt") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-att-\(UUID().uuidString).\(ext)")
        try contents.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    private func tempPath(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-out-\(UUID().uuidString).\(ext)")
    }

    private func unzip(_ archive: URL, to dest: URL) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", archive.path, "-d", dest.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, "unzip exited \(proc.terminationStatus)")
    }

    /// A schema with one regular type ("Book") plus one Vault type
    /// ("Diary"), driven through SchemaRegistry so visibleTypes /
    /// vaultTypeIds compute correctly. Returns the registry + AppSettings
    /// stub to pass to the service.
    @MainActor
    private func makeSchema() throws -> (SchemaRegistry, AppSettings) {
        let schemaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-schema-\(UUID().uuidString).json")
        let registry = SchemaRegistry(fileURL: schemaURL)

        var book = ObjectType(
            id: "Book",
            name: "Book", pluralName: "Books",
            systemImage: "book", colorHex: "#8b65c1",
            fields: [
                FieldDef(id: "f-title", key: "title", name: "Title",
                         kind: .text, options: [], required: true, description: nil),
                FieldDef(id: "f-rating", key: "rating", name: "Rating",
                         kind: .rating, options: [], required: false, description: nil)
            ],
            builtIn: false,
            primaryFieldKey: "title"
        )
        book.updatedAt = "2026-05-16T00:00:00Z"

        var diary = ObjectType(
            id: "Diary",
            name: "Diary", pluralName: "Diaries",
            systemImage: "lock", colorHex: "#9D4DCC",
            fields: [
                FieldDef(id: "f-d-title", key: "title", name: "Title",
                         kind: .text, options: [], required: true, description: nil)
            ],
            builtIn: false,
            primaryFieldKey: "title"
        )
        diary.isVault = true
        diary.updatedAt = "2026-05-16T00:00:00Z"

        registry.upsertType(book)
        registry.upsertType(diary)

        var settings = AppSettings()
        settings.tagVocabulary = [
            TagDef.make(name: "Important", colorHex: "#FF0000")
        ]
        return (registry, settings)
    }

    // MARK: - Envelope basics

    @MainActor
    func testEnvelopeContainsFormatTagAndCounts() throws {
        try wipe()
        let (schema, settings) = try makeSchema()
        let book = try ObjectEngine.create(typeId: "Book", fields: ["title": "Dune", "rating": 5])

        let envelope = try PlaintextSnapshotService.buildEnvelope(
            schema: schema,
            settings: settings,
            excludingTypeIds: [],
            inlineAttachmentBytes: false
        )
        // SchemaRegistry seeds the built-in catalog when the schema file
        // doesn't exist, so the registry holds (seed count + 2). Assert
        // on membership rather than exact count.
        XCTAssertEqual(envelope.format, PlaintextSnapshotService.formatTag)
        XCTAssertEqual(envelope.counts.records, 1)
        XCTAssertEqual(envelope.records.first?.id, book.id)
        XCTAssertTrue(envelope.schema.types.contains { $0.id == "Book" })
        XCTAssertTrue(envelope.schema.types.contains { $0.id == "Diary" })
        XCTAssertEqual(envelope.counts.types, envelope.schema.types.count)
        XCTAssertEqual(envelope.schema.tags.count, 1)
        XCTAssertFalse(envelope.exportedAt.isEmpty)
    }

    @MainActor
    func testRecordFieldsAreDecodedDictionaries() throws {
        try wipe()
        let (schema, settings) = try makeSchema()
        _ = try ObjectEngine.create(typeId: "Book", fields: [
            "title": "The Hobbit",
            "rating": 4
        ])

        let envelope = try PlaintextSnapshotService.buildEnvelope(
            schema: schema,
            settings: settings,
            excludingTypeIds: [],
            inlineAttachmentBytes: false
        )
        let record = try XCTUnwrap(envelope.records.first)
        // Round-trip via the encoder to confirm AnyCodable writes the
        // nested dict as proper JSON object (not stringified).
        let encoded = try JSONEncoder().encode(record)
        let asAny = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let fields = asAny?["fields"] as? [String: Any]
        XCTAssertEqual(fields?["title"] as? String, "The Hobbit")
        // JSONSerialization can hand back either NSNumber-as-Int or -as-Double; both are acceptable.
        let rating = fields?["rating"]
        XCTAssertTrue((rating as? Int) == 4 || (rating as? Double) == 4.0,
                      "rating should round-trip as a number, got: \(String(describing: rating))")
    }

    // MARK: - Vault exclusion

    @MainActor
    func testVaultExclusionDropsVaultRecords() throws {
        try wipe()
        let (schema, settings) = try makeSchema()
        _ = try ObjectEngine.create(typeId: "Book",  fields: ["title": "Public"])
        _ = try ObjectEngine.create(typeId: "Diary", fields: ["title": "Private"])

        let envelopeAll = try PlaintextSnapshotService.buildEnvelope(
            schema: schema, settings: settings,
            excludingTypeIds: [], inlineAttachmentBytes: false
        )
        XCTAssertEqual(envelopeAll.counts.records, 2)
        XCTAssertTrue(envelopeAll.schema.types.contains { $0.id == "Diary" })

        let envelopeNoVault = try PlaintextSnapshotService.buildEnvelope(
            schema: schema, settings: settings,
            excludingTypeIds: schema.vaultTypeIds,
            inlineAttachmentBytes: false
        )
        XCTAssertEqual(envelopeNoVault.counts.records, 1, "Vault record must be filtered out")
        XCTAssertEqual(envelopeNoVault.records.first?.typeId, "Book")
        XCTAssertFalse(envelopeNoVault.schema.types.contains { $0.id == "Diary" },
                       "Vault type definition must not leak when excluded")
        XCTAssertEqual(envelopeNoVault.counts.types, envelopeNoVault.schema.types.count)
        XCTAssertEqual(envelopeNoVault.counts.types, envelopeAll.counts.types - 1)
    }

    // MARK: - ZIP-with-sidecars shape

    @MainActor
    func testZIPWritesSnapshotJSONReadmeAndAttachments() throws {
        try wipe()
        let (schema, settings) = try makeSchema()
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "Attached"])
        let src = try writeTempFile("hello attachment", ext: "txt")
        _ = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")

        let out = tempPath(ext: "zip")
        let result = try PlaintextSnapshotService.export(
            to: out,
            format: .zipWithSidecars,
            schema: schema, settings: settings
        )
        XCTAssertEqual(result.format, .zipWithSidecars)
        XCTAssertEqual(result.attachmentCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-verify-\(UUID().uuidString)")
        try unzip(out, to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }

        let snapshotURL = staging.appendingPathComponent("snapshot.json")
        let readmeURL   = staging.appendingPathComponent("README.txt")
        let attachDir   = staging.appendingPathComponent("attachments")

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeURL.path))

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        let attEntries = try FileManager.default.contentsOfDirectory(at: attachDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(attEntries.count, 1, "Should write one attachment file per unique sha256")

        // ZIP mode never inlines bytes — readme says where to find them.
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)
        XCTAssertTrue(readme.contains("plaintext snapshot"))
        XCTAssertTrue(readme.contains(PlaintextSnapshotService.formatTag))
        XCTAssertTrue(readme.contains("1 attachment(s)"))

        let envelope = try JSONDecoder().decode(
            PlaintextSnapshotService.Envelope.self,
            from: Data(contentsOf: snapshotURL)
        )
        XCTAssertEqual(envelope.records.count, 1)
        XCTAssertEqual(envelope.records.first?.attachments.count, 1)
        XCTAssertNil(envelope.records.first?.attachments.first?.bytesBase64,
                     "ZIP mode keeps bytes in the sidecar, not in the manifest")
    }

    // MARK: - Single-JSON shape

    @MainActor
    func testSingleJSONInlinesAttachmentBytesMatchingSha256() throws {
        try wipe()
        let (schema, settings) = try makeSchema()
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "Inline"])
        let payload = "snapshot test payload \(UUID().uuidString)"
        let src = try writeTempFile(payload, ext: "txt")
        let row = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")

        let out = tempPath(ext: "json")
        let result = try PlaintextSnapshotService.export(
            to: out,
            format: .singleJSON,
            schema: schema, settings: settings
        )
        XCTAssertEqual(result.format, .singleJSON)

        let envelope = try JSONDecoder().decode(
            PlaintextSnapshotService.Envelope.self,
            from: Data(contentsOf: out)
        )
        let att = try XCTUnwrap(envelope.records.first?.attachments.first)
        let base64 = try XCTUnwrap(att.bytesBase64, "single-JSON mode must inline bytesBase64")
        let bytes = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), payload,
                       "round-trip of inline bytes must match the original plaintext")
        XCTAssertEqual(AttachmentService.sha256(data: bytes), att.sha256,
                       "Inlined bytes must hash to the metadata sha256 — the future-reader's integrity check")
        XCTAssertEqual(att.sha256, row.sha256)
    }

    // MARK: - defaultFilename

    @MainActor
    func testDefaultFilenamePrefixAndExtension() {
        let zipName = PlaintextSnapshotService.defaultFilename(format: .zipWithSidecars)
        XCTAssertTrue(zipName.hasPrefix(PlaintextSnapshotService.filenamePrefix))
        XCTAssertTrue(zipName.hasSuffix(".zip"))

        let jsonName = PlaintextSnapshotService.defaultFilename(format: .singleJSON)
        XCTAssertTrue(jsonName.hasPrefix(PlaintextSnapshotService.filenamePrefix))
        XCTAssertTrue(jsonName.hasSuffix(".json"))
    }
}
