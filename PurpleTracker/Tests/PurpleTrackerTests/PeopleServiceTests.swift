import XCTest
@testable import PurpleTracker

@MainActor
final class PeopleServiceTests: XCTestCase {

    func testParseHandlesQuotedFieldsAndEmbeddedCommas() {
        let csv = """
        Associate ID,First Name,Last Name,Job Title Description
        AID-1,Jane,Doe,"Director, Risk & Compliance"
        AID-2,John,Smith,Engineer
        """
        let rows = PeopleService.parseCSV(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][3], "Director, Risk & Compliance")
        XCTAssertEqual(rows[2][1], "John")
    }

    func testParseHandlesEscapedQuotes() {
        let csv = "a,b\n\"He said \"\"hi\"\"\",x"
        let rows = PeopleService.parseCSV(csv)
        XCTAssertEqual(rows[1][0], "He said \"hi\"")
    }

    func testPersonDisplayNameUsesPreferredAndTitleCases() {
        let p = Person(
            id: "AID-1", firstName: "OSAZUWA", lastName: "AGBONTAEN",
            preferredName: "OZ", jobTitle: "SENIOR ENGINEER",
            workEmail: "oz@x.com", department: "ENG", location: "AMH",
            positionStatus: "Active", managerAssociateId: "", updatedAt: Date()
        )
        XCTAssertEqual(p.displayName, "Oz Agbontaen")
        XCTAssertEqual(p.displayNameWithTitle, "Oz Agbontaen (Senior Engineer)")
        XCTAssertTrue(p.isActive)
    }

    func testPersonFallsBackToFirstNameWhenNoPreferred() {
        let p = Person(
            id: "AID-2", firstName: "Jane", lastName: "Doe",
            preferredName: "", jobTitle: "",
            workEmail: "", department: "", location: "",
            positionStatus: "Terminated", managerAssociateId: "", updatedAt: Date()
        )
        XCTAssertEqual(p.displayName, "Jane Doe")
        XCTAssertEqual(p.displayNameWithTitle, "Jane Doe")
        XCTAssertFalse(p.isActive)
    }
}
