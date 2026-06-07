import XCTest
@testable import ArchiveKit

/// Raw split archives (.001/.002/…): detect the set and transparently reassemble
/// so list/extract work when the user opens any single part.
final class MultiVolumeTests: XCTestCase {
    private var tmp: URL!
    private var fm: FileManager { .default }

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("pa-vol-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    /// Split `data` into `count` files named `<base>.001`, `.002`, …
    private func split(_ data: Data, base: URL, count: Int) throws {
        let chunk = (data.count + count - 1) / count
        for i in 0..<count {
            let lo = i * chunk
            guard lo < data.count else { break }
            let hi = min(lo + chunk, data.count)
            let part = base.appendingPathExtension(String(format: "%03d", i + 1))
            try data.subdata(in: lo..<hi).write(to: part)
        }
    }

    func testDetectsAndReassembles() throws {
        let svc = ArchiveService()
        // Build a real zip with a few files.
        let src = tmp.appendingPathComponent("src")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        for n in 0..<5 {
            var d = Data(count: 6000)
            for j in d.indices { d[j] = UInt8((n &* 11 &+ j) & 0xFF) }
            try d.write(to: src.appendingPathComponent("f\(n).bin"))
        }
        let zip = tmp.appendingPathComponent("payload.zip")
        try svc.create(zip, inputs: [src])

        // Split it into 3 raw volumes; remove the whole zip so only parts remain.
        let data = try Data(contentsOf: zip)
        try split(data, base: zip, count: 3)
        try fm.removeItem(at: zip)

        let p1 = zip.appendingPathExtension("001")
        let p3 = zip.appendingPathExtension("003")
        XCTAssertTrue(fm.fileExists(atPath: p1.path))

        // Detection finds all parts from any member.
        XCTAssertEqual(MultiVolume.volumeParts(for: p1)?.count, 3)
        XCTAssertEqual(MultiVolume.volumeParts(for: p3)?.count, 3)
        // A non-split file isn't mistaken for one.
        XCTAssertNil(MultiVolume.volumeParts(for: src.appendingPathComponent("f0.bin")))

        // List + extract work through any part.
        let entries = try svc.list(p1).filter { !$0.isDirectory }
        XCTAssertEqual(entries.count, 5)

        let out = tmp.appendingPathComponent("out")
        try svc.extract(p3, options: ExtractOptions(destination: out))
        try assertEqualTrees(src, out.appendingPathComponent("src"))
        XCTAssertTrue(try svc.test(p1))
    }

    private func assertEqualTrees(_ a: URL, _ b: URL) throws {
        let names = try fm.contentsOfDirectory(atPath: a.path).sorted()
        XCTAssertEqual(names, try fm.contentsOfDirectory(atPath: b.path).sorted())
        for n in names {
            XCTAssertEqual(try Data(contentsOf: a.appendingPathComponent(n)),
                           try Data(contentsOf: b.appendingPathComponent(n)), "content \(n)")
        }
    }
}
