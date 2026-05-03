import Foundation

@MainActor
class OllamaService: ObservableObject {
    @Published var availableModels: [OllamaModel] = []
    @Published var selectedModel: String
    @Published var isConnected: Bool = false

    private let baseURL = "http://localhost:11434"

    init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "dolphin-mistral"
        Task { await checkConnection() }
    }

    func checkConnection() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
            availableModels = response.models
            isConnected = true
        } catch {
            isConnected = false
        }
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedModel")
    }

    func generateResponse(
        messages: [Message],
        character: Character,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) async throws {
        let model = character.preferredModel ?? selectedModel

        var payload: [[String: String]] = [["role": "system", "content": character.systemPrompt]]
        for msg in messages where msg.role != .system {
            payload.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": payload,
            "stream": true,
            "options": [
                "temperature": 0.88,
                "top_p": 0.9,
                "num_predict": 700
            ]
        ]

        guard let url = URL(string: "\(baseURL)/api/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let (asyncBytes, _) = try await URLSession.shared.bytes(for: request)

        for try await line in asyncBytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let msg = json["message"] as? [String: Any],
               let content = msg["content"] as? String,
               !content.isEmpty {
                await MainActor.run { onToken(content) }
            }

            if let done = json["done"] as? Bool, done { break }
        }

        await MainActor.run { onComplete() }
    }
}
