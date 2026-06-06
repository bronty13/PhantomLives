import XCTest
@testable import ArchiveKit

/// Create → extract → byte-compare across every writable format, plus the
/// security and edge cases that matter (AES round-trip, wrong password,
/// zip-slip rejection, hashing).
final class RoundTripTests: XCTestCase {

    private var tmp: URL!
    private var fm: FileManager { .default }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("parc-rt-\(ProcessInfo.processInfo.globallyUniqueString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    /// A small tree: a top file, a nested file, and a binary blob.
    private func makeSource() throws -> URL {
        let src = tmp.appendingPathComponent("src")
        try fm.createDirectory(at: src.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "alpha\n".write(to: src.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta nested\n".write(to: src.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        var blob = Data(count: 40_000)
        for i in blob.indices { blob[i] = UInt8((i * 31) & 0xFF) }
        try blob.write(to: src.appendingPathComponent("blob.bin"))
        return src
    }

    private func assertTreesEqual(_ a: URL, _ b: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let ea = try fm.contentsOfDirectory(atPath: a.path).sorted()
        let eb = try fm.contentsOfDirectory(atPath: b.path).sorted()
        XCTAssertEqual(ea, eb, "dir entries differ", file: file, line: line)
        for name in ea {
            let pa = a.appendingPathComponent(name), pb = b.appendingPathComponent(name)
            var da: ObjCBool = false, db: ObjCBool = false
            _ = fm.fileExists(atPath: pa.path, isDirectory: &da)
            _ = fm.fileExists(atPath: pb.path, isDirectory: &db)
            XCTAssertEqual(da.boolValue, db.boolValue, "type differs for \(name)", file: file, line: line)
            if da.boolValue { try assertTreesEqual(pa, pb, file: file, line: line) }
            else {
                XCTAssertEqual(try Data(contentsOf: pa), try Data(contentsOf: pb),
                               "content differs for \(name)", file: file, line: line)
            }
        }
    }

    func testRoundTripAllFormats() throws {
        let src = try makeSource()
        let svc = ArchiveService()
        let formats: [(String, ArchiveFormat)] = [
            ("out.zip", .zip), ("out.tar", .tar), ("out.tar.gz", .tarGz),
            ("out.tar.bz2", .tarBz2), ("out.tar.xz", .tarXz), ("out.tar.zst", .tarZst),
        ]
        for (name, fmt) in formats {
            let archive = tmp.appendingPathComponent(name)
            let made = try svc.create(archive, inputs: [src], format: fmt)
            XCTAssertGreaterThanOrEqual(made, 4, "\(name): expected ≥4 entries")
            let dest = tmp.appendingPathComponent("x-\(fmt.rawValue)")
            try svc.extract(archive, options: ExtractOptions(destination: dest))
            try assertTreesEqual(src, dest.appendingPathComponent("src"))
            XCTAssertTrue(try svc.test(archive), "\(name): integrity test failed")
        }
    }

    func testEncryptedZipRoundTrip() throws {
        let src = try makeSource()
        let svc = ArchiveService()
        let archive = tmp.appendingPathComponent("secret.zip")
        try svc.create(archive, inputs: [src], options: CompressionOptions(password: "hunter2"))

        // Entries report as encrypted.
        let entries = try svc.list(archive)
        XCTAssertTrue(entries.contains { $0.isEncrypted && !$0.isDirectory })

        // Correct password extracts and matches.
        let dest = tmp.appendingPathComponent("dec")
        try svc.extract(archive, options: ExtractOptions(destination: dest, password: "hunter2"))
        try assertTreesEqual(src, dest.appendingPathComponent("src"))
    }

    func testWrongPasswordFails() throws {
        let src = try makeSource()
        let svc = ArchiveService()
        let archive = tmp.appendingPathComponent("secret.zip")
        try svc.create(archive, inputs: [src], options: CompressionOptions(password: "correct"))
        let dest = tmp.appendingPathComponent("bad")
        XCTAssertThrowsError(
            try svc.extract(archive, options: ExtractOptions(destination: dest, password: "wrong"))
        )
    }

    func testSingleFileZstdRequiresOneFile() throws {
        let src = try makeSource()
        let svc = ArchiveService()
        // A folder can't go into a single-file .zst.
        XCTAssertThrowsError(try svc.create(tmp.appendingPathComponent("o.zst"), inputs: [src]))
        // A single file is fine and round-trips.
        let one = src.appendingPathComponent("a.txt")
        let zst = tmp.appendingPathComponent("a.zst")
        try svc.create(zst, inputs: [one])
        let dest = tmp.appendingPathComponent("z")
        try svc.extract(zst, options: ExtractOptions(destination: dest))
        // raw zstd extracts to a single file named after the stream.
        let extracted = try fm.contentsOfDirectory(atPath: dest.path)
        XCTAssertEqual(extracted.count, 1)
    }

    func testZipSlipRejected() {
        let root = tmp.appendingPathComponent("dest").standardizedFileURL.resolvingSymlinksInPath()
        // `../` traversal that escapes the destination is refused.
        XCTAssertNil(LibArchiveEngine.safeDestination("../escape.txt", under: root))
        XCTAssertNil(LibArchiveEngine.safeDestination("a/../../escape.txt", under: root))
        // Normal relative paths are accepted.
        XCTAssertNotNil(LibArchiveEngine.safeDestination("ok/inside.txt", under: root))
        // Absolute entries are de-rooted INTO the destination (safe, like GNU
        // tar's "removing leading /") — not nil, but contained under root.
        let abs = LibArchiveEngine.safeDestination("/etc/passwd", under: root)
        XCTAssertNotNil(abs)
        XCTAssertTrue(abs!.path.hasPrefix(root.path + "/"), "absolute path must stay under dest")
        // A `..` inside an otherwise-absolute path that still lands inside is OK,
        // but one that escapes is refused.
        XCTAssertNil(LibArchiveEngine.safeDestination("/../../../etc/passwd", under: root))
    }

    func testTreeBuilding() throws {
        let src = try makeSource()
        let svc = ArchiveService()
        let archive = tmp.appendingPathComponent("t.zip")
        try svc.create(archive, inputs: [src])
        let tree = try svc.tree(archive)
        XCTAssertEqual(tree.fileCount, 3)
        XCTAssertGreaterThan(tree.totalSize, 40_000)
    }

    func testHashKnownVector() throws {
        // SHA-256("abc") is a well-known test vector.
        let f = tmp.appendingPathComponent("abc.txt")
        try "abc".write(to: f, atomically: true, encoding: .utf8)
        let digest = try Hasher.hash(f, algorithm: .sha256)
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(Hasher.hash(Data("abc".utf8), algorithm: .md5), "900150983cd24fb0d6963f7d28e17f72")
    }
}
