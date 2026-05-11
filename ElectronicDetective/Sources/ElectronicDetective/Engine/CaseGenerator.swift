import Foundation

/// Generates a random, valid `GameCase` honoring every distribution rule from
/// the original game's manual:
///
///   • Exactly 1 of the 20 suspects is the victim — removed from play.
///   • 19 living suspects spread across 5 of the 6 locations: 4 + 4 + 4 + 4 + 3.
///   • The 6th location holds only the victim's body (no living suspects).
///   • Each location has at most 2 male and at most 2 female suspects.
///   • Any same-sex pair at a location has one odd-id and one even-id suspect.
///   • Exactly 2 weapons — one `.38`, one `.45` — placed at distinct, non-body
///     locations.
///   • The murderer is one of the 19 living suspects and is at neither weapon's
///     location nor the body's location.
///
/// Strategy: pick the high-level layout (victim, body location, weapon
/// locations, the 3-suspect location, murderer & their slot), then derive
/// per-location male/female counts *deterministically* from the surviving sex
/// distribution. The 3-suspect location gets `2M+1F` or `1M+2F` depending on
/// which sex has the spare body. Once counts are fixed, a depth-first
/// backtracker places suspects under the parity rule — the tight per-location
/// caps make placement effectively O(1) and the whole generate() routine
/// finishes in well under a millisecond. Deterministic when seeded.
enum CaseGenerator {

    struct GenerationError: Error, CustomStringConvertible {
        let attempts: Int
        var description: String { "Could not generate a valid case in \(attempts) attempts" }
    }

    /// Generate a `GameCase`. `seed = nil` uses `SystemRandomNumberGenerator`.
    static func generate(seed: UInt64? = nil, maxAttempts: Int = 200) throws -> GameCase {
        let actualSeed = seed ?? UInt64.random(in: 1...UInt64.max)
        var rng = SeededRNG(seed: actualSeed)
        for _ in 0..<maxAttempts {
            if let c = attempt(rng: &rng, seed: actualSeed) {
                return c
            }
        }
        throw GenerationError(attempts: maxAttempts)
    }

    // MARK: - One attempt

    private static func attempt(rng: inout SeededRNG, seed: UInt64) -> GameCase? {
        // 1. Victim and body location.
        let victimId = Int.random(in: 1...20, using: &rng)
        let victimSex = SuspectRoster.suspect(id: victimId).sex
        let livingIds = (1...20).filter { $0 != victimId }
        let bodyLocation = Location.allCases.randomElement(using: &rng)!
        let livingLocations = Location.allCases.filter { $0 != bodyLocation }   // 5 locations

        // 2. Two weapon locations from the living set (distinct).
        let shuffledLiving = livingLocations.shuffled(using: &rng)
        let weaponLocs = Array(shuffledLiving.prefix(2))
        let nonWeaponLiving = Array(shuffledLiving.suffix(3))                   // 3 of 5

        // 3. Murderer is one of the 19 living, placed at a non-weapon non-body location.
        let murdererId = livingIds.randomElement(using: &rng)!
        let murdererLocation = nonWeaponLiving.randomElement(using: &rng)!
        let murderer = SuspectRoster.suspect(id: murdererId)

        // 4. Per-sex counts among the 19 living. The 4+4+4+4+3 shape demands
        //    the 3-suspect location holds the "spare" sex's last body. With
        //    male/female pools of size 10 each, removing one victim yields:
        //
        //       victim female → 10 males, 9 females → 3-loc must be 2M+1F
        //       victim male   →  9 males, 10 females → 3-loc must be 1M+2F
        //
        //    All other 4-suspect locations must be exactly 2M+2F.
        let totalMales = SuspectRoster.maleIds.count - (victimSex == .male ? 1 : 0)
        let totalFemales = SuspectRoster.femaleIds.count - (victimSex == .female ? 1 : 0)

        let threeLocation = livingLocations.randomElement(using: &rng)!
        var maleCap: [Location: Int] = [:]
        var femaleCap: [Location: Int] = [:]
        for loc in livingLocations {
            if loc == threeLocation {
                if totalMales > totalFemales {
                    maleCap[loc]   = 2
                    femaleCap[loc] = 1
                } else {
                    maleCap[loc]   = 1
                    femaleCap[loc] = 2
                }
            } else {
                maleCap[loc]   = 2
                femaleCap[loc] = 2
            }
        }

        // 5. Place the murderer first — this seats one body and decrements caps.
        var placements: [Int: Location] = [:]
        var maleAtLoc: [Location: Set<IDParity>] = Dictionary(uniqueKeysWithValues: livingLocations.map { ($0, []) })
        var femaleAtLoc: [Location: Set<IDParity>] = Dictionary(uniqueKeysWithValues: livingLocations.map { ($0, []) })
        if !occupy(suspect: murderer, at: murdererLocation,
                   maleCap: &maleCap, femaleCap: &femaleCap,
                   maleAtLoc: &maleAtLoc, femaleAtLoc: &femaleAtLoc) {
            return nil   // murderer's gender doesn't fit at the chosen 3-loc — retry the attempt
        }
        placements[murdererId] = murdererLocation

        // 6. Split the remaining 18 suspects by sex and shuffle each list. The
        //    parity rule binds locally to a single location, so a simple
        //    sex-first DFS converges fast.
        var remainingMales   = livingIds.filter { $0 != murdererId && SuspectRoster.suspect(id: $0).sex == .male   }.shuffled(using: &rng)
        var remainingFemales = livingIds.filter { $0 != murdererId && SuspectRoster.suspect(id: $0).sex == .female }.shuffled(using: &rng)

        if !placeSex(
            sex: .male,
            remaining: &remainingMales,
            livingLocations: livingLocations.shuffled(using: &rng),
            placements: &placements,
            sexCap: &maleCap,
            sexAtLoc: &maleAtLoc
        ) { return nil }

        if !placeSex(
            sex: .female,
            remaining: &remainingFemales,
            livingLocations: livingLocations.shuffled(using: &rng),
            placements: &placements,
            sexCap: &femaleCap,
            sexAtLoc: &femaleAtLoc
        ) { return nil }

        // 7. Weapons get random calibers in the picked locations.
        let weaponCalibers = WeaponCaliber.allCases.shuffled(using: &rng)
        let weapons = [
            Weapon(caliber: weaponCalibers[0], location: weaponLocs[0]),
            Weapon(caliber: weaponCalibers[1], location: weaponLocs[1]),
        ]

        return GameCase(
            victimId: victimId,
            murdererId: murdererId,
            victimLocation: bodyLocation,
            weapons: weapons,
            suspectLocations: placements,
            seed: seed
        )
    }

