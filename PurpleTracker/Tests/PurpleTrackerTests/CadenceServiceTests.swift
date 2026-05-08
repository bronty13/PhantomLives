import XCTest
@testable import PurpleTracker

@MainActor
final class CadenceServiceTests: XCTestCase {

    func testEachCadenceShiftsDueAtCorrectly() {
        let cal = Calendar(identifier: .gregorian)
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!

        let cases: [(CadenceKind, DateComponents)] = [
            (.daily,      DateComponents(day: 1)),
            (.weekly,     DateComponents(day: 7)),
            (.biweekly,   DateComponents(day: 14)),
            (.monthly,    DateComponents(month: 1)),
            (.quarterly,  DateComponents(month: 3)),
            (.semiannual, DateComponents(month: 6)),
            (.annual,     DateComponents(year: 1)),
        ]
        for (kind, delta) in cases {
            let cad = Cadence(id: "c", kind: kind, customIntervalDays: nil)
            let next = cad.nextDate(after: base)
            let expected = cal.date(byAdding: delta, to: base)!
            XCTAssertEqual(next, expected, "\(kind) shifted incorrectly")
        }
    }

    func testCustomCadenceUsesIntervalDays() {
        let base = Date(timeIntervalSince1970: 0)
        let cad = Cadence(id: "c", kind: .custom, customIntervalDays: 17)
        let next = cad.nextDate(after: base)
        XCTAssertEqual(next.timeIntervalSince(base), 17 * 86400, accuracy: 1)
    }

    func testNextMatterCarriesRefsAndResetsResolution() {
        let now = Date()
        let prev = Matter(
            id: "2026-05-07-00001", title: "Quarterly Review",
            typeId: "type-cadenced", status: "Closed",
            descriptionMd: "desc", dueAt: now,
            createdAt: now, accessedAt: now, modifiedAt: now,
            external1Number: "INC-1", external1Url: "https://snow",
            external2Number: "ADO-2", external2Url: "https://ado",
            external3Number: "CR-3",  external3Url: "https://cr",
            timeTrackingCode: "BU-7",
            resolutionMd: "did the thing",
            lessonsMd: "next time...",
            notesMd: "notes",
            fileStorePrimary: "/tmp/p", fileStoreSecondary: "/tmp/s",
            cadenceId: "cad-q",
            parentMatterId: nil,
            requestorAssociateId: "",
            priority: MatterPriority.p2High.rawValue,
            interestedParty1AssociateId: "AID-IP1", interestedParty2AssociateId: "",
            interestedParty3AssociateId: "", interestedParty4AssociateId: "",
            interestedParty5AssociateId: "",
            externalInterestedParty1: "Acme Corp", externalInterestedParty2: "",
            externalInterestedParty3: "", externalInterestedParty4: "",
            externalInterestedParty5: ""
        )
        let cad = Cadence(id: "cad-q", kind: .quarterly, customIntervalDays: nil)
        let next = CadenceService.nextMatter(after: prev, cadence: cad)

        XCTAssertEqual(next.title, prev.title)
        XCTAssertEqual(next.typeId, prev.typeId)
        XCTAssertEqual(next.status, "New")
        XCTAssertEqual(next.parentMatterId, prev.id)
        XCTAssertEqual(next.cadenceId, "cad-q")
        XCTAssertEqual(next.timeTrackingCode, "BU-7")
        XCTAssertEqual(next.external1Number, "INC-1")
        XCTAssertEqual(next.external2Url, "https://ado")
        XCTAssertEqual(next.resolutionMd, "")
        XCTAssertEqual(next.lessonsMd, "")
        XCTAssertEqual(next.notesMd, "")
        XCTAssertEqual(next.interestedParty1AssociateId, "AID-IP1",
                       "Interested parties should carry forward to the cadence successor")
        XCTAssertEqual(next.externalInterestedParty1, "Acme Corp",
                       "External interested parties should carry forward")
        XCTAssertEqual(next.priority, MatterPriority.p2High.rawValue,
                       "Priority should carry forward to the cadence successor")
        XCTAssertNotNil(next.dueAt)
    }
}
