import Foundation
import Testing
import IRCKit
@testable import Ircle

/// The Notify (friends) list: a persisted global nick list, ISON polling to
/// learn who's online, and 303 (RPL_ISON) parsing into per-connection presence.
@MainActor
@Suite("Notify / friends list")
struct NotifyListTests {

    private func makeSession() -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        return IrcleSession(config: cfg, displayName: "Example")
    }

    private func tempStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(directory: dir, secretStore: InMemorySecretStore())
    }

    // MARK: - ISON command building

    @Test func isonCommandNilWhenEmpty() {
        let s = makeSession()
        #expect(s.isonCommand() == nil)
    }

    @Test func isonCommandListsFriends() {
        let s = makeSession()
        s.notifyNicks = ["alice", "bob", "  "]   // blank entries are dropped
        #expect(s.isonCommand() == "ISON alice bob")
    }

    // MARK: - 303 parsing → presence

    @Test func parses303IntoOnlineFriends() {
        let s = makeSession()
        s.ingest(":server 303 me :alice Carol")
        #expect(s.isFriendOnline("alice"))
        #expect(s.isFriendOnline("CAROL"))   // case-insensitive
        #expect(!s.isFriendOnline("bob"))
    }

    @Test func empty303ClearsPresence() {
        let s = makeSession()
        s.ingest(":server 303 me :alice")
        #expect(s.isFriendOnline("alice"))
        s.ingest(":server 303 me :")          // nobody online now
        #expect(!s.isFriendOnline("alice"))
    }

    // MARK: - Persistence

    @Test func notifyNicksDefaultsEmptyAndRoundTrips() throws {
        #expect(AppSettings().notifyNicks.isEmpty)
        var s = AppSettings()
        s.notifyNicks = ["alice", "bob"]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(back.notifyNicks == ["alice", "bob"])
    }

    @Test func legacyDocumentWithoutNotifyDecodesEmpty() throws {
        let legacy = #"{"appearance":"platinum","fontSize":12}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(s.notifyNicks.isEmpty)
    }

    // MARK: - Model management

    @Test func addDedupesCaseInsensitivelyAndRemoveWorks() {
        let model = IrcleModel(settingsStore: tempStore(), runLaunchBackup: false)
        model.addNotify("Alice")
        model.addNotify("alice")            // dupe (case-folded) — ignored
        model.addNotify("bob")
        #expect(model.notifyNicks == ["Alice", "bob"])
        model.removeNotify("ALICE")         // case-insensitive removal
        #expect(model.notifyNicks == ["bob"])
    }

    @Test func newSessionInheritsNotifyList() {
        let model = IrcleModel(settingsStore: tempStore(), runLaunchBackup: false)
        model.addNotify("alice")
        guard let profile = model.settingsStore.settings.servers.first else {
            Issue.record("expected a seeded server profile"); return
        }
        let s = model.openSession(for: profile, autoConnect: false)
        #expect(s.notifyNicks == ["alice"])
    }
}
