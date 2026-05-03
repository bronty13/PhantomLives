import SwiftUI

enum EditorMode {
    case create
    case edit(Character)
}

struct CharacterEditorView: View {
    let mode: EditorMode
    @EnvironmentObject var characterStore: CharacterStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var avatar = "🤖"
    @State private var tagline = ""
    @State private var systemPrompt = ""
    @State private var greeting = ""
    @State private var accentColor = "blue"
    @State private var preferredModel = ""
    @State private var showingEmojiPicker = false

    private let emojiOptions = [
        "🤖", "🧙‍♂️", "🦸", "🕵️", "👑", "🧛", "🏴‍☠️", "🦊", "🐉", "👻",
        "🧜‍♀️", "🌙", "⚡", "🔮", "🗡️", "🌹", "🎩", "🧪", "🔭", "🌵",
        "🦁", "🐺", "🦋", "🌊", "🔥", "❄️", "☁️", "💀", "🎭", "🏹"
    ]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isSaveable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canReset: Bool {
        guard case .edit(let char) = mode else { return false }
        return characterStore.canResetToDefault(char)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text(isEditing ? "Edit Character" : "New Character").font(.headline)
                Spacer()
                if canReset {
                    Button("Reset") {
                        if case .edit(let char) = mode {
                            characterStore.resetToDefault(char)
                        }
                        dismiss()
                    }
                    .foregroundStyle(.orange)
                    .padding(.trailing, 6)
                }
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!isSaveable)
            }
            .padding()

            Divider()

            Form {
                Section("Identity") {
                    HStack {
                        Text("Avatar")
                        Spacer()
                        Menu {
                            let columns = emojiOptions.chunked(into: 6)
                            ForEach(columns.indices, id: \.self) { row in
                                HStack {
                                    ForEach(columns[row], id: \.self) { emoji in
                                        Button(emoji) { avatar = emoji }
                                    }
                                }
                            }
                        } label: {
                            Text(avatar).font(.title2)
                                .frame(width: 44, height: 36)
                                .background(colorFor(accentColor).opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .menuStyle(.borderlessButton)
                    }

                    TextField("Character name", text: $name)
                    TextField("Short tagline", text: $tagline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 130)
                        .overlay(alignment: .topLeading) {
                            if systemPrompt.isEmpty {
                                Text("System prompt — describe who this character is, their personality, speaking style, background, and how they should respond…")
                                    .foregroundStyle(.tertiary)
                                    .font(.body)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Personality / System Prompt")
                }

                Section("Greeting") {
                    TextEditor(text: $greeting)
                        .frame(minHeight: 60)
                        .overlay(alignment: .topLeading) {
                            if greeting.isEmpty {
                                Text("First message shown when starting a chat (optional)")
                                    .foregroundStyle(.tertiary)
                                    .font(.body)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Accent Color") {
                    HStack(spacing: 10) {
                        ForEach(Character.accentColors, id: \.self) { color in
                            Button { accentColor = color } label: {
                                Circle()
                                    .fill(colorFor(color))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle().stroke(.white, lineWidth: accentColor == color ? 3 : 0)
                                    )
                                    .shadow(radius: accentColor == color ? 3 : 0)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Advanced") {
                    TextField("Preferred model (optional, overrides global)", text: $preferredModel)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 640)
        .onAppear { populateIfEditing() }
    }

    private func populateIfEditing() {
        guard case .edit(let char) = mode else { return }
        name = char.name
        avatar = char.avatar
        tagline = char.tagline
        systemPrompt = char.systemPrompt
        greeting = char.greeting
        accentColor = char.accentColor
        preferredModel = char.preferredModel ?? ""
    }

    private func save() {
        let model: String? = preferredModel.trimmingCharacters(in: .whitespaces).isEmpty ? nil : preferredModel

        if case .edit(let existing) = mode {
            var updated = existing
            updated.name = name
            updated.avatar = avatar
            updated.tagline = tagline
            updated.systemPrompt = systemPrompt
            updated.greeting = greeting
            updated.accentColor = accentColor
            updated.preferredModel = model
            characterStore.updateCharacter(updated)
        } else {
            let char = Character(
                name: name,
                avatar: avatar,
                tagline: tagline,
                systemPrompt: systemPrompt,
                greeting: greeting,
                preferredModel: model,
                accentColor: accentColor
            )
            characterStore.addCharacter(char)
            characterStore.selectedCharacter = characterStore.characters.last
        }
        dismiss()
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
