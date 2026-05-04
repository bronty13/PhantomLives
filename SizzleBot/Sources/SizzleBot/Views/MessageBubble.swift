import SwiftUI
import AppKit

struct MessageBubble: View {
    let message: Message
    let character: Character

    @State private var fullscreenImageBase64: String?

    private var isUser: Bool { message.role == .user }

    private var shouldShowPromptActions: Bool {
        !isUser && character.supportsImages && !message.content.isEmpty
    }

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

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !isUser {
                    Text(character.name)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(character.color)
                        .padding(.leading, 4)
                }

                if let images = message.images, !images.isEmpty {
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, base64 in
                            attachmentView(base64: base64)
                        }
                    }
                }

                if !message.content.isEmpty {
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
                }

                if shouldShowPromptActions {
                    let parsed = PromptExporter.parse(message.content)
                    PromptActionsPanel(paragraph: parsed.paragraph, variants: parsed.variants)
                }

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
        .sheet(item: Binding(
            get: { fullscreenImageBase64.map { ImageSheetItem(base64: $0) } },
            set: { fullscreenImageBase64 = $0?.base64 }
        )) { item in
            FullscreenImage(base64: item.base64) { fullscreenImageBase64 = nil }
        }
    }

    @ViewBuilder
    private func attachmentView(base64: String) -> some View {
        if let nsImage = ImageAttachment.decode(base64: base64) {
            Button {
                fullscreenImageBase64 = base64
            } label: {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Click to view full size")
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

private struct ImageSheetItem: Identifiable {
    let base64: String
    var id: String { base64 }
}

private struct FullscreenImage: View {
    let base64: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.95).ignoresSafeArea()
            if let nsImage = ImageAttachment.decode(base64: base64) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(40)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .padding(16)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 600, idealWidth: 900, minHeight: 400, idealHeight: 700)
    }
}
