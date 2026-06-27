import Foundation

/// A machine PurpleMirror monitors: the local Mac, or a remote one reached over SSH.
///
/// Remote hosts let a single PurpleMirror (e.g. on Vortex or MB14) see and control the
/// launchd jobs running on the dedicated archive "runner". The local host is always present
/// and behaves exactly as PurpleMirror always has — remote support is purely additive.
///
/// Named `MonitoredHost` (not `Host`) to avoid colliding with `Foundation.Host` (the old `NSHost`).
struct MonitoredHost: Codable, Equatable, Identifiable {
    var id: String                 // stable id ("local", or a user-chosen slug like "runner")
    var displayName: String
    var isLocal: Bool
    var sshUser: String            // "" for local
    var sshHost: String            // hostname / IP, "" for local
    var port: Int
    var identityFile: String?      // e.g. "~/.ssh/purplemirror_runner" (optional → ssh default keys)
    var connectTimeout: Int        // seconds; keeps an unreachable/asleep host from stalling refresh

    /// True when this host came from the shared fleet config (vs. a manual Settings add). Transient
    /// — not persisted to hosts.json (excluded from CodingKeys) — used to mark fleet hosts read-only.
    var fromFleet: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, displayName, isLocal, sshUser, sshHost, port, identityFile, connectTimeout
    }

    /// The always-present local machine. Existing installs (no hosts.json) run with just this.
    static let local = MonitoredHost(id: "local", displayName: "This Mac", isLocal: true,
                                     sshUser: "", sshHost: "", port: 22, identityFile: nil, connectTimeout: 6)

    /// Convenience constructor for a remote SSH host.
    static func remote(id: String, displayName: String, user: String, host: String,
                       port: Int = 22, identityFile: String? = nil, connectTimeout: Int = 6) -> MonitoredHost {
        MonitoredHost(id: id, displayName: displayName, isLocal: false, sshUser: user, sshHost: host,
                      port: port, identityFile: identityFile, connectTimeout: connectTimeout)
    }

    /// `user@host` (or just `host` if no user) for the ssh destination.
    var sshTarget: String { sshUser.isEmpty ? sshHost : "\(sshUser)@\(sshHost)" }
}
