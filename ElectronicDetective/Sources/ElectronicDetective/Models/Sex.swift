import Foundation

/// The two-value sex attribute used by the original game's logic. Drives
/// per-location placement caps and the fingerprint-truth rules in
/// `Interrogator`.
enum Sex: String, Codable, CaseIterable, Hashable {
    case male
    case female
}

/// Even-or-odd id parity is a load-bearing rule from the original: the murder
/// weapon's fingerprints belong to either an odd- or an even-numbered suspect,
/// and same-sex pairs at a location always have one of each parity.
enum IDParity: String, Codable, Hashable {
    case odd
    case even

    init(_ id: Int) { self = id.isMultiple(of: 2) ? .even : .odd }
}
