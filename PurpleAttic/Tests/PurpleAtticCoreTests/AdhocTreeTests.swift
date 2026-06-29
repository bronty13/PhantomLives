import XCTest
@testable import PurpleAtticCore

/// Covers the pure folder-tree builder that turns flat decrypted paths into a navigable hierarchy.
final class AdhocTreeTests: XCTestCase {

    private func f(_ path: String, _ size: Int64) -> AdhocFile {
        AdhocFile(path: path, name: (path as NSString).lastPathComponent, size: size,
                  modTime: Date(timeIntervalSince1970: 1_700_000_000), isDir: false,
                  lastSeen: Date(timeIntervalSince1970: 0))
    }

    func testBuildsNestedFoldersWithRecursiveAggregates() {
        let roots = AdhocTree.build([
            f("HOTW/a.pdf", 10),
            f("HOTW/sub/b.pdf", 20),
            f("HOTW/sub/c.pdf", 30),
            f("root.txt", 5),
        ])
        // Top level: folder HOTW first, then file root.txt.
        XCTAssertEqual(roots.map(\.name), ["HOTW", "root.txt"])
        XCTAssertEqual(roots.map(\.isDir), [true, false])

        let hotw = roots[0]
        XCTAssertEqual(hotw.id, "HOTW")
        XCTAssertEqual(hotw.fileCount, 3, "recursive file count")
        XCTAssertEqual(hotw.size, 60, "recursive byte total")

        // HOTW's children: folder "sub" first, then file "a.pdf".
        let kids = hotw.children ?? []
        XCTAssertEqual(kids.map(\.name), ["sub", "a.pdf"])
        let sub = kids[0]
        XCTAssertEqual(sub.fileCount, 2)
        XCTAssertEqual(sub.size, 50)
        XCTAssertEqual(sub.children?.map(\.name), ["b.pdf", "c.pdf"])

        // Files are leaves (nil children → no disclosure triangle); folders carry their file.
        XCTAssertNil(kids[1].children)
        XCTAssertNotNil(kids[1].file)
        XCTAssertNil(hotw.file)
    }

    func testEmptyInput() {
        XCTAssertTrue(AdhocTree.build([]).isEmpty)
    }

    func testSingleRootFile() {
        let roots = AdhocTree.build([f("only.txt", 7)])
        XCTAssertEqual(roots.count, 1)
        XCTAssertFalse(roots[0].isDir)
        XCTAssertEqual(roots[0].id, "only.txt")
    }

    func testDirectoryEntriesAreIgnored() {
        // A stray isDir entry shouldn't create a phantom node; folders come from file paths.
        let dir = AdhocFile(path: "HOTW", name: "HOTW", size: -1,
                            modTime: Date(timeIntervalSince1970: 0), isDir: true,
                            lastSeen: Date(timeIntervalSince1970: 0))
        let roots = AdhocTree.build([dir, f("HOTW/a.pdf", 1)])
        XCTAssertEqual(roots.map(\.name), ["HOTW"])
        XCTAssertTrue(roots[0].isDir)
        XCTAssertEqual(roots[0].children?.map(\.name), ["a.pdf"])
    }
}
