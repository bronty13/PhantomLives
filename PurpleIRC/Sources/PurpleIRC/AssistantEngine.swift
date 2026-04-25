import Foundation
import Combine

/// One pending suggestion for a specific buffer. The view layer reads this
/// to render the suggestion strip above the input bar; the engine writes
/// it whenever a generation completes (or fails).
struct AssistantSuggestion: Identifiable, Equatable {
    let id: UUID = UUID()
    /// `IRCConnection.id` of the connection that owns the buffer.
    let connectionID: UUID
    /// `Buffer.id` of the target query / channel.
    let bufferID: UUID
    /// Persona name at the time of generation — purely informational, so
    /// the strip can show "Suggestion (Snarky friend)" or similar.
    let personaName: String
    /// The model's draft reply text, already trimmed.
    let text: String
    /// Set when the request failed instead of producing text. The strip
    /// renders this inline so the user sees what went wrong.
    let error: String?

    var isError: Bool { error != nil }
}

/// Lifecycle states the strip can be in for a given buffer.
enum AssistantState: Equatable {
    case idle
    case generating
    case ready(AssistantSuggestion)
    case failed(String)
}

/// Per-buffer assistant orchestration. ChatModel owns one of these and
/// fans out: subscribes to inbound .privmsg events, builds a chat-history
/// prompt from recent buffer lines, calls Ollama, publishes the result.
///
/// Engagement is opt-in: a buffer must be in `engaged` before the engine
/// generates anything. `/assist` toggles engagement; the suggestion strip
/// also exposes accept / edit / regenerate / dismiss.
@MainActor
final class AssistantEngine: ObservableObject {
    /// Buffers (by `Buffer.id`) currently engaged. The engine watches
    /// these and produces suggestions on each new inbound message.
    @Published private(set) var engagedBuffers: Set<UUID> = []
    /// Per-buffer persona override. Falls back to settings.assistant
    /// `.defaultPersonaID` (or the first persona) when absent.
    @Published private(set) var personaForBuffer: [UUID: UUID] = [:]
    /// Per-buffer suggestion state. Read by the SuggestionStrip view.
    @Published private(set) var stateForBuffer: [UUID: AssistantState] = [:]

    /// Settings + persona accessor — set by ChatModel on init. Avoids
    /// holding a strong reference to the whole ChatModel here.
    var personasProvider: () -> [AssistantPersona] = { [] }
    var settingsProvider: () -> AssistantSettings = { AssistantSettings() }

    /// Outbound entry point — accepting a suggestion calls this with the
    /// final text so it threads through the same /msg path the user
    /// would have typed manually. Set by ChatModel.attach.
    var sendBlock: ((_ connectionID: UUID, _ bufferID: UUID, _ text: String) -> Void)?

    private var cancellables: Set<AnyCancellable> = []

