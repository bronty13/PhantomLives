import XCTest
@testable import ElectronicDetective

final class InterrogatorTests: XCTestCase {

    /// "Where were you" returns the placed location for living suspects.
    func testWhereWereYouReturnsPlacedLocation() throws {
        let c = try CaseGenerator.generate(seed: 42)
        for (id, expected) in c.suspectLocations {
            let ans = Interrogator.answer(question: .whereWereYou, suspectId: id, in: c)
            if case .location(let got) = ans {
                XCTAssertEqual(got, expected, "suspect \(id)")
            } else {
                XCTFail("expected .location for suspect \(id), got \(ans)")
            }
        }
    }

    /// Asking the victim returns `.dead`.
    func testAskingTheVictimReturnsDead() throws {
        let c = try CaseGenerator.generate(seed: 7)
        let ans = Interrogator.answer(question: .whereWereYou, suspectId: c.victimId, in: c)
        XCTAssertEqual(ans, .dead)
    }

    /// Fingerprint: suspects NOT at a weapon location reply `.dontKnow`.
    func testFingerprintIDontKnowAwayFromWeapons(){
        do {
            let c = try CaseGenerator.generate(seed: 99)
            let weaponLocs = c.weaponLocations
            for (id, loc) in c.suspectLocations where !weaponLocs.contains(loc) {
                let ans = Interrogator.answer(question: .fingerprintParity, suspectId: id, in: c)
                XCTAssertEqual(ans, .dontKnow, "expected IDK for suspect \(id) at \(loc)")
            }
        } catch { XCTFail("\(error)") }
    }

    /// Fingerprint: suspects AT a weapon location return the correct parity.
    func testFingerprintTruthAtWeaponLocations() throws {
        let c = try CaseGenerator.generate(seed: 555)
        for (id, loc) in c.suspectLocations where c.weaponLocations.contains(loc) {
            let ans = Interrogator.answer(question: .fingerprintParity, suspectId: id, in: c)
            XCTAssertEqual(ans, .parity(c.fingerprintParity),
                           "suspect \(id) at \(loc) parity mismatch")
        }
    }

    /// Fingerprint parity tracks the murderer's id parity.
    func testFingerprintParityMatchesMurdererId() throws {
        let c = try CaseGenerator.generate(seed: 1001)
        XCTAssertEqual(c.fingerprintParity, IDParity(c.murdererId))
    }
}
