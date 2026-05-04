import SwiftUI

struct Character: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var avatar: String
    var tagline: String
    var systemPrompt: String
    var greeting: String
    var preferredModel: String?
    var isBuiltIn: Bool
    var accentColor: String
    var createdAt: Date
    /// True if the character is meant to receive image attachments (vision bot).
    /// Optional for backward compat with persisted Characters from < 1.3.0.
    var acceptsImages: Bool?

    var supportsImages: Bool { acceptsImages ?? false }

    init(
        id: UUID = UUID(),
        name: String,
        avatar: String,
        tagline: String,
        systemPrompt: String,
        greeting: String,
        preferredModel: String? = nil,
        isBuiltIn: Bool = false,
        accentColor: String = "blue",
        createdAt: Date = Date(),
        acceptsImages: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.tagline = tagline
        self.systemPrompt = systemPrompt
        self.greeting = greeting
        self.preferredModel = preferredModel
        self.isBuiltIn = isBuiltIn
        self.accentColor = accentColor
        self.createdAt = createdAt
        self.acceptsImages = acceptsImages
    }

    var color: Color {
        switch accentColor {
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "cyan": return .cyan
        case "indigo": return .indigo
        default: return .blue
        }
    }

    static let accentColors = ["blue", "purple", "pink", "red", "orange", "green", "teal", "indigo", "cyan"]
}
