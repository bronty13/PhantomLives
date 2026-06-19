import Foundation
import Testing
@testable import Ircle

/// Passwords must live in the SecretStore (Keychain in production), never in
/// settings.json — and any legacy plaintext from older builds must migrate out.
@MainActor
@Suite("Credential storage")
struct CredentialStorageTests {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-cred-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var jsonURL: (URL) -> URL { { $0.appendingPathComponent("settings.json") } }

    @Test func passwordsGoToSecretStoreNotJSON() throws {
        let dir = tempDir()
        let secrets = InMemorySecretStore()
        let store = SettingsStore(directory: dir, secretStore: secrets)

        var s = store.settings
        s.servers = [ServerProfile(name: "Sec", host: "irc.example.org")]
        s.servers[0].serverPassword = "hunter2"
        s.servers[0].saslPassword = "swordfish"
        store.settings = s                       // didSet → save()

        let id = store.settings.servers[0].id.uuidString
        // Secrets landed in the secret store …
        #expect(secrets.get("\(id).serverPassword") == "hunter2")
        #expect(secrets.get("\(id).saslPassword") == "swordfish")
        // … and are NOT present anywhere in the on-disk JSON.
        let json = try String(contentsOf: jsonURL(dir), encoding: .utf8)
        #expect(!json.contains("hunter2"))
        #expect(!json.contains("swordfish"))
    }

    @Test func passwordsReloadFromSecretStore() {
        let dir = tempDir()
        let secrets = InMemorySecretStore()
        let id: String
        do {
            let store = SettingsStore(directory: dir, secretStore: secrets)
            var s = store.settings
            s.servers = [ServerProfile(name: "Sec", host: "irc.example.org")]
            s.servers[0].serverPassword = "topsecret"
            store.settings = s
            id = store.settings.servers[0].id.uuidString
        }
        // A fresh store over the same dir + same secret store rehydrates the pw.
        let reloaded = SettingsStore(directory: dir, secretStore: secrets)
        let server = reloaded.settings.servers.first { $0.id.uuidString == id }
        #expect(server?.serverPassword == "topsecret")
    }

    @Test func legacyPlaintextPasswordMigratesToSecretStore() throws {
        let dir = tempDir()
        // Simulate an OLD settings.json that still has a plaintext password.
        let pid = UUID()
        let legacy = """
        {"servers":[{"id":"\(pid.uuidString)","name":"Old","host":"irc.example.org",\
        "port":6697,"useTLS":true,"nick":"me","user":"me","realName":"Me",\
        "serverPassword":"leaked","saslMechanism":"NONE","saslAccount":"",\
        "saslPassword":"","autoJoin":[]}],"appearance":"platinum",\
        "showTimestamps":true,"fontSize":12,"autoBackupEnabled":true,\
        "backupPath":"","backupRetentionDays":14,"lastBackupAt":""}
        """
        try legacy.data(using: .utf8)!.write(to: jsonURL(dir))

        let secrets = InMemorySecretStore()
        let store = SettingsStore(directory: dir, secretStore: secrets)

        // Loaded into memory…
        #expect(store.settings.servers.first?.serverPassword == "leaked")
        // …moved into the secret store…
        #expect(secrets.get("\(pid.uuidString).serverPassword") == "leaked")
        // …and scrubbed from the rewritten JSON.
        let json = try String(contentsOf: jsonURL(dir), encoding: .utf8)
        #expect(!json.contains("leaked"))
    }
}
