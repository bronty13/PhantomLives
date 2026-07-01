import Foundation

/// Where a PeekServer instance lives + who we are to it. The password is NOT stored here
/// (it lives in the Keychain, keyed by `account`); it's supplied to `PeekServerClient` at use.
struct PeekServerConnection: Codable, Equatable {
    var host: String
    var port: Int
    var user: String

    /// Keychain account key for this connection's password.
    var account: String { "\(user)@\(host):\(port)" }

    var baseURL: URL? {
        var c = URLComponents()
        c.scheme = "http"          // trusted LAN; PeekServer serves plain HTTP
        c.host = host
        c.port = port
        return c.url
    }
}

enum PeekServerError: LocalizedError {
    case notConfigured
    case badResponse(Int)
    case notFound
    case decoding(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:      return "No PeekServer connection is configured."
        case .badResponse(let c): return "PeekServer returned HTTP \(c)."
        case .notFound:           return "The requested item was not found on PeekServer."
        case .decoding(let m):    return "Couldn't read PeekServer's response: \(m)"
        case .unsupported(let m): return m
        }
    }
}

// MARK: - Wire DTOs (decode PeekServer's JSON exactly, incl. its Int 0/1 booleans)

/// One row from `GET /api/roots` (`roots_with_counts`). `total` is a COUNT; the SUM columns
/// (`undecided`/`kept`/`skipped`) are null when a root has no rows.
struct PeekRootDTO: Decodable {
    let path: String
    let label: String?
    let kind: String?
    let last_scanned_at: String?
    let sort_order: Int?
    let total: Int
    let undecided: Int?
    let kept: Int?
    let skipped: Int?
}

/// One row from `GET /api/items` (`list_media`). `is_favorite`/`is_hidden` arrive as ints 0/1;
/// `keep` is null/0/1. Fields PeekServer doesn't return here (created/updated/modified/hash) are
/// filled with defaults when mapping to `MediaFile`.
struct PeekItemDTO: Decodable {
    let id: String
    let scan_root: String
    let file_path: String
    let file_name: String
    let file_type: String
    let file_size: Int64?
    let keep: Int?
    let is_favorite: Int
    let title: String?
    let caption: String?
    let is_hidden: Int
    let imported_at: String?
    let photos_asset_id: String?
}

struct PeekItemsResponse: Decodable {
    let total: Int
    let items: [PeekItemDTO]
}

struct PeekRootsResponse: Decodable {
    let roots: [PeekRootDTO]
    let scanning: Bool
}

/// `GET /api/item/<id>` returns the full media row plus these two lists. We only need the lists;
/// `Decodable` ignores the other columns.
struct PeekItemDetailDTO: Decodable {
    let keywords: [String]
    let albums: [String]
}

// MARK: - Client

/// Thin async HTTP client for PeekServer's JSON API. Pure transport + typed decoding — no model
/// mapping (that's `RemotePeekDataSource`). Safe to call from `@MainActor`: `URLSession`'s async
/// methods suspend cooperatively, they don't block the actor.
struct PeekServerClient {
    let connection: PeekServerConnection
    let password: String
    var session: URLSession = .shared

    private var authHeader: String {
        let raw = "\(connection.user):\(password)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    private func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let base = connection.baseURL else { throw PeekServerError.notConfigured }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { comps?.queryItems = query }
        guard let url = comps?.url else { throw PeekServerError.notConfigured }
        var req = URLRequest(url: url)
        if !connection.user.isEmpty {
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// GET a JSON endpoint and decode it. 404 → `.notFound` so callers can treat a missing item
    /// as nil rather than a hard error.
    private func getJSON<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let req = try request(path: path, query: query)
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw PeekServerError.notFound }
        guard code == 200 else { throw PeekServerError.badResponse(code) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw PeekServerError.decoding(String(describing: error)) }
    }

    // MARK: Endpoints

    func roots() async throws -> [PeekRootDTO] {
        try await getJSON("/api/roots", as: PeekRootsResponse.self).roots
    }

    func items(root: String, decision: String = "all", offset: Int = 0, limit: Int = 500) async throws -> PeekItemsResponse {
        try await getJSON("/api/items", query: [
            .init(name: "root", value: root),
            .init(name: "decision", value: decision),
            .init(name: "offset", value: String(offset)),
            .init(name: "limit", value: String(limit)),
        ], as: PeekItemsResponse.self)
    }

    func item(id: String) async throws -> PeekItemDetailDTO {
        try await getJSON("/api/item/\(id)", as: PeekItemDetailDTO.self)
    }

    /// POST a partial decision. CRITICAL: send ONLY the keys being changed — PeekServer's
    /// `update_decision` writes every key present in the body, so including a nil'd field would
    /// clear it. Values are the raw wire types (keep as Int/NSNull, is_favorite as 0/1, arrays of
    /// names for keywords/albums).
    func postDecision(id: String, fields: [String: Any]) async throws {
        guard let base = connection.baseURL else { throw PeekServerError.notConfigured }
        var req = URLRequest(url: base.appendingPathComponent("/api/decision"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !connection.user.isEmpty { req.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        var body = fields
        body["id"] = id
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw PeekServerError.badResponse(code) }
    }

    /// Fire `POST /api/scan` to have the server re-discover files under all roots.
    func triggerScan() async throws {
        guard let base = connection.baseURL else { throw PeekServerError.notConfigured }
        var req = URLRequest(url: base.appendingPathComponent("/api/scan"))
        req.httpMethod = "POST"
        if !connection.user.isEmpty { req.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        let (_, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw PeekServerError.badResponse(code) }
    }
}
