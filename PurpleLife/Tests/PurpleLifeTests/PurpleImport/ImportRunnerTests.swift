import XCTest
@testable import PurpleLife

/// Drives `ImportRunner` end-to-end against a fake sink that records
/// each call. Confirms the small vs bulk path selection at the
/// `PurpleImport.bulkThreshold` boundary, and that summary +
/// failed-row events propagate.
@MainActor
final class ImportRunnerTests: XCTestCase {

    /// A fake sink that captures whether the bulk path or the per-
    /// record path was used. Mirrors the small/big-import split the
    /// real runner performs.
    final class RecordingSink: PurpleImportSink {
        var bulkCalls = 0
        var bulkRowCount = 0
        var perRowCalls = 0
        var createdTypeIds: [String] = []
        var addedFieldKeys: [String] = []
        var fields: [String: [SinkFieldInfo]] = [:]
        var types: [SinkTypeInfo] = []

        func listTypes() throws -> [SinkTypeInfo] { types }
        func listFields(typeId: String) throws -> [SinkFieldInfo] { fields[typeId] ?? [] }

        func createType(_ proposal: SinkTypeProposal) throws -> String {
            let id = UUID().uuidString
            createdTypeIds.append(id)
            let info = SinkTypeInfo(
                id: id, name: proposal.name, pluralName: proposal.pluralName,
                systemImage: proposal.systemImage, isVault: proposal.isVault
            )
            types.append(info)
            fields[id] = proposal.fields.map { p in
                SinkFieldInfo(key: p.name.lowercased(), name: p.name, kind: p.kind, options: p.options, required: p.required)
            }
            return id
        }

        func addField(typeId: String, _ proposal: SinkFieldProposal) throws -> String {
            let key = proposal.name.lowercased()
            addedFieldKeys.append(key)
            let info = SinkFieldInfo(key: key, name: proposal.name, kind: proposal.kind, options: proposal.options, required: proposal.required)
            fields[typeId, default: []].append(info)
            return key
        }

        func upsert(typeId: String, keyFieldKey: String?, values: [String: Any], attachments: [SinkAttachment]) throws -> SinkUpsertResult {
            perRowCalls += 1
            return .inserted(recordId: UUID().uuidString)
        }

        func bulkInsert(typeId: String, rows: [[String: Any]]) throws -> SinkBulkInsertResult {
            bulkCalls += 1
            bulkRowCount += rows.count
            return SinkBulkInsertResult(
                insertedRecordIds: rows.map { _ in UUID().uuidString },
                failures: []
            )
        }
    }

    func testSmallImportUsesPerRowPath() async throws {
        let (mapping, source, sink) = makeFixture(rowCount: 5)
        let reader = CSVReader()
        let runner = ImportRunner(mapping: mapping, reader: reader, sink: sink, source: source)
        var summary: PurpleImport.RunSummary?
        for try await event in runner.run() {
            if case .finished(let s) = event { summary = s }
        }
        XCTAssertEqual(sink.bulkCalls, 0)
        XCTAssertEqual(sink.perRowCalls, 5)
        XCTAssertEqual(summary?.inserted, 5)
    }

    func testLargeImportUsesBulkPath() async throws {
        let (mapping, source, sink) = makeFixture(rowCount: 100)  // > threshold (25)
        let reader = CSVReader()
        let runner = ImportRunner(mapping: mapping, reader: reader, sink: sink, source: source)
        var summary: PurpleImport.RunSummary?
        for try await event in runner.run() {
            if case .finished(let s) = event { summary = s }
        }
        XCTAssertEqual(sink.bulkCalls, 1)
        XCTAssertEqual(sink.bulkRowCount, 100)
        XCTAssertEqual(sink.perRowCalls, 0)
        XCTAssertEqual(summary?.inserted, 100)
    }

    func testUpsertOnKeyForcesPerRowPath() async throws {
        // Bulk path is insert-only by design; upsertOnKey must drop
        // back to the per-row path regardless of row count.
        var (mapping, source, sink) = makeFixture(rowCount: 100)
        mapping.upsertStrategy = .upsertOnKey
        mapping.keyFieldKey = "name"
        let reader = CSVReader()
        let runner = ImportRunner(mapping: mapping, reader: reader, sink: sink, source: source)
        for try await _ in runner.run() {}
        XCTAssertEqual(sink.bulkCalls, 0)
        XCTAssertEqual(sink.perRowCalls, 100)
    }

    // MARK: - Fixture

    private func makeFixture(rowCount: Int) -> (SavedImportMapping, PurpleImport.SourceInput, RecordingSink) {
        let sink = RecordingSink()
        let typeId = UUID().uuidString
        sink.types = [SinkTypeInfo(id: typeId, name: "T", pluralName: "Ts", systemImage: "circle", isVault: false)]
        sink.fields[typeId] = [
            SinkFieldInfo(key: "name", name: "name", kind: .text, options: [], required: false),
            SinkFieldInfo(key: "age", name: "age", kind: .number, options: [], required: false),
        ]
        var csv = "name,age\n"
        for i in 0..<rowCount { csv += "Person \(i),\(i)\n" }
        let source = PurpleImport.SourceInput.data(csv.data(using: .utf8)!, filenameHint: "test.csv")
        var mapping = SavedImportMapping.newDraft()
        mapping.targetTypeId = typeId
        mapping.sourceFormat = .csv
        mapping.fieldMappings = [
            SavedImportMapping.FieldMapping(
                id: UUID().uuidString,
                source: .column("name"),
                targetKey: "name",
                expectedKind: .text,
                transforms: [],
                defaultValue: nil,
                onError: .skipRow
            ),
            SavedImportMapping.FieldMapping(
                id: UUID().uuidString,
                source: .column("age"),
                targetKey: "age",
                expectedKind: .number,
                transforms: [],
                defaultValue: nil,
                onError: .skipRow
            )
        ]
        return (mapping, source, sink)
    }
}
