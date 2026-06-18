import Foundation

/// SASL authentication mechanism selected for a connection. Lives in IRCKit
/// (rather than an app's settings layer) because `IRCConnectionConfig` and the
/// `SASLNegotiator` both depend on it — it is part of the wire contract, not a
/// UI preference. Apps persist it as part of their own server/identity models.
public enum SASLMechanism: String, Codable, CaseIterable, Identifiable {
    case none = "NONE"
    case plain = "PLAIN"
    case external = "EXTERNAL"
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .plain: return "PLAIN (account + password)"
        case .external: return "EXTERNAL (client cert)"
        }
    }
}
