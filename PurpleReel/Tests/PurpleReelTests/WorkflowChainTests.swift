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

    // MARK: - continueOnFailure (C33 E2)

    func testContinueOnFailureDefaultsToFalse() {
        let chain = WorkflowChain(name: "Default", steps: [])
        XCTAssertFalse(chain.continueOnFailure,
                        "Pre-C33 chains and the default initializer "
                        + "must keep abort-on-first-failure behavior")
    }

    /// Pre-C33 JSON didn't carry the `continueOnFailure` field. The
    /// custom decoder defaults missing values to false so upgraded
    /// users don't lose their saved chains.
    func testLegacyJSONWithoutContinueOnFailureDecodesAsFalse() throws {
        let legacy = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "notes": "",
          "steps": [],
          "runOnCameraMediaMount": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkflowChain.self, from: legacy)
        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertFalse(decoded.continueOnFailure,
                        "Missing continueOnFailure field must decode as false")
    }

    func testContinueOnFailureSurvivesRoundTrip() throws {
        let original = WorkflowChain(
            name: "Best-effort",
            steps: [.transcode(.defaults)],
            continueOnFailure: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkflowChain.self, from: data)
        XCTAssertTrue(decoded.continueOnFailure)
    }

    // MARK: - Templates catalogue (C33 E4)

    func testEveryTemplateBuildsAValidChain() {
        // Catch a future template-author mistake that ships a
        // template whose `build()` factory produces an invalid
        // chain (empty steps, etc.).
        //
        // Templates that include a Verified Backup step
        // intentionally leave `destinationPaths` empty — that's the
        // user-customisable hook (forces a deliberate choice of
        // where to back up to). validate() rejects that with a
        // "no destinations" message, which is expected here.
        for template in WorkflowChainTemplates.catalogue {
            let chain = template.build()
            XCTAssertFalse(chain.steps.isEmpty,
                "Template \(template.id) must contain at least one step")
            let err = WorkflowChainsService.validate(chain)
            if let err {
                XCTAssertTrue(err.contains("no destinations"),
                    "Template \(template.id) failed validation for an unexpected reason: \(err)")
            }
        }
    }

    func testTemplateBuildsAreNotAliased() {
        // Each invocation of `build()` must mint a fresh UUID so
        // two "Add from template" clicks don't produce two rows
        // with the same id (would break Identifiable / List
        // selection).
        guard let template = WorkflowChainTemplates.catalogue.first
        else { return XCTFail("Catalogue is empty") }
        let a = template.build()
        let b = template.build()
        XCTAssertNotEqual(a.id, b.id,
            "Each template build must mint a fresh UUID")
    }

    func testDailyDeliveryTemplateHasContinueOnFailureOn() {
        // Specific contract: the "Daily Delivery" template
        // documents itself as best-effort. If a future edit
        // accidentally flips this, the template's own description
        // would be a lie.
        guard let t = WorkflowChainTemplates.catalogue
            .first(where: { $0.id == "daily-delivery" })
        else { return XCTFail("Missing daily-delivery template") }
        XCTAssertTrue(t.build().continueOnFailure)
    }

    func testCardOffloadTemplateAutoTriggersOnMount() {
        guard let t = WorkflowChainTemplates.catalogue
            .first(where: { $0.id == "card-offload" })
        else { return XCTFail("Missing card-offload template") }
        XCTAssertTrue(t.build().runOnCameraMediaMount)
    }
}
