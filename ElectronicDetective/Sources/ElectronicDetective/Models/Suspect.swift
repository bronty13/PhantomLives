import Foundation

/// One of the 20 cards in the rolodex. The full cast is built in
/// `SuspectRoster`; this struct is the value type passed around the engine.
///
/// IDs 1–10 are male and 11–20 are female — that mapping is hard-coded into
/// the original game's logic and `SuspectRoster.all` honors it.
struct Suspect: Identifiable, Hashable, Codable, Sendable {
    let id: Int            // 1...20
    let name: String
    let occupation: String
    let sex: Sex

    var parity: IDParity { IDParity(id) }
}
