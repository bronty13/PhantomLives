import Foundation

/// Thin async client for an Ollama HTTP server (`ollama serve`, default
/// `http://localhost:11434`). Ollama's API is documented at
/// https://github.com/ollama/ollama/blob/main/docs/api.md.
///
/// We use three endpoints:
/// - `/api/version` — health check ("is Ollama running?").
/// - `/api/tags`    — list installed models for the Setup picker.
/// - `/api/chat`    — message-list completion. Non-streaming for the MVP;
///   streaming token-by-token can be layered later for the suggestion bar
///   without changing this client's call sites.
///
/// Errors propagate as `OllamaClient.Error`. Network errors include the
/// underlying URLError so the UI can surface "is Ollama running?" vs.
/// "model not found" distinctly.
struct OllamaClient {
    let baseURL: URL

    enum Error: Swift.Error, LocalizedError {
        case invalidBaseURL(String)
        case nonLocalHost(String)
        case transport(URLError)
        case httpStatus(Int, body: String)
        case decoding(String)
        case modelNotFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL(let s):     return "Bad Ollama URL: \(s) — use a full http(s) URL like http://localhost:11434"
            case .nonLocalHost(let h):       return "The assistant only talks to a local Ollama. '\(h)' looks like a public host — your private chat would leave this machine, so the request was blocked. Use localhost or a LAN address."
            case .transport(let err):        return "Network error: \(err.localizedDescription)"
            case .httpStatus(let code, let body):
                return "Ollama returned HTTP \(code): \(body.prefix(200))"
            case .decoding(let detail):      return "Decoding failed: \(detail)"
            case .modelNotFound(let name):   return "Model `\(name)` is not installed (`ollama pull \(name)`)"
            }
        }
    }

    /// Request timeouts. Health/list calls should fail fast; a chat
    /// generation can legitimately take a while on a big model, but is
    /// still bounded so a stalled server can't wedge the suggestion strip
    /// forever (and an engaged buffer that's disengaged cancels the Task).
    private static let healthTimeout: TimeInterval = 10
    private static let chatTimeout: TimeInterval = 60

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Convenience init with explicit error handling — used by ChatModel /
    /// Setup when constructing from a user-entered string. Validates that
    /// the URL is a well-formed http(s) endpoint (a bare `localhost:11434`
    /// has no scheme and is rejected) AND that the host is local/LAN, so
    /// private chat content can't be POSTed to an arbitrary public server.
    init(rawURL: String) throws {
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            throw Error.invalidBaseURL(rawURL)
        }
        guard Self.isLocalHost(host) else { throw Error.nonLocalHost(host) }
        self.baseURL = url
    }

    /// True when `host` is loopback, an RFC1918 / link-local IPv4 literal,
    /// an IPv6 loopback / link-local / unique-local literal, an mDNS/intranet
    /// name (`*.local`, `*.lan`, `*.internal`, `*.home`), or a single-label
    /// host (no dots) — i.e. somewhere on this machine or its LAN. A public
    /// hostname or routable IP returns false.
    static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return true }
        if h.hasSuffix(".local") || h.hasSuffix(".lan")
            || h.hasSuffix(".internal") || h.hasSuffix(".home")
            || h.hasSuffix(".localdomain") { return true }
        // IPv4 literal → check the routability blocks.
        let octets = h.split(separator: ".").compactMap { UInt32($0) }
        if octets.count == 4, octets.allSatisfy({ $0 <= 255 }) {
            if octets[0] == 127 { return true }                           // loopback
            if octets[0] == 10 { return true }                            // 10/8
            if octets[0] == 192 && octets[1] == 168 { return true }       // 192.168/16
            if octets[0] == 172 && (16...31).contains(octets[1]) { return true } // 172.16/12
            if octets[0] == 169 && octets[1] == 254 { return true }       // link-local
            return false                                                  // routable IPv4
        }
        // IPv6 link-local (fe80::/10) or unique-local (fc00::/7).
        if h.hasPrefix("fe80") || h.hasPrefix("fc") || h.hasPrefix("fd") { return true }
        // Single-label intranet name (no dots, not an IPv6 literal).
        if !h.contains(".") && !h.contains(":") { return true }
        return false
    }

    // MARK: - Wire types

    /// One message in a chat conversation. Roles match Ollama's
    /// expectation: "system", "user", "assistant".
    struct Message: Codable, Hashable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options?
        struct Options: Encodable {
            var temperature: Double?
            var num_predict: Int?
        }
    }

    private struct ChatResponse: Decodable {
        let model: String
        let message: Message
        let done: Bool
    }

    private struct TagsResponse: Decodable {
        let models: [Tag]
        struct Tag: Decodable, Hashable {
            let name: String
            let size: Int64?
            let modified_at: String?
        }
    }

    private struct VersionResponse: Decodable {
        let version: String
    }

    // MARK: - Health + list

    /// Hit `/api/version`. Used by Setup to verify the URL works before
    /// the user wades into model picking.
    func version() async throws -> String {
        let body: VersionResponse = try await get("/api/version")
        return body.version
    }

    /// Names of every locally-installed model — feeds the Setup model
    /// picker. Returned in the order Ollama reports.
    func listModels() async throws -> [String] {
        let body: TagsResponse = try await get("/api/tags")
        return body.models.map { $0.name }
    }

    // MARK: - Chat

    /// Single non-streaming chat completion. Returns the assistant's
    /// reply text. Streaming would let the suggestion bar fade in
    /// token-by-token; not worth the wiring for the MVP.
    func chat(model: String,
              messages: [Message],
              temperature: Double = 0.7,
              maxTokens: Int = 200) async throws -> String {
        let req = ChatRequest(
            model: model,
            messages: messages,
            stream: false,
            options: .init(temperature: temperature, num_predict: maxTokens))
        let body: ChatResponse = try await post("/api/chat", body: req)
        return body.message.content
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.timeoutInterval = Self.healthTimeout
        return try await send(req)
    }

    private func post<Req: Encodable, Resp: Decodable>(
        _ path: String, body: Req) async throws -> Resp
    {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = Self.chatTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw Error.decoding("encode \(Req.self): \(error)")
        }
        return try await send(req)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlErr as URLError {
            throw Error.transport(urlErr)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            // Ollama uses a 404 with `{"error":"model 'foo' not found"}`
            // when you ask for a model that isn't installed. Translate.
            if http.statusCode == 404,
               let s = String(data: data, encoding: .utf8),
               s.contains("not found") {
                throw Error.modelNotFound(extractedModelName(from: s))
            }
            throw Error.httpStatus(http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw Error.decoding("decode \(T.self): \(error). body=\(preview)")
        }
    }

    /// Best-effort extraction of the missing model name from Ollama's
    /// 404 body. Falls back to "unknown" so the error message at least
    /// flags the right action.
    private func extractedModelName(from body: String) -> String {
        if let firstQuote = body.firstIndex(of: "'"),
           let close = body[body.index(after: firstQuote)...].firstIndex(of: "'") {
            return String(body[body.index(after: firstQuote)..<close])
        }
        return "unknown"
    }
}
