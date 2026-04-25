import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

/// Cover `SessionHistoryStore` — per-network archive of recent ChatLines
/// that drives the "previous session" replay on launch. Tests cover the
/// happy roundtrip, encryption, the safeWrite refuse-to-clobber guard,
/// and the empty-buffer trim.
@MainActor
@Suite("SessionHistoryStore")
struct SessionHistoryStoreTests {

    private func tempSupportDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessHistTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    private func sampleHistory() -> SessionHistoryStore.NetworkHistory {
        var nh = SessionHistoryStore.NetworkHistory()
        nh.buffers["#swift"] = [
            ChatLine(timestamp: Date(timeIntervalSince1970: 1),
                     kind: .privmsg(nick: "alice", isSelf: false),
                     text: "morning"),
            ChatLine(timestamp: Date(timeIntervalSince1970: 2),
                     kind: .privmsg(nick: "bob", isSelf: false),
                     text: "hey alice")
        ]
        nh.buffers["alice"] = [
            ChatLine(timestamp: Date(timeIntervalSince1970: 3),
                     kind: .privmsg(nick: "alice", isSelf: false),
                     text: "private hi")
        ]
        return nh
    }

    @Test func emptyLoadOnFreshStore() {
        let store = SessionHistoryStore(supportDirectoryURL: tempSupportDir())
        let h = store.load(networkSlug: "anything")
        #expect(h.buffers.isEmpty)
    }

    @Test func saveLoadPlaintextRoundtrip() {
        let dir = tempSupportDir()
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        store.save(networkSlug: "undernet", history: sampleHistory())

        let loaded = SessionHistoryStore(supportDirectoryURL: dir)
        let read = loaded.load(networkSlug: "undernet")
        #expect(read.buffers.count == 2)
        #expect(read.buffers["#swift"]?.count == 2)
        #expect(read.buffers["alice"]?.count == 1)
        #expect(read.buffers["alice"]?.first?.text == "private hi")
    }

    @Test func saveLoadEncryptedRoundtrip() {
        let dir = tempSupportDir()
        let key = SymmetricKey(size: .bits256)
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        store.setEncryptionKey(key)
        store.save(networkSlug: "undernet", history: sampleHistory())

        // Reopen with same key → unwraps cleanly.
        let reopened = SessionHistoryStore(supportDirectoryURL: dir)
        reopened.setEncryptionKey(key)
        let read = reopened.load(networkSlug: "undernet")
        #expect(read.buffers["#swift"]?.count == 2)
        #expect(read.buffers["alice"]?.first?.text == "private hi")
    }

    @Test func encryptedFileWithoutKeyDoesNotLeak() {
        let dir = tempSupportDir()
        let key = SymmetricKey(size: .bits256)
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        store.setEncryptionKey(key)
        store.save(networkSlug: "undernet", history: sampleHistory())

        // No key now — load returns empty default rather than the
        // plaintext lines (which would be a serious confidentiality bug).
        let reopened = SessionHistoryStore(supportDirectoryURL: dir)
        let read = reopened.load(networkSlug: "undernet")
        #expect(read.buffers.isEmpty)
    }

    @Test func saveDropsEmptyBuffers() {
        let dir = tempSupportDir()
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        var nh = SessionHistoryStore.NetworkHistory()
        nh.buffers["#kept"] = [
            ChatLine(timestamp: Date(), kind: .info, text: "ok")
        ]
        nh.buffers["#dropped"] = []                // empty buffer
        store.save(networkSlug: "undernet", history: nh)

        let read = store.load(networkSlug: "undernet")
        #expect(read.buffers.keys.sorted() == ["#kept"])
    }

    @Test func saveWithoutKeyOverEncryptedFileRefusesToClobber() {
        // safeWrite invariant: if the on-disk file is encrypted but no key
        // is in hand, leave it alone. Without this guard, an early-init
        // save would clobber an encrypted history file with plaintext.
        let dir = tempSupportDir()
        let key = SymmetricKey(size: .bits256)
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        store.setEncryptionKey(key)
        store.save(networkSlug: "undernet", history: sampleHistory())

        // Drop the key, save fresh (different) data — should be a no-op.
        store.setEncryptionKey(nil)
        var different = SessionHistoryStore.NetworkHistory()
        different.buffers["#chan"] = [
            ChatLine(timestamp: Date(), kind: .info, text: "different")
        ]
        store.save(networkSlug: "undernet", history: different)

        // The encrypted file is still there. Load with the key recovers
        // the ORIGINAL data, not the would-be plaintext clobber.
        store.setEncryptionKey(key)
        let read = store.load(networkSlug: "undernet")
        #expect(read.buffers["#swift"]?.count == 2)        // original, not clobbered
        #expect(read.buffers["#chan"] == nil)
    }

    @Test func networksAreKeyedSeparately() {
        let dir = tempSupportDir()
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        var und = SessionHistoryStore.NetworkHistory()
        und.buffers["alice"] = [ChatLine(timestamp: Date(),
                                         kind: .info, text: "und")]
        var dal = SessionHistoryStore.NetworkHistory()
        dal.buffers["alice"] = [ChatLine(timestamp: Date(),
                                         kind: .info, text: "dal")]
        store.save(networkSlug: "undernet", history: und)
        store.save(networkSlug: "dalnet", history: dal)

        #expect(store.load(networkSlug: "undernet").buffers["alice"]?.first?.text == "und")
        #expect(store.load(networkSlug: "dalnet").buffers["alice"]?.first?.text == "dal")
    }

    @Test func clearRemovesNetworkFile() {
        let dir = tempSupportDir()
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        store.save(networkSlug: "undernet", history: sampleHistory())
        #expect(!store.load(networkSlug: "undernet").buffers.isEmpty)

        store.clear(networkSlug: "undernet")
        #expect(store.load(networkSlug: "undernet").buffers.isEmpty)
    }

    @Test func loadIgnoresGarbageOnDisk() throws {
        // A corrupt history file shouldn't block the rest of the app —
        // the loader must fall through to an empty default rather than
        // throwing.
        let dir = tempSupportDir()
        let historyDir = dir.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(
            at: historyDir, withIntermediateDirectories: true)
        try Data("not actually json".utf8).write(
            to: historyDir.appendingPathComponent("corrupt.json"))
        let store = SessionHistoryStore(supportDirectoryURL: dir)
        let read = store.load(networkSlug: "corrupt")
        #expect(read.buffers.isEmpty)
    }
}
