import Foundation
import Testing
@testable import Ircle

@Suite("Default servers")
struct DefaultServersTests {

    @Test func presetsAreSaneAndUnique() {
        let servers = ServerProfile.defaultServers()
        #expect(servers.count >= 12)
        // Names are unique (the merge dedups by name).
        let names = servers.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
        // Presets don't force-join a channel.
        #expect(servers.allSatisfy { $0.autoJoin.isEmpty })
        // TLS defaults are correct: Libera secure, Undernet plaintext (the
        // exact case that bit the maintainer).
        let libera = servers.first { $0.name == "Libera Chat" }
        #expect(libera?.useTLS == true && libera?.port == 6697)
        let undernet = servers.first { $0.name == "Undernet" }
        #expect(undernet?.useTLS == false && undernet?.port == 6667)
    }

    /// Mirrors ConnectionSettingsView.addMissingDefaults — add only by-name
    /// missing presets, never duplicating or touching the user's own servers.
    @Test func mergeAddsOnlyMissingByName() {
        var servers = [
            ServerProfile(name: "My Server", host: "irc.example.org"),
            ServerProfile(name: "Libera Chat", host: "irc.libera.chat"),
        ]
        let existing = Set(servers.map { $0.name.lowercased() })
        let missing = ServerProfile.defaultServers().filter {
            !existing.contains($0.name.lowercased())
        }
        servers.append(contentsOf: missing)

        let names = servers.map { $0.name.lowercased() }
        #expect(names.filter { $0 == "libera chat" }.count == 1)  // not duplicated
        #expect(names.contains("undernet"))                       // missing one added
        #expect(names.contains("my server"))                      // custom preserved
    }
}

@MainActor
@Suite("Fresh-install seeding")
struct FreshInstallSeedingTests {
    @Test func freshStoreSeedsTheDefaultNetworks() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-seed-\(UUID().uuidString)", isDirectory: true)
        let store = SettingsStore(directory: dir, secretStore: InMemorySecretStore())
        #expect(store.settings.servers.count == ServerProfile.defaultServers().count)
        #expect(store.settings.servers.contains { $0.name == "Libera Chat" })
        // And it persisted, so a reload sees the same list (no re-seed wipe).
        let reloaded = SettingsStore(directory: dir)
        #expect(reloaded.settings.servers.count == store.settings.servers.count)
    }
}
