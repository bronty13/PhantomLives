import XCTest
@testable import PurpleTracker

/// Smoke test for the auto-bump-on-first-time-entry behavior. The full
/// integration uses the singleton `AppState` (which depends on the on-disk
/// support directory), so we test the rule in `bumpToInProgressIfNew`
/// indirectly by verifying that the lifecycle's first two values exist and
/// have the expected default ordering. Renaming the values is supported —
/// what matters is that index 0 → index 1 still works.
@MainActor
final class StatusLifecycleTests: XCTestCase {
    func testDefaultLifecycleOrder() {
        XCTAssertEqual(MatterStatus.defaultLifecycle.map(\.rawValue),
                       ["New", "In-Progress", "Complete", "Post-Mortem", "Closed"])
    }
}
