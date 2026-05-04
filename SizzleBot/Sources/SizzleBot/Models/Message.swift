import Foundation

struct Message: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    /// Base64-encoded image attachments (typically JPEG).
    /// Optional for backward compat with messages persisted before 1.3.0.
    var images: [String]?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        images: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.images = images
    }

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }
}
