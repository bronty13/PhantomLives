import XCTest
@testable import PurpleLife

/// Schema-versioning safety net. Two prongs covered here:
///
/// 1. **Defensive merge** in `ObjectEngine.update` — preserves any
///    keys the caller didn't include, so a peer with a stale schema
///    can't drop fields the remote schema knows about.
/// 2. **Per-type `updatedAt` stamping** in `SchemaRegistry` — every
///    mutation bumps the timestamp so CloudKit LWW reconciliation
///    picks the more recent version.
///
/// The CloudKit push/pull plumbing itself isn't unit-testable
/// without real APNS — covered by the same Mac→Mac trial that
/// validates the silent-push subscriptions.
final class SchemaVersioningTests: XCTestCase {

    // MARK: - Defensive merge in ObjectEngine.update

    @MainActor
    func testUpdatePreservesUnknownFieldsFromExistingRecord() throws {
        let typeId = "test-defensive-\(UUID().uuidString)"
        // Insert directly into the DB without going through ObjectEngine
        // so the test doesn't depend on the schema being registered.
        let initialJSON = #"{"known":"alpha","unknown_from_remote":"don't lose me"}"#
        let record = ObjectRecord(
            id: UUID().uuidString,
            typeId: typeId,
            parentId: nil,
            fieldsJSON: initialJSON,
            createdAt: "2026-05-10T00:00:00Z",
            updatedAt: "2026-05-10T00:00:00Z"
        )
        try DatabaseService.shared.insertObject(record)
        defer { try? DatabaseService.shared.deleteObject(id: record.id) }

        // Caller updates with only "known" — the local schema doesn't
        // know about "unknown_from_remote", so the form omits it.
        // After update, both keys must still be present.
        let updated = try ObjectEngine.update(record, fields: ["known": "beta"])
        let merged = updated.fields()
        XCTAssertEqual(merged["known"] as? String, "beta", "incoming value should win")
        XCTAssertEqual(merged["unknown_from_remote"] as? String, "don't lose me",
                       "unknown remote field must be preserved across update")
    }

    @MainActor
    func testUpdateAllowsExplicitlyClearingKnownFields() throws {
        let typeId = "test-clear-\(UUID().uuidString)"
        let initialJSON = #"{"a":"keep","b":"clear me"}"#
        let record = ObjectRecord(
            id: UUID().uuidString,
            typeId: typeId,
            parentId: nil,
            fieldsJSON: initialJSON,
            createdAt: "2026-05-10T00:00:00Z",
            updatedAt: "2026-05-10T00:00:00Z"
        )
        try DatabaseService.shared.insertObject(record)
        defer { try? DatabaseService.shared.deleteObject(id: record.id) }

        // The form passes both keys. Clearing a field means setting it
        // to empty / "" — not omitting it. The merge should respect
        // that and write the empty value.
        let updated = try ObjectEngine.update(record, fields: ["a": "keep", "b": ""])
        let merged = updated.fields()
        XCTAssertEqual(merged["a"] as? String, "keep")
        XCTAssertEqual(merged["b"] as? String, "", "explicit empty must replace prior value")
    }

    // MARK: - Per-type updatedAt stamping

    @MainActor
    func testBuiltInTypesCarryEpochUpdatedAt() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-stamp-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)
        // Built-in types stamp the epoch on construction so that the
        // first real edit on any peer wins LWW over an unedited copy.
        let person = reg.type(id: "Person")
        XCTAssertEqual(person?.updatedAt, ObjectType.epochTimestamp,
                       "untouched built-ins should carry the epoch timestamp")
    }

    @MainActor
    func testUpsertStampsUpdatedAt() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-stamp-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let custom = ObjectType(
            id: "custom-\(UUID().uuidString)",
            name: "Custom", pluralName: "Customs",
            systemImage: "square", colorHex: "#000000",
            fields: [], builtIn: false,
            primaryFieldKey: nil, kanbanGroupKey: nil,
            calendarDateKey: nil, galleryAttachmentKey: nil,
            updatedAt: nil
        )
        reg.upsertType(custom)
        let stored = reg.type(id: custom.id)
        XCTAssertNotNil(stored?.updatedAt)
        XCTAssertNotEqual(stored?.updatedAt, ObjectType.epochTimestamp,
                          "upsert should bump updatedAt past the epoch default")
    }

    @MainActor
    func testApplyRemoteWinsOnlyWhenStampIsNewer() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-lww-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let typeId = "lww-\(UUID().uuidString)"
        let local = ObjectType(
            id: typeId, name: "Local", pluralName: "Locals",
            systemImage: "circle", colorHex: "#111111",
            fields: [], builtIn: false,
            primaryFieldKey: nil, kanbanGroupKey: nil,
            calendarDateKey: nil, galleryAttachmentKey: nil,
            updatedAt: "2026-05-10T12:00:00Z"
        )
        // Insert directly — bypass upsertType's stamping so we control timestamps.
        reg.applyRemote(local)

        // Older remote — should be ignored.
        var older = local
        older.name = "OLDER REMOTE"
        older.updatedAt = "2026-05-10T11:00:00Z"
        reg.applyRemote(older)
        XCTAssertEqual(reg.type(id: typeId)?.name, "Local",
                       "older remote must not overwrite newer local")

        // Newer remote — should win.
        var newer = local
        newer.name = "NEWER REMOTE"
        newer.updatedAt = "2026-05-10T13:00:00Z"
        reg.applyRemote(newer)
        XCTAssertEqual(reg.type(id: typeId)?.name, "NEWER REMOTE",
                       "newer remote must replace older local")
    }
}
