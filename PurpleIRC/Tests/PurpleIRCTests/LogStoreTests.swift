import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

/// Coverage for `LogStore`: append/read roundtrip, encryption, the
/// persistent index that the chat-log viewer depends on, and the
/// orphan-by-slug recovery path. LogStore is an actor; we bridge to
/// sync test bodies via `runAsync` because the swift-testing macro
/// hits a "@section" compile-time limit when too many `@Test async`
/// records are emitted from a single file.
@Suite("LogStore")
struct LogStoreTests {

    // MARK: - Helpers

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogStoreTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    /// Run an async closure to completion synchronously. The semaphore
    /// keeps test bodies non-async, sidestepping the macro limit. Safe
    /// here because nothing in the tests touches the main run loop.
    private func runAsync<T: Sendable>(_ block: @escaping @Sendable () async -> T) -> T {
        let sem = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task.detached {
            let r = await block()
            box.set(r)
            sem.signal()
        }
        sem.wait()
        return box.get()
    }

    /// Wraps a single value across the actor / continuation boundary so
    /// the captured semaphore signal hands it back to the calling thread.
    private final class ResultBox<T: Sendable>: @unchecked Sendable {
        private var value: T?
        func set(_ v: T) { value = v }
        func get() -> T { value! }
    }

    /// Mirror of LogStore.slug(_:) — lowercase, then first 8 bytes of
    /// SHA-256 as hex. Defined inline so the slug-by-content tests stay
    /// buildable while the implementation is private. If the algorithm
    /// ever changes, the slug-key tests fail loudly and we adjust.
    private func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.lowercased().utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Plaintext path

