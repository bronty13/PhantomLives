import SwiftUI

struct MessageBubble: View {
    let message: Message
    let character: Character

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                Text(character.avatar)
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
                    .background(character.color.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                if !isUser {
                    Text(character.name)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(character.color)
                        .padding(.leading, 4)
                }

                markdownText(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser
                        ? AnyShapeStyle(character.color)
                        : AnyShapeStyle(Color(.quaternarySystemFill)))
                    .foregroundStyle(isUser
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(Color.primary))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser {
                Spacer(minLength: 60)
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func markdownText(_ content: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(content)
        }
    }
}
