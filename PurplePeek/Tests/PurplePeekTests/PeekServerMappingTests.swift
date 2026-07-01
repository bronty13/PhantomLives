import XCTest
@testable import PurplePeek

/// Verifies PurplePeek decodes PeekServer's exact JSON (incl. its Int 0/1 booleans) and maps it to
/// PurplePeek's models correctly. Hermetic — sample JSON strings, no live server. The sample bodies
/// mirror the shapes emitted by `db.roots_with_counts` / `db.list_media` / `db.get_media`.
final class PeekServerMappingTests: XCTestCase {

    // MARK: Roots

    func testDecodeAndMapRoots() throws {
        let json = """
        {"roots": [
          {"path": "/Volumes/ROG_AIRY/Rachel NEW PHOTOS TO REVIEW", "label": "Rachel — Photos",
           "kind": "photos", "last_scanned_at": "2026-06-30T23:37:04Z", "sort_order": 1,
           "total": 977, "undecided": 90, "kept": 81, "skipped": 806},
          {"path": "/Volumes/REDONE/Empty", "label": null, "kind": "photos",
           "last_scanned_at": null, "sort_order": 0, "total": 0,
           "undecided": null, "kept": null, "skipped": null}
        ], "scanning": true}
        """
        let resp = try JSONDecoder().decode(PeekRootsResponse.self, from: Data(json.utf8))
        XCTAssertTrue(resp.scanning)
        XCTAssertEqual(resp.roots.count, 2)

        let r0 = RemotePeekDataSource.map(resp.roots[0])
        XCTAssertEqual(r0.path, "/Volumes/ROG_AIRY/Rachel NEW PHOTOS TO REVIEW")
        XCTAssertEqual(r0.label, "Rachel — Photos")
        XCTAssertEqual(r0.totalFiles, 977)        // COUNT → totalFiles
        XCTAssertEqual(r0.sortOrder, 1)
        XCTAssertNil(r0.sectionId)                 // remote roots never carry a local section
        XCTAssertEqual(r0.displayName, "Rachel — Photos")

        // Missing last_scanned_at (null) must default, not crash; label nil → displayName falls back.
        let r1 = RemotePeekDataSource.map(resp.roots[1])
        XCTAssertEqual(r1.lastScannedAt, "")
        XCTAssertEqual(r1.displayName, "Empty")
    }

    // MARK: Items

    func testDecodeAndMapItemsIntBooleansAndKeepTriState() throws {
        let json = """
        {"total": 3, "items": [
          {"id": "4110bbb8fbcb0858", "scan_root": "/r", "file_path": "/r/a.mov", "file_name": "a.mov",
           "file_type": "video", "file_size": 28436469, "keep": 0, "is_favorite": 0, "title": null,
           "caption": "UGC Ice Cream Shop", "is_hidden": 0, "imported_at": null, "photos_asset_id": null},
          {"id": "abc", "scan_root": "/r", "file_path": "/r/b.jpg", "file_name": "b.jpg",
           "file_type": "photo", "file_size": null, "keep": 1, "is_favorite": 1, "title": "Hi",
           "caption": null, "is_hidden": 1, "imported_at": "2026-06-30T00:00:00Z", "photos_asset_id": "AX/1"},
          {"id": "def", "scan_root": "/r", "file_path": "/r/c.png", "file_name": "c.png",
           "file_type": "photo", "file_size": 10, "keep": null, "is_favorite": 0, "title": null,
           "caption": null, "is_hidden": 0, "imported_at": null, "photos_asset_id": null}
        ]}
        """
        let resp = try JSONDecoder().decode(PeekItemsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.total, 3)

        let a = RemotePeekDataSource.map(resp.items[0])
        XCTAssertEqual(a.id, "4110bbb8fbcb0858")           // PeekServer's sha1 id passes through
        XCTAssertEqual(a.mediaType, .video)
        XCTAssertEqual(a.keepDecision, false)              // keep 0 → skip
        XCTAssertFalse(a.isFavorite)                       // Int 0 → false
        XCTAssertEqual(a.caption, "UGC Ice Cream Shop")
        XCTAssertNil(a.title)

        let b = RemotePeekDataSource.map(resp.items[1])
        XCTAssertEqual(b.keepDecision, true)               // keep 1 → keep
        XCTAssertTrue(b.isFavorite)                        // Int 1 → true
        XCTAssertTrue(b.isHidden)                          // Int 1 → true
        XCTAssertTrue(b.isImported)                        // imported_at present
        XCTAssertEqual(b.photosAssetId, "AX/1")
        XCTAssertNil(b.fileSize)

        let c = RemotePeekDataSource.map(resp.items[2])
        XCTAssertNil(c.keepDecision)                       // keep null → undecided
        XCTAssertEqual(c.fileSize, 10)
    }

    func testImageFileTypeMapsToPhoto() {
        // PeekServer emits file_type "image" for photos; must map to MediaType.photo.
        let dto = PeekItemDTO(id: "x", scan_root: "/r", file_path: "/r/p.jpg", file_name: "p.jpg",
                              file_type: "image", file_size: 1, keep: nil, is_favorite: 0,
                              title: nil, caption: nil, is_hidden: 0, imported_at: nil, photos_asset_id: nil)
        XCTAssertEqual(RemotePeekDataSource.map(dto).mediaType, .photo)
    }

    func testDecodeItemDetailKeywordsAndAlbums() throws {
        // /api/item returns SELECT * plus these two lists; decoding must ignore the extra columns.
        let json = """
        {"id": "abc", "scan_root": "/r", "file_path": "/r/b.jpg", "file_name": "b.jpg",
         "file_type": "photo", "keep": 1, "is_favorite": 0, "created_at": "x", "updated_at": "y",
         "keywords": ["Beach", "Summer"], "albums": ["Highlights"]}
        """
        let detail = try JSONDecoder().decode(PeekItemDetailDTO.self, from: Data(json.utf8))
        XCTAssertEqual(detail.keywords, ["Beach", "Summer"])
        XCTAssertEqual(detail.albums, ["Highlights"])
    }

    // MARK: Connection + auth

    func testConnectionAccountAndBaseURL() {
        let c = PeekServerConnection(host: "10.0.0.59", port: 8788, user: "peek")
        XCTAssertEqual(c.account, "peek@10.0.0.59:8788")     // Keychain key
        XCTAssertEqual(c.baseURL?.absoluteString, "http://10.0.0.59:8788")
    }
}
