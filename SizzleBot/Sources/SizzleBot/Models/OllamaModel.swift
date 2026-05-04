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
    enum Alignment: String {
        case uncensored = "Uncensored"
        case lightlyAligned = "Lightly aligned"
        case aligned = "Aligned"

        var color: String {
            switch self {
            case .uncensored: return "green"
            case .lightlyAligned: return "yellow"
            case .aligned: return "orange"
            }
        }
    }

    enum Kind: String {
        case chat
        case vision
    }

    struct Recommendation: Identifiable, Hashable {
        let id: String
        let name: String
        let description: String
        let alignment: Alignment
        let kind: Kind

        init(id: String, name: String, description: String, alignment: Alignment, kind: Kind = .chat) {
            self.id = id
            self.name = name
            self.description = description
            self.alignment = alignment
            self.kind = kind
        }
    }

    static let recommended: [Recommendation] = [
        Recommendation(id: "dolphin-mistral", name: "Dolphin Mistral 7B",
                       description: "Uncensored — default; ideal for character roleplay & uninhibited chat",
                       alignment: .uncensored),
        Recommendation(id: "dolphin-llama3", name: "Dolphin Llama 3 8B",
                       description: "Uncensored Llama 3 — stronger reasoning, still roleplay-friendly",
                       alignment: .uncensored),
        Recommendation(id: "nous-hermes2", name: "Nous Hermes 2",
                       description: "Lightly aligned, expressive — strong for character work and long scenes",
                       alignment: .lightlyAligned),
        Recommendation(id: "wizard-vicuna-uncensored", name: "Wizard Vicuna 7B (Uncensored)",
                       description: "Heavily uncensored — adult fiction & no-holds-barred roleplay",
                       alignment: .uncensored),
        Recommendation(id: "llama3.2-vision", name: "Llama 3.2 Vision 11B",
                       description: "Vision-capable — describes images and answers visual questions; powers the Likeness Architect bot",
                       alignment: .aligned, kind: .vision),
        Recommendation(id: "llava", name: "LLaVA 7B",
                       description: "Vision-language model — fast image description, lighter than Llama Vision",
                       alignment: .lightlyAligned, kind: .vision),
        Recommendation(id: "moondream", name: "Moondream 2B",
                       description: "Tiny & fast vision model — runs even on modest hardware",
                       alignment: .lightlyAligned, kind: .vision),
        Recommendation(id: "llama3.2", name: "Llama 3.2 3B",
                       description: "Compact & fast — aligned; may inject safety caveats",
                       alignment: .aligned),
        Recommendation(id: "llama3.1", name: "Llama 3.1 8B",
                       description: "Larger & capable — aligned; may inject safety caveats",
                       alignment: .aligned),
        Recommendation(id: "mistral", name: "Mistral 7B",
                       description: "Fast, well-rounded — moderately aligned",
                       alignment: .lightlyAligned),
        Recommendation(id: "gemma3", name: "Gemma 3 4B",
                       description: "Efficient on Apple Silicon — Google-aligned, more cautious",
                       alignment: .aligned),
        Recommendation(id: "qwen2.5", name: "Qwen 2.5 7B",
                       description: "Strong multilingual — moderately aligned",
                       alignment: .lightlyAligned),
        Recommendation(id: "phi4", name: "Phi-4 14B",
                       description: "High quality Microsoft model — heavily aligned, hedges often",
                       alignment: .aligned),
    ]

    /// Looks up a recommendation by the bare or fully-qualified ollama tag (e.g.
    /// `dolphin-mistral` or `dolphin-mistral:latest`). Returns nil for unknown
    /// models so callers can fall back to a neutral display.
    static func recommendation(for modelName: String) -> Recommendation? {
        let bare = modelName.components(separatedBy: ":").first ?? modelName
        return recommended.first { $0.id == bare }
    }
}
