import XCTest
@testable import PurpleReel

final class WorkflowChainTests: XCTestCase {

    // MARK: - Validation

    func testEmptyStepsChainRejected() {
        let chain = WorkflowChain(name: "Empty", steps: [])
        XCTAssertEqual(
            WorkflowChainsService.validate(chain),
            "Chain has no steps."
        )
    }

    func testValidChainPasses() {
        let chain = WorkflowChain(
            name: "Standard offload",
            steps: [
                .verifiedBackup(
                    WorkflowChain.VerifiedBackupParams(
                        destinationPaths: ["/Volumes/Backup1"],
                        hashAlgorithm: "SHA-1",
                        mhlFormat: "MHL v1.1"
                    )
                ),
                .transcode(WorkflowChain.TranscodeParams.defaults),
                .exportReport(WorkflowChain.ReportParams.defaults),
            ]
        )
        XCTAssertNil(WorkflowChainsService.validate(chain),
            "Well-formed chain must validate")
    }

    func testBackupWithoutDestinationsIsRejectedWithStepNumber() {
        let chain = WorkflowChain(
            name: "Missing destinations",
            steps: [
                .transcode(WorkflowChain.TranscodeParams.defaults),
                .verifiedBackup(  // step 2 has no destinations
                    WorkflowChain.VerifiedBackupParams(
                        destinationPaths: [],
                        hashAlgorithm: "SHA-1",
                        mhlFormat: "MHL v1.1"
                    )
                ),
            ]
        )
        let err = WorkflowChainsService.validate(chain)
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.contains("Step 2") ?? false,
            "Error should pinpoint the offending step: \(err ?? "nil")")
    }

    // MARK: - Persistence round-trip

    func testJSONRoundTripPreservesEveryField() throws {
        // The Store uses UserDefaults. Test uses Codable directly
        // to avoid leaking state into the real defaults.
        let original = WorkflowChain(
            name: "Roundtrip test",
            notes: "Multi-line\nnotes survive",
            steps: [
                .verifiedBackup(
                    WorkflowChain.VerifiedBackupParams(
                        destinationPaths: ["/Volumes/A", "/Volumes/B"],
                        hashAlgorithm: "C4",
                        mhlFormat: "ASC-MHL v2.0"
                    )
                ),
                .transcode(
                    WorkflowChain.TranscodeParams(
                        presetID: "prores-422-proxy",
                        outputPath: "/tmp/proxies"
                    )
                ),
                .exportReport(
                    WorkflowChain.ReportParams(
                        format: "html",
                        outputPath: ""
                    )
                ),
            ],
            runOnCameraMediaMount: true
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode([original])
        let decoded = try decoder.decode([WorkflowChain].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        guard let r = decoded.first else { return }
        XCTAssertEqual(r.name, "Roundtrip test")
        XCTAssertEqual(r.notes, "Multi-line\nnotes survive")
        XCTAssertEqual(r.runOnCameraMediaMount, true)
        XCTAssertEqual(r.steps.count, 3)
        XCTAssertEqual(r, original,
            "Codable round-trip must preserve every field")
    }

    // MARK: - Step shape

    func testStepDisplayNames() {
        XCTAssertEqual(
            WorkflowChain.Step.verifiedBackup(.defaults).displayName,
            "Verified Backup"
        )
        XCTAssertEqual(
            WorkflowChain.Step.transcode(.defaults).displayName,
            "Transcode"
        )
        XCTAssertEqual(
            WorkflowChain.Step.exportReport(.defaults).displayName,
            "Export Report"
        )
    }

    func testStepIcons() {
        // The sheet uses these systemNames; renaming would break
        // the UI silently. Pin them.
        XCTAssertEqual(
            WorkflowChain.Step.verifiedBackup(.defaults).icon,
            "externaldrive.badge.checkmark"
        )
        XCTAssertEqual(
            WorkflowChain.Step.transcode(.defaults).icon,
            "wand.and.stars"
        )
        XCTAssertEqual(
            WorkflowChain.Step.exportReport(.defaults).icon,
            "doc.text"
        )
    }
}
