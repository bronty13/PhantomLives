import Foundation

/// `DataSource` backed by a PeekServer instance over the LAN. Maps PeekServer's wire DTOs to
/// PurplePeek's models and routes decision writes to `POST /api/decision`. Used in "remote mode"
/// (whole-app), where all roots/items/decisions come from the server instead of local GRDB.
///
/// A few `DataSource` methods have no direct PeekServer endpoint and degrade gracefully:
///  - `allFileKeywordNames` / `distinctAlbumNames`: no bulk endpoint → return empty (the grid's
///    keyword-label map and the album quick-add list are conveniences; per-file tags still load via
///    `/api/item`, and albums can still be typed). Revisit if a bulk endpoint is added.
///  - `markImported` / `markExported` / `markDeleted` are fully implemented (P6, client-side
///    import model): they record the client's import/export on the server and route deletes to
///    the server-side headless trash (`POST /api/trash`).
@MainActor
final class RemotePeekDataSource: DataSource {
    let client: PeekServerClient

    init(connection: PeekServerConnection, password: String, session: URLSession = PeekTransport.interactive) {
        self.client = PeekServerClient(connection: connection, password: password, session: session)
    }

    // MARK: DTO → model mapping (static + pure, so it's unit-testable without a live server)

    nonisolated static func map(_ r: PeekRootDTO) -> ScanRoot {
        ScanRoot(
            path: r.path,
            lastScannedAt: r.last_scanned_at ?? "",
            totalFiles: r.total,
            label: r.label,
            sectionId: nil,                 // remote roots have no local sidebar sections
            sortOrder: r.sort_order ?? 0
        )
    }

    nonisolated static func map(_ i: PeekItemDTO) -> MediaFile {
        MediaFile(
            id: i.id,
            scanRoot: i.scan_root,
            filePath: i.file_path,
            fileName: i.file_name,
            // PeekServer classifies photos as "image"; PurplePeek's MediaType uses "photo".
            fileType: i.file_type == "image" ? "photo" : i.file_type,
            fileSize: i.file_size,
            fileModifiedAt: i.file_modified_at,
            keep: i.keep,
            isFavorite: i.is_favorite != 0,
            isHidden: i.is_hidden != 0,
            title: i.title,
            caption: i.caption,
            importedAt: i.imported_at,
            exportedAt: nil,
            deletedAt: nil,
            missingAt: nil,
            contentHash: nil,
            photosAssetId: i.photos_asset_id,
            createdAt: i.created_at ?? "",  // first-seen = "arrived" (Date filter basis, ≥0.7.2)
            updatedAt: ""
        )
    }

    // MARK: Reads

    func fetchAllScanRoots() async throws -> [ScanRoot] {
        try await client.roots().map(Self.map)
    }

    func fetchMediaFiles(scanRoot: String) async throws -> [MediaFile] {
        // /api/items caps at 500/page. Fetch page 1 to learn `total`, then pull the REST of the
        // pages concurrently — strictly-serial paging cost one Wi-Fi round trip per 500 items
        // (a 20k-item root = 40 sequential RTTs of blank grid). Order is restored by offset.
        let limit = 500
        let first = try await client.items(root: scanRoot, offset: 0, limit: limit)
        var out = first.items.map(Self.map)
        guard !first.items.isEmpty, out.count < first.total else { return out }
        let client = self.client
        let rest = try await withThrowingTaskGroup(of: (Int, [MediaFile]).self) { group in
            for offset in stride(from: out.count, to: first.total, by: limit) {
                group.addTask {
                    (offset, try await client.items(root: scanRoot, offset: offset, limit: limit).items.map(Self.map))
                }
            }
            var pages: [(Int, [MediaFile])] = []
            for try await page in group { pages.append(page) }
            return pages.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        }
        out.append(contentsOf: rest)
        return out
    }

    func allFileKeywordNames() async throws -> [String: [String]] {
        [:]  // no bulk endpoint; see type doc
    }

    func keywordNames(forFile fileId: String) async throws -> [String] {
        try await client.item(id: fileId).keywords
    }

    func albums(forFile fileId: String) async throws -> [String] {
        try await client.item(id: fileId).albums
    }

    /// One `/api/item` fetch for both lists — the default protocol composition would hit the
    /// same endpoint twice per selection change (2× Wi-Fi RTT for one JSON document).
    func tagDetail(forFile fileId: String) async throws -> (keywords: [String], albums: [String]) {
        let detail = try await client.item(id: fileId)
        return (detail.keywords, detail.albums)
    }

    func distinctAlbumNames() async throws -> [String] {
        []  // no endpoint; see type doc
    }

    // MARK: Decision writes → POST /api/decision (send ONLY the changed field)

    func updateKeep(id: String, keep: Int?, now: String) async throws {
        try await client.postDecision(id: id, fields: ["keep": keep ?? NSNull()])
    }

    func updateFavorite(id: String, isFavorite: Bool, now: String) async throws {
        try await client.postDecision(id: id, fields: ["is_favorite": isFavorite ? 1 : 0])
    }

    func updateHidden(id: String, isHidden: Bool, now: String) async throws {
        try await client.postDecision(id: id, fields: ["is_hidden": isHidden ? 1 : 0])
    }

    func updateTitle(id: String, title: String?, now: String) async throws {
        try await client.postDecision(id: id, fields: ["title": title ?? NSNull()])
    }

    func updateCaption(id: String, caption: String?, now: String) async throws {
        try await client.postDecision(id: id, fields: ["caption": caption ?? NSNull()])
    }

    func setAlbums(fileId: String, albumNames: [String]) async throws {
        try await client.postDecision(id: fileId, fields: ["albums": albumNames])
    }

    func setKeywordNames(fileId: String, names: [String]) async throws {
        try await client.postDecision(id: fileId, fields: ["keywords": names])
    }

    // MARK: Import/trash state (client-side import model — see P6)

    /// Record that the client imported this keeper to ITS OWN Photos library.
    func markImported(id: String, assetId: String?, now: String) async throws {
        try await client.markImported(id: id, assetId: assetId)
    }
    /// Record a client audio keep-export.
    func markExported(id: String, now: String) async throws {
        try await client.markExported(id: id)
    }
    /// Trash a rejected review file server-side (recoverable, headless).
    func markDeleted(id: String, now: String) async throws {
        try await client.trash(id: id)
    }
}
