import XCTest
@testable import PurpleDedupCore

/// Tests the Apple Photos library auto-detection / auto-lock behaviour. We
/// build a fake `.photoslibrary` directory tree (it's just a folder under
/// the hood) and assert the walker traverses only `originals/` and that
/// `TrashManager` refuses to delete anything that lands in it.
final class PhotosLibraryTests: XCTestCase {

    func testScanSourceAutoLocksPhotosLibrary() {
        let regular = ScanSource(url: URL(fileURLWithPath: "/tmp/some-folder"))
        XCTAssertFalse(regular.isLocked)
        XCTAssertFalse(regular.isPhotosLibrary)

        let lib = ScanSource(url: URL(fileURLWithPath: "/Users/me/Pictures/Photos.photoslibrary"))
        XCTAssertTrue(lib.isLocked, "A .photoslibrary source must be auto-locked")
        XCTAssertTrue(lib.isPhotosLibrary)
    }

    func testWalkerOnlyTraversesOriginalsSubdirectoryOfPhotosLibrary() async throws {
        let dir = try TestFixtures.makeTempDir("photoslib")
        defer { TestFixtures.cleanup(dir) }

        // Build a fake `.photoslibrary` package: originals/ contains user
        // photos, database/ and resources/ contain Photos.app internals that
        // should NEVER appear in scan results.
        let lib = dir.appendingPathComponent("Test.photoslibrary")
        let originals = lib.appendingPathComponent("originals")
        let database = lib.appendingPathComponent("database")
        let derivatives = lib.appendingPathComponent("resources/derivatives")
        try TestFixtures.write("photo-bytes-A", to: originals.appendingPathComponent("A/IMG_001.jpg"))
        try TestFixtures.write("photo-bytes-B", to: originals.appendingPathComponent("B/IMG_002.jpg"))
        try TestFixtures.write("photoskit-internal", to: database.appendingPathComponent("Photos.sqlite"))
        try TestFixtures.write("thumb", to: derivatives.appendingPathComponent("derivative.jpg"))

        var seen: [String] = []
        for try await f in FileWalker().walk(
            sources: [ScanSource(url: lib)],
            options: ScanOptions(kinds: [.photo])
        ) {
            seen.append(f.url.lastPathComponent)
            XCTAssertTrue(f.isLocked, "Files inside .photoslibrary must surface as locked")
        }
        XCTAssertEqual(Set(seen), Set(["IMG_001.jpg", "IMG_002.jpg"]))
    }

    func testTrashManagerRefusesPhotosLibraryFiles() throws {
        let dir = try TestFixtures.makeTempDir("photoslib-trash")
        defer { TestFixtures.cleanup(dir) }
        let lib = dir.appendingPathComponent("Test.photoslibrary")
        let f = lib.appendingPathComponent("originals/A/IMG_001.jpg")
        try TestFixtures.write("photo", to: f)

        // Synthetic DiscoveredFile with isLocked=false to exercise the
        // belt-and-braces path check (the lock guard would normally catch
        // this first).
        let unlocked = DiscoveredFile(
            url: f, sizeBytes: 5,
            modificationTime: Date(), isLocked: false
        )
        let manager = TrashManager()
        XCTAssertThrowsError(try manager.move(unlocked, to: .trash)) { error in
            guard case TrashManager.TrashError.insidePhotosLibrary = error else {
                return XCTFail("Expected .insidePhotosLibrary, got \(error)")
            }
        }
    }
}
