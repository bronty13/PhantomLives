import Foundation

/// Persists the set of monitored hosts as JSON in Application Support. Seeded with the local
/// host so a fresh install (no `hosts.json`) behaves exactly as PurpleMirror always has —
/// a single local machine. Remote hosts are added by the user in Settings ▸ Hosts.
enum HostStore {

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support"))
        return base.appendingPathComponent("PurpleMirror", isDirectory: true)
    }

    static func fileURL() -> URL { defaultDirectory().appendingPathComponent("hosts.json") }

    /// Load the host list (always local-first, exactly one local). Missing/empty/corrupt → `[.local]`.
    static func load() -> [MonitoredHost] {
        guard let data = try? Data(contentsOf: fileURL()),
              let hosts = try? JSONDecoder().decode([MonitoredHost].self, from: data),
              !hosts.isEmpty else {
            return [.local]
        }
        return normalized(hosts)
    }

    static func save(_ hosts: [MonitoredHost]) {
        try? FileManager.default.createDirectory(at: defaultDirectory(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(normalized(hosts)) {
            try? data.write(to: fileURL(), options: .atomic)
        }
    }

    /// Guarantee exactly one local host, placed first, with remotes following in their given order.
    /// (Drops any persisted "local" duplicates and always uses the canonical `Host.local`.)
    static func normalized(_ hosts: [MonitoredHost]) -> [MonitoredHost] {
        let remotes = hosts.filter { !$0.isLocal }
        return [.local] + remotes
    }
}
