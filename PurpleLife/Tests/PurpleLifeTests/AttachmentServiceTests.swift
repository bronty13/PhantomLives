import XCTest
import GRDB
@testable import PurpleLife

/// Phase 5 attachment storage — content-addressing semantics:
/// add-twice de-dupes the file on disk; deleting a row only removes
/// the file when its sha256 isn't referenced by any other row.
final class AttachmentServiceTests: XCTestCase {

    @MainActor
    private func wipe() throws {
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM attachments")
            try db.execute(sql: "DELETE FROM objects_fts")
            try db.execute(sql: "DELETE FROM objects")
        }
    }

    /// Drop an arbitrary file into a temp location so we can import it.
    private func writeTempFile(_ contents: String, ext: String = "txt") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("att-\(UUID().uuidString).\(ext)")
        try contents.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    func testAddPersistsRowAndFile() throws {
        try wipe()
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "A"])
        let src = try writeTempFile("hello world")

        let row = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")
        XCTAssertEqual(row.parentObjectId, parent.id)
        XCTAssertEqual(row.fieldKey, "cover")
        XCTAssertEqual(row.sizeBytes, 11)
        XCTAssertTrue(FileManager.default.fileExists(atPath: AttachmentService.fileURL(forSha256: row.sha256)!.path))
    }

    @MainActor
    func testAddingIdenticalContentDeduplicatesOnDisk() throws {
        try wipe()
        let parentA = try ObjectEngine.create(typeId: "Book", fields: ["title": "A"])
        let parentB = try ObjectEngine.create(typeId: "Book", fields: ["title": "B"])

        // Two different source files with the same content → same sha256.
        let srcA = try writeTempFile("identical payload")
        let srcB = try writeTempFile("identical payload")
        let rowA = try AttachmentService.add(from: srcA, parentObjectId: parentA.id, fieldKey: "cover")
        let rowB = try AttachmentService.add(from: srcB, parentObjectId: parentB.id, fieldKey: "cover")

        XCTAssertEqual(rowA.sha256, rowB.sha256, "Same content → same sha256")
        XCTAssertNotEqual(rowA.id, rowB.id, "Two rows, one file")
        XCTAssertNotNil(AttachmentService.fileURL(forSha256: rowA.sha256))

        // Both rows present.
        let listA = try AttachmentService.list(forParent: parentA.id)
        let listB = try AttachmentService.list(forParent: parentB.id)
        XCTAssertEqual(listA.count, 1)
        XCTAssertEqual(listB.count, 1)
    }

    @MainActor
    func testDeleteKeepsFileWhenOtherRowReferencesIt() throws {
        try wipe()
        let parentA = try ObjectEngine.create(typeId: "Book", fields: ["title": "A"])
        let parentB = try ObjectEngine.create(typeId: "Book", fields: ["title": "B"])
        let srcA = try writeTempFile("shared payload")
        let srcB = try writeTempFile("shared payload")
        let rowA = try AttachmentService.add(from: srcA, parentObjectId: parentA.id, fieldKey: "cover")
        let rowB = try AttachmentService.add(from: srcB, parentObjectId: parentB.id, fieldKey: "cover")
        let sharedURL = AttachmentService.fileURL(forSha256: rowA.sha256)!

        // Delete A — B still references the same sha256, so the file
        // must stay on disk.
        _ = try AttachmentService.deleteRow(id: rowA.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path),
                      "File must remain while any other row references it")

        // Delete B — last ref gone, file should be removed.
        _ = try AttachmentService.deleteRow(id: rowB.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedURL.path),
                       "Last ref deleted → file pruned")
    }

    @MainActor
    func testCascadingDeletesViaObjectDelete() throws {
        try wipe()
        let parent = try ObjectEngine.create(typeId: "Book", fields: ["title": "A"])
        let src = try writeTempFile("cascade-test")
        let row = try AttachmentService.add(from: src, parentObjectId: parent.id, fieldKey: "cover")
        XCTAssertNotNil(AttachmentService.fileURL(forSha256: row.sha256))

        // Phase 1 v2_attachments migration sets parent_object_id → objects(id)
        // with ON DELETE CASCADE, so deleting the parent should also clear
        // the row from the `attachments` table.
        try ObjectEngine.delete(id: parent.id)
        let listAfter = try AttachmentService.list(forParent: parent.id)
        XCTAssertTrue(listAfter.isEmpty, "Cascading FK should drop the attachment row")
    }

    @MainActor
    func testSha256Determinism() {
        let s1 = AttachmentService.sha256(data: "abc".data(using: .utf8)!)
        let s2 = AttachmentService.sha256(data: "abc".data(using: .utf8)!)
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
