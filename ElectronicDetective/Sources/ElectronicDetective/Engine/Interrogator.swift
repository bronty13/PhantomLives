import Foundation

/// Answers a private question against a `GameCase`, honoring the original's
/// truth / lie / "I don't know" rules:
///
///   • A suspect can only be asked about facts on their own card — for our
///     digital recreation that reduces to: "where were you" (always truthful),
///     "what was your alibi" (always truthful), and the fingerprint question.
///   • Only same-sex-as-murderer suspects who are AT the murder weapon's
///     location can answer the fingerprint question. They generally tell the
///     truth, but the manual notes that opposite-sex-of-murderer suspects at
///     the weapon's location may lie. We treat the murderer's sex as the
///     truth-anchor: same-sex same-location → truth; opposite-sex same-location
///     → may lie; everyone else → "I don't know".
///   • Suspects not at a weapon location reply `.dontKnow` to fingerprint.
enum Interrogator {

    enum Question: Codable, Hashable, Sendable {
        case whereWereYou
        case fingerprintParity            // odd-or-even id of the murderer
    }

    enum Answer: Codable, Hashable, Sendable {
        case location(Location)
        case parity(IDParity)
        case dontKnow
        case dead                         // asked about the victim
    }

    /// In the original, the truth rule for fingerprints depends on whether
    /// the responder is at the weapon location and same-sex as the murderer.
    /// We don't yet model deliberate lies on the part of the console — that's
    /// an M3 nicety with a "fingerprintLiesEnabled" toggle. For M1 the
    /// interrogator is strict-truthful for every case it can answer.
    static func answer(question: Question, suspectId: Int, in gameCase: GameCase) -> Answer {
        if suspectId == gameCase.victimId { return .dead }
        guard let suspectLocation = gameCase.suspectLocations[suspectId] else {
            return .dontKnow   // unknown id
        }

        switch question {
        case .whereWereYou:
            return .location(suspectLocation)

        case .fingerprintParity:
            // The murderer's parity is the canonical answer. Only suspects at
            // a weapon location and of the same sex as the murderer "know" it
            // truthfully; everyone else replies "I don't know."
            let isAtWeaponLocation = gameCase.weaponLocations.contains(suspectLocation)
            guard isAtWeaponLocation else { return .dontKnow }
            let murdererSex = SuspectRoster.suspect(id: gameCase.murdererId).sex
            let suspectSex  = SuspectRoster.suspect(id: suspectId).sex
            if suspectSex == murdererSex {
                return .parity(gameCase.fingerprintParity)
            } else {
                // Opposite-sex same-location: original allows lies; for M1 we
                // still surface the truth. A future toggle will allow this
                // branch to flip the parity to model the suspect lying.
                return .parity(gameCase.fingerprintParity)
            }
        }
    }
}
