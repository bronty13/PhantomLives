import Testing
import Foundation
@testable import SizzleBot

@Suite("OllamaModel parsing")
struct OllamaModelTests {

    @Test("Parses model name and size from JSON")
    func parsesJSON() throws {
        let json = """
        {"name":"dolphin-mistral:latest","size":4113370432,"modified_at":"2026-05-03T00:00:00Z"}
        """
        let model = try JSONDecoder().decode(OllamaModel.self, from: json.data(using: .utf8)!)
        #expect(model.name == "dolphin-mistral:latest")
        #expect(model.size == 4_113_370_432)
        #expect(model.id == "dolphin-mistral:latest")
    }

    @Test("displayName strips the tag component")
    func displayNameStripsTag() throws {
        let json = """
        {"name":"llama3.1:8b-instruct-q4_K_M","size":null,"modified_at":null}
        """
        let model = try JSONDecoder().decode(OllamaModel.self, from: json.data(using: .utf8)!)
        #expect(model.displayName == "llama3.1")
    }

    @Test("sizeString formats gigabytes correctly")
    func sizeStringGB() throws {
        let json = """
        {"name":"big-model:latest","size":7800000000,"modified_at":null}
        """
        let model = try JSONDecoder().decode(OllamaModel.self, from: json.data(using: .utf8)!)
        #expect(model.sizeString.contains("GB"))
    }

    @Test("sizeString formats megabytes correctly")
    func sizeStringMB() throws {
        let json = """
        {"name":"tiny-model:latest","size":500000000,"modified_at":null}
        """
        let model = try JSONDecoder().decode(OllamaModel.self, from: json.data(using: .utf8)!)
        #expect(model.sizeString.contains("MB"))
    }

    @Test("sizeString returns empty string when size is null")
    func sizeStringNil() throws {
        let json = """
        {"name":"unknown:latest","size":null,"modified_at":null}
        """
        let model = try JSONDecoder().decode(OllamaModel.self, from: json.data(using: .utf8)!)
        #expect(model.sizeString.isEmpty)
    }

    @Test("OllamaModelsResponse parses a models array")
    func parsesModelsResponse() throws {
        let json = """
        {"models":[
          {"name":"model-a:latest","size":1000000000,"modified_at":null},
          {"name":"model-b:latest","size":2000000000,"modified_at":null}
        ]}
        """
        let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: json.data(using: .utf8)!)
        #expect(response.models.count == 2)
        #expect(response.models[0].name == "model-a:latest")
    }

    @Test("Recommended models list is non-empty")
    func recommendedListNonEmpty() {
        #expect(!OllamaModel.recommended.isEmpty)
    }

    @Test("All recommended models have non-empty id, name, and description")
    func recommendedListComplete() {
        for rec in OllamaModel.recommended {
            #expect(!rec.id.isEmpty, "empty id in recommended list")
            #expect(!rec.name.isEmpty, "empty name for id \(rec.id)")
            #expect(!rec.description.isEmpty, "empty description for \(rec.id)")
        }
    }
}