    @Test func appendThenReadPlaintext() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        runAsync { await store.append(network: "Undernet", buffer: "#swift", line: "<alice> hi") }
        runAsync { await store.append(network: "Undernet", buffer: "#swift", line: "<bob> hello") }
        let text = runAsync { await store.read(network: "Undernet", buffer: "#swift") }
        #expect(text != nil)
        #expect(text?.contains("hi") == true)
        #expect(text?.contains("hello") == true)
    }

    @Test func readReturnsNilWhenNoFile() {
        let store = LogStore(baseURL: tempDir())
        let text = runAsync { await store.read(network: "absent", buffer: "absent") }
        #expect(text == nil)
    }

    /// purge() must only delete log-shaped files — a stale `index.json`
    /// older than the cutoff must survive, or every log is orphaned.
    @Test func purgeKeepsIndexAndRemovesOldLogs() throws {
        let dir = tempDir()
        let fm = FileManager.default
        let netDir = dir.appendingPathComponent("net", isDirectory: true)
        try fm.createDirectory(at: netDir, withIntermediateDirectories: true)
        let indexURL = dir.appendingPathComponent("index.json")
        let logURL = netDir.appendingPathComponent("buffer.log")
        try Data("{}".utf8).write(to: indexURL)
        try Data("old line\n".utf8).write(to: logURL)
        let old = Date().addingTimeInterval(-100 * 86_400)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: indexURL.path)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: logURL.path)

        let store = LogStore(baseURL: dir)
        let removed = runAsync { await store.purge(olderThanDays: 30) }
        #expect(removed == 1)                          // only the .log
        #expect(fm.fileExists(atPath: indexURL.path))  // index survived
        #expect(!fm.fileExists(atPath: logURL.path))   // log purged
    }

    @Test func readBySlugMatchesReadByName() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        runAsync { await store.append(network: "FooNet", buffer: "#bar", line: "<alice> testing") }
        let byName = runAsync { await store.read(network: "FooNet", buffer: "#bar") }
        let netSlug = sha256Hex("FooNet")
        let bufSlug = sha256Hex("#bar")
        let bySlug = runAsync { await store.readBySlug(networkSlug: netSlug, bufferSlug: bufSlug) }
        #expect(byName != nil)
        #expect(byName == bySlug)
    }

    // MARK: - Encrypted path

    @Test func encryptedRoundtrip() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        let key = SymmetricKey(size: .bits256)
        runAsync { await store.setEncryptionKey(key) }
        runAsync { await store.append(network: "FooNet", buffer: "#bar", line: "<alice> secret message") }
        let plain = runAsync { await store.read(network: "FooNet", buffer: "#bar") }
        #expect(plain != nil)
        #expect(plain?.contains("secret message") == true)
    }

    @Test func encryptedFileHasMagicHeader() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        let key = SymmetricKey(size: .bits256)
        runAsync { await store.setEncryptionKey(key) }
        runAsync { await store.append(network: "n", buffer: "b", line: "x") }
        let url = dir.appendingPathComponent(sha256Hex("n"), isDirectory: true)
            .appendingPathComponent(sha256Hex("b") + ".log")
        let bytes = try? Data(contentsOf: url)
        #expect(bytes != nil)
        let magic: [UInt8] = [0x50, 0x4C, 0x4F, 0x47, 0x01]   // "PLOG\x01"
        #expect(Array(bytes!.prefix(5)) == magic)
    }

    @Test func encryptedReadWithoutKeyReturnsPlaceholder() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        let key = SymmetricKey(size: .bits256)
        runAsync { await store.setEncryptionKey(key) }
        runAsync { await store.append(network: "n", buffer: "b", line: "secret") }
        runAsync { await store.setEncryptionKey(nil) }
        let text = runAsync { await store.read(network: "n", buffer: "b") }
        #expect(text != nil)
        #expect(text?.contains("secret") == false)
        #expect(text?.contains("encrypted") == true)
    }

    // MARK: - Index + enumerate

    @Test func appendRecordsInIndex() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        runAsync { await store.append(network: "Undernet", buffer: "#swift", line: "x") }
        runAsync { await store.append(network: "Undernet", buffer: "alice",  line: "y") }
        let entries = runAsync { await store.enumerateIndex() }
        let pairs = entries.map { "\($0.network)/\($0.buffer)" }.sorted()
        #expect(pairs == ["Undernet/#swift", "Undernet/alice"])
    }

    @Test func appendIsIdempotentInIndex() {
        let store = LogStore(baseURL: tempDir())
        for _ in 0..<10 {
            runAsync { await store.append(network: "n", buffer: "b", line: "line") }
        }
        let entries = runAsync { await store.enumerateIndex() }
        #expect(entries.count == 1)
    }

    @Test func backfillIndexAddsKnownPairs() {
        let store = LogStore(baseURL: tempDir())
        runAsync {
            await store.backfillIndex([
                (network: "Net1", buffer: "#chan"),
                (network: "Net1", buffer: "alice"),
                (network: "Net2", buffer: "#other")
            ])
        }
        let entries = runAsync { await store.enumerateIndex() }
        #expect(entries.count == 3)
        let pairs = entries.map { "\($0.network)/\($0.buffer)" }.sorted()
        #expect(pairs == ["Net1/#chan", "Net1/alice", "Net2/#other"])
    }

    @Test func enumerateAllLogsSeparatesNamedFromOrphans() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        runAsync { await store.append(network: "FooNet", buffer: "#known", line: "x") }
        // Plant a raw .log file with slugs that never went through append.
        // The enumerate API should surface this as an orphan.
        let netSlug = sha256Hex("ForgottenNet")
        let bufSlug = sha256Hex("#forgotten")
        let netDir = dir.appendingPathComponent(netSlug, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: netDir, withIntermediateDirectories: true)
        try? Data("hello".utf8).write(
            to: netDir.appendingPathComponent("\(bufSlug).log"))

        let result = runAsync { await store.enumerateAllLogs() }
        #expect(result.named.count == 1)
        #expect(result.named.first?.network == "FooNet")
        #expect(result.named.first?.buffer == "#known")
        #expect(result.orphans.count == 1)
        #expect(result.orphans.first?.networkSlug == netSlug)
        #expect(result.orphans.first?.bufferSlug == bufSlug)
    }

    @Test func enumerateAllLogsSkipsOrphanWhenIndexClaims() {
        let dir = tempDir()
        let store = LogStore(baseURL: dir)
        runAsync { await store.append(network: "FooNet", buffer: "#known", line: "x") }
        let result = runAsync { await store.enumerateAllLogs() }
        #expect(result.named.count == 1)
        #expect(result.orphans.isEmpty)
    }

    @Test func indexSurvivesAcrossInstances() {
        let dir = tempDir()
        let store1 = LogStore(baseURL: dir)
        runAsync { await store1.append(network: "Net", buffer: "#chan", line: "first") }
        // Fresh actor over the same directory — index should re-load.
        let store2 = LogStore(baseURL: dir)
        let entries = runAsync { await store2.enumerateIndex() }
        #expect(entries.count == 1)
        #expect(entries.first?.network == "Net")
        #expect(entries.first?.buffer == "#chan")
    }

    @Test func indexRoundtripUnderEncryption() {
        let dir = tempDir()
        let key = SymmetricKey(size: .bits256)
        let store1 = LogStore(baseURL: dir)
        runAsync { await store1.setEncryptionKey(key) }
        runAsync { await store1.append(network: "EncNet", buffer: "#chan", line: "x") }
        let store2 = LogStore(baseURL: dir)
        runAsync { await store2.setEncryptionKey(key) }
        let entries = runAsync { await store2.enumerateIndex() }
        #expect(entries.count == 1)
        #expect(entries.first?.network == "EncNet")
    }

    // MARK: - search() — cross-network unified search (1.0.247)
    //
    // These tests use native `@Test async` bodies rather than the
    // `runAsync` sync-bridge pattern used elsewhere in this file.
    // Mixing nine semaphore-bridged calls per test with swift-testing's
    // parallel scheduler starved the cooperative pool and deadlocked
    // the suite. Async-native tests sidestep the issue.

    @Test func searchFindsLineByCaseInsensitiveSubstring() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Libera", buffer: "#swift",
                            line: "<alice> hello world")
        await store.append(network: "Libera", buffer: "#swift",
                            line: "<alice> nothing interesting")
        let hits = await store.search(query: "HELLO")
        #expect(hits.count == 1)
        #expect(hits.first?.network == "Libera")
        #expect(hits.first?.buffer == "#swift")
        #expect(hits.first?.line.contains("hello world") == true)
        #expect(hits.first?.lineNumber == 1)
    }

    @Test func searchHonorsCaseSensitivity() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Libera", buffer: "#a",
                            line: "alice said HELLO")
        let csInsensitive = await store.search(query: "hello")
        let csSensitive   = await store.search(query: "hello", caseSensitive: true)
        #expect(csInsensitive.count == 1)
        #expect(csSensitive.isEmpty)
    }

    @Test func searchFoldsAcrossNetworksAndBuffers() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Libera", buffer: "#swift",
                            line: "<alice> ship it")
        await store.append(network: "OFTC",  buffer: "#kernel",
                            line: "<bob> shipping now")
        await store.append(network: "Libera", buffer: "#offtopic",
                            line: "<carol> off-topic chat")
        let hits = await store.search(query: "ship")
        #expect(hits.count == 2)
        let nets = Set(hits.map { $0.network })
        #expect(nets == Set(["Libera", "OFTC"]))
        let bufs = Set(hits.map { $0.buffer })
        #expect(bufs == Set(["#swift", "#kernel"]))
    }

    @Test func searchEmptyQueryReturnsEmpty() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Net", buffer: "#chan", line: "anything")
        let empty1 = await store.search(query: "")
        let empty2 = await store.search(query: "   ")
        #expect(empty1.isEmpty)
        #expect(empty2.isEmpty)
    }

    @Test func searchNoMatch() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Net", buffer: "#chan",
                            line: "completely unrelated content")
        let hits = await store.search(query: "xyzzy")
        #expect(hits.isEmpty)
    }

    @Test func searchHonorsResultLimit() async {
        let store = LogStore(baseURL: tempDir())
        for i in 0..<10 {
            await store.append(network: "Net", buffer: "#chan",
                                line: "match #\(i)")
        }
        let hits = await store.search(query: "match", limit: 3)
        #expect(hits.count == 3)
    }

    @Test func searchWorksUnderEncryption() async {
        let dir = tempDir()
        let key = SymmetricKey(size: .bits256)
        let store1 = LogStore(baseURL: dir)
        await store1.setEncryptionKey(key)
        await store1.append(network: "EncNet", buffer: "#chan",
                             line: "<alice> secret message")
        // Fresh actor, same key — should still find the line after
        // transparent decryption.
        let store2 = LogStore(baseURL: dir)
        await store2.setEncryptionKey(key)
        let hits = await store2.search(query: "secret")
        #expect(hits.count == 1)
        #expect(hits.first?.line.contains("secret message") == true)
    }

    @Test func searchParsesIso8601Timestamp() async {
        let store = LogStore(baseURL: tempDir())
        let before = Date()
        await store.append(network: "Net", buffer: "#chan", line: "needle line")
        let after = Date()
        let hits = await store.search(query: "needle")
        #expect(hits.count == 1)
        let ts = hits.first?.timestamp
        #expect(ts != nil)
        if let ts {
            #expect(ts >= before.addingTimeInterval(-1))
            #expect(ts <= after.addingTimeInterval(1))
        }
    }

    @Test func parseLogTimestampHandlesMalformedLines() {
        // Direct unit test of the parser — defends against a stray
        // hand-edited log line landing in the search results without
        // a timestamp (resulting in nil instead of a crash).
        #expect(LogStore.parseLogTimestamp("no-timestamp-here") == nil)
        #expect(LogStore.parseLogTimestamp("") == nil)
        let ok = LogStore.parseLogTimestamp("2026-05-12T12:00:00.000Z body")
        #expect(ok != nil)
    }

    // MARK: - searchAuthored() — fuzzy authored-by nick search

    /// Authored-by search returns the target's own lines plus fuzzy variants
    /// (decoration / alt-padding), and crucially EXCLUDES a line that merely
    /// *mentions* the nick but was written by someone else.
    @Test func searchAuthoredMatchesVariantsAndExcludesMentions() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Libera", buffer: "#swift", line: "<john_doe> first")
        await store.append(network: "Libera", buffer: "#swift", line: "<johndoe1> alt-nick line")
        await store.append(network: "Libera", buffer: "#swift", line: "* johnny waves")
        // Mention only — authored by bob, just talking about john_doe.
        await store.append(network: "Libera", buffer: "#swift", line: "<bob> hey john_doe you around?")
        // Unrelated author.
        await store.append(network: "Libera", buffer: "#swift", line: "<zelda> hi all")

        let hits = await store.searchAuthored(nick: "john_doe", threshold: 0.84)
        let authors = Set(hits.compactMap { $0.matchedNick })
        #expect(authors.contains("john_doe"))
        #expect(authors.contains("johndoe1"))
        #expect(authors.contains("johnny"))
        #expect(!authors.contains("bob"))     // mention-only excluded
        #expect(!authors.contains("zelda"))   // unrelated excluded
        // bob's mention line must not appear at all.
        #expect(!hits.contains { $0.line.contains("hey john_doe") })
    }

    @Test func searchAuthoredThresholdControlsReach() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Net", buffer: "#chan", line: "<jdough1> distant variant")
        // Too far at the default fuzziness…
        let tight = await store.searchAuthored(nick: "john_doe", threshold: 0.84)
        #expect(tight.isEmpty)
        // …reachable once loosened.
        let loose = await store.searchAuthored(nick: "john_doe", threshold: 0.50)
        #expect(loose.count == 1)
        #expect(loose.first?.matchedNick == "jdough1")
    }

    @Test func searchAuthoredEmptyNickReturnsEmpty() async {
        let store = LogStore(baseURL: tempDir())
        await store.append(network: "Net", buffer: "#chan", line: "<alice> hi")
        let hits = await store.searchAuthored(nick: "   ", threshold: 0.5)
        #expect(hits.isEmpty)
    }
}
