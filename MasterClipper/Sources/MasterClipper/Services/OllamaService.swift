import Foundation

@MainActor
final class OllamaService: ObservableObject {
    @Published var availableModels: [String] = []
    @Published var isReachable: Bool = false
    @Published var lastError: String? = nil

    static let shared = OllamaService()

    private init() {}

    func baseURL(from settings: AppSettings) -> URL {
        URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
    }

    func checkConnection(settings: AppSettings) async {
        let url = baseURL(from: settings).appendingPathComponent("api/tags")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                availableModels = models.compactMap { $0["name"] as? String }
            }
            isReachable = true
            lastError = nil
        } catch {
            isReachable = false
            lastError = error.localizedDescription
        }
    }

    /// If the configured model isn't installed but other models are, return the
    /// first installed model so the caller can offer it as a default. Returns nil
    /// when the configured model is fine or no models are installed.
    func suggestedFallbackModel(currentModel: String) -> String? {
        guard !availableModels.isEmpty else { return nil }
        if availableModels.contains(currentModel) { return nil }
        return availableModels.first
    }

    /// Stream a refinement. Off-actor so URLSession streaming doesn't block the main
    /// thread. `onToken` is called on the main actor for each streamed chunk.
    /// Throws on HTTP error, JSON `error` field, or transport failure — every
    /// failure is visible.
    nonisolated static func refine(
        description: String,
        promptTemplate: String,
        model: String,
        baseURLString: String,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws {
        let prompt = promptTemplate.replacingOccurrences(of: "{{description}}", with: description)
        let baseURL = URL(string: baseURLString) ?? URL(string: "http://localhost:11434")!
        let url = baseURL.appendingPathComponent("api/chat")

        // Greedy decoding (temperature 0, top_p 1) for the proofread task.
        // Any creativity is a regression: we want the model to pick the most
        // likely next token every time, which closely matches "echo input back
        // with minimal fixes". `num_predict` left generous to handle long
        // descriptions; `repeat_penalty` lowered so the model doesn't avoid
        // repeating words the creator used (the input may legitimately repeat
        // body-part / slang terms many times).
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": true,
            "options": [
                "temperature": 0.0,
                "top_p": 1.0,
                "repeat_penalty": 1.0,
                "num_predict": 1500
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        // Surface HTTP errors. Body of an Ollama 404 looks like
        //   {"error":"model \"dolphin-mistral\" not found, try pulling it first"}
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var collected = Data()
            for try await chunk in asyncBytes { collected.append(chunk) }
            let bodyStr = String(data: collected, encoding: .utf8) ?? ""
            if let json = try? JSONSerialization.jsonObject(with: collected) as? [String: Any],
               let err = json["error"] as? String {
                throw OllamaError.api(status: http.statusCode, message: err)
            }
            throw OllamaError.api(status: http.statusCode, message: bodyStr.isEmpty ? "(empty body)" : bodyStr)
        }

        for try await line in asyncBytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if let err = json["error"] as? String {
                throw OllamaError.api(status: 0, message: err)
            }
            if let msg = json["message"] as? [String: Any],
               let content = msg["content"] as? String,
               !content.isEmpty {
                await onToken(content)
            }
            if let done = json["done"] as? Bool, done { break }
        }
    }
}

enum OllamaError: Error, LocalizedError {
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .api(let status, let message):
            if status == 0 { return message }
            return "Ollama HTTP \(status): \(message)"
        }
    }
}
