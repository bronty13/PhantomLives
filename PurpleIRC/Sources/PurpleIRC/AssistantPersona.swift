import Foundation

/// One assistant persona — a system prompt fed to the local LLM, plus a
/// human-readable name + UUID for identifying it across launches. Built-in
/// templates ship with PurpleIRC; users can edit their copies or create
/// from a blank starter. The `isBuiltin` flag is informational only — every
/// persona stored in `AppSettings.assistantPersonas` is editable.
struct AssistantPersona: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var systemPrompt: String = ""
    /// True for templates we shipped — surfaced in the UI as a small badge
    /// so users know they can revert to the default. Mutable: changing a
    /// builtin clears the flag in the editor (so "edited builtin" reads
    /// as a regular custom entry).
    var isBuiltin: Bool = false

    init(id: UUID = UUID(), name: String = "",
         systemPrompt: String = "", isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.isBuiltin = isBuiltin
    }

    // MARK: - Built-ins

    /// IRC-specific guidance every persona inherits. Local LLMs trained on
    /// general chat data tend to over-format (markdown, long paragraphs) —
    /// this preamble nudges them toward IRC's terse register before the
    /// per-persona character notes kick in.
    private static let ircContract = """
        You are drafting a single chat reply on IRC.
        - Keep replies short. One or two sentences is normal; three is the upper limit unless explicitly asked for more.
        - Plain text only. No markdown, no headers, no bullet points, no code fences. Inline `code spans` are allowed when discussing code.
        - Match the conversational register — if the other party is casual, be casual; if formal, be formal.
        - Do not repeat the user's message back at them, do not preface ("Sure!", "Of course,"), do not sign off.
        - Reply ONLY as the persona below. Output the reply text and nothing else — no labels, no quotes around your reply, no roleplay narration.
        """

    /// The six starter templates that populate `AppSettings.assistantPersonas`
    /// the first time the assistant is enabled. The IDs are fixed so future
    /// app updates can detect "this is the unmodified casual-chat template"
    /// vs. an edited copy.
    static func defaultPersonas() -> [AssistantPersona] {
        [
            AssistantPersona(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000c10a7")!,
                name: "Casual chat",
                systemPrompt: """
                    \(ircContract)

                    Persona: a friendly, easy-going chat partner. Warm but not sappy. Comfortable with banter, dry humour, and self-deprecation. Asks a follow-up question when it makes the conversation flow better — not every message.
                    """,
                isBuiltin: true),
            AssistantPersona(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000007ec40")!,
                name: "Tech sidekick",
                systemPrompt: """
                    \(ircContract)

                    Persona: a competent, no-nonsense technical helper. You know your way around shells, programming languages, networking, and ops. Give the answer first; explain only if there's room. Use inline code spans for symbols, file paths, and short snippets. If the question is ambiguous, ask one clarifying question rather than guessing.
                    """,
                isBuiltin: true),
            AssistantPersona(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000513a4c")!,
                name: "Snarky friend",
                systemPrompt: """
                    \(ircContract)

                    Persona: a quick-witted friend with a deadpan, sarcastic streak. Affectionate sarcasm, never mean-spirited. Lean into IRC culture — wordplay, callbacks, the occasional dramatic eyeroll in text. Punch up, never down.
                    """,
                isBuiltin: true),
            AssistantPersona(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000e1957")!,
                name: "Empathetic listener",
                systemPrompt: """
                    \(ircContract)

                    Persona: a warm, attentive listener. Mirror back what the other person said when it shows you understood, then ask one open-ended follow-up. Don't jump to advice unless they ask for it. Validate feelings without flattery.
                    """,
                isBuiltin: true),
            AssistantPersona(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000fee10")!,
                name: "Roleplay (fill-in)",
                systemPrompt: """
                    \(ircContract)

                    Persona: {{character_name}}, a {{traits}}. Stay in character at all times. The user may ask "the assistant" out of character by prefacing a message with `OOC:`; respond OOC briefly and then return to character on the next reply. No narration, no scene-setting — just dialogue as {{character_name}} would speak it.
                    """,
                isBuiltin: true),
            AssistantPersona(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000b1a4cf")!,
                name: "Blank template",
                systemPrompt: """
                    \(ircContract)

                    Persona:
                    """,
                isBuiltin: true)
        ]
    }
}

/// Settings block bundling the assistant's user-facing configuration.
/// Lives inside `AppSettings` so it shares the same encrypted-on-disk
/// envelope as everything else.
struct AssistantSettings: Codable, Equatable {
    /// Master switch. Off by default — most PurpleIRC users won't have
    /// Ollama installed, and we don't want to be poking a localhost socket
    /// every keystroke for nothing.
    var enabled: Bool = false

    /// Ollama HTTP endpoint. Default is what `ollama serve` listens on.
    var ollamaURL: String = "http://localhost:11434"

    /// Model name as known to Ollama (e.g. "dolphin3:8b"). Free-form so
    /// the user can pick whatever they've `ollama pull`'d.
    var modelName: String = "dolphin3:8b"

    /// Persona used for query buffers that haven't picked one explicitly.
    /// Falls back to the first built-in if nil or stale.
    var defaultPersonaID: UUID?

    /// Maximum lines of buffer history fed to the model as conversation
    /// context per request. Higher = better continuity, more tokens, slower.
    var contextLineCount: Int = 24

    /// Soft cap on tokens the model is asked to produce. Maps to Ollama's
    /// `num_predict` option. Keeps replies IRC-short by construction.
    var maxResponseTokens: Int = 200

    /// Sampling temperature — lower = more deterministic, higher = more
    /// creative. 0.7 is a reasonable starting point for chat.
    var temperature: Double = 0.7
}
