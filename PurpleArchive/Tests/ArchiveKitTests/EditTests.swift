import XCTest
@testable import ArchiveKit

/// In-place add / rename / delete: verify untouched entries survive byte-for-byte
/// and the mutations land, across zip (random-access) and tar.zst (solid).
final class EditTests: XCTestCase {
    private var tmp: URL!
    private var fm: FileManager { .default }

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("pa-edit-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    private func makeSource() throws -> URL {
        let src = tmp.appendingPathComponent("src")
        try fm.createDirectory(at: src.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "alpha".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: src.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        try "gamma".write(to: src.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        return src
    }

    private func names(_ url: URL) throws -> Set<String> {
        Set(try ArchiveService().list(url).filter { !$0.isDirectory }.map(\.displayPath))
    }

    func testDeleteRenameAddRoundTrip() throws {
        let svc = ArchiveService()
        let src = try makeSource()
        let archive = tmp.appendingPathComponent("e.zip")
        try svc.create(archive, inputs: [src])
        XCTAssertEqual(try names(archive), ["src/a.txt", "src/sub/b.txt", "src/c.txt"])

        // A file to add.
        let extra = tmp.appendingPathComponent("extra.txt")
        try "delta".write(to: extra, atomically: true, encoding: .utf8)

        try svc.edit(archive, operations: [
            .delete(path: "src/c.txt"),
            .rename(from: "src/a.txt", to: "src/renamed.txt"),
            .add(fileURL: extra, at: "src/added.txt"),
        ])

        XCTAssertEqual(try names(archive),
                       ["src/sub/b.txt", "src/renamed.txt", "src/added.txt"])

        // Surviving + added content is intact.
        let out = tmp.appendingPathComponent("out")
        try svc.extract(archive, options: ExtractOptions(destination: out))
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("src/sub/b.txt"), encoding: .utf8), "beta")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("src/renamed.txt"), encoding: .utf8), "alpha")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("src/added.txt"), encoding: .utf8), "delta")
    }

    func testEditTarZstPreservesContents() throws {
        let svc = ArchiveService()
        let src = try makeSource()
        let archive = tmp.appendingPathComponent("e.tar.zst")
        try svc.create(archive, inputs: [src])
        try svc.edit(archive, operations: [.delete(path: "src/c.txt")])
        XCTAssertEqual(try names(archive), ["src/a.txt", "src/sub/b.txt"])
        XCTAssertTrue(try svc.test(archive), "edited tar.zst must verify")
    }

    func testEditingReadOnlyFormatThrows() throws {
        // A made-up .rar path routes read-only; editing must refuse clearly.
        let svc = ArchiveService()
        let src = try makeSource()
        let zip = tmp.appendingPathComponent("real.zip")
        try svc.create(zip, inputs: [src])
        // .gz single-file isn't a multi-file container → not editable.
        let one = src.appendingPathComponent("a.txt")
        let gz = tmp.appendingPathComponent("a.gz")
        try svc.create(gz, inputs: [one])
        XCTAssertThrowsError(try svc.edit(gz, operations: [.delete(path: "a.txt")]))
    }
}
