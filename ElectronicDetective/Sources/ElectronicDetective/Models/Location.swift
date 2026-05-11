import Foundation

/// The six city locations. Each lives in one of three north–south zones and
/// one of two east–west sides — the printed notepad's "Who Was Where?" grid
/// arranges them on that axis.
enum Location: String, CaseIterable, Codable, Hashable, Sendable {
    case artShow       = "Art Show"
    case boxAtTheater  = "Box at Theater"
    case cardParty     = "Card Party"
    case docks         = "Docks"
    case embassy       = "Embassy"
    case factory       = "Factory"

    enum Zone: String, Codable, CaseIterable { case uptown, midtown, downtown }
    enum Side: String, Codable, CaseIterable { case west, east }

    var zone: Zone {
        switch self {
        case .artShow, .boxAtTheater: return .uptown
        case .cardParty, .docks:      return .midtown
        case .embassy, .factory:      return .downtown
        }
    }

    var side: Side {
        switch self {
        case .artShow, .cardParty, .embassy: return .west
        case .boxAtTheater, .docks, .factory: return .east
        }
    }

    var displayName: String { rawValue }

    /// Stable, short single-letter code used for the LED readout.
    var code: String {
        switch self {
        case .artShow:      return "ART"
        case .boxAtTheater: return "BOX"
        case .cardParty:    return "CRD"
        case .docks:        return "DOC"
        case .embassy:      return "EMB"
        case .factory:      return "FAC"
        }
    }
}
