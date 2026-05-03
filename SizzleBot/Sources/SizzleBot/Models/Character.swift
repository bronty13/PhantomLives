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
        createdAt: Date = Date()
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
