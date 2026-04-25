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
        case transport(URLError)
        case httpStatus(Int, body: String)
        case decoding(String)
        case modelNotFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL(let s):     return "Bad Ollama URL: \(s)"
            case .transport(let err):        return "Network error: \(err.localizedDescription)"
            case .httpStatus(let code, let body):
                return "Ollama returned HTTP \(code): \(body.prefix(200))"
            case .decoding(let detail):      return "Decoding failed: \(detail)"
            case .modelNotFound(let name):   return "Model `\(name)` is not installed (`ollama pull \(name)`)"
            }
        }
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Convenience init with explicit error handling — used by ChatModel
    /// when constructing from user-entered settings.
    init(rawURL: String) throws {
        guard let url = URL(string: rawURL) else { throw Error.invalidBaseURL(rawURL) }
        self.baseURL = url
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
        return try await send(req)
    }

    private func post<Req: Encodable, Resp: Decodable>(
        _ path: String, body: Req) async throws -> Resp
    {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
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