    /// Wire the engine to ChatModel's merged event stream. Called by
    /// `ChatModel.init`.
    func attach(eventStream: AnyPublisher<(UUID, IRCConnectionEvent), Never>,
                resolveBufferID: @escaping (_ connectionID: UUID, _ bufferName: String) -> UUID?) {
        eventStream
            .sink { [weak self] tuple in
                Task { @MainActor in
                    self?.handle(connectionID: tuple.0, event: tuple.1,
                                 resolveBufferID: resolveBufferID)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Engagement

    func isEngaged(bufferID: UUID) -> Bool {
        engagedBuffers.contains(bufferID)
    }

    /// Toggle engagement on a buffer. Returns the new state so the
    /// caller can echo "engaged" / "disengaged" in the buffer.
    @discardableResult
    func toggleEngagement(bufferID: UUID, persona: AssistantPersona? = nil) -> Bool {
        if engagedBuffers.contains(bufferID) {
            engagedBuffers.remove(bufferID)
            personaForBuffer.removeValue(forKey: bufferID)
            stateForBuffer[bufferID] = .idle
            return false
        }
        engagedBuffers.insert(bufferID)
        if let persona { personaForBuffer[bufferID] = persona.id }
        stateForBuffer[bufferID] = .idle
        return true
    }

    /// Switch which persona the engine uses on subsequent generations
    /// for this buffer. Doesn't regenerate the current suggestion.
    func setPersona(_ persona: AssistantPersona, bufferID: UUID) {
        personaForBuffer[bufferID] = persona.id
    }

    /// Active persona for a given buffer, falling back to the global
    /// default when nothing is set per-buffer. Returns nil only when the
    /// persona library is empty.
    func activePersona(bufferID: UUID) -> AssistantPersona? {
        let library = personasProvider()
        guard !library.isEmpty else { return nil }
        if let pid = personaForBuffer[bufferID],
           let p = library.first(where: { $0.id == pid }) {
            return p
        }
        if let pid = settingsProvider().defaultPersonaID,
           let p = library.first(where: { $0.id == pid }) {
            return p
        }
        return library.first
    }

    // MARK: - Suggestion lifecycle

    /// User explicitly asked for a fresh suggestion — bypass the
    /// "needs a new inbound message" gate. Used by the Regenerate button.
    func requestSuggestion(connectionID: UUID, bufferID: UUID,
                           historyProvider: @escaping () -> [ChatLine]) {
        guard isEngaged(bufferID: bufferID) else { return }
        let lines = historyProvider()
        generate(connectionID: connectionID, bufferID: bufferID, history: lines)
    }

    /// Discard the current suggestion. Strip falls back to "engaged but
    /// idle" — the next inbound message will trigger generation again.
    func dismissSuggestion(bufferID: UUID) {
        stateForBuffer[bufferID] = .idle
    }

    /// Pulled out of `requestSuggestion` so both the new-message path
    /// and the regenerate button share the same execution.
    private func generate(connectionID: UUID, bufferID: UUID,
                          history lines: [ChatLine]) {
        guard let persona = activePersona(bufferID: bufferID) else {
            stateForBuffer[bufferID] = .failed("No persona configured.")
            return
        }
        let settings = settingsProvider()
        guard settings.enabled else {
            stateForBuffer[bufferID] = .failed("Assistant is disabled in Setup.")
            return
        }
        let messages = Self.buildMessages(persona: persona,
                                          lines: lines,
                                          contextLines: settings.contextLineCount)
        stateForBuffer[bufferID] = .generating

        Task { @MainActor in
            do {
                let client = try OllamaClient(rawURL: settings.ollamaURL)
                let reply = try await client.chat(
                    model: settings.modelName,
                    messages: messages,
                    temperature: settings.temperature,
                    maxTokens: settings.maxResponseTokens)
                let trimmed = Self.cleanup(reply)
                let suggestion = AssistantSuggestion(
                    connectionID: connectionID,
                    bufferID: bufferID,
                    personaName: persona.name,
                    text: trimmed,
                    error: nil)
                stateForBuffer[bufferID] = .ready(suggestion)
            } catch {
                stateForBuffer[bufferID] = .failed(error.localizedDescription)
            }
        }
    }

    /// Trim quotes / leading "Assistant:" / trailing whitespace that
    /// some models prepend even with explicit instructions not to. Keeps
    /// the strip's preview tight without re-engineering the prompt.
    private static func cleanup(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["Assistant:", "AI:", "Reply:", "Response:"] {
            if s.lowercased().hasPrefix(label.lowercased()) {
                s = String(s.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        // Strip outer quotes if the model wrapped its whole reply in them.
        if s.count >= 2,
           let first = s.first, let last = s.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Assemble the [system, user, assistant, …] message list Ollama
    /// expects. We feed `contextLines` of the most recent buffer history
    /// so the model has continuity, then end with the freshest inbound
    /// line as the user turn it should reply to.
    static func buildMessages(persona: AssistantPersona,
                              lines: [ChatLine],
                              contextLines: Int) -> [OllamaClient.Message] {
        var out: [OllamaClient.Message] = [
            .init(role: "system", content: persona.systemPrompt)
        ]
        let tail = Array(lines.suffix(max(0, contextLines)))
        for line in tail {
            switch line.kind {
            case .privmsg(_, let isSelf):
                out.append(.init(role: isSelf ? "assistant" : "user",
                                 content: IRCFormatter.stripCodes(line.text)))
            case .action(let nick):
                out.append(.init(role: "user",
                                 content: "/me \(nick) \(IRCFormatter.stripCodes(line.text))"))
            default:
                continue   // skip joins/parts/notices/etc — noise to the model
            }
        }
        // If the last line we sent was an assistant turn, the model has
        // nothing new to reply to — the engine only fires on inbound.
        return out
    }

    // MARK: - Event handling

    private func handle(connectionID: UUID, event: IRCConnectionEvent,
                        resolveBufferID: (UUID, String) -> UUID?) {
        // Only respond to inbound PRIVMSG (no notices, no own messages).
        guard case let .privmsg(from: _, target: target, text: _,
                                isAction: _, isMention: _) = event else { return }
        guard let bufferID = resolveBufferID(connectionID, target),
              isEngaged(bufferID: bufferID) else { return }
        // Generation needs the buffer's lines — but the engine doesn't
        // hold the connection. ChatModel.attach passes a closure that
        // resolves both bufferID and lines on demand.
        if let provider = historyProviders[bufferID] {
            generate(connectionID: connectionID, bufferID: bufferID,
                     history: provider())
        }
    }

    /// Per-buffer history closures. ChatModel registers one per
    /// connection at attach time; the engine calls them when it needs
    /// to build a prompt.
    private var historyProviders: [UUID: () -> [ChatLine]] = [:]

    func registerHistoryProvider(bufferID: UUID,
                                 provider: @escaping () -> [ChatLine]) {
        historyProviders[bufferID] = provider
    }

    func removeHistoryProvider(bufferID: UUID) {
        historyProviders.removeValue(forKey: bufferID)
    }
}
