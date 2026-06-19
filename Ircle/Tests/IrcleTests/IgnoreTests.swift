import Foundation
import Testing
import IRCKit
@testable import Ircle

/// The ignore list: inbound messages from a matching hostmask are dropped, and
/// the list is managed (case-insensitive dedup) + persisted.
@MainActor
@Suite("Ignore list")
struct IgnoreTests {

    private func session() -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        return IrcleSession(config: cfg, displayName: "Example")
    }

    private func model() -> IrcleModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IrcleModel(settingsStore: SettingsStore(directory: dir, secretStore: InMemorySecretStore()),
                          runLaunchBackup: false)
    }

    private func texts(_ s: IrcleSession, _ chan: String) -> [String] {
        (s.buffers.first { $0.name == chan }?.lines.map(\.text)) ?? []
    }

    @Test func ignoredNickMessagesAreDropped() {
        let s = session()
        s.ignoreMasks = ["spammer"]
        s.ingest(":alice!u@h PRIVMSG #x :hello")
        s.ingest(":spammer!u@h PRIVMSG #x :spam")
        #expect(texts(s, "#x").contains("hello"))
        #expect(!texts(s, "#x").contains("spam"))
    }

    @Test func ignoreByHostMaskDrops() {
        let s = session()
        s.ignoreMasks = ["*!*@bad.host"]
        s.ingest(":x!y@bad.host PRIVMSG #x :nope")
        s.ingest(":good!y@ok.host PRIVMSG #x :yes")
        #expect(texts(s, "#x").contains("yes"))
        #expect(!texts(s, "#x").contains("nope"))
    }

    @Test func noIgnoreListLetsEverythingThrough() {
        let s = session()
        s.ingest(":anyone!u@h PRIVMSG #x :hi")
        #expect(texts(s, "#x").contains("hi"))
    }

    @Test func addRemoveDedupsCaseInsensitively() {
        let m = model()
        m.addIgnore("bob")
        m.addIgnore("BOB")          // dupe
        m.addIgnore("*!*@x.net")
        #expect(m.ignoreMasks == ["bob", "*!*@x.net"])
        m.removeIgnore("BOB")
        #expect(m.ignoreMasks == ["*!*@x.net"])
    }

    @Test func ignoreMasksDefaultEmptyAndRoundTrip() throws {
        #expect(AppSettings().ignoreMasks.isEmpty)
        var s = AppSettings()
        s.ignoreMasks = ["a", "b!*@*"]
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).ignoreMasks == ["a", "b!*@*"])
    }
}
