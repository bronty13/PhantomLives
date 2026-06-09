import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PurpleDedupCore

/// Audit classification is fully unit-testable without PhotoKit: a plain temp
/// directory stands in for the Photos library (the engine's `.photoslibrary`
/// special-casing is only in the walker's `originals/` shard handling — a plain
/// folder walks normally), so we can build a known library + folder and assert
/// the in/missing partition exactly.
final class AuditEngineTests: XCTestCase {

    private func classification(_ f: AuditEngine.AuditedFile) -> String {
        switch f.classification {
        case .inPhotosExact: return "exact"
        case .inPhotosPreview: return "preview"
        case .likelyInPhotosPerceptual: return "perceptual"
        case .likelyInPhotosFilename: return "filename"
        case .missing: return "missing"
        }
    }

    // MARK: - Exact

    func testExactPartition() async throws {
        let lib = try TestFixtures.makeTempDir("audit-lib")
        let folder = try TestFixtures.makeTempDir("audit-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }

        // Library has one original; folder has a byte-identical copy (diff name)
        // plus two unique files.
        try TestFixtures.write("PHOTO-ONE-BYTES", to: lib.appendingPathComponent("orig.jpg"))
        try TestFixtures.write("PHOTO-ONE-BYTES", to: folder.appendingPathComponent("copy.jpg"))
        try TestFixtures.write("PHOTO-TWO-BYTES", to: folder.appendingPathComponent("new1.jpg"))
        try TestFixtures.write("PHOTO-THREE", to: folder.appendingPathComponent("new2.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact,
            options: ScanOptions(kinds: [.all])
        )

        XCTAssertEqual(result.files.count, 3)
        XCTAssertEqual(result.inPhotos.count, 1)
        XCTAssertEqual(result.missing.count, 2)
        let inName = result.inPhotos.first?.url.lastPathComponent
        XCTAssertEqual(inName, "copy.jpg")
        XCTAssertEqual(classification(result.inPhotos.first!), "exact")
    }

    func testInPhotosAndMissingAreDisjoint() async throws {
        let lib = try TestFixtures.makeTempDir("audit-disjoint-lib")
        let folder = try TestFixtures.makeTempDir("audit-disjoint-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        try TestFixtures.write("X", to: lib.appendingPathComponent("a.jpg"))
        try TestFixtures.write("X", to: folder.appendingPathComponent("a.jpg"))
        try TestFixtures.write("Y", to: folder.appendingPathComponent("b.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all])
        )
        let inURLs = Set(result.inPhotos.map(\.url))
        let missingURLs = Set(result.missingURLs)
        XCTAssertTrue(inURLs.isDisjoint(with: missingURLs))
        XCTAssertEqual(inURLs.count + missingURLs.count, result.files.count)
    }

    func testSizeShortCircuitStillFindsMatch() async throws {
        // A bunch of differently-sized library files are never hashed (their
        // size matches nothing in the folder), but the one size-matching
        // duplicate is still found.
        let lib = try TestFixtures.makeTempDir("audit-size-lib")
        let folder = try TestFixtures.makeTempDir("audit-size-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }

        try TestFixtures.write("HELLO", to: lib.appendingPathComponent("match.jpg"))   // 5 bytes
        for (i, bytes) in ["a", "bb", "cccc", "ddddddd", "eeeeeeeeee"].enumerated() {
            try TestFixtures.write(bytes, to: lib.appendingPathComponent("decoy\(i).jpg"))
        }
        try TestFixtures.write("HELLO", to: folder.appendingPathComponent("copy.jpg")) // 5 bytes
        try TestFixtures.write("XYZ", to: folder.appendingPathComponent("unique.jpg"))  // 3 bytes

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all])
        )
        XCTAssertEqual(result.inPhotos.count, 1)
        XCTAssertEqual(result.inPhotos.first?.url.lastPathComponent, "copy.jpg")
        XCTAssertEqual(result.missing.count, 1)
        XCTAssertEqual(result.missing.first?.url.lastPathComponent, "unique.jpg")
    }

    // MARK: - Hidden items

    func testHiddenMatchIsTagged() async throws {
        let lib = try TestFixtures.makeTempDir("audit-hidden-lib")
        let folder = try TestFixtures.makeTempDir("audit-hidden-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        // Library file whose stem is "hidden" (passed lowercase to exercise the
        // case-insensitive stem match) and a visible one.
        try TestFixtures.write("HID", to: lib.appendingPathComponent("abchidden.jpg"))
        try TestFixtures.write("VIS", to: lib.appendingPathComponent("zzzvisible.jpg"))
        try TestFixtures.write("HID", to: folder.appendingPathComponent("a.jpg"))
        try TestFixtures.write("VIS", to: folder.appendingPathComponent("b.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]),
            includeHidden: true, hiddenAssetStems: ["abchidden"]
        )
        XCTAssertEqual(result.inPhotos.count, 2)
        XCTAssertEqual(result.hiddenInPhotos.count, 1)
        let byName = Dictionary(uniqueKeysWithValues: result.files.map { ($0.url.lastPathComponent, $0) })
        XCTAssertEqual(byName["a.jpg"]!.hiddenMatch, .hiddenOnly)
        XCTAssertEqual(byName["b.jpg"]!.hiddenMatch, .none)
    }

    func testAlsoHiddenWhenBothVisibleAndHidden() async throws {
        let lib = try TestFixtures.makeTempDir("audit-also-lib")
        let folder = try TestFixtures.makeTempDir("audit-also-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        // Same bytes exist as BOTH a hidden and a visible library asset.
        try TestFixtures.write("DUP", to: lib.appendingPathComponent("abchidden.jpg"))
        try TestFixtures.write("DUP", to: lib.appendingPathComponent("zzzvisible.jpg"))
        try TestFixtures.write("DUP", to: folder.appendingPathComponent("a.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]),
            includeHidden: true, hiddenAssetStems: ["abchidden"]
        )
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files.first?.hiddenMatch, .alsoHidden)
        XCTAssertTrue(result.files.first!.inPhotosHidden)
    }

    func testExcludeHiddenMakesHiddenOnlyMatchMissing() async throws {
        let lib = try TestFixtures.makeTempDir("audit-exhidden-lib")
        let folder = try TestFixtures.makeTempDir("audit-exhidden-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        try TestFixtures.write("HID", to: lib.appendingPathComponent("ABCHIDDEN.jpg"))
        try TestFixtures.write("VIS", to: lib.appendingPathComponent("ZZZVISIBLE.jpg"))
        try TestFixtures.write("HID", to: folder.appendingPathComponent("a.jpg"))
        try TestFixtures.write("VIS", to: folder.appendingPathComponent("b.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]),
            includeHidden: false, hiddenAssetStems: ["ABCHIDDEN"]
        )
        // a's only library copy is hidden → excluded → missing. b stays in Photos.
        XCTAssertEqual(result.inPhotos.count, 1)
        XCTAssertEqual(result.inPhotos.first?.url.lastPathComponent, "b.jpg")
        XCTAssertEqual(result.missing.count, 1)
        XCTAssertEqual(result.missing.first?.url.lastPathComponent, "a.jpg")
        XCTAssertEqual(result.hiddenInPhotos.count, 0)
    }

    // MARK: - Filename safety net

    func testFilenameSafetyNet() async throws {
        let lib = try TestFixtures.makeTempDir("audit-fname-lib")
        let folder = try TestFixtures.makeTempDir("audit-fname-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        // Library bytes differ (simulating an iCloud stub) but the filename matches.
        try TestFixtures.write("STUB-BYTES", to: lib.appendingPathComponent("ignored.jpg"))
        try TestFixtures.write("REAL-DIFFERENT-BYTES", to: folder.appendingPathComponent("IMG_42.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]),
            knownPhotoBasenames: ["IMG_42.jpg"]
        )
        XCTAssertEqual(result.missing.count, 0)
        XCTAssertEqual(result.inPhotos.count, 1)
        XCTAssertEqual(classification(result.inPhotos.first!), "filename")
    }

    func testFilenameSafetyNetMatchesAcrossFormat() async throws {
        // Mimics a Photos drag-export under Optimize Mac Storage: PhotoKit knows
        // the asset as IMG_99.HEIC (no matching bytes on disk), and the exported
        // folder file is IMG_99.jpeg — different bytes AND extension. Stem match
        // must still flag it as in-Photos.
        let lib = try TestFixtures.makeTempDir("audit-fmt-lib")
        let folder = try TestFixtures.makeTempDir("audit-fmt-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        try TestFixtures.write("UNRELATED", to: lib.appendingPathComponent("something.jpg"))
        try TestFixtures.write("RE-ENCODED-BYTES", to: folder.appendingPathComponent("IMG_99.jpeg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]),
            knownPhotoBasenames: ["IMG_99.HEIC"]
        )
        XCTAssertEqual(result.missing.count, 0)
        XCTAssertEqual(result.inPhotos.count, 1)
        if case .likelyInPhotosFilename = result.inPhotos.first!.classification {} else {
            XCTFail("expected filename match across format")
        }
    }

    func testUUIDNamedFileMatchesAssetUUID() async throws {
        // Some assets (often videos) have no original filename, so Photos exports
        // them under the asset UUID — which is also the on-disk originals/ stem.
        // Such a file must match even with no original-filename and no on-disk bytes.
        let lib = try TestFixtures.makeTempDir("audit-uuid-lib")
        let folder = try TestFixtures.makeTempDir("audit-uuid-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        let uuid = "8DFBAE08-AA28-4B59-8FA3-8BB0C7CC647F"
        try TestFixtures.write("UNRELATED", to: lib.appendingPathComponent("x.mov"))
        try TestFixtures.write("RE-ENCODED", to: folder.appendingPathComponent("\(uuid).mov"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]),
            knownAssetUUIDs: [uuid]   // case-insensitive: stored as-is, matched lowercased
        )
        XCTAssertEqual(result.missing.count, 0)
        XCTAssertEqual(result.inPhotos.count, 1)
        if case .likelyInPhotosFilename = result.inPhotos.first!.classification {} else {
            XCTFail("expected UUID/filename match")
        }
    }

    // MARK: - Perceptual

    func testPerceptualReclassifiesResizedCopy() async throws {
        let lib = try TestFixtures.makeTempDir("audit-perc-lib")
        let folder = try TestFixtures.makeTempDir("audit-perc-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }

        // Library: a 256px gradient. Folder: the SAME image at 384px (different
        // bytes → exact miss, same visual → perceptual hit) + a distinct checker.
        try writePNG(gradient(side: 256), at: lib.appendingPathComponent("g.png"))
        try writePNG(gradient(side: 384), at: folder.appendingPathComponent("resized.png"))
        try writePNG(checker(side: 256), at: folder.appendingPathComponent("distinct.png"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .perceptual, options: ScanOptions(kinds: [.photo])
        )
        let byName = Dictionary(uniqueKeysWithValues: result.files.map { ($0.url.lastPathComponent, $0) })
        XCTAssertEqual(classification(byName["resized.png"]!), "perceptual")
        XCTAssertEqual(classification(byName["distinct.png"]!), "missing")
    }

    func testExactModeDoesNotPerceptualMatch() async throws {
        let lib = try TestFixtures.makeTempDir("audit-exonly-lib")
        let folder = try TestFixtures.makeTempDir("audit-exonly-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        try writePNG(gradient(side: 256), at: lib.appendingPathComponent("g.png"))
        try writePNG(gradient(side: 384), at: folder.appendingPathComponent("resized.png"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.photo])
        )
        XCTAssertEqual(result.missing.count, 1, "Exact mode must not perceptual-match a resized copy")
    }

    // MARK: - Derivatives (Optimize Mac Storage)

    func testDerivativeMatchFindsICloudOnlyPhoto() async throws {
        // iCloud-only asset: NO original on disk, but a preview derivative exists.
        let lib = try makePhotosLibrary("audit-deriv")
        let folder = try TestFixtures.makeTempDir("audit-deriv-folder")
        defer { TestFixtures.cleanup(lib.deletingLastPathComponent()); TestFixtures.cleanup(folder) }

        let uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try writeJPEG(gradient(side: 256),
                      at: lib.appendingPathComponent("resources/derivatives/A/\(uuid)_1_105_c.jpeg"))
        // Folder copy: same image resized (mimics a Photos export), unrelated name
        // so only the derivative *content* can match it.
        try writeJPEG(gradient(side: 384), at: folder.appendingPathComponent("exported.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .perceptual, options: ScanOptions(kinds: [.photo])
        )
        XCTAssertEqual(result.inPhotos.count, 1)
        XCTAssertEqual(classification(result.inPhotos.first!), "preview",
                       "iCloud-only photo should match via its on-device preview")
    }

    func testDerivativesOffLeavesICloudOnlyMissing() async throws {
        let lib = try makePhotosLibrary("audit-derivoff")
        let folder = try TestFixtures.makeTempDir("audit-derivoff-folder")
        defer { TestFixtures.cleanup(lib.deletingLastPathComponent()); TestFixtures.cleanup(folder) }
        let uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try writeJPEG(gradient(side: 256),
                      at: lib.appendingPathComponent("resources/derivatives/A/\(uuid)_1_105_c.jpeg"))
        try writeJPEG(gradient(side: 384), at: folder.appendingPathComponent("exported.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .perceptual, options: ScanOptions(kinds: [.photo]),
            matchDerivatives: false
        )
        XCTAssertEqual(result.missing.count, 1, "with derivatives off, an iCloud-only photo is missing")
    }

    func testDerivativeSkippedWhenOriginalOnDisk() async throws {
        // When the original IS on disk, the asset is matched as an original
        // (perceptual), NOT as a preview — the derivative is skipped.
        let lib = try makePhotosLibrary("audit-derivskip")
        let folder = try TestFixtures.makeTempDir("audit-derivskip-folder")
        defer { TestFixtures.cleanup(lib.deletingLastPathComponent()); TestFixtures.cleanup(folder) }
        let uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try writeJPEG(gradient(side: 512), at: lib.appendingPathComponent("originals/A/\(uuid).jpeg"))
        try writeJPEG(gradient(side: 256), at: lib.appendingPathComponent("resources/derivatives/A/\(uuid)_1_105_c.jpeg"))
        try writeJPEG(gradient(side: 384), at: folder.appendingPathComponent("exported.jpg"))

        let result = try await AuditEngine().audit(
            folder: folder, photosLibrary: lib, mode: .perceptual, options: ScanOptions(kinds: [.photo])
        )
        XCTAssertEqual(result.inPhotos.count, 1)
        XCTAssertEqual(classification(result.inPhotos.first!), "perceptual",
                       "on-disk original should win over its derivative")
    }

    // MARK: - Cache

    func testCacheSecondRunIdentical() async throws {
        let lib = try TestFixtures.makeTempDir("audit-cache-lib")
        let folder = try TestFixtures.makeTempDir("audit-cache-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        try TestFixtures.write("SAME", to: lib.appendingPathComponent("a.jpg"))
        try TestFixtures.write("SAME", to: folder.appendingPathComponent("a.jpg"))
        try TestFixtures.write("DIFF", to: folder.appendingPathComponent("b.jpg"))

        let db = try Database.inMemory()
        let engine = AuditEngine(database: db)
        let first = try await engine.audit(folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]))
        let second = try await engine.audit(folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]))
        XCTAssertEqual(first.inPhotos.count, second.inPhotos.count)
        XCTAssertEqual(first.missing.count, second.missing.count)
        XCTAssertEqual(second.inPhotos.count, 1)
    }

    // MARK: - Filter helper

    func testFilterPartition() async throws {
        let lib = try TestFixtures.makeTempDir("audit-filter-lib")
        let folder = try TestFixtures.makeTempDir("audit-filter-folder")
        defer { TestFixtures.cleanup(lib); TestFixtures.cleanup(folder) }
        try TestFixtures.write("M", to: lib.appendingPathComponent("a.jpg"))
        try TestFixtures.write("M", to: folder.appendingPathComponent("a.jpg"))
        try TestFixtures.write("N", to: folder.appendingPathComponent("b.jpg"))
        try TestFixtures.write("O", to: folder.appendingPathComponent("c.jpg"))

        let r = try await AuditEngine().audit(folder: folder, photosLibrary: lib, mode: .exact, options: ScanOptions(kinds: [.all]))
        XCTAssertEqual(r.files(for: .all).count, 3)
        XCTAssertEqual(r.files(for: .inPhotos).count, 1)
        XCTAssertEqual(r.files(for: .missing).count, 2)
        // missingURLs never includes an in-Photos file.
        XCTAssertFalse(Set(r.missingURLs).contains(r.inPhotos.first!.url))
    }

    // MARK: - image helpers

    private func gradient(side: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<side { for x in 0..<side {
            buf[y * side + x] = UInt8(min(255, max(0, (x + y) * 255 / (2 * side - 1))))
        } }
        return ctx.makeImage()!
    }

    private func checker(side: Int, blockSize: Int = 16) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<side { for x in 0..<side {
            buf[y * side + x] = ((x / blockSize + y / blockSize) % 2 == 0) ? 0 : 255
        } }
        return ctx.makeImage()!
    }

    @discardableResult
    private func writePNG(_ image: CGImage, at url: URL) throws -> URL {
        try write(image, at: url, type: UTType.png)
    }

    @discardableResult
    private func writeJPEG(_ image: CGImage, at url: URL) throws -> URL {
        try write(image, at: url, type: UTType.jpeg)
    }

    @discardableResult
    private func write(_ image: CGImage, at url: URL, type: UTType) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "AuditEngineTests", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "AuditEngineTests", code: 2) }
        return url
    }

    /// Build a temp `.photoslibrary` with the given originals + derivatives.
    /// `originals`/`derivatives` are (relativePathUnderFolder, CGImage).
    private func makePhotosLibrary(_ label: String) throws -> URL {
        let root = try TestFixtures.makeTempDir(label)
        let lib = root.appendingPathComponent("Test.photoslibrary", isDirectory: true)
        try FileManager.default.createDirectory(
            at: lib.appendingPathComponent("originals/0", isDirectory: true),
            withIntermediateDirectories: true)
        return lib
    }
}
