import Foundation

/// The two weapon calibers used by the original. The console picks one of the
/// two as the murder weapon and places each at a distinct (non-body) location.
enum WeaponCaliber: String, Codable, CaseIterable, Hashable, Sendable {
    case thirtyEight = ".38"
    case fortyFive   = ".45"

    var displayName: String { rawValue }
}

struct Weapon: Codable, Hashable, Sendable {
    let caliber: WeaponCaliber
    let location: Location
}
