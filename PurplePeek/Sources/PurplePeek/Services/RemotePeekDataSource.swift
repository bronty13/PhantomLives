import Foundation

/// `DataSource` backed by a PeekServer instance over the LAN. Maps PeekServer's wire DTOs to
/// PurplePeek's models and routes decision writes to `POST /api/decision`. Used in "remote mode"
/// (whole-app), where all roots/items/decisions come from the server instead of local GRDB.
///
/// A few `DataSource` methods have no direct PeekServer endpoint and degrade gracefully:
///  - `allFileKeywordNames` / `distinctAlbumNames`: no bulk endpoint → return empty (the grid's
///    keyword-label map and the album quick-add list are conveniences; per-file tags still load via
///    `/api/item`, and albums can still be typed). Revisit if a bulk endpoint is added.
///  - `markImported` / `markExported` / `markDeleted`: import/trash state is owned server-side
///    (`POST /api/process`); these throw `.unsupported` — the P6 import/trash pipeline drives that
///    flow directly rather than through these per-row marks.
@MainActor
final class RemotePeekDataSource: DataSource {
    let client: PeekServerClient

    init(connection: PeekServerConnection, password: String, session: URLSession = .shared) {
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
            fileModifiedAt: nil,
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
            createdAt: "",                  // PeekServer's item list omits these; not shown in review UI
            updatedAt: ""
        )
    }

    // MARK: Reads

    func fetchAllScanRoots() async throws -> [ScanRoot] {
        try await client.roots().map(Self.map)
    }

    func fetchMediaFiles(scanRoot: String) async throws -> [MediaFile] {
        // /api/items caps at 500/page → page through until we've collected `total`.
        var out: [MediaFile] = []
        var offset = 0
        let limit = 500
        while true {
            let page = try await client.items(root: scanRoot, offset: offset, limit: limit)
            out.append(contentsOf: page.items.map(Self.map))
            offset += page.items.count
            if page.items.isEmpty || out.count >= page.total { break }
        }
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
