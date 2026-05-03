import Foundation

struct Conversation: Identifiable, Codable {
    var id: UUID
    var characterId: UUID
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date

    init(characterId: UUID, messages: [Message] = []) {
        self.id = UUID()
        self.characterId = characterId
        self.messages = messages
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
