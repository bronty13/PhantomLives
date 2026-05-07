import XCTest
@testable import Timeliner

final class SampleDataServiceTests: XCTestCase {

    /// The shipped Madeline Soto JSON should be findable in the app bundle
    /// (XcodeGen auto-bundles non-Swift files inside the `Sources/Timeliner`
    /// path) and should decode into the documented totals.
    @MainActor
    func testBundledMadelineSotoSamplePayloadParses() throws {
        let url = Bundle.main.url(
            forResource: "madeline_soto_case_data",
            withExtension: "json",
            subdirectory: "SampleData"
        ) ?? Bundle.main.url(
            forResource: "madeline_soto_case_data",
            withExtension: "json"
        )
        guard let url else {
            XCTFail("madeline_soto_case_data.json not bundled in Timeliner.app")
            return
        }
        let data = try Data(contentsOf: url)
        let payload = try SampleDataService.decodePayload(data)
        XCTAssertEqual(payload.case_.id, "case_001")
        XCTAssertEqual(payload.case_.name, "Murder of Madeline Soto")
        XCTAssertEqual(payload.people.count, 43)
        XCTAssertEqual(payload.timeline_events.count, 150)
    }

    @MainActor
    func testRoleMappingHandlesAllSampleCategories() {
        XCTAssertEqual(SampleDataService.mapRole("Victim", fallback: "Victim"), .victim)
        XCTAssertEqual(SampleDataService.mapRole("Suspect", fallback: "Suspect"), .suspect)
        XCTAssertEqual(SampleDataService.mapRole("Law Enforcement", fallback: "Detective"), .detective)
        XCTAssertEqual(SampleDataService.mapRole("Forensics", fallback: "Medical Examiner"), .detective)
        XCTAssertEqual(SampleDataService.mapRole("Prosecution", fallback: "Assistant State Attorney"), .attorney)
        XCTAssertEqual(SampleDataService.mapRole("Legal Counsel", fallback: "Defense Attorney"), .attorney)
        XCTAssertEqual(SampleDataService.mapRole("Family / Witness", fallback: "Mother"), .witness)
        XCTAssertEqual(SampleDataService.mapRole("Family", fallback: "Father"), .other)
        XCTAssertEqual(SampleDataService.mapRole("Civilian Witness", fallback: "Witness"), .witness)
        XCTAssertEqual(SampleDataService.mapRole("Court Personnel", fallback: "Judge"), .other)
        XCTAssertEqual(SampleDataService.mapRole("Other", fallback: "Tangential"), .other)
        XCTAssertEqual(SampleDataService.mapRole(nil, fallback: nil), .other)
    }

    @MainActor
    func testImportanceMappingFromCategoryNames() {
        XCTAssertEqual(SampleDataService.mapImportance("Day of Disappearance"), .critical)
        XCTAssertEqual(SampleDataService.mapImportance("Body Recovery"),       .critical)
        XCTAssertEqual(SampleDataService.mapImportance("Resolution"),          .critical)
        XCTAssertEqual(SampleDataService.mapImportance("Charges"),             .high)
        XCTAssertEqual(SampleDataService.mapImportance("Arrest"),              .high)
        XCTAssertEqual(SampleDataService.mapImportance("Court"),               .high)
        XCTAssertEqual(SampleDataService.mapImportance("Memorial"),            .high)
        XCTAssertEqual(SampleDataService.mapImportance("Pre-Disappearance"),   .medium)
        XCTAssertEqual(SampleDataService.mapImportance("Investigation"),       .medium)
        XCTAssertEqual(SampleDataService.mapImportance("Forensics"),           .medium)
        XCTAssertEqual(SampleDataService.mapImportance("Background"),          .low)
        XCTAssertEqual(SampleDataService.mapImportance("Tangential"),          .low)
        XCTAssertEqual(SampleDataService.mapImportance(nil),                   .low)
    }

    /// Verifies the date-padding shortcuts: year-only, year-month, full date,
    /// and the optional time fold-in. Sort-stable ISO output is the contract
    /// the rest of the timeline UI depends on.
    @MainActor
    func testIsoDateAcceptsYearYearMonthAndFullDate() {
        XCTAssertEqual(SampleDataService.isoDate(date: "2015",       time: nil),     "2015-01-01T00:00:00Z")
        XCTAssertEqual(SampleDataService.isoDate(date: "2023-11",    time: nil),     "2023-11-01T00:00:00Z")
        XCTAssertEqual(SampleDataService.isoDate(date: "2024-02-25", time: nil),     "2024-02-25T00:00:00Z")
        XCTAssertEqual(SampleDataService.isoDate(date: "2024-02-25", time: "20:00"), "2024-02-25T20:00:00Z")
        XCTAssertEqual(SampleDataService.isoDate(date: "2024-02-26", time: "09:41"), "2024-02-26T09:41:00Z")
        XCTAssertNil(SampleDataService.isoDate(date: "", time: nil))
    }

    @MainActor
    func testCaseStatusMapsConvictionToClosed() {
        XCTAssertEqual(SampleDataService.caseStatus(for: "Closed - Conviction"),
                       CaseStatus.closed.rawValue)
        XCTAssertEqual(SampleDataService.caseStatus(for: "Resolved"),
                       CaseStatus.closed.rawValue)
        XCTAssertEqual(SampleDataService.caseStatus(for: "Cold case"),
                       CaseStatus.cold.rawValue)
        XCTAssertEqual(SampleDataService.caseStatus(for: "Open investigation"),
                       CaseStatus.active.rawValue)
    }
}
