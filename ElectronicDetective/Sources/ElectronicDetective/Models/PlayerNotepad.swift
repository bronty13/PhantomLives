import Foundation

/// One player's on-screen Case Fact Sheet — the four sections of the original
/// printed pad. Auto-recorded in hybrid mode (`AppSettings.transcriptionMode
/// == .auto`); user-typed in strict mode.
struct PlayerNotepad: Codable, Hashable, Sendable {
    // MARK: - Section 1: "THE MURDER FACTS"
    var murdererSex: Sex?
    var weaponCaliber: WeaponCaliber?
    var fingerprintParity: IDParity?
    var murderLocation: Location?

    // MARK: - Section 2: "WHO WAS WHERE?" — suspect id → location
    var locationsBySuspect: [Int: Location] = [:]

    // MARK: - Section 3: "WHO SAID WHAT?" — free-form alibi/question notes
    var notes: [Int: String] = [:]   // suspect id → freeform text

    // MARK: - Section 4: "WHO DID IT?" — final accusation prepared by the player
    var prospectiveAccusationId: Int?

    static let empty = PlayerNotepad()
}
