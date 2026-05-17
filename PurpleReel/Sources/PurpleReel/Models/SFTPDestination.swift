import Foundation

/// Connection config for an SFTP delivery target. Password auth is
/// intentionally **not** in the MVP: we shell out to system `sftp`,
/// which won't read a password from stdin without `sshpass` (a
/// non-default tool). Users wire up key auth via `~/.ssh/config` or
/// pass an explicit `identityFile` path here; that covers ~all
/// production SFTP servers used for media delivery.
struct SFTPDestination: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var nickname: String = ""
    var host: String = ""
    var port: Int = 22
    var user: String = ""
    var remotePath: String = ""
    var identityFile: String = ""    // optional, absolute or "~/..." path
    var acceptNewHostKeys: Bool = true

    /// Display label for the picker.
    var displayName: String {
        if !nickname.isEmpty { return nickname }
        if !user.isEmpty && !host.isEmpty { return "\(user)@\(host)" }
        return host.isEmpty ? "New destination" : host
    }

    var isValid: Bool {
        !host.isEmpty && !user.isEmpty && !remotePath.isEmpty
    }
}

/// Persistence store for SFTP destinations. Stored as JSON in
/// UserDefaults — small data, infrequent writes, no need for the DB.
enum SFTPDestinationStore {
    private static let key = "sftpDestinations"

    static func load() -> [SFTPDestination] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SFTPDestination].self, from: data)) ?? []
    }

    static func save(_ destinations: [SFTPDestination]) {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
