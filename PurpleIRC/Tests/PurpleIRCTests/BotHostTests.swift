import Foundation
import Testing
@testable import PurpleIRC

/// Scripting-host invariants for `BotHost` (the JavaScriptCore PurpleBot).
/// Covers the integrity check that refuses tampered script source and the
/// per-script store bridge — the parts the audit flagged as the highest-risk
/// scripting logic with no coverage.
@MainActor
@Suite("BotHost scripting")
struct BotHostTests {

    private func tempHost() -> BotHost {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BotHostTests-\(UUID().uuidString)", isDirectory: true)
        return BotHost(supportDir: dir)
    }

    /// A script's source carries a SHA-256 captured at save time; if the
    /// on-disk bytes change underneath us (tamper, partial decrypt), the
    /// loader must refuse to run it.
    @Test func tamperedScriptRejectedByContentHash() throws {
        let host = tempHost()
        let s = host.addScript(name: "greeter", source: "var greeting = 'hi';")
        // Pristine source loads.
        #expect(!host.scriptSource(s).isEmpty)

        // Rewrite the file behind the recorded hash.
        let url = host.scriptsDirectoryURL.appendingPathComponent(s.filename)
        try Data("doEvil();".utf8).write(to: url)

        // Hash mismatch → refused (empty source, logged).
        #expect(host.scriptSource(s).isEmpty)
    }

    /// The store bridge resolves a per-script ephemeral token, so a script
    /// writes to its own store and two scripts never collide. This drives
    /// the real JS wrapper end-to-end (set via `irc.store.set`).
    @Test func eachScriptWritesOnlyItsOwnStore() {
        let host = tempHost()
        let a = host.addScript(name: "a", source: "irc.store.set('k', 'A');")
        let b = host.addScript(name: "b", source: "irc.store.set('k', 'B');")

        #expect(host.scriptStore.get(scriptID: a.id, key: "k") as? String == "A")
        #expect(host.scriptStore.get(scriptID: b.id, key: "k") as? String == "B")
    }

    /// A script passing a raw script-UUID to the underscore store bridge
    /// must NOT reach another script's store — the bridge only trusts the
    /// ephemeral token it minted for the *calling* script. Here script B
    /// tries to read A's store by guessing A's UUID; it must come back empty.
    @Test func scriptCannotReachAnotherStoreByUUID() {
        let host = tempHost()
        let a = host.addScript(name: "a", source: "irc.store.set('secret', 'A-private');")
        // B forges a call with A's real UUID and records what it got back
        // into its own store so we can inspect it from Swift.
        let bSource = """
        var stolen = globalThis.irc._storeGet('\(a.id.uuidString)', 'secret');
        irc.store.set('stolen', stolen === undefined || stolen === null ? 'NONE' : String(stolen));
        """
        let b = host.addScript(name: "b", source: bSource)

        #expect(host.scriptStore.get(scriptID: a.id, key: "secret") as? String == "A-private")
        // The forged read returned nothing — isolation held.
        #expect(host.scriptStore.get(scriptID: b.id, key: "stolen") as? String == "NONE")
    }
}
