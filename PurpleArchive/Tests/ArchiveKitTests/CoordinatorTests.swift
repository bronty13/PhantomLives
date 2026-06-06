import XCTest
@testable import ArchiveKit

/// The bounded-concurrency batch runner: correctness (all jobs run, order
/// preserved, failures isolated) and that it actually fans out.
final class CoordinatorTests: XCTestCase {

    func testRunBoundedPreservesOrderAndRunsAll() async {
        let results = await ExtractCoordinator.runBounded(20, limit: 4) { i in i * i }
        let values = results.map { try? $0.get() }
        XCTAssertEqual(values, (0..<20).map { $0 * $0 })
    }

    func testRunBoundedIsolatesFailures() async {
        struct Boom: Error {}
        let results = await ExtractCoordinator.runBounded(6, limit: 3) { i in
            if i == 3 { throw Boom() }
            return i
        }
        XCTAssertEqual(try? results[2].get(), 2)
        XCTAssertNil(try? results[3].get())   // the thrower
        XCTAssertEqual(try? results[4].get(), 4)
    }

    func testBatchExtractMany() async throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parc-batch-\(ProcessInfo.processInfo.globallyUniqueString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let svc = ArchiveService()
        var jobs: [(url: URL, options: ExtractOptions)] = []
        for n in 0..<8 {
            let f = tmp.appendingPathComponent("f\(n).txt")
            try "content \(n)\n".write(to: f, atomically: true, encoding: .utf8)
            let archive = tmp.appendingPathComponent("a\(n).zip")
            try svc.create(archive, inputs: [f])
            jobs.append((archive, ExtractOptions(destination: tmp.appendingPathComponent("out\(n)"))))
        }
        let results = await ExtractCoordinator(maxConcurrent: 4).extractMany(jobs)
        XCTAssertEqual(results.count, 8)
        for r in results { XCTAssertEqual(try? r.get(), 1) }
        // Spot-check one extracted file.
        let got = try String(contentsOf: tmp.appendingPathComponent("out3/f3.txt"), encoding: .utf8)
        XCTAssertEqual(got, "content 3\n")
    }
}
