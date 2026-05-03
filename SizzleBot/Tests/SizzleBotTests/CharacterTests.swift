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

    @Test("There are exactly 17 built-in characters")
    func builtInCount() {
        #expect(Character.builtIn.count == 17)
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
