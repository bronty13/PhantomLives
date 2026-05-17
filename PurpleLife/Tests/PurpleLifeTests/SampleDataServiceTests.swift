import XCTest
import GRDB
@testable import PurpleLife

/// SampleDataService — narrative dataset that the user can populate /
/// clear from Settings. Tests lock the design contract: id-prefix
/// matching, idempotent re-populate, link-target consistency, and
/// "user-created records survive a clear" because that's the most
/// load-bearing safety property of the whole feature.
final class SampleDataServiceTests: XCTestCase {

    @MainActor
    private func wipe() throws {
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM attachments")
            try db.execute(sql: "DELETE FROM objects_fts")
            try db.execute(sql: "DELETE FROM objects")
        }
    }

    @MainActor
    func testPopulateInsertsRecordsWithSamplePrefix() throws {
        try wipe()
        let result = try SampleDataService.populate()
        XCTAssertGreaterThan(result.inserted, 100, "Expect ~130 records seeded")
        XCTAssertEqual(result.replaced, 0)
        XCTAssertEqual(result.total, result.inserted + result.replaced)

        let all = try ObjectEngine.fetchAll()
        XCTAssertEqual(all.count, result.total)
        for record in all {
            XCTAssertTrue(record.id.hasPrefix(SampleDataService.idPrefix),
                          "Every populated record must start with sample-, got \(record.id)")
        }
    }

    @MainActor
    func testPopulateIsIdempotent() throws {
        try wipe()
        let first = try SampleDataService.populate()
        let second = try SampleDataService.populate()
        XCTAssertEqual(second.inserted, 0, "Second populate should insert nothing")
        XCTAssertEqual(second.replaced, first.total, "All records should be replaced in place")

        let all = try ObjectEngine.fetchAll()
        XCTAssertEqual(all.count, first.total, "Total record count must stay the same across populates")
    }

    @MainActor
    func testClearRemovesOnlySamplePrefixedRecords() throws {
        try wipe()
        _ = try SampleDataService.populate()

        // Insert a user-created record with a UUID id (i.e. no sample- prefix).
        let user = try ObjectEngine.create(typeId: "Book", fields: [
            "title":  "User's real book",
            "author": "User",
        ])
        XCTAssertFalse(user.id.hasPrefix(SampleDataService.idPrefix))

        let removed = try SampleDataService.clearSampleData()
        XCTAssertGreaterThan(removed, 100, "Should remove all populated sample records")

        let survivors = try ObjectEngine.fetchAll()
        XCTAssertEqual(survivors.count, 1, "Only the user record should survive")
        XCTAssertEqual(survivors.first?.id, user.id, "User's record id must be preserved across clear")
    }

    @MainActor
    func testClearOnEmptyDBIsNoOp() throws {
        try wipe()
        let removed = try SampleDataService.clearSampleData()
        XCTAssertEqual(removed, 0)
    }

    @MainActor
    func testCurrentSampleRecordCountReflectsState() throws {
        try wipe()
        XCTAssertEqual(SampleDataService.currentSampleRecordCount(), 0)
        let populated = try SampleDataService.populate()
        XCTAssertEqual(SampleDataService.currentSampleRecordCount(), populated.total)
        _ = try SampleDataService.clearSampleData()
        XCTAssertEqual(SampleDataService.currentSampleRecordCount(), 0)
    }

    // MARK: - Dataset shape

    @MainActor
    func testDatasetHasNoVaultTypes() {
        let records = SampleDataService.makeRecords(now: Date())
        let typeIds = Set(records.map(\.typeId))
        // Built-in types are all non-Vault by default. If someone adds
        // a Vault type to the seed catalog and the sample dataset
        // accidentally references it, this test catches it.
        for typeId in typeIds {
            if let type = SchemaSeed.allTypes.first(where: { $0.id == typeId }) {
                XCTAssertFalse(type.isVault,
                               "Sample dataset must not reference Vault type \(typeId) — privacy contract")
            }
        }
    }

    @MainActor
    func testPhotoShootCameraLinksResolveWithinDataset() {
        let records = SampleDataService.makeRecords(now: Date())
        let cameraIds = Set(records.filter { $0.typeId == "Camera" }.map(\.id))
        for shoot in records where shoot.typeId == "PhotoShoot" {
            if let cameraRef = shoot.fields()["camera"] as? String {
                XCTAssertTrue(cameraIds.contains(cameraRef),
                              "Shoot \(shoot.id) references camera id \(cameraRef) that doesn't exist in the dataset")
            }
        }
    }

    @MainActor
    func testPhotoLinksResolveWithinDataset() {
        let records = SampleDataService.makeRecords(now: Date())
        let cameraIds = Set(records.filter { $0.typeId == "Camera" }.map(\.id))
        let shootIds  = Set(records.filter { $0.typeId == "PhotoShoot" }.map(\.id))
        for photo in records where photo.typeId == "Photo" {
            let fields = photo.fields()
            if let c = fields["camera"] as? String {
                XCTAssertTrue(cameraIds.contains(c),
                              "Photo \(photo.id) references camera id \(c) that doesn't exist")
            }
            if let s = fields["shoot"] as? String {
                XCTAssertTrue(shootIds.contains(s),
                              "Photo \(photo.id) references shoot id \(s) that doesn't exist")
            }
        }
    }

    @MainActor
    func testFieldKeysMatchSeedSchema() {
        // The dataset uses field keys derived from FieldDef.slugify on
        // the seed names. If a seed renames a field, the dataset stops
        // writing into that field silently — values would land in the
        // JSON blob under the wrong key and not render. This guard
        // catches that.
        let records = SampleDataService.makeRecords(now: Date())
        for record in records {
            guard let type = SchemaSeed.allTypes.first(where: { $0.id == record.typeId }) else {
                XCTFail("Sample record \(record.id) references unknown type \(record.typeId)")
                continue
            }
            let validKeys = Set(type.fields.map(\.key))
            for key in record.fields().keys {
                XCTAssertTrue(validKeys.contains(key),
                              "Record \(record.id) writes field key \(key) that doesn't exist on type \(record.typeId)")
            }
        }
    }

    @MainActor
    func testStableIdShape() {
        XCTAssertEqual(SampleDataService.sampleId(for: "Book", index: 3),
                       "\(SampleDataService.idPrefix)Book-3")
        XCTAssertTrue(SampleDataService.sampleId(for: "Note", index: 0)
                        .hasPrefix(SampleDataService.idPrefix))
    }
}
