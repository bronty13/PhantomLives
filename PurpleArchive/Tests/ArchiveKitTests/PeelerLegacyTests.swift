import XCTest
import CryptoKit
@testable import ArchiveKit

/// Validates the vendored (AI-generated) `peeler` legacy-Mac backend against its
/// own redistributable corpus: extract each StuffIt / Compact Pro / BinHex /
/// MacBinary archive and byte-verify every data fork against the committed
/// ground-truth MD5s. peeler is trusted only because these checks pass — not
/// because of its label.
final class PeelerLegacyTests: XCTestCase {

    /// `LegacyCorpus/<name>/{testfile.*, md5sums.txt}` — copied into the test
    /// bundle as a resource.
    private func corpusRoot() throws -> URL {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "LegacyCorpus", withExtension: nil),
            "LegacyCorpus resource missing from test bundle")
        return url
    }

    func testLibArchiveRejectsLegacyFormats() throws {
        // Sanity: these are exactly the formats libarchive can't open, proving
        // peeler is covering a real gap (not duplicating libarchive).
        let root = try corpusRoot()
        let sit = root.appendingPathComponent("stuffit45_dlx.mac9.sit/testfile.stuffit45_dlx.mac9.sit")
        XCTAssertThrowsError(try LibArchiveEngine().list(sit))
        XCTAssertTrue(PeelerEngine().canHandle(sit))
    }

    func testExtractAllCorpusDataForksMatchGroundTruth() throws {
        let fm = FileManager.default
        let root = try corpusRoot()
        let dirs = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
        XCTAssertGreaterThanOrEqual(dirs.count, 5, "expected the committed legacy corpus")

        var totalChecked = 0
        for dir in dirs {
            let archive = try XCTUnwrap(
                try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix("testfile.") },
                "no testfile.* in \(dir.lastPathComponent)")
            let expected = try parseMD5Sums(dir.appendingPathComponent("md5sums.txt"))

            let out = fm.temporaryDirectory.appendingPathComponent("peel-\(UUID().uuidString)")
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: out) }

            try ArchiveService().extract(archive, options: ExtractOptions(destination: out))

            for (name, sum) in expected where !name.hasPrefix("._") {
                let file = out.appendingPathComponent(name)
                guard fm.fileExists(atPath: file.path) else {
                    XCTFail("\(dir.lastPathComponent): missing extracted “\(name)”"); continue
                }
                let got = md5(try Data(contentsOf: file))
                XCTAssertEqual(got, sum, "\(dir.lastPathComponent): MD5 mismatch for “\(name)”")
                totalChecked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(totalChecked, 30, "expected many verified data forks")
    }

    // MARK: - helpers

    /// Parse `md5sums.txt` lines ("<md5>  <name>"), normalizing the leading "./".
    private func parseMD5Sums(_ url: URL) throws -> [(name: String, md5: String)] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("./") { name.removeFirst(2) }
            return (name, String(parts[0]))
        }
    }

    private func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
