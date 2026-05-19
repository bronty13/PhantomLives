import XCTest
@testable import PurpleReel

/// Coverage for C13's `AnalysisScope` OptionSet (Kyno-parity, the
/// Pre-analyze dialog). The runtime side (`preAnalyzeSelected(scope:)`)
/// is wired through MediaScanner + ThumbnailService — those have
/// their own integration coverage; here we pin the OptionSet shape
/// and the Kyno-default selections.
final class AnalysisScopeTests: XCTestCase {

    func testDefaultMatchesKynoImage90() {
        // Image #90: Technical metadata + Thumbnails checked, Key
        // frames unchecked.
        XCTAssertTrue(AnalysisScope.default.contains(.technicalMetadata))
        XCTAssertTrue(AnalysisScope.default.contains(.thumbnails))
        XCTAssertFalse(AnalysisScope.default.contains(.keyFrames),
                        "Key frames must default off per Kyno's Image #90")
    }

    func testIndividualOptionsAreDisjoint() {
        // Raw values must not overlap — OptionSet bit-masking
        // depends on distinct rawValue bits.
        let tech = AnalysisScope.technicalMetadata.rawValue
        let thumbs = AnalysisScope.thumbnails.rawValue
        let key = AnalysisScope.keyFrames.rawValue
        XCTAssertEqual(tech & thumbs, 0,
                        ".technicalMetadata and .thumbnails must use distinct bits")
        XCTAssertEqual(tech & key, 0,
                        ".technicalMetadata and .keyFrames must use distinct bits")
        XCTAssertEqual(thumbs & key, 0,
                        ".thumbnails and .keyFrames must use distinct bits")
    }

    func testEmptyScopeIsActuallyEmpty() {
        // The dialog disables Start when scope.isEmpty; verify
        // the underlying check is honest.
        var scope: AnalysisScope = []
        XCTAssertTrue(scope.isEmpty)
        scope.insert(.thumbnails)
        XCTAssertFalse(scope.isEmpty)
        scope.remove(.thumbnails)
        XCTAssertTrue(scope.isEmpty)
    }

    func testCodableRoundTrip() {
        // Persist via JSON to future-proof — settings persistence
        // for the dialog's sticky default could land later.
        let scope: AnalysisScope = [.technicalMetadata, .thumbnails]
        let data = try? JSONEncoder().encode(scope)
        XCTAssertNotNil(data)
        let back = try? JSONDecoder().decode(AnalysisScope.self, from: data ?? Data())
        XCTAssertEqual(back, scope)
    }
}
