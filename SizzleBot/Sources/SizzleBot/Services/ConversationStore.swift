import Foundation

@MainActor
class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [UUID: Conversation] = [:]

    private let saveKey = "sizzleBot.conversations"

    init() { load() }

    func conversation(for characterId: UUID) -> Conversation {
        conversations[characterId] ?? Conversation(characterId: characterId)
    }

    func addMessage(_ message: Message, to characterId: UUID) {
        var conv = conversation(for: characterId)
        conv.messages.append(message)
        conv.updatedAt = Date()
        conversations[characterId] = conv
        save()
    }

    func appendToken(_ token: String, to characterId: UUID) {
        guard var conv = conversations[characterId], !conv.messages.isEmpty else { return }
        conv.messages[conv.messages.count - 1].content += token
        conv.updatedAt = Date()
        conversations[characterId] = conv
    }

    func clearConversation(for characterId: UUID) {
        conversations[characterId] = Conversation(characterId: characterId)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([UUID: Conversation].self, from: data)
        else { return }
        conversations = decoded
    }
}
