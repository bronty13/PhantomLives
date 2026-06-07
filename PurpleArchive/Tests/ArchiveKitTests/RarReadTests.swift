import XCTest
@testable import ArchiveKit

/// RAR reading via the vendored unrar — including RAR5 + recovery record, the
/// one variant libarchive's reader can't open. Corpus from ssokolow/rar-test-files.
final class RarReadTests: XCTestCase {

    private func corpus() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "RarCorpus", withExtension: nil))
    }

    func testUnrarHandlesRARMagic() throws {
        let url = try corpus().appendingPathComponent("testfile.rar5.rar")
        XCTAssertTrue(UnrarEngine().canHandle(url))
    }

    func testListAndExtractAllVariants() throws {
        let fm = FileManager.default
        let dir = try corpus()
        let rars = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "rar" }
        XCTAssertGreaterThanOrEqual(rars.count, 5)

        let svc = ArchiveService()
        for rar in rars {
            // Lists at least one entry.
            let entries = try svc.list(rar)
            XCTAssertTrue(entries.contains { $0.displayPath.hasSuffix("testfile.txt") },
                          "\(rar.lastPathComponent): expected testfile.txt, got \(entries.map(\.displayPath))")
            // Extracts with the correct content.
            let out = fm.temporaryDirectory.appendingPathComponent("rar-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: out) }
            try svc.extract(rar, options: ExtractOptions(destination: out))
            let txt = out.appendingPathComponent("testfile.txt")
            XCTAssertTrue(fm.fileExists(atPath: txt.path), "\(rar.lastPathComponent): no extracted file")
            let content = try String(contentsOf: txt, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(content, "Testing 123", "\(rar.lastPathComponent): wrong content")
            // Integrity test passes (decompresses every entry).
            XCTAssertTrue(try svc.test(rar), "\(rar.lastPathComponent): integrity test failed")
        }
    }

    func testRAR5WithRecoveryRecord() throws {
        // The variant libarchive's reader fails on ("error 0") — unrar reads it.
        let svc = ArchiveService()
        let url = try corpus().appendingPathComponent("testfile.rar5.rr.rar")
        let entries = try svc.list(url)
        XCTAssertEqual(entries.filter { !$0.isDirectory }.count, 1)
    }
}
