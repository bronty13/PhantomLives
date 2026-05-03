import SwiftUI

struct ChatView: View {
    let character: Character
    @EnvironmentObject var conversationStore: ConversationStore
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var characterStore: CharacterStore

    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var streamBuffer = ""
    @State private var errorMessage: String?
    @State private var showingEditor = false
    @State private var scrollProxy: ScrollViewProxy?

    var messages: [Message] {
        conversationStore.conversation(for: character.id).messages
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(character: character, showingEditor: $showingEditor)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            GreetingCard(character: character)
                                .padding(.top, 40)
                        }

                        ForEach(messages) { msg in
                            MessageBubble(message: msg, character: character)
                                .id(msg.id)
                        }

                        if isGenerating {
                            if streamBuffer.isEmpty {
                                TypingIndicator(character: character)
                                    .id("typing")
                            } else {
                                StreamingBubble(content: streamBuffer, character: character)
                                    .id("streaming")
                            }
                        }

                        if let err = errorMessage {
                            ErrorBanner(message: err) { errorMessage = nil }
                        }

                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom") }
                }
                .onChange(of: streamBuffer) { _, _ in
                    proxy.scrollTo("bottom")
                }
                .onChange(of: isGenerating) { _, new in
                    if new { withAnimation { proxy.scrollTo("bottom") } }
                }
            }

            Divider()
            MessageInputView(
                text: $inputText,
                isGenerating: isGenerating,
                accentColor: character.color,
                onSend: sendMessage,
                onStop: { isGenerating = false }
            )
        }
        .sheet(isPresented: $showingEditor) {
            CharacterEditorView(mode: .edit(character))
                .environmentObject(characterStore)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        errorMessage = nil
        streamBuffer = ""
        isGenerating = true

        let userMsg = Message(role: .user, content: text)
        conversationStore.addMessage(userMsg, to: character.id)

        let history = conversationStore.conversation(for: character.id).messages

        Task {
            do {
                try await ollamaService.generateResponse(
                    messages: history,
                    character: character,
                    onToken: { token in
                        streamBuffer += token
                    },
                    onComplete: {
                        let finalMsg = Message(role: .assistant, content: streamBuffer)
                        conversationStore.addMessage(finalMsg, to: character.id)
                        streamBuffer = ""
                        isGenerating = false
                    }
                )
            } catch {
                streamBuffer = ""
                isGenerating = false
                errorMessage = "Could not reach Ollama. Make sure it is running on localhost:11434."
            }
        }
    }
}

struct ChatHeader: View {
    let character: Character
    @Binding var showingEditor: Bool
    @EnvironmentObject var conversationStore: ConversationStore
    @EnvironmentObject var ollamaService: OllamaService

    var body: some View {
        HStack(spacing: 12) {
            Text(character.avatar)
                .font(.system(size: 30))
                .frame(width: 46, height: 46)
                .background(character.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(character.name).font(.headline)
                Text(character.tagline).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Edit Character") { showingEditor = true }
                Divider()
                Button("Clear Conversation", role: .destructive) {
                    conversationStore.clearConversation(for: character.id)
                }
                Divider()
                Text("Model: \(character.preferredModel ?? ollamaService.selectedModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct GreetingCard: View {
    let character: Character

    var body: some View {
        VStack(spacing: 14) {
            Text(character.avatar)
                .font(.system(size: 60))
            Text(character.name)
                .font(.title2.bold())
            Text(character.greeting)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 24)
    }
}

struct StreamingBubble: View {
    let content: String
    let character: Character

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(character.avatar)
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(character.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(character.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(character.color)
                    .padding(.leading, 4)

                markdownText(content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.quaternarySystemFill))
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Spacer(minLength: 60)
        }
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption)
            Spacer()
            Button("Dismiss", action: onDismiss).font(.caption).buttonStyle(.borderless)
        }
        .padding(10)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