    // MARK: - Per-sex placement (each sex placed independently — locations
    // are pre-capped so the two passes can't interfere with each other).

    private static func placeSex(
        sex: Sex,
        remaining: inout [Int],
        livingLocations: [Location],
        placements: inout [Int: Location],
        sexCap: inout [Location: Int],
        sexAtLoc: inout [Location: Set<IDParity>]
    ) -> Bool {
        return placeRecursive(
            sex: sex, index: 0, ids: remaining,
            locationsOrder: livingLocations,
            placements: &placements,
            sexCap: &sexCap, sexAtLoc: &sexAtLoc
        )
    }

    private static func placeRecursive(
        sex: Sex,
        index: Int, ids: [Int],
        locationsOrder: [Location],
        placements: inout [Int: Location],
        sexCap: inout [Location: Int],
        sexAtLoc: inout [Location: Set<IDParity>]
    ) -> Bool {
        if index == ids.count { return true }
        let id = ids[index]
        let parity = IDParity(id)

        for loc in locationsOrder {
            guard let cap = sexCap[loc], cap > 0 else { continue }
            var atLoc = sexAtLoc[loc] ?? []
            if atLoc.contains(parity) { continue }   // same-sex pair must have opposite parity

            atLoc.insert(parity); sexAtLoc[loc] = atLoc
            sexCap[loc] = cap - 1
            placements[id] = loc

            if placeRecursive(sex: sex, index: index + 1, ids: ids,
                              locationsOrder: locationsOrder,
                              placements: &placements,
                              sexCap: &sexCap, sexAtLoc: &sexAtLoc) {
                return true
            }

            placements.removeValue(forKey: id)
            sexCap[loc] = cap
            atLoc.remove(parity); sexAtLoc[loc] = atLoc
        }
        return false
    }

    private static func occupy(
        suspect: Suspect, at loc: Location,
        maleCap: inout [Location: Int],
        femaleCap: inout [Location: Int],
        maleAtLoc: inout [Location: Set<IDParity>],
        femaleAtLoc: inout [Location: Set<IDParity>]
    ) -> Bool {
        switch suspect.sex {
        case .male:
            guard let cap = maleCap[loc], cap > 0 else { return false }
            var s = maleAtLoc[loc] ?? []
            if s.contains(suspect.parity) { return false }
            s.insert(suspect.parity); maleAtLoc[loc] = s
            maleCap[loc] = cap - 1
        case .female:
            guard let cap = femaleCap[loc], cap > 0 else { return false }
            var s = femaleAtLoc[loc] ?? []
            if s.contains(suspect.parity) { return false }
            s.insert(suspect.parity); femaleAtLoc[loc] = s
            femaleCap[loc] = cap - 1
        }
        return true
    }
}

// MARK: - Seeded RNG (so cases are reproducible from a seed)

/// SplitMix64 — fast, decent statistical quality; perfect for game seeds
/// where the goal is reproducibility, not crypto.
struct SeededRNG: RandomNumberGenerator {
    var seed: UInt64
    init(seed: UInt64) { self.seed = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var z = seed
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
}
