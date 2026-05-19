import XCTest
@testable import PurpleReel

/// Coverage for the C16 `CombineSource` trim model. The runtime
/// (`CombineClipsJob.run()`) feeds these into AVMutableComposition;
/// here we pin the value-type shape and the legacy URL-only
/// convenience init so older callers (workflow chains, scripted
/// invocations) keep compiling.
final class CombineSourceTests: XCTestCase {

    func testDefaultTrimIsNilOnBothSides() {
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        let src = CombineSource(url: url)
        XCTAssertEqual(src.url, url)
        XCTAssertNil(src.trimInSeconds,
                      "Default trimInSeconds must be nil (= use clip start)")
        XCTAssertNil(src.trimOutSeconds,
                      "Default trimOutSeconds must be nil (= use clip end)")
    }

    func testTrimRangeRoundTrips() {
        var src = CombineSource(url: URL(fileURLWithPath: "/tmp/a.mov"))
        src.trimInSeconds = 1.5
        src.trimOutSeconds = 8.25
        XCTAssertEqual(src.trimInSeconds, 1.5)
        XCTAssertEqual(src.trimOutSeconds, 8.25)
    }

    /// Two `CombineSource` values with identical url + trim should
    /// be Equatable-equal. UI uses Equatable for change detection.
    func testEquatableConformanceMatchesValues() {
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        var a = CombineSource(url: url)
        var b = CombineSource(url: url)
        // Distinct UUIDs make these distinct Identifiables, so direct
        // == on the struct compares all stored properties including
        // id — they should be NOT equal.
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a, b)
        // Same instance to itself is equal.
        a.trimInSeconds = 5
        b = a
        XCTAssertEqual(a, b)
    }

    /// Legacy URL-only convenience init wraps each URL into a
    /// CombineSource with no trim — same behavior as pre-C16.
    /// Verifies workflow-chain call sites stay compiling.
    @MainActor
    func testLegacyURLsInitWrapsInUnTrimmedSources() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.mov"),
            URL(fileURLWithPath: "/tmp/b.mov"),
        ]
        let preset = TranscodePreset.all.first { $0.id == "prores-422" }!
        let job = CombineClipsJob(
            sources: urls,
            outputURL: URL(fileURLWithPath: "/tmp/out.mov"),
            preset: preset
        )
        XCTAssertEqual(job.sources.count, 2)
        XCTAssertEqual(job.sources.map(\.url), urls)
        for src in job.sources {
            XCTAssertNil(src.trimInSeconds)
            XCTAssertNil(src.trimOutSeconds)
        }
    }
}
