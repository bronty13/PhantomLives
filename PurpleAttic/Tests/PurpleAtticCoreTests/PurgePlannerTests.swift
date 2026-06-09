import XCTest
@testable import PurpleAtticCore

final class PurgePlannerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func iso(daysAgo days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func record(uuid: String, daysAgo: Int, favorite: Bool = false,
                        albums: [String] = [], keywords: [String] = [],
                        filename: String = "IMG.HEIC", size: Int = 1000,
                        ismissing: Bool = false, intrash: Bool = false) -> OsxphotosRecord {
        OsxphotosRecord(uuid: uuid, date: iso(daysAgo: daysAgo), favorite: favorite,
                        albums: albums, keywords: keywords,
                        originalFilename: filename, originalFilesize: size,
                        ismissing: ismissing, intrash: intrash)
    }

    private let policy = RetentionPolicy(keepWindowDays: 365, keepAlbumNames: ["Save"],
                                         keepKeywords: ["save"], keepFavorites: false)

    func testRecentPhotoNotEligible() {
        let plan = PurgePlanner.plan(records: [record(uuid: "a", daysAgo: 10)],
                                     policy: policy, now: now,
                                     primary: ArchiveIndex(map: ["img.heic": [1000]]),
                                     mirrors: [ArchiveIndex(map: ["img.heic": [1000]])])
        XCTAssertEqual(plan.candidates.count, 0)
    }

    func testOldVerifiedPhotoIsDeletable() {
        let primary = ArchiveIndex(map: ["img.heic": [1000]])
        let mirror = ArchiveIndex(map: ["img.heic": [1000]])
        let plan = PurgePlanner.plan(records: [record(uuid: "a", daysAgo: 500)],
                                     policy: policy, now: now, primary: primary, mirrors: [mirror])
        XCTAssertEqual(plan.candidates.count, 1)
        XCTAssertEqual(plan.verified.count, 1)
        XCTAssertTrue(plan.candidates[0].deletable)
    }

    func testOldButOnlyInPrimaryIsNotDeletable() {
        let primary = ArchiveIndex(map: ["img.heic": [1000]])
        let plan = PurgePlanner.plan(records: [record(uuid: "a", daysAgo: 500)],
                                     policy: policy, now: now, primary: primary, mirrors: [])
        XCTAssertEqual(plan.candidates.count, 1)
        XCTAssertEqual(plan.verified.count, 0, "no mirror → not verified → not deletable")
        XCTAssertEqual(plan.unverified.count, 1)
    }

    func testSizeMismatchFailsVerification() {
        let primary = ArchiveIndex(map: ["img.heic": [999]]) // wrong size
        let mirror = ArchiveIndex(map: ["img.heic": [999]])
        let plan = PurgePlanner.plan(records: [record(uuid: "a", daysAgo: 500, size: 1000)],
                                     policy: policy, now: now, primary: primary, mirrors: [mirror])
        XCTAssertEqual(plan.verified.count, 0, "name matches but size differs → unverified")
    }

    func testPinnedBySaveAlbumExcluded() {
        let idx = ArchiveIndex(map: ["img.heic": [1000]])
        let plan = PurgePlanner.plan(records: [record(uuid: "a", daysAgo: 500, albums: ["Save"])],
                                     policy: policy, now: now, primary: idx, mirrors: [idx])
        XCTAssertEqual(plan.candidates.count, 0, "Save-album photo is not even eligible")
    }

    func testTrashedRecordSkipped() {
        let idx = ArchiveIndex(map: ["img.heic": [1000]])
        let plan = PurgePlanner.plan(records: [record(uuid: "a", daysAgo: 500, intrash: true)],
                                     policy: policy, now: now, primary: idx, mirrors: [idx])
        XCTAssertEqual(plan.candidates.count, 0)
    }

    func testUnparseableDateSkipped() {
        let bad = OsxphotosRecord(uuid: "a", date: nil, favorite: false, albums: [], keywords: [],
                                  originalFilename: "x.heic", originalFilesize: 1, ismissing: false, intrash: false)
        let plan = PurgePlanner.plan(records: [bad], policy: policy, now: now,
                                     primary: ArchiveIndex(map: [:]), mirrors: [])
        XCTAssertEqual(plan.candidates.count, 0)
    }

    func testDateParsingWithOffset() {
        XCTAssertNotNil(OsxphotosRecord.parseDate("1997-12-31T19:00:00-05:00"))
        XCTAssertNil(OsxphotosRecord.parseDate(nil))
        XCTAssertNil(OsxphotosRecord.parseDate(""))
    }

    func testArchiveIndexNameAndSizeMatching() {
        let idx = ArchiveIndex(map: ["photo.heic": [10, 20]])
        XCTAssertTrue(idx.contains(filename: "PHOTO.HEIC", size: 10)) // case-insensitive
        XCTAssertTrue(idx.contains(filename: "photo.heic", size: 20))
        XCTAssertFalse(idx.contains(filename: "photo.heic", size: 30))
        XCTAssertTrue(idx.contains(filename: "photo.heic", size: nil))
        XCTAssertFalse(idx.contains(filename: "other.heic", size: nil))
    }
}
