import XCTest
@testable import ElectronicDetective

final class CaseGeneratorTests: XCTestCase {

    /// Generates many cases and asserts every invariant the original rules
    /// require. Catches placement bugs (caps, parity), murderer placement
    /// (must not be at body or weapon locations), and weapon validity.
    func testManyCasesAreAllValid() throws {
        let runs = 200
        for i in 0..<runs {
            let gameCase = try CaseGenerator.generate(seed: UInt64(i + 1))
            try assertValid(gameCase, run: i)
        }
    }

    /// Generation must be cheap — the app launch path calls it synchronously
    /// when the user presses ON. 200 cases should fit in <500ms on this
    /// machine; if it doesn't, an unlucky seed could make the UI appear hung.
    func testGenerationIsFast() throws {
        let start = Date()
        for i in 0..<200 {
            _ = try CaseGenerator.generate(seed: UInt64(i + 1))
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5, "200 cases took \(elapsed)s — generator too slow")
    }

    /// Same seed → same case. Catches accidental use of un-seeded RNG inside
    /// the generator.
    func testGenerationIsReproducibleFromSeed() throws {
        let a = try CaseGenerator.generate(seed: 12345)
        let b = try CaseGenerator.generate(seed: 12345)
        XCTAssertEqual(a, b)
    }

    /// Different seeds → different cases (with overwhelming probability).
    /// Catches a generator that ignored its seed.
    func testDifferentSeedsProduceDifferentCases() throws {
        let a = try CaseGenerator.generate(seed: 1)
        let b = try CaseGenerator.generate(seed: 2)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Invariant checker

    private func assertValid(_ c: GameCase, run: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let ctx = "run \(run) seed \(c.seed)"

        // Victim and murderer basic sanity
        XCTAssertTrue((1...20).contains(c.victimId),    "\(ctx): victim id out of range")
        XCTAssertTrue((1...20).contains(c.murdererId),  "\(ctx): murderer id out of range")
        XCTAssertNotEqual(c.victimId, c.murdererId,     "\(ctx): victim == murderer")

        // Suspect placements: 19 living, none of them the victim
        XCTAssertEqual(c.suspectLocations.count, 19,    "\(ctx): living count != 19")
        XCTAssertFalse(c.suspectLocations.keys.contains(c.victimId), "\(ctx): victim is placed")
        XCTAssertNotNil(c.suspectLocations[c.murdererId], "\(ctx): murderer not placed")
        for id in c.suspectLocations.keys {
            XCTAssertTrue((1...20).contains(id), "\(ctx): placed suspect \(id) out of range")
        }

        // Weapons: 2 distinct calibers, 2 distinct locations, neither at body
        XCTAssertEqual(c.weapons.count, 2, "\(ctx): weapon count != 2")
        XCTAssertEqual(Set(c.weapons.map(\.caliber)).count, 2, "\(ctx): duplicate caliber")
        XCTAssertEqual(Set(c.weapons.map(\.location)).count, 2, "\(ctx): duplicate weapon location")
        for w in c.weapons {
            XCTAssertNotEqual(w.location, c.victimLocation, "\(ctx): weapon at body location")
        }

        // Murderer NOT at body or weapon locations
        let murdererLoc = c.suspectLocations[c.murdererId]!
        XCTAssertNotEqual(murdererLoc, c.victimLocation,                  "\(ctx): murderer at body location")
        XCTAssertFalse(c.weaponLocations.contains(murdererLoc),          "\(ctx): murderer at weapon location")

        // Per-location distribution: 5 living locations summing to 19,
        // shape = 4 of size 4 and 1 of size 3.
        var counts: [Location: Int] = [:]
        for loc in c.suspectLocations.values { counts[loc, default: 0] += 1 }
        XCTAssertEqual(counts[c.victimLocation, default: 0], 0, "\(ctx): living at body location")
        let sizes = counts.values.sorted()
        XCTAssertEqual(sizes, [3, 4, 4, 4, 4], "\(ctx): bad size distribution \(sizes)")

        // Per-location sex and parity caps.
        for (loc, ids) in groupedSuspectIds(c) {
            let suspects = ids.map { SuspectRoster.suspect(id: $0) }
            let males   = suspects.filter { $0.sex == .male }
            let females = suspects.filter { $0.sex == .female }
            XCTAssertLessThanOrEqual(males.count,   2, "\(ctx): >2 males at \(loc)")
            XCTAssertLessThanOrEqual(females.count, 2, "\(ctx): >2 females at \(loc)")
            if males.count == 2 {
                XCTAssertNotEqual(males[0].parity, males[1].parity,
                                  "\(ctx): same-sex male pair both \(males[0].parity) at \(loc)")
            }
            if females.count == 2 {
                XCTAssertNotEqual(females[0].parity, females[1].parity,
                                  "\(ctx): same-sex female pair both \(females[0].parity) at \(loc)")
            }
        }
    }

    private func groupedSuspectIds(_ c: GameCase) -> [Location: [Int]] {
        var out: [Location: [Int]] = [:]
        for (id, loc) in c.suspectLocations { out[loc, default: []].append(id) }
        return out
    }
}
