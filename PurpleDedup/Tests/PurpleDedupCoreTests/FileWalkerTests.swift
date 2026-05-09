import XCTest
@testable import PurpleDedupCore

final class FileWalkerTests: XCTestCase {

    func testYieldsRegularFilesMatchingExtension() async throws {
        let root = try TestFixtures.makeTempDir("walker-basic")
        defer { TestFixtures.cleanup(root) }

        try TestFixtures.write("a", to: root.appendingPathComponent("one.jpg"))
        try TestFixtures.write("b", to: root.appendingPathComponent("two.HEIC"))   // case-insensitive
        try TestFixtures.write("c", to: root.appendingPathComponent("notes.txt")) // wrong type → filtered
        try TestFixtures.write("d", to: root.appendingPathComponent("nested/clip.mp4"))

        let walker = FileWalker()
        var seen: [String] = []
        for try await f in walker.walk(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo, .video])
        ) {
            seen.append(f.url.lastPathComponent)
        }
        XCTAssertEqual(Set(seen), Set(["one.jpg", "two.HEIC", "clip.mp4"]))
    }

    func testHonorsSizeFilters() async throws {
        let root = try TestFixtures.makeTempDir("walker-size")
        defer { TestFixtures.cleanup(root) }

        try TestFixtures.write(String(repeating: "x", count: 10), to: root.appendingPathComponent("a.jpg"))
        try TestFixtures.write(String(repeating: "y", count: 1000), to: root.appendingPathComponent("b.jpg"))
        try TestFixtures.write(String(repeating: "z", count: 100_000), to: root.appendingPathComponent("c.jpg"))

        let walker = FileWalker()
        var names: [String] = []
        for try await f in walker.walk(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo], minSizeBytes: 100, maxSizeBytes: 10_000)
        ) {
            names.append(f.url.lastPathComponent)
        }
        XCTAssertEqual(Set(names), Set(["b.jpg"]))
    }

    func testHiddenFilesSkippedByDefault() async throws {
        let root = try TestFixtures.makeTempDir("walker-hidden")
        defer { TestFixtures.cleanup(root) }

        try TestFixtures.write("v", to: root.appendingPathComponent(".secret.jpg"))
        try TestFixtures.write("v", to: root.appendingPathComponent("visible.jpg"))

        let walker = FileWalker()
        var defaultNames: [String] = []
        for try await f in walker.walk(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo], includeHidden: false)
        ) {
            defaultNames.append(f.url.lastPathComponent)
        }
        XCTAssertEqual(defaultNames, ["visible.jpg"])

        var allNames: [String] = []
        for try await f in walker.walk(
            sources: [ScanSource(url: root)],
            options: ScanOptions(kinds: [.photo], includeHidden: true)
        ) {
            allNames.append(f.url.lastPathComponent)
        }
        XCTAssertEqual(Set(allNames), Set([".secret.jpg", "visible.jpg"]))
    }

    func testLockedFlagPropagates() async throws {
        let root = try TestFixtures.makeTempDir("walker-locked")
        defer { TestFixtures.cleanup(root) }

        try TestFixtures.write("v", to: root.appendingPathComponent("keep.jpg"))

        let walker = FileWalker()
        for try await f in walker.walk(
            sources: [ScanSource(url: root, isLocked: true)],
            options: ScanOptions(kinds: [.photo])
        ) {
            XCTAssertTrue(f.isLocked, "Locked source must propagate to discovered files")
        }
    }
}
