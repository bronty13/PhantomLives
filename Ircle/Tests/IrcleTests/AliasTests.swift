import Foundation
import Testing
import IRCKit
@testable import Ircle

@MainActor
@Suite("Command aliases")
struct AliasTests {

    // MARK: - Expander (pure)

    @Test func positionalAndRest() {
        #expect(AliasExpander.expand("/join $1", args: ["#x"]) == "/join #x")
        #expect(AliasExpander.expand("/msg $1 $2-", args: ["bob", "hi", "there"]) == "/msg bob hi there")
        #expect(AliasExpander.expand("/me $*", args: ["waves", "hello"]) == "/me waves hello")
    }

    @Test func noPlaceholderAppendsArgs() {
        #expect(AliasExpander.expand("/join", args: ["#x"]) == "/join #x")
        #expect(AliasExpander.expand("/away", args: []) == "/away")
    }

    @Test func missingArgYieldsEmpty() {
        #expect(AliasExpander.expand("/op $1", args: []) == "/op ")
        #expect(AliasExpander.expand("a$2b", args: ["one"]) == "ab")
    }

    // MARK: - Management + persistence

    private func model() -> IrcleModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IrcleModel(settingsStore: SettingsStore(directory: dir, secretStore: InMemorySecretStore()),
                          runLaunchBackup: false)
    }

    @Test func setAndRemoveLowercases() {
        let m = model()
        m.setAlias("J", "/join")
        #expect(m.settingsStore.settings.aliases["j"] == "/join")
        m.removeAlias("J")
        #expect(m.settingsStore.settings.aliases["j"] == nil)
    }

    @Test func aliasesRoundTrip() throws {
        var s = AppSettings()
        #expect(s.aliases.isEmpty)
        s.aliases = ["j": "/join", "w": "/me waves"]
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).aliases == s.aliases)
    }

    // MARK: - End-to-end: alias → command → local echo

    @Test func aliasExpandsAndRunsTheCommand() {
        let m = model()
        guard let profile = m.settingsStore.settings.servers.first else {
            Issue.record("no seeded profile"); return
        }
        let session = m.openSession(for: profile, autoConnect: false)
        m.setAlias("hi", "/me says hi to $1")
        let q = session.ensureQuery("bob")
        m.submitInput("/hi bob", in: q)
        let action = q.lines.first { $0.kind == .action }
        #expect(action?.text == "says hi to bob")
    }
}
