import Foundation
import Testing
import CryptoKit
@testable import PurpleIRC

@MainActor
@Suite("ScriptStore")
struct ScriptStoreTests {

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PurpleIRCScriptStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func getReturnsNilForUnknownKey() {
        let store = ScriptStore(directory: makeTempDir())
        #expect(store.get(scriptID: UUID(), key: "missing") == nil)
    }

    @Test func setThenGetRoundTrips() {
        let store = ScriptStore(directory: makeTempDir())
        let id = UUID()
        store.set(scriptID: id, key: "count", value: 7)
        let v = store.get(scriptID: id, key: "count") as? Int
        #expect(v == 7)
    }

    @Test func deleteRemovesTheKey() {
        let store = ScriptStore(directory: makeTempDir())
        let id = UUID()
        store.set(scriptID: id, key: "x", value: "hello")
        #expect(store.get(scriptID: id, key: "x") as? String == "hello")
        store.delete(scriptID: id, key: "x")
        #expect(store.get(scriptID: id, key: "x") == nil)
    }

    @Test func keysReturnsLiveSnapshot() {
        let store = ScriptStore(directory: makeTempDir())
        let id = UUID()
        store.set(scriptID: id, key: "a", value: 1)
        store.set(scriptID: id, key: "b", value: 2)
        #expect(Set(store.keys(scriptID: id)) == Set(["a", "b"]))
        store.delete(scriptID: id, key: "a")
        #expect(Set(store.keys(scriptID: id)) == Set(["b"]))
    }

    @Test func scriptsAreIsolated() {
        // Per HANDOFF: each script gets its own JSON file. Two scripts
        // hitting the same key MUST get back what THEY wrote, not what
        // the other wrote. This is the whole point of the IIFE wrapper.
        let store = ScriptStore(directory: makeTempDir())
        let a = UUID()
        let b = UUID()
        store.set(scriptID: a, key: "count", value: 10)
        store.set(scriptID: b, key: "count", value: 99)
        #expect(store.get(scriptID: a, key: "count") as? Int == 10)
        #expect(store.get(scriptID: b, key: "count") as? Int == 99)
    }

    @Test func persistsAcrossInstancesPlaintext() {
        // Plaintext path (no DEK): a fresh ScriptStore at the same
        // directory must read back the prior session's writes.
        let dir = makeTempDir()
        let id = UUID()
        do {
            let store = ScriptStore(directory: dir)
            store.set(scriptID: id, key: "msg", value: "persisted")
        }
        let store2 = ScriptStore(directory: dir)
        #expect(store2.get(scriptID: id, key: "msg") as? String == "persisted")
    }

    @Test func persistsAcrossInstancesEncrypted() {
        // Encrypted path: write under a DEK, then read back from a
        // second instance with the same DEK and verify the round trip.
        let dir = makeTempDir()
        let key = SymmetricKey(size: .bits256)
        let id = UUID()
        do {
            let store = ScriptStore(directory: dir)
            store.setEncryptionKey(key)
            store.set(scriptID: id, key: "secret", value: "shhh")
        }
        let store2 = ScriptStore(directory: dir)
        store2.setEncryptionKey(key)
        #expect(store2.get(scriptID: id, key: "secret") as? String == "shhh")
    }

    @Test func purgeWipesBothCacheAndFile() {
        let dir = makeTempDir()
        let store = ScriptStore(directory: dir)
        let id = UUID()
        store.set(scriptID: id, key: "x", value: "y")

        store.purge(scriptID: id)
        #expect(store.get(scriptID: id, key: "x") == nil)

        // File must be gone, not just emptied.
        let file = dir.appendingPathComponent("\(id.uuidString).store.json")
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    @Test func setToNilSemanticallyHidesTheKey() {
        // JS `irc.store.set('x', null)` lands here as a nil/NSNull
        // value. The contract: a subsequent `get` returns nil so the
        // user can use null as a "delete me" sentinel without
        // remembering to call `delete`. The key technically stays in
        // the dictionary (so `keys()` still reports it), which is
        // useful for debugging persisted state without forgetting
        // entries existed.
        let store = ScriptStore(directory: makeTempDir())
        let id = UUID()
        store.set(scriptID: id, key: "x", value: 5)
        store.set(scriptID: id, key: "x", value: nil)
        #expect(store.get(scriptID: id, key: "x") == nil)
    }
}
