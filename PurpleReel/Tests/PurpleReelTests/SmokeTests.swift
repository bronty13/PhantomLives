import XCTest
@testable import PurpleReel

final class SmokeTests: XCTestCase {
    func testAssetKindFromExtension() {
        XCTAssertEqual(AssetKind.from(extension: "MOV"), .video)
        XCTAssertEqual(AssetKind.from(extension: "heic"), .image)
        XCTAssertEqual(AssetKind.from(extension: "wav"), .audio)
        XCTAssertEqual(AssetKind.from(extension: "xyz"), .other)
    }
}
