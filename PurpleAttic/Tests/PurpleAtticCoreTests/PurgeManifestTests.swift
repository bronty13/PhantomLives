import XCTest
@testable import PurpleAtticCore

/// Tests for the purge manifest: building it from a plan (verified items only), staleness, and the
/// document store round-trip.
final class PurgeManifestTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func candidate(_ uuid: String, verified: Bool, size: Int) -> PurgeCandidate {
        PurgeCandidate(uuid: uuid, filename: "\(uuid).HEIC", date: now.addingTimeInterval(-86_400 * 400),
                       sizeBytes: size, ismissing: false,
                       verification: VerificationResult(inPrimary: verified, mirrorsMatched: verified ? 1 : 0))
    }

    func testManifestFromPlanKeepsOnlyVerified() {
        let plan = PurgePlan(
            cutoff: now.addingTimeInterval(-86_400 * 365),
            recordsConsidered: 100,
            candidates: [candidate("A", verified: true, size: 1000),
                         candidate("B", verified: true, size: 2000),
                         candidate("C", verified: false, size: 4000)])
        let m = PurgeManifest(from: plan, profileName: "Main", keepWindowDays: 365, computedAt: now)
        XCTAssertEqual(m.eligibleCount, 3)
        XCTAssertEqual(m.verifiedCount, 2)
        XCTAssertEqual(m.unverifiedCount, 1)
        XCTAssertEqual(m.items.map { $0.uuid }.sorted(), ["A", "B"])  // C (unverified) excluded
        XCTAssertEqual(m.verifiedBytes, 3000)
        XCTAssertEqual(m.recordsConsidered, 100)
    }

    func testStaleness() {
        let plan = PurgePlan(cutoff: now, recordsConsidered: 0, candidates: [])
        let m = PurgeManifest(from: plan, profileName: "Main", keepWindowDays: 365,
                              computedAt: now.addingTimeInterval(-3600))  // 1h old
        XCTAssertFalse(m.isStale(asOf: now, maxAge: 2 * 3600))  // within 2h → fresh
        XCTAssertTrue(m.isStale(asOf: now, maxAge: 30 * 60))    // older than 30m → stale
    }

    func testStoreRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purge-plan-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = PurgePlan(cutoff: now, recordsConsidered: 5,
                             candidates: [candidate("A", verified: true, size: 500)])
        let m = PurgeManifest(from: plan, profileName: "Main", keepWindowDays: 365, computedAt: now)
        XCTAssertTrue(PurgeManifestStore.write(m, to: url))
        let read = PurgeManifestStore.read(from: url)
        XCTAssertEqual(read?.verifiedCount, 1)
        XCTAssertEqual(read?.items.first?.uuid, "A")
        XCTAssertEqual(read?.profileName, "Main")
    }

    func testReadMissingReturnsNil() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nope-\(UUID().uuidString).json")
        XCTAssertNil(PurgeManifestStore.read(from: url))
    }
}
