import XCTest
@testable import PurpleAtticCore

final class SchedulerTests: XCTestCase {

    /// The default schedule must land in WAKING HOURS, never overnight: an unattended run
    /// parks on the macOS "access data from other apps" consent prompt until a human clicks
    /// Allow, so a 2 AM default sat blocked for hours. Lock the default to a daytime hour.
    func testDefaultScheduleIsWakingHours() {
        let s = ArchiveSchedule()
        XCTAssertEqual(s.hour, 12, "default archive hour should be noon, not the wee hours")
        XCTAssertTrue((8...18).contains(s.hour), "default must be a waking-hours time")
        XCTAssertEqual(s.cadence, .daily)
    }

    func testDailyCalendarKeysOmitWeekday() {
        let s = ArchiveSchedule(enabled: true, cadence: .daily, hour: 2, minute: 30)
        let keys = s.calendarKeys
        XCTAssertEqual(keys.map { $0.key }, ["Hour", "Minute"])
        XCTAssertEqual(keys.first { $0.key == "Hour" }?.value, 2)
        XCTAssertEqual(keys.first { $0.key == "Minute" }?.value, 30)
    }

    func testHourlyCalendarKeysAreMinuteOnly() {
        // Only Minute → launchd fires every hour at that minute.
        let s = ArchiveSchedule(enabled: true, cadence: .hourly, hour: 5, minute: 0)
        let keys = s.calendarKeys
        XCTAssertEqual(keys.map { $0.key }, ["Minute"])
        XCTAssertEqual(keys.first?.value, 0)
    }

    func testHourlyPlistHasNoHour() {
        let s = ArchiveSchedule(enabled: true, cadence: .hourly, hour: 9, minute: 0)
        let xml = LaunchAgentPlist.build(label: "x", programArguments: ["a"], schedule: s,
                                         stdoutPath: "/tmp/o", stderrPath: "/tmp/e")
        XCTAssertTrue(xml.contains("<key>Minute</key>"))
        XCTAssertFalse(xml.contains("<key>Hour</key>"), "hourly fires every hour — no Hour key")
        XCTAssertFalse(xml.contains("<key>Weekday</key>"))
    }

    func testNextRunHourlyMatchesMinute() {
        let s = ArchiveSchedule(enabled: true, cadence: .hourly, hour: 0, minute: 0)
        let next = s.nextRun(after: Date())
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
        XCTAssertEqual(Calendar.current.component(.minute, from: next!), 0)
    }

    func testWeeklyCalendarKeysIncludeWeekday() {
        let s = ArchiveSchedule(enabled: true, cadence: .weekly, hour: 9, minute: 0, weekday: 3)
        let keys = s.calendarKeys
        XCTAssertEqual(keys.map { $0.key }, ["Weekday", "Hour", "Minute"])
        XCTAssertEqual(keys.first { $0.key == "Weekday" }?.value, 3)
    }

    func testPlistContainsExpectedFields() {
        let s = ArchiveSchedule(enabled: true, cadence: .daily, hour: 2, minute: 0)
        let xml = LaunchAgentPlist.build(
            label: "com.bronty13.PurpleAttic.archive",
            programArguments: ["/Applications/PurpleAttic.app/Contents/MacOS/pattic", "export"],
            schedule: s,
            stdoutPath: "/tmp/out.log",
            stderrPath: "/tmp/err.log")
        XCTAssertTrue(xml.contains("<key>Label</key>"))
        XCTAssertTrue(xml.contains("com.bronty13.PurpleAttic.archive"))
        XCTAssertTrue(xml.contains("<string>export</string>"))
        XCTAssertTrue(xml.contains("<key>StartCalendarInterval</key>"))
        XCTAssertTrue(xml.contains("<key>Hour</key>"))
        XCTAssertTrue(xml.contains("<integer>2</integer>"))
        XCTAssertTrue(xml.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(xml.contains("<false/>"), "must not run at load — only on schedule")
        XCTAssertFalse(xml.contains("<key>Weekday</key>"), "daily schedule has no Weekday")
    }

    func testPlistWeeklyHasWeekday() {
        let s = ArchiveSchedule(enabled: true, cadence: .weekly, hour: 1, minute: 15, weekday: 0)
        let xml = LaunchAgentPlist.build(label: "x", programArguments: ["a"], schedule: s,
                                         stdoutPath: "/tmp/o", stderrPath: "/tmp/e")
        XCTAssertTrue(xml.contains("<key>Weekday</key>"))
        XCTAssertTrue(xml.contains("<integer>0</integer>"))
    }

    func testNextRunDailyIsInFuture() {
        let now = Date()
        let s = ArchiveSchedule(enabled: true, cadence: .daily, hour: 2, minute: 0)
        let next = s.nextRun(after: now)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, now)
        XCTAssertEqual(Calendar.current.component(.hour, from: next!), 2)
        XCTAssertEqual(Calendar.current.component(.minute, from: next!), 0)
    }

    func testNextRunWeeklyLandsOnWeekday() {
        let s = ArchiveSchedule(enabled: true, cadence: .weekly, hour: 8, minute: 0, weekday: 2) // Tuesday
        let next = s.nextRun(after: Date())
        XCTAssertNotNil(next)
        // launchd weekday 2 == Calendar weekday 3 (Sun=1).
        XCTAssertEqual(Calendar.current.component(.weekday, from: next!), 3)
    }

    func testHumanDescription() {
        XCTAssertEqual(ArchiveSchedule(cadence: .hourly, hour: 0, minute: 0).humanDescription,
                       "Every hour at :00")
        XCTAssertEqual(ArchiveSchedule(cadence: .daily, hour: 2, minute: 5).humanDescription,
                       "Every day at 02:05")
        XCTAssertEqual(ArchiveSchedule(cadence: .weekly, hour: 9, minute: 0, weekday: 1).humanDescription,
                       "Every Monday at 09:00")
    }

    func testXMLEscaping() {
        let xml = LaunchAgentPlist.build(label: "a&b", programArguments: ["<x>"], schedule: ArchiveSchedule(),
                                         stdoutPath: "/o", stderrPath: "/e")
        XCTAssertTrue(xml.contains("a&amp;b"))
        XCTAssertTrue(xml.contains("&lt;x&gt;"))
    }
}
