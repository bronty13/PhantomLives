import Foundation

struct OllamaModel: Codable, Identifiable, Hashable {
    let name: String
    let size: Int64?
    let modifiedAt: String?

    var id: String { name }

    var displayName: String {
        name.components(separatedBy: ":").first ?? name
    }

    var sizeString: String {
        guard let size = size else { return "" }
        let gb = Double(size) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(size) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case modifiedAt = "modified_at"
    }
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

extension OllamaModel {
    static let recommended: [(id: String, name: String, description: String)] = [
        ("dolphin-mistral", "Dolphin Mistral 7B", "Uncensored, great for roleplay & character chat"),
        ("dolphin-llama3", "Dolphin Llama 3 8B", "Uncensored Llama 3, strong & balanced"),
        ("llama3.2", "Llama 3.2 3B", "Compact and fast on Apple Silicon"),
        ("llama3.1", "Llama 3.1 8B", "Larger, more capable"),
        ("mistral", "Mistral 7B", "Fast, well-rounded model"),
        ("gemma3", "Gemma 3 4B", "Google's model, efficient on Apple Silicon"),
        ("qwen2.5", "Qwen 2.5 7B", "Strong multilingual capability"),
        ("nous-hermes2", "Nous Hermes 2", "Creative and expressive for roleplay"),
        ("phi4", "Phi-4 14B", "High quality Microsoft model"),
    ]
}
