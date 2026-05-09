import XCTest
@testable import PurpleDedupCore

final class ExactClustererTests: XCTestCase {

    func testFindsTwoCopiesOfSameFile() async throws {
        let root = try TestFixtures.makeTempDir("clust-twocopies")
        defer { TestFixtures.cleanup(root) }

        let payload = Data("hello-photo".utf8)
        try TestFixtures.write(payload, to: root.appendingPathComponent("a.jpg"))
        try TestFixtures.write(payload, to: root.appendingPathComponent("nested/b.jpg"))
        // Decoy: same size, different bytes — should not cluster with the dupes.
        try TestFixtures.write(Data("zzzzzzzzzzz".utf8), to: root.appendingPathComponent("c.jpg"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo])
        )

        XCTAssertEqual(result.filesScanned, 3)
        XCTAssertEqual(result.exactClusters.count, 1)
        XCTAssertEqual(result.exactClusters.first?.files.count, 2)
    }

    func testUniqueFilesProduceNoClusters() async throws {
        let root = try TestFixtures.makeTempDir("clust-unique")
        defer { TestFixtures.cleanup(root) }

        try TestFixtures.write("alpha", to: root.appendingPathComponent("a.jpg"))
        try TestFixtures.write("beta beta", to: root.appendingPathComponent("b.jpg"))
        try TestFixtures.write("gamma gamma gamma", to: root.appendingPathComponent("c.jpg"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo])
        )
        XCTAssertEqual(result.filesScanned, 3)
        XCTAssertEqual(result.exactClusters.count, 0)
        XCTAssertEqual(result.candidatesHashed, 0,
            "Files of unique size must not be hashed (Stage 1 short-circuit)")
    }

    func testReportSerializesToJSON() async throws {
        let root = try TestFixtures.makeTempDir("clust-json")
        defer { TestFixtures.cleanup(root) }

        let payload = Data("dup-bytes".utf8)
        try TestFixtures.write(payload, to: root.appendingPathComponent("x.jpg"))
        try TestFixtures.write(payload, to: root.appendingPathComponent("y.jpg"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo])
        )
        let report = result.report()
        let data = try report.toJSONData(pretty: false)
        let decoded = try JSONDecoder().decode(ScanReport.self, from: data)

        XCTAssertEqual(decoded.totalClusters, 1)
        XCTAssertEqual(decoded.clusters.first?.fileCount, 2)
        XCTAssertEqual(decoded.clusters.first?.kind, "exact")
        XCTAssertNotNil(decoded.clusters.first?.contentHash)
    }

    func testSizeBucketShortCircuit() async throws {
        let root = try TestFixtures.makeTempDir("clust-sizes")
        defer { TestFixtures.cleanup(root) }

        // 200 distinct sizes, no dupes: hasher must run zero times.
        for n in 1...200 {
            try TestFixtures.write(
                String(repeating: "q", count: n),
                to: root.appendingPathComponent("f\(n).jpg")
            )
        }

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo])
        )
        XCTAssertEqual(result.filesScanned, 200)
        XCTAssertEqual(result.candidatesHashed, 0)
        XCTAssertEqual(result.exactClusters.count, 0)
    }
}
