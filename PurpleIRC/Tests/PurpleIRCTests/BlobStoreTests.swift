import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

@Suite("BlobStore")
struct BlobStoreTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purpleirc-blobtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func payload(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - store / read round-trip

    @Test func storeAndReadRoundTripsPlaintext() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        let owner = UUID()

        guard let rec = await store.store(
            data: payload("hello"),
            filename: "hi.txt",
            contentType: "text/plain",
            attachedTo: owner
        ) else {
            Issue.record("store returned nil")
            return
        }
        #expect(rec.filename == "hi.txt")
        #expect(rec.contentType == "text/plain")
        #expect(rec.sizeBytes == 5)
        #expect(rec.attachedTo == owner)

        let read = await store.read(rec.id)
        #expect(read == payload("hello"))
    }

    @Test func storeAndReadRoundTripsEncrypted() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        let key = SymmetricKey(size: .bits256)
        await store.setEncryptionKey(key)

        guard let rec = await store.store(
            data: payload("secret"),
            filename: "s.txt",
            contentType: "text/plain",
            attachedTo: nil
        ) else {
            Issue.record("store returned nil")
            return
        }
        let read = await store.read(rec.id)
        #expect(read == payload("secret"))
    }

    @Test func emptyContentTypeFallsBackToOctetStream() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        guard let rec = await store.store(
            data: payload("x"),
            filename: "x.bin",
            contentType: "",
            attachedTo: nil
        ) else {
            Issue.record("store returned nil"); return
        }
        #expect(rec.contentType == "application/octet-stream")
    }

    // MARK: - delete

    @Test func deleteRemovesFileAndIndex() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        guard let rec = await store.store(
            data: payload("bye"),
            filename: "bye.txt",
            contentType: "text/plain",
            attachedTo: nil
        ) else { Issue.record("store nil"); return }

        await store.delete(rec.id)

        // Both metadata and bytes are gone.
        let r = await store.record(rec.id)
        #expect(r == nil)
        let bytes = await store.read(rec.id)
        #expect(bytes == nil)
    }

    @Test func deleteIsIdempotent() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        let id = UUID()
        await store.delete(id)   // unknown id — should not throw
        await store.delete(id)   // second time — still fine
    }

    // MARK: - writeToTempFile

    @Test func writeToTempFileProducesReadableFile() async throws {
        let store = BlobStore(supportDirectoryURL: tempDir())
        guard let rec = await store.store(
            data: payload("temp"),
            filename: "temp.txt",
            contentType: "text/plain",
            attachedTo: nil
        ) else { Issue.record("store nil"); return }

        guard let url = await store.writeToTempFile(rec.id) else {
            Issue.record("writeToTempFile returned nil"); return
        }
        let read = try Data(contentsOf: url)
        #expect(read == payload("temp"))
        #expect(url.lastPathComponent == "temp.txt")
    }

    @Test func writeToTempFileReturnsNilForUnknownID() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        let url = await store.writeToTempFile(UUID())
        #expect(url == nil)
    }

    // MARK: - Index persistence across instances

    @Test func indexSurvivesAcrossInstances() async {
        let dir = tempDir()
        let store1 = BlobStore(supportDirectoryURL: dir)
        guard let rec = await store1.store(
            data: payload("survives"),
            filename: "s.txt",
            contentType: "text/plain",
            attachedTo: nil
        ) else { Issue.record("store nil"); return }

        // Fresh instance pointed at the same dir should see the
        // record + bytes via the on-disk index + payload.
        let store2 = BlobStore(supportDirectoryURL: dir)
        let r = await store2.record(rec.id)
        #expect(r?.filename == "s.txt")
        let bytes = await store2.read(rec.id)
        #expect(bytes == payload("survives"))
    }

    @Test func encryptedIndexSurvivesAcrossInstances() async {
        let dir = tempDir()
        let key = SymmetricKey(size: .bits256)

        let store1 = BlobStore(supportDirectoryURL: dir)
        await store1.setEncryptionKey(key)
        guard let rec = await store1.store(
            data: payload("encrypted-survives"),
            filename: "es.txt",
            contentType: "text/plain",
            attachedTo: nil
        ) else { Issue.record("store nil"); return }

        // New instance — without key, encrypted index loads empty.
        let store2 = BlobStore(supportDirectoryURL: dir)
        let beforeKey = await store2.allRecords()
        #expect(beforeKey.isEmpty)

        // Push the key — index re-loads.
        await store2.setEncryptionKey(key)
        let afterKey = await store2.allRecords()
        #expect(afterKey.count == 1)
        #expect(afterKey.first?.id == rec.id)

        let bytes = await store2.read(rec.id)
        #expect(bytes == payload("encrypted-survives"))
    }

    // MARK: - allRecords sorting

    @Test func allRecordsSortsNewestFirst() async {
        let store = BlobStore(supportDirectoryURL: tempDir())
        guard let r1 = await store.store(
            data: payload("a"), filename: "a", contentType: "", attachedTo: nil
        ) else { Issue.record("store nil"); return }
        try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms — enough to differ
        guard let r2 = await store.store(
            data: payload("b"), filename: "b", contentType: "", attachedTo: nil
        ) else { Issue.record("store nil"); return }

        let all = await store.allRecords()
        #expect(all.count == 2)
        #expect(all[0].id == r2.id)   // newest first
        #expect(all[1].id == r1.id)
    }

    // MARK: - store(fileURL:)

    @Test func storeFromFileURLPicksUpMimeFromExtension() async throws {
        let dir = tempDir()
        let store = BlobStore(supportDirectoryURL: dir)
        // Synthesise a tiny .json file and let the store import it.
        let src = dir.appendingPathComponent("source.json")
        try Data("{}".utf8).write(to: src)
        guard let rec = await store.store(fileURL: src, attachedTo: nil) else {
            Issue.record("store(fileURL:) returned nil"); return
        }
        #expect(rec.filename == "source.json")
        // UTType machinery returns "application/json" on macOS for .json.
        #expect(rec.contentType.contains("json"))
    }
}
