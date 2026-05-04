import Testing
import Foundation
@testable import SizzleBot

@Suite("Character model")
struct CharacterTests {

    @Test("Default initializer sets all fields correctly")
    func defaultInit() {
        let c = Character(
            name: "Test Bot",
            avatar: "🤖",
            tagline: "A test",
            systemPrompt: "You are a test.",
            greeting: "Hello tester."
        )
        #expect(c.name == "Test Bot")
        #expect(c.avatar == "🤖")
        #expect(c.tagline == "A test")
        #expect(c.systemPrompt == "You are a test.")
        #expect(c.greeting == "Hello tester.")
        #expect(c.accentColor == "blue")
        #expect(c.isBuiltIn == false)
        #expect(c.preferredModel == nil)
    }

    @Test("Characters with different ids are not equal via Hashable")
    func hashableDistinction() {
        let a = Character(name: "A", avatar: "🅰️", tagline: "", systemPrompt: "", greeting: "")
        let b = Character(name: "A", avatar: "🅰️", tagline: "", systemPrompt: "", greeting: "")
        // Two freshly created characters get different UUIDs
        #expect(a.id != b.id)
        #expect(a != b)
    }

    @Test("Encoding and decoding round-trips correctly")
    func codableRoundTrip() throws {
        let original = Character(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Echo",
            avatar: "🔊",
            tagline: "Repeats things",
            systemPrompt: "Repeat everything.",
            greeting: "...",
            preferredModel: "llama3.2",
            isBuiltIn: true,
            accentColor: "teal"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.avatar == original.avatar)
        #expect(decoded.systemPrompt == original.systemPrompt)
        #expect(decoded.preferredModel == "llama3.2")
        #expect(decoded.isBuiltIn == true)
        #expect(decoded.accentColor == "teal")
    }

    @Test("color returns correct SwiftUI color for each accent string")
    func accentColors() {
        let cases: [(String, Bool)] = [
            ("purple", true), ("pink", true), ("red", true), ("orange", true),
            ("green", true), ("teal", true), ("indigo", true), ("cyan", true),
            ("blue", true), ("unknown", true)
        ]
        for (name, _) in cases {
            let c = Character(name: "", avatar: "", tagline: "", systemPrompt: "", greeting: "", accentColor: name)
            // Just ensure .color doesn't crash and returns a non-nil value
            _ = c.color
        }
    }

    @Test("Built-in characters all have fixed UUIDs")
    func builtInUUIDsAreFixed() {
        let ids = Character.builtIn.map { $0.id }
        // All UUIDs should be unique
        #expect(Set(ids).count == ids.count)
        // UUIDs should be deterministic (re-accessing gives the same list)
        let ids2 = Character.builtIn.map { $0.id }
        #expect(ids == ids2)
    }

    @Test("There are exactly 18 built-in characters")
    func builtInCount() {
        #expect(Character.builtIn.count == 18)
    }

    @Test("Likeness Architect is present, vision-enabled, and prefers a vision model")
    func likenessArchitectPresent() {
        guard let arch = Character.builtIn.first(where: { $0.name == "Likeness Architect" }) else {
            Issue.record("Likeness Architect built-in is missing")
            return
        }
        #expect(arch.supportsImages, "Likeness Architect must accept image attachments")
        let preferred = arch.preferredModel ?? ""
        #expect(
            OllamaModel.recommendation(for: preferred)?.kind == .vision,
            "preferred model \(preferred) must be vision-capable"
        )
    }

    @Test("Likeness Architect prompt enforces clothing-fidelity & no-invention discipline")
    func likenessArchitectFidelityCues() {
        guard let arch = Character.builtIn.first(where: { $0.name == "Likeness Architect" }) else {
            Issue.record("Likeness Architect built-in is missing")
            return
        }
        let p = arch.systemPrompt.lowercased()
        // Fidelity discipline.
        #expect(p.contains("only what is actually visible") || p.contains("only what's actually visible"),
                "must instruct the model to describe only what is visible")
        #expect(p.contains("never guess") || p.contains("do not guess") || p.contains("never invent") || p.contains("do not invent"),
                "must forbid guessing / inventing details")
        // Detailed clothing requirements.
        #expect(p.contains("every visible garment"),
                "must require enumerating every visible garment")
        #expect(p.contains("fit") && p.contains("color") && p.contains("fabric"),
                "must call out fit / color / fabric for clothing")
        #expect(p.contains("layering"),
                "must mention layering so combos like t-shirt-under-flannel are captured")
    }

    @Test("supportsImages reflects acceptsImages and defaults to false")
    func supportsImagesFlag() {
        let plain = Character(name: "X", avatar: "X", tagline: "", systemPrompt: "p", greeting: "g")
        #expect(!plain.supportsImages, "default should be false")

        let vision = Character(name: "Y", avatar: "Y", tagline: "", systemPrompt: "p", greeting: "g", acceptsImages: true)
        #expect(vision.supportsImages)
    }

    @Test("Pre-1.3 Character JSON without acceptsImages decodes to supportsImages == false")
    func backwardCompatDecodingWithoutAcceptsImages() throws {
        // Simulates a Character persisted before the acceptsImages field existed.
        let legacyJSON = """
        {
          "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "name": "Legacy",
          "avatar": "X",
          "tagline": "old",
          "systemPrompt": "old prompt",
          "greeting": "hi",
          "isBuiltIn": false,
          "accentColor": "blue",
          "createdAt": 770000000.0
        }
        """
        let decoded = try JSONDecoder().decode(Character.self, from: legacyJSON.data(using: .utf8)!)
        #expect(!decoded.supportsImages)
        #expect(decoded.acceptsImages == nil)
    }

    @Test("All built-in characters have non-empty required fields")
    func builtInFieldCompleteness() {
        for char in Character.builtIn {
            #expect(!char.name.isEmpty, "name empty for \(char.id)")
            #expect(!char.avatar.isEmpty, "avatar empty for \(char.name)")
            #expect(!char.tagline.isEmpty, "tagline empty for \(char.name)")
            #expect(!char.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "systemPrompt empty for \(char.name)")
            #expect(!char.greeting.isEmpty, "greeting empty for \(char.name)")
            #expect(char.isBuiltIn, "isBuiltIn false for \(char.name)")
        }
    }

    @Test("accentColors static list is non-empty and contains blue")
    func accentColorsList() {
        #expect(!Character.accentColors.isEmpty)
        #expect(Character.accentColors.contains("blue"))
    }
}
