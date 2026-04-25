import SwiftUI

/// Setup → Bot subsection for the local-LLM assistant. Wires the
/// AssistantSettings struct to a Form-style UI, lists available models
/// fetched from Ollama, and lets the user manage their persona library.
struct AssistantSetupSection: View {
    @ObservedObject var settings: SettingsStore

    /// Ollama health probe state — populated by the "Test connection"
    /// button. Lets us surface a usable error when the URL is wrong or
    /// `ollama serve` isn't running.
    @State private var probeStatus: ProbeStatus = .unknown
    @State private var availableModels: [String] = []
    @State private var probing: Bool = false

    /// Persona being edited in the inline editor sheet, if any.
    @State private var editingPersona: AssistantPersona?
    /// True when the editor sheet is for a brand-new persona vs an existing one.
    @State private var editingIsNew: Bool = false

    enum ProbeStatus: Equatable {
        case unknown
        case ok(version: String, modelCount: Int)
        case error(String)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable local-LLM chat assistant",
                       isOn: $settings.settings.assistant.enabled)
                Text("When on, /assist in a query buffer engages a local model running under Ollama. The model drafts replies you accept, edit, or dismiss — nothing sends without your action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.settings.assistant.enabled {
                    Divider()
                    connectionRows
                    Divider()
                    personaRows
                    Divider()
                    tuningRows
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Local-LLM assistant", systemImage: "sparkles")
                .font(.headline)
        }
        .sheet(item: $editingPersona) { editing in
            PersonaEditor(
                draft: editing,
                isNew: editingIsNew,
                onSave: { saved in commit(saved) },
                onCancel: { editingPersona = nil }
            )
        }
    }

    // MARK: - Connection

    private var connectionRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ollama URL").frame(width: 110, alignment: .trailing)
                TextField("http://localhost:11434",
                          text: $settings.settings.assistant.ollamaURL)
                    .textFieldStyle(.roundedBorder)
                Button("Test") { probe() }
                    .disabled(probing)
            }
            HStack {
                Text("Model").frame(width: 110, alignment: .trailing)
                if availableModels.isEmpty {
                    TextField("dolphin3:8b",
                              text: $settings.settings.assistant.modelName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $settings.settings.assistant.modelName) {
                        ForEach(availableModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        // Allow a custom value the user typed manually that
                        // doesn't appear in the picker — tag it as itself
                        // so the binding round-trips cleanly.
                        if !availableModels.contains(settings.settings.assistant.modelName) {
                            Text(settings.settings.assistant.modelName + " (not installed)")
                                .tag(settings.settings.assistant.modelName)
                        }
                    }
                    .labelsHidden()
                }
            }
            switch probeStatus {
            case .unknown:
                Text("Not yet tested. We recommend `dolphin3:8b` (`ollama pull dolphin3:8b`) — light alignment, well-suited for casual chat. Alternatives: `hermes3:8b`, `mistral-nemo:12b`.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .ok(let version, let count):
                Label("Connected to Ollama \(version) — \(count) model\(count == 1 ? "" : "s") installed.",
                      systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(Color.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    // MARK: - Personas

    private var personaRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Default persona").frame(width: 110, alignment: .trailing)
                Picker("", selection: defaultPersonaBinding) {
                    ForEach(settings.settings.assistantPersonas) { p in
                        Text(p.name).tag(p.id as UUID?)
                    }
                    if settings.settings.assistantPersonas.isEmpty {
                        Text("(no personas)").tag(UUID?.none)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text("Library").frame(width: 110, alignment: .trailing)
                Spacer()
                Button {
                    editingIsNew = true
                    editingPersona = AssistantPersona(name: "New persona")
                } label: { Label("New", systemImage: "plus") }
                Button {
                    seedBuiltins()
                } label: { Label("Restore built-ins", systemImage: "arrow.counterclockwise") }
                    .help("Re-add any built-in personas you've removed. Existing entries unaffected.")
            }
            personaList
        }
    }

    private var personaList: some View {
        VStack(spacing: 0) {
            ForEach(settings.settings.assistantPersonas) { persona in
                HStack(spacing: 6) {
                    Image(systemName: persona.isBuiltin ? "sparkles" : "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(persona.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if persona.isBuiltin {
                        Text("built-in")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Edit") {
                        editingIsNew = false
                        editingPersona = persona
                    }
                    .controlSize(.small)
                    Button(role: .destructive) {
                        delete(persona)
                    } label: { Image(systemName: "trash") }
                        .controlSize(.small)
                        .help("Remove from library")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(4)
            }
        }
    }

    // MARK: - Tuning

    private var tuningRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Context lines").frame(width: 110, alignment: .trailing)
                Stepper(value: $settings.settings.assistant.contextLineCount,
                        in: 4...64, step: 2) {
                    Text("\(settings.settings.assistant.contextLineCount) lines fed to the model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Reply token cap").frame(width: 110, alignment: .trailing)
                Stepper(value: $settings.settings.assistant.maxResponseTokens,
                        in: 50...600, step: 25) {
                    Text("up to \(settings.settings.assistant.maxResponseTokens) tokens (~\(settings.settings.assistant.maxResponseTokens / 4) words)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Temperature").frame(width: 110, alignment: .trailing)
                Slider(value: $settings.settings.assistant.temperature,
                       in: 0.1...1.5, step: 0.05)
                Text(String(format: "%.2f", settings.settings.assistant.temperature))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - Bindings + actions

    private var defaultPersonaBinding: Binding<UUID?> {
        Binding(
            get: { settings.settings.assistant.defaultPersonaID },
            set: { settings.settings.assistant.defaultPersonaID = $0 }
        )
    }

    private func probe() {
        probing = true
        let raw = settings.settings.assistant.ollamaURL
        Task { @MainActor in
            defer { probing = false }
            do {
                let client = try OllamaClient(rawURL: raw)
                let version = try await client.version()
                let models = (try? await client.listModels()) ?? []
                self.availableModels = models
                self.probeStatus = .ok(version: version, modelCount: models.count)
            } catch {
                self.probeStatus = .error(error.localizedDescription)
                self.availableModels = []
            }
        }
    }

    private func seedBuiltins() {
        let existingIDs = Set(settings.settings.assistantPersonas.map { $0.id })
        for builtin in AssistantPersona.defaultPersonas() {
            if !existingIDs.contains(builtin.id) {
                settings.settings.assistantPersonas.append(builtin)
            }
        }
    }

    private func delete(_ persona: AssistantPersona) {
        settings.settings.assistantPersonas.removeAll { $0.id == persona.id }
        // If the default just got removed, fall back to the first remaining.
        if settings.settings.assistant.defaultPersonaID == persona.id {
            settings.settings.assistant.defaultPersonaID =
                settings.settings.assistantPersonas.first?.id
        }
    }

    private func commit(_ persona: AssistantPersona) {
        if let i = settings.settings.assistantPersonas.firstIndex(
            where: { $0.id == persona.id }
        ) {
            settings.settings.assistantPersonas[i] = persona
        } else {
            settings.settings.assistantPersonas.append(persona)
        }
        editingPersona = nil
    }
}

/// Modal sheet that edits one persona's name + system prompt. Long-form
/// prompt body uses our spell-checked TextEditor so users can write
/// careful instructions without their nicks getting flagged.
private struct PersonaEditor: View {
    @State var draft: AssistantPersona
    let isNew: Bool
    let onSave: (AssistantPersona) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New persona" : "Edit persona")
                    .font(.headline)
                Spacer()
                if draft.isBuiltin {
                    Text("built-in")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding()
            Divider()
            Form {
                Section("Name") {
                    TextField("Casual chat", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                Section("System prompt") {
                    SpellCheckedTextEditor(text: $draft.systemPrompt,
                                           font: .systemFont(ofSize: 13))
                        .frame(minHeight: 220)
                    Text("This text is sent as the system message before each request. Use `{{slots}}` like `{{character_name}}` if you want to leave fields to fill in later — they're not auto-substituted; you edit the persona to set them.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") {
                    var saved = draft
                    // Editing a built-in clears the badge — diverges
                    // from the shipped template so future restores
                    // re-add the original alongside the user's edit.
                    if saved.isBuiltin && originalBuiltin?.systemPrompt != saved.systemPrompt {
                        saved.isBuiltin = false
                        saved.id = UUID()    // new identity to preserve the original
                    }
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    /// If this draft started life as a built-in, find the original so we
    /// can detect "user changed the prompt" — that flips the entry into
    /// a custom one to preserve the shipped template.
    private var originalBuiltin: AssistantPersona? {
        AssistantPersona.defaultPersonas().first { $0.id == draft.id }
    }
}
