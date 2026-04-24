import Foundation
import Testing
@testable import PurpleIRC

@Suite("Seen store")
@MainActor
struct SeenStoreTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purpleirc-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func recordThenLookupRoundtrip() {
        let store = SeenStore(supportDirectoryURL: tempDir())
        let net = UUID()
        store.record(networkID: net, networkSlug: "libera",
                     nick: "alice", kind: "msg",
                     channel: "#swift", detail: "hello world")
        let hit = store.lookup(networkID: net, networkSlug: "libera", nick: "alice")
        #expect(hit != nil)
        #expect(hit?.nick == "alice")
        #expect(hit?.kind == "msg")
        #expect(hit?.channel == "#swift")
        #expect(hit?.detail == "hello world")
    }

    @Test func lookupIsCaseInsensitive() {
        let store = SeenStore(supportDirectoryURL: tempDir())
        let net = UUID()
        store.record(networkID: net, networkSlug: "libera",
                     nick: "AliCe", kind: "msg", channel: "#c", detail: "hi")
        #expect(store.lookup(networkID: net, networkSlug: "libera", nick: "alice") != nil)
        #expect(store.lookup(networkID: net, networkSlug: "libera", nick: "ALICE") != nil)
    }

    @Test func unknownNickReturnsNil() {
        let store = SeenStore(supportDirectoryURL: tempDir())
        let net = UUID()
        #expect(store.lookup(networkID: net, networkSlug: "libera", nick: "nobody") == nil)
    }

    @Test func nickChangeForwardsOldNickToNew() {
        let store = SeenStore(supportDirectoryURL: tempDir())
        let net = UUID()
        store.record(networkID: net, networkSlug: "libera",
                     nick: "alice", kind: "msg",
                     channel: "#swift", detail: "hello")
        store.recordNickChange(networkID: net, networkSlug: "libera",
                               oldNick: "alice", newNick: "alice2")

        let oldHit = store.lookup(networkID: net, networkSlug: "libera", nick: "alice")
        #expect(oldHit?.kind == "nick")
        #expect(oldHit?.renamedTo == "alice2")

        let newHit = store.lookup(networkID: net, networkSlug: "libera", nick: "alice2")
        #expect(newHit != nil)
        #expect(newHit?.detail == "was alice")
    }

    @Test func persistsAcrossInstances() {
        let dir = tempDir()
        let net = UUID()
        do {
            let store = SeenStore(supportDirectoryURL: dir)
            store.record(networkID: net, networkSlug: "libera",
                         nick: "bob", kind: "join",
                         channel: "#swift", detail: nil)
            store.flushNow(networkID: net, slug: "libera")
        }
        // Fresh store, same directory — should re-read JSON file.
        let store2 = SeenStore(supportDirectoryURL: dir)
        let hit = store2.lookup(networkID: net, networkSlug: "libera", nick: "bob")
        #expect(hit != nil)
        #expect(hit?.kind == "join")
    }

    @Test func clearErasesPersistedFile() {
        let dir = tempDir()
        let net = UUID()
        let store = SeenStore(supportDirectoryURL: dir)
        store.record(networkID: net, networkSlug: "libera",
                     nick: "alice", kind: "msg",
                     channel: "#x", detail: "hi")
        store.flushNow(networkID: net, slug: "libera")
        store.clear(networkID: net, networkSlug: "libera")
        #expect(store.lookup(networkID: net, networkSlug: "libera", nick: "alice") == nil)

        // New instance over the same directory should also see it as empty.
        let store2 = SeenStore(supportDirectoryURL: dir)
        #expect(store2.lookup(networkID: net, networkSlug: "libera", nick: "alice") == nil)
    }

    @Test func slugNormalization() {
        #expect(SeenStore.slug(for: "Libera Chat") == "libera-chat")
        #expect(SeenStore.slug(for: "irc.undernet.org") == "irc-undernet-org")
        #expect(SeenStore.slug(for: "") == "network")
    }

    @Test func describeProducesReadableText() {
        var entry = SeenEntry(nick: "alice",
                              timestamp: Date().addingTimeInterval(-3600),
                              kind: "msg",
                              channel: "#swift",
                              detail: "hi all")
        let line = BotEngine.describe(entry, queriedNick: "alice")
        #expect(line.contains("alice"))
        #expect(line.contains("#swift"))
        #expect(line.contains("hi all"))

        entry.kind = "nick"
        entry.renamedTo = "alice2"
        entry.channel = nil
        let rename = BotEngine.describe(entry, queriedNick: "alice")
        #expect(rename.contains("changed nick"))
        #expect(rename.contains("alice2"))
    }
}
