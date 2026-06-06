import XCTest
@testable import ArchiveKit

/// Phase 0 smoke tests: prove the vendored libraries link and run, and that a
/// real archive created on the fly lists back correctly through libarchive.
final class EngineSmokeTests: XCTestCase {

    func testLibraryVersionsLink() {
        XCTAssertFalse(ArchiveKitVersions.libarchive.isEmpty)
        XCTAssertTrue(ArchiveKitVersions.zstd.hasPrefix("1.5"),
                      "expected vendored zstd 1.5.x, got \(ArchiveKitVersions.zstd)")
    }

    func testZstdRoundTrip() {
        let engine = ZstdEngine()
        let original = Data("the quick brown fox jumps over the lazy dog".utf8)
        let compressed = engine.compress(original, level: 19)
        XCTAssertFalse(compressed.isEmpty)
        let restored = engine.decompress(compressed, expectedSize: original.count)
        XCTAssertEqual(restored, original)
    }

    /// Build a small zip with the system `zip` tool, then list it via libarchive.
    func testListSystemCreatedZip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parc-smoke-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fileA = tmp.appendingPathComponent("hello.txt")
        try "hello phantom\n".write(to: fileA, atomically: true, encoding: .utf8)
        let subdir = tmp.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "deeper\n".write(to: subdir.appendingPathComponent("b.txt"),
                             atomically: true, encoding: .utf8)

        let zipURL = tmp.appendingPathComponent("fixture.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", zipURL.path, "hello.txt", "nested"]
        zip.currentDirectoryURL = tmp
        try zip.run()
        zip.waitUntilExit()
        try XCTSkipUnless(zip.terminationStatus == 0, "system zip unavailable")

        let entries = try LibArchiveEngine().list(zipURL)
        let names = entries.map(\.displayPath)
        XCTAssertTrue(names.contains("hello.txt"), "got \(names)")
        XCTAssertTrue(names.contains { $0.hasSuffix("b.txt") }, "got \(names)")
    }
}
