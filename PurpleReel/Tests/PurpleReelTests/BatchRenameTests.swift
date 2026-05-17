import XCTest
@testable import PurpleReel

final class BatchRenameTests: XCTestCase {

    private func makeAsset(filename: String, mod: Date,
                            codec: String? = "avc1",
                            fps: Double? = 29.97,
                            width: Int? = 1920,
                            height: Int? = 1080,
                            sizeBytes: Int64 = 200_000_000) -> Asset {
        Asset(rowId: nil,
              path: "/tmp/\(filename)",
              filename: filename,
              sizeBytes: sizeBytes,
              modifiedAt: mod,
              codec: codec,
              widthPx: width,
              heightPx: height,
              durationSeconds: 30,
              frameRate: fps,
              sha1: nil,
              addedAt: Date())
    }

    func testOrigAndExtTokens() {
        let asset = makeAsset(filename: "IMG_4501.mov", mod: Date())
        let plans = BatchRenameService.plan(template: "{orig}_v2{ext}", items: [asset])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].proposedName, "IMG_4501_v2.mov")
        XCTAssertFalse(plans[0].isNoop)
        XCTAssertFalse(plans[0].conflicts)
    }

    func testCounterTokenPadding() {
        let mod = Date()
        let assets = (1...3).map { makeAsset(filename: "clip\($0).mov", mod: mod) }
        let plans = BatchRenameService.plan(template: "{counter:04}_{orig}{ext}",
                                              items: assets, startCounter: 7)
        XCTAssertEqual(plans.map { $0.proposedName }, [
            "0007_clip1.mov", "0008_clip2.mov", "0009_clip3.mov",
        ])
    }

    func testDateTokenDefaultAndCustomFormat() {
        let mod = ISO8601DateFormatter().date(from: "2026-03-14T15:00:00Z")!
        let asset = makeAsset(filename: "raw.mov", mod: mod)
        let defaultPlan = BatchRenameService.plan(
            template: "{date}_{orig}{ext}", items: [asset])[0]
        XCTAssertEqual(defaultPlan.proposedName, "2026-03-14_raw.mov")
        let customPlan = BatchRenameService.plan(
            template: "{date:yyyyMMdd}_{orig}{ext}", items: [asset])[0]
        XCTAssertEqual(customPlan.proposedName, "20260314_raw.mov")
    }

    func testTechnicalTokens() {
        let asset = makeAsset(filename: "src.mov", mod: Date(),
                               codec: "hvc1", fps: 23.976,
                               width: 3840, height: 2160,
                               sizeBytes: 1_500_000_000)
        let plan = BatchRenameService.plan(
            template: "{codec}_{w}x{h}_{fps}_{size_mb}MB{ext}",
            items: [asset])[0]
        // fps formats with 2 decimals; size_mb is integer.
        XCTAssertEqual(plan.proposedName, "hvc1_3840x2160_23.98_1430MB.mov")
    }

    func testUnknownTokenLeftLiteralForVisibility() {
        // Typo in a token should be preserved verbatim so the user
        // notices in the preview.
        let asset = makeAsset(filename: "src.mov", mod: Date())
        let plan = BatchRenameService.plan(
            template: "{orig}_{forty_two}{ext}", items: [asset])[0]
        XCTAssertEqual(plan.proposedName, "src_{forty_two}.mov")
    }

    func testWithinBatchCollisionFlagsConflict() {
        let mod = Date()
        // Two distinct files but the template collapses them to the
        // same final name — should mark the second as conflict.
        let a = makeAsset(filename: "shot1.mov", mod: mod)
        let b = makeAsset(filename: "shot2.mov", mod: mod)
        let plans = BatchRenameService.plan(
            template: "same{ext}", items: [a, b])
        XCTAssertFalse(plans[0].conflicts)
        XCTAssertTrue(plans[1].conflicts)
    }
}
