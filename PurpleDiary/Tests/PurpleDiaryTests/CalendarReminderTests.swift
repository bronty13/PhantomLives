import XCTest
@testable import PurpleDiary

/// Phase-6: calendar heatmap bucketing + the daily-reminder helpers (pure parts;
/// actual notification scheduling is a system side-effect verified by hand).
final class CalendarReminderTests: XCTestCase {

    func testHeatmapLevels() {
        XCTAssertEqual(CalendarHeatmap.level(words: 0), 0)
        XCTAssertEqual(CalendarHeatmap.level(words: 10), 1)
        XCTAssertEqual(CalendarHeatmap.level(words: 100), 2)
        XCTAssertEqual(CalendarHeatmap.level(words: 250), 3)
        XCTAssertEqual(CalendarHeatmap.level(words: 1000), 4)
    }

    func testHeatmapOpacityIsMonotonic() {
        let ops = (0...4).map { CalendarHeatmap.opacity(level: $0) }
        XCTAssertEqual(ops, ops.sorted(), "opacity should increase with level")
        XCTAssertLessThan(ops[0], ops[4])
    }

    func testReminderTriggerComponentsClampToValidRange() {
        let c = NotificationService.triggerComponents(hour: 25, minute: -5)
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 0)
        let ok = NotificationService.triggerComponents(hour: 8, minute: 30)
        XCTAssertEqual(ok.hour, 8)
        XCTAssertEqual(ok.minute, 30)
    }

    func testReminderBodyRotatesByWeekdayAndIsStable() {
        let cal = Calendar(identifier: .gregorian)
        let d = DateComponents(calendar: cal, year: 2026, month: 5, day: 31).date!  // a Sunday
        let body = NotificationService.body(for: d, calendar: cal)
        XCTAssertTrue(NotificationService.messages.contains(body))
        XCTAssertEqual(body, NotificationService.body(for: d, calendar: cal))  // deterministic
    }
}
