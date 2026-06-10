import XCTest
@testable import PurpleAtticCore

final class RunProgressTests: XCTestCase {

    func testPhaseLifecycleAndEmbedSkips() {
        var last: RunProgress?
        let tracker = RunProgressTracker(kinds: [.exportHEIC, .mirror, .verify]) { last = $0 }

        tracker.startPhase(.exportHEIC, detail: "starting…")
        XCTAssertEqual(last?.activeStep?.kind, .exportHEIC)
        XCTAssertEqual(last?.steps.first?.state, .running)

        tracker.addEmbedSkip(); tracker.addEmbedSkip()
        tracker.finishPhase(.exportHEIC, state: .done, detail: "exit 0")
        XCTAssertEqual(last?.embedSkips, 2)
        XCTAssertEqual(last?.steps.first(where: { $0.kind == .exportHEIC })?.state, .done)
        XCTAssertNil(last?.activeStep, "no phase running between startPhase calls")

        tracker.startPhase(.mirror)
        XCTAssertEqual(last?.activeStep?.kind, .mirror)
        tracker.finishPhase(.mirror, state: .skipped, detail: "0 ok, 1 skipped")
        XCTAssertEqual(last?.steps.first(where: { $0.kind == .mirror })?.state, .skipped)

        tracker.finishRun()
        XCTAssertEqual(last?.finished, true)
    }

    func testStepsInitialisePending() {
        var last: RunProgress?
        let t = RunProgressTracker(kinds: [.exportHEIC, .exportJPEG, .cloud]) { last = $0 }
        t.startPhase(.exportHEIC)   // force a first emit
        XCTAssertEqual(last?.steps.map { $0.kind }, [.exportHEIC, .exportJPEG, .cloud])
        XCTAssertEqual(last?.steps.last?.state, .pending)
    }
}
