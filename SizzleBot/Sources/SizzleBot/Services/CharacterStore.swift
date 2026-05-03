import Foundation

@MainActor
class CharacterStore: ObservableObject {
    @Published var characters: [Character] = []
    @Published var selectedCharacter: Character?

    private let userKey = "sizzleBot.userCharacters"
    private let overridesKey = "sizzleBot.builtInOverrides"

    // Canonical defaults — never mutated, always available for reset
    private let defaults: [UUID: Character] = Dictionary(
        uniqueKeysWithValues: Character.builtIn.map { ($0.id, $0) }
    )

    init() {
        let overrides = loadBuiltInOverrides()
        let builtin = Character.builtIn.map { overrides[$0.id] ?? $0 }
        let user = loadUserCharacters()
        characters = builtin + user
        selectedCharacter = characters.first
    }

    // MARK: - CRUD

    func addCharacter(_ character: Character) {
        var char = character
        char.isBuiltIn = false
        characters.append(char)
        saveUserCharacters()
    }

    func updateCharacter(_ character: Character) {
        guard let idx = characters.firstIndex(where: { $0.id == character.id }) else { return }
        characters[idx] = character
        if selectedCharacter?.id == character.id { selectedCharacter = character }

        if character.isBuiltIn {
            saveBuiltInOverrides()
        } else {
            saveUserCharacters()
        }
    }

    func deleteCharacter(_ character: Character) {
        guard !character.isBuiltIn else { return }
        characters.removeAll { $0.id == character.id }
        if selectedCharacter?.id == character.id { selectedCharacter = characters.first }
        saveUserCharacters()
    }

    // MARK: - Reset

    func canResetToDefault(_ character: Character) -> Bool {
        guard character.isBuiltIn, let original = defaults[character.id] else { return false }
        return character.name != original.name
            || character.avatar != original.avatar
            || character.tagline != original.tagline
            || character.systemPrompt != original.systemPrompt
            || character.greeting != original.greeting
            || character.accentColor != original.accentColor
    }

    func resetToDefault(_ character: Character) {
        guard character.isBuiltIn, let original = defaults[character.id],
              let idx = characters.firstIndex(where: { $0.id == character.id })
        else { return }
        characters[idx] = original
        if selectedCharacter?.id == original.id { selectedCharacter = original }
        saveBuiltInOverrides()
    }

    func resetAllBuiltIns() {
        for (idx, char) in characters.enumerated() {
            guard char.isBuiltIn, let original = defaults[char.id] else { continue }
            characters[idx] = original
        }
        if let sel = selectedCharacter, sel.isBuiltIn, let original = defaults[sel.id] {
            selectedCharacter = original
        }
        UserDefaults.standard.removeObject(forKey: overridesKey)
    }

    // MARK: - Computed

    var builtInCharacters: [Character] { characters.filter { $0.isBuiltIn } }
    var userCharacters: [Character] { characters.filter { !$0.isBuiltIn } }

    // MARK: - Persistence

    private func loadUserCharacters() -> [Character] {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let decoded = try? JSONDecoder().decode([Character].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveUserCharacters() {
        if let data = try? JSONEncoder().encode(characters.filter { !$0.isBuiltIn }) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    private func loadBuiltInOverrides() -> [UUID: Character] {
        guard let data = UserDefaults.standard.data(forKey: overridesKey),
              let list = try? JSONDecoder().decode([Character].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    private func saveBuiltInOverrides() {
        let modified = characters.filter { canResetToDefault($0) }
        if let data = try? JSONEncoder().encode(modified) {
            UserDefaults.standard.set(data, forKey: overridesKey)
        }
    }
}
