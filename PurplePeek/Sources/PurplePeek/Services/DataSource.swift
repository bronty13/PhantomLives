import Foundation

/// The seam between PurplePeek's UI/state layer and wherever its review data lives.
///
/// In **local mode** this is `DatabaseService` (GRDB over the on-disk `purplepeek.sqlite`);
/// in **remote mode** it's `RemotePeekDataSource` (URLSession over a PeekServer instance on the
/// LAN). `AppState` holds a `DataSource` for exactly the operations a PeekServer-connected session
/// reaches — "list roots, list media, read a file's tags, record a decision" — which is precisely
/// PeekServer's JSON API surface.
///
/// Everything NOT on this protocol stays on the concrete `DatabaseService` and never goes remote:
/// folder scanning + duplicate hashing (server-side `POST /api/scan` in remote mode), the sidebar
/// section CRUD + root ordering/management (a local organizing feature — remote roots come from
/// `/api/roots`), and the keyword *vocabulary* CRUD (remote tagging sends keyword *names* via
/// `POST /api/decision`; the local keyword table remains the picker's convenience vocabulary).
///
/// Methods are `async throws`: the local impl's synchronous GRDB bodies satisfy the async
/// requirements directly (Swift lets a synchronous function witness an `async` requirement — on
/// the `@MainActor` local impl the call runs inline), while the remote impl genuinely suspends on
/// URLSession. Both conformers are `@MainActor`, so the whole seam stays on the main actor and no
/// cross-actor hops are introduced.
@MainActor
protocol DataSource {
    // MARK: Reads — the reviewable data set
    func fetchAllScanRoots() async throws -> [ScanRoot]
    func fetchMediaFiles(scanRoot: String) async throws -> [MediaFile]
    /// file_id → sorted keyword names, for every tagged file (bulk grid label/filter map).
    func allFileKeywordNames() async throws -> [String: [String]]
    func keywordNames(forFile fileId: String) async throws -> [String]
    func albums(forFile fileId: String) async throws -> [String]
    func distinctAlbumNames() async throws -> [String]

    // MARK: Decision writes — one row's review state
    func updateKeep(id: String, keep: Int?, now: String) async throws
    func updateFavorite(id: String, isFavorite: Bool, now: String) async throws
    func updateHidden(id: String, isHidden: Bool, now: String) async throws
    func updateTitle(id: String, title: String?, now: String) async throws
    func updateCaption(id: String, caption: String?, now: String) async throws
    func setAlbums(fileId: String, albumNames: [String]) async throws
    func markImported(id: String, assetId: String?, now: String) async throws
    func markExported(id: String, now: String) async throws
    func markDeleted(id: String, now: String) async throws
}

/// `DatabaseService`'s existing synchronous, `@MainActor` methods witness every `async throws`
/// requirement above verbatim — so local mode is the classic app with zero behavior change.
extension DatabaseService: DataSource {}
