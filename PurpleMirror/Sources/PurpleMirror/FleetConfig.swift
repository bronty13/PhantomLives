import Foundation

/// A machine in the PurpleMirror **fleet** — the shared set of Macs that should all monitor and
/// control each other. The fleet is defined once and placed on every node; each node identifies
/// *itself* by `computerName` and turns the other machines into remote hosts, so every node meshes
/// with every other without per-node manual host entry.
///
/// IMPORTANT: the real `fleet.json` is **local-only** (App Support, never committed) because it
/// carries LAN IPs / usernames / key paths and the repo is public. Only `fleet.example.json`
/// (placeholders) is in git. Distribute the real file peer-to-peer over SSH, not via the repo.
struct FleetMachine: Codable, Equatable {
    var id: String
    var displayName: String
    var computerName: String      // must equal `scutil --get ComputerName` on that Mac (self-id)
    var sshUser: String
    var sshHost: String
    var port: Int
    var identityFile: String?

    func asRemoteHost() -> MonitoredHost {
        var h = MonitoredHost.remote(id: id, displayName: displayName, user: sshUser, host: sshHost,
                                     port: port, identityFile: identityFile)
        h.fromFleet = true
        return h
    }
}

struct FleetConfig: Codable, Equatable {
    var machines: [FleetMachine]
}

enum FleetStore {
    static func fileURL() -> URL {
        HostStore.defaultDirectory().appendingPathComponent("fleet.json")
    }

    /// The fleet machines (empty if there's no fleet.json).
    static func load() -> [FleetMachine] {
        guard let data = try? Data(contentsOf: fileURL()),
              let cfg = try? JSONDecoder().decode(FleetConfig.self, from: data) else { return [] }
        return cfg.machines
    }

    /// This Mac's ComputerName (matches `scutil --get ComputerName`), used to exclude self.
    /// (`Host` here is `Foundation.Host` — our model type is `MonitoredHost`.)
    static func localComputerName() -> String {
        Host.current().localizedName ?? ""
    }

    /// Optional explicit self-identifier: the fleet `id` of THIS node, written to
    /// `~/Library/Application Support/PurpleMirror/node-id` during deploy. Bulletproof self-match
    /// (no dependence on ComputerName encoding). Nil if the file is absent.
    static func localNodeID() -> String? {
        let url = HostStore.defaultDirectory().appendingPathComponent("node-id")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Pure: the fleet machines that are NOT this node, as remote hosts. A machine is "self" if its
    /// `id` matches `localNodeID` (when set) OR its `computerName` matches (case-insensitive). If
    /// neither identifies this Mac, every machine becomes a remote host.
    static func remoteHosts(machines: [FleetMachine], localComputerName: String,
                            localNodeID: String?) -> [MonitoredHost] {
        machines.filter { m in
            let selfByID = (localNodeID.map { !$0.isEmpty && m.id == $0 }) ?? false
            let selfByName = m.computerName.caseInsensitiveCompare(localComputerName) == .orderedSame
            return !(selfByID || selfByName)
        }.map { $0.asRemoteHost() }
    }
}
