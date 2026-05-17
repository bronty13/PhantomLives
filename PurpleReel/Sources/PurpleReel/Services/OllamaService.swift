import Foundation

/// Local LLM access via Ollama's HTTP API (`localhost:11434`). All
/// generation happens on-device; no data leaves the machine.
enum OllamaService {

    enum OllamaError: Error, LocalizedError {
        case serverUnreachable
        case httpStatus(Int, String)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .serverUnreachable:
                return "Ollama isn't responding at http://localhost:11434. Install from ollama.com and run `ollama serve`."
            case .httpStatus(let code, let body):
                return "Ollama HTTP \(code): \(body.prefix(200))"
            case .decodeFailed:
                return "Could not decode Ollama response"
            }
        }
    }

    static let defaultModel = "llama3.2:1b"
    static let endpoint = URL(string: "http://localhost:11434/api/generate")!

    /// Generate a short clip description from filename + transcript
    /// snippet. Prompt is intentionally narrow so a small model
    /// (1B-3B params) returns useful text quickly.
    static func describe(filename: String,
                          transcriptSnippet: String?,
                          model: String = defaultModel) async throws -> String {
        var prompt = "You are a video editor describing a clip in 1-2 sentences for a media catalogue. "
        prompt += "Be concrete; no marketing language. "
        prompt += "Filename: \(filename)\n"
        if let snippet = transcriptSnippet, !snippet.isEmpty {
            let clipped = String(snippet.prefix(800))
            prompt += "Dialogue excerpt: \(clipped)\n"
        }
        prompt += "Description:"
        return try await generate(model: model, prompt: prompt)
    }

    /// Low-level generate. `stream:false` → single JSON response.
    static func generate(model: String, prompt: String) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw OllamaError.serverUnreachable
            }
            if http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw OllamaError.httpStatus(http.statusCode, body)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? String else {
                throw OllamaError.decodeFailed
            }
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let e as OllamaError {
            throw e
        } catch {
            // URLSession will throw NSURLErrorCannotConnectToHost when
            // Ollama isn't running locally — surface that as a clearer
            // unreachable error.
            throw OllamaError.serverUnreachable
        }
    }

    /// Quick reachability probe — used to gate the Auto-Describe menu
    /// item so we don't surprise users with a long timeout.
    static func isReachable() async -> Bool {
        var req = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        req.timeoutInterval = 1.0
        req.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
