import Foundation

/// A fully generated scenario. Produced by `CaseGenerator`; consumed by
/// `Interrogator` and `Accuser`. Pure value type, fully `Codable` so it can be
/// persisted, replayed, or shared.
///
/// Invariants (verified by the generator):
///   • `victimId` ∈ 1…20 and is NOT present in `suspectLocations`.
///   • `murdererId` ∈ 1…20, ≠ `victimId`, and IS present in `suspectLocations`.
///   • `weapons.count == 2`, distinct calibers (one `.38`, one `.45`),
///     distinct locations, neither at `victimLocation`.
///   • `murderer` is NOT at `victimLocation` nor at either weapon's location.
///   • `suspectLocations.count == 19` (all living suspects).
///   • Per-location: 4+4+4+4+3 across the 5 living-suspect locations; ≤2
///     suspects of each sex; same-sex pairs at a location have opposite
///     id parity.
struct GameCase: Codable, Hashable, Sendable {
    let victimId: Int
    let murdererId: Int
    let victimLocation: Location
    let weapons: [Weapon]
    let suspectLocations: [Int: Location]
    let seed: UInt64

    var fingerprintParity: IDParity { IDParity(murdererId) }

    var murderer: Suspect { SuspectRoster.suspect(id: murdererId) }
    var victim: Suspect   { SuspectRoster.suspect(id: victimId) }

    /// All living suspect ids placed at the given location.
    func suspects(at location: Location) -> [Int] {
        suspectLocations.compactMap { $0.value == location ? $0.key : nil }.sorted()
    }

    func weapon(at location: Location) -> Weapon? {
        weapons.first { $0.location == location }
    }

    var weaponLocations: Set<Location> { Set(weapons.map(\.location)) }

    /// Locations that hold living suspects (everywhere except the victim's body).
    var livingLocations: [Location] {
        Location.allCases.filter { $0 != victimLocation }
    }
}
