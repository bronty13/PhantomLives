import XCTest
@testable import PurplePeek

final class MediaDiscoveryTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pp-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func write(_ name: String, in dir: URL? = nil) throws {
        let base = dir ?? tempRoot!
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base.appendingPathComponent(name))
    }

    func testClassifiesByTypeAndIgnoresNonMedia() throws {
        try write("a.jpg")
        try write("b.png")
        try write("c.mp4")
        try write("d.m4a")
        try write("notes.txt")       // ignored (not media)
        try write("archive.zip")     // ignored

        let found = MediaDiscoveryService.scan(root: tempRoot)
        let byType = Dictionary(grouping: found, by: { $0.type })

        XCTAssertEqual(found.count, 4)
        XCTAssertEqual(byType[.photo]?.count, 2)
        XCTAssertEqual(byType[.video]?.count, 1)
        XCTAssertEqual(byType[.audio]?.count, 1)
        XCTAssertFalse(found.contains { $0.name == "notes.txt" })
        XCTAssertFalse(found.contains { $0.name == "archive.zip" })
    }

    func testSkipsHiddenFiles() throws {
        try write("visible.jpg")
        try write(".hidden.jpg")

        let found = MediaDiscoveryService.scan(root: tempRoot)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, "visible.jpg")
    }

    func testRecursesIntoSubfolders() throws {
        try write("top.jpg")
        try write("nested.mp4", in: tempRoot.appendingPathComponent("Sub/Deeper", isDirectory: true))

        let found = MediaDiscoveryService.scan(root: tempRoot)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains { $0.name == "nested.mp4" && $0.type == .video })
    }

    func testCapturesSizeAndPath() throws {
        try write("a.jpg")
        let found = MediaDiscoveryService.scan(root: tempRoot)
        let file = try XCTUnwrap(found.first)
        XCTAssertEqual(file.size, 1)                       // "x"
        XCTAssertTrue(file.path.hasSuffix("/a.jpg"))
    }
}
