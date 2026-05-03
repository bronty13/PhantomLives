import Testing
import Foundation
@testable import SizzleBot

@Suite("CharacterStore — reset logic")
@MainActor
struct CharacterStoreTests {

    // Wipe all SizzleBot UserDefaults keys so each test starts from a clean slate.
    private func makeStore() -> CharacterStore {
        UserDefaults.standard.removeObject(forKey: "sizzleBot.builtInOverrides")
        UserDefaults.standard.removeObject(forKey: "sizzleBot.userCharacters")
        UserDefaults.standard.synchronize()
        return CharacterStore()
    }

    @Test("Store loads all built-in characters on init")
    func loadsBuiltIns() {
        let store = makeStore()
        #expect(store.builtInCharacters.count == Character.builtIn.count)
        #expect(store.userCharacters.isEmpty)
    }

    @Test("canResetToDefault returns false for unmodified built-in")
    func canResetFalseForUnmodified() {
        let store = makeStore()
        guard let char = store.builtInCharacters.first else {
            Issue.record("No built-in characters")
            return
        }
        #expect(!store.canResetToDefault(char))
    }

    @Test("canResetToDefault returns false for user-created character")
    func canResetFalseForUserChar() {
        let store = makeStore()
        let custom = Character(name: "Custom", avatar: "🦄", tagline: "t",
                               systemPrompt: "p", greeting: "g")
        store.addCharacter(custom)
        guard let found = store.userCharacters.first else {
            Issue.record("User character not added")
            return
        }
        #expect(!store.canResetToDefault(found))
    }

    @Test("updateCharacter modifies the character in the store")
    func updateModifiesCharacter() {
        let store = makeStore()
        guard var char = store.builtInCharacters.first else {
            Issue.record("No built-in characters")
            return
        }
        let originalName = char.name
        char.name = "Modified Name"
        store.updateCharacter(char)

        let updated = store.characters.first { $0.id == char.id }
        #expect(updated?.name == "Modified Name")
        #expect(updated?.name != originalName)
    }

    @Test("canResetToDefault returns true after updating a built-in")
    func canResetTrueAfterUpdate() {
        let store = makeStore()
        guard var char = store.builtInCharacters.first else {
            Issue.record("No built-in characters")
            return
        }
        char.name = "Totally Different Name"
        store.updateCharacter(char)

        let modified = store.characters.first { $0.id == char.id }!
        #expect(store.canResetToDefault(modified))
    }

    @Test("resetToDefault restores original name and system prompt")
    func resetToDefaultRestoresFields() {
        let store = makeStore()
        guard let original = store.builtInCharacters.first else {
            Issue.record("No built-in characters")
            return
        }
        let originalName = original.name
        let originalPrompt = original.systemPrompt

        var modified = original
        modified.name = "Hacked Name"
        modified.systemPrompt = "Do nothing."
        store.updateCharacter(modified)
        store.resetToDefault(modified)

        let restored = store.characters.first { $0.id == original.id }!
        #expect(restored.name == originalName)
        #expect(restored.systemPrompt == originalPrompt)
        #expect(!store.canResetToDefault(restored))
    }

    @Test("addCharacter appends to userCharacters")
    func addCharacter() {
        let store = makeStore()
        let before = store.userCharacters.count
        let custom = Character(name: "New Bot", avatar: "🎯", tagline: "t",
                               systemPrompt: "p", greeting: "g")
        store.addCharacter(custom)
        #expect(store.userCharacters.count == before + 1)
        #expect(store.userCharacters.last?.name == "New Bot")
    }

    @Test("addCharacter forces isBuiltIn to false")
    func addCharacterForcesIsBuiltInFalse() {
        let store = makeStore()
        var char = Character(name: "Sneaky", avatar: "🎭", tagline: "", systemPrompt: "", greeting: "")
        char.isBuiltIn = true  // attempt to pass as built-in
        store.addCharacter(char)
        let added = store.userCharacters.last
        #expect(added?.isBuiltIn == false)
    }

    @Test("deleteCharacter removes user character")
    func deleteCharacter() {
        let store = makeStore()
        let custom = Character(name: "Temp", avatar: "🗑️", tagline: "", systemPrompt: "", greeting: "")
        store.addCharacter(custom)
        let added = store.userCharacters.last!
        store.deleteCharacter(added)
        #expect(!store.userCharacters.contains { $0.id == added.id })
    }

    @Test("deleteCharacter does not remove built-in characters")
    func deleteDoesNotRemoveBuiltIn() {
        let store = makeStore()
        let builtInCount = store.builtInCharacters.count
        let builtIn = store.builtInCharacters.first!
        store.deleteCharacter(builtIn)
        #expect(store.builtInCharacters.count == builtInCount)
    }

    @Test("resetAllBuiltIns restores every built-in to original")
    func resetAllBuiltIns() {
        let store = makeStore()
        // Modify several built-ins
        for i in 0..<3 {
            var char = store.builtInCharacters[i]
            char.name = "Changed \(i)"
            store.updateCharacter(char)
        }
        #expect(store.builtInCharacters.prefix(3).allSatisfy { store.canResetToDefault($0) })

        store.resetAllBuiltIns()
        #expect(store.builtInCharacters.allSatisfy { !store.canResetToDefault($0) })
    }

    @Test("builtInCharacters and userCharacters are mutually exclusive")
    func partitionIsExclusive() {
        let store = makeStore()
        store.addCharacter(Character(name: "X", avatar: "❌", tagline: "", systemPrompt: "", greeting: ""))
        let builtInIds = Set(store.builtInCharacters.map { $0.id })
        let userIds = Set(store.userCharacters.map { $0.id })
        #expect(builtInIds.isDisjoint(with: userIds))
    }
}
