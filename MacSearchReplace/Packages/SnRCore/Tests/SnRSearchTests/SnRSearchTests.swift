import Testing
import Foundation
@testable import SnRSearch

@Suite("Searcher")
struct SearcherTests {

    func makeFixtures() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snr-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "alpha\nbeta brown\ngamma".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "no matches here".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "brown brown brown".write(to: dir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func nativeLiteralSearch() async throws {
        let dir = try makeFixtures(); defer { try? FileManager.default.removeItem(at: dir) }
        let spec = SearchSpec(pattern: "brown", roots: [dir])
        var hits = 0, files = 0
        for try await m in Searcher.nativeFallback.stream(spec: spec) {
            files += 1; hits += m.hits.count
        }
        #expect(files == 2)
        #expect(hits == 4)
    }

    @Test func nativeRegexCaseInsensitive() async throws {
        let dir = try makeFixtures(); defer { try? FileManager.default.removeItem(at: dir) }
        let spec = SearchSpec(
            pattern: "BROWN",
            kind: .regex,
            caseInsensitive: true,
            roots: [dir]
        )
        var total = 0
        for try await m in Searcher.nativeFallback.stream(spec: spec) {
            total += m.hits.count
        }
        #expect(total == 4)
    }

    @Test func ripgrepLocatorDoesNotCrash() {
        _ = RipgrepLocator.locate()
    }
}
