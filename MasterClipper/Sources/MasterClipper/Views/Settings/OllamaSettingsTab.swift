import SwiftUI

struct OllamaSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var ollama = OllamaService.shared
    @StateObject private var setup = OllamaSetup.shared

    @State private var refineSample: String = "She wears black pantyhose and tease tease so much. So nylon."
    @State private var refineOutput: String = ""
    @State private var refining: Bool = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ollama integration")
                    .font(.title3.weight(.semibold))

                Form {
                    Toggle("Enable Ollama", isOn: Binding(
                        get: { appState.settings.ollamaEnabled },
                        set: { var s = appState.settings; s.ollamaEnabled = $0; appState.settings = s }
                    ))

                    Toggle("Auto-start `ollama serve` on launch", isOn: Binding(
                        get: { appState.settings.ollamaAutoStart },
                        set: { var s = appState.settings; s.ollamaAutoStart = $0; appState.settings = s }
                    ))

                    TextField("Base URL", text: Binding(
                        get: { appState.settings.ollamaBaseURL },
                        set: { var s = appState.settings; s.ollamaBaseURL = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Picker("Model", selection: Binding(
                            get: { appState.settings.ollamaModel },
                            set: { var s = appState.settings; s.ollamaModel = $0; appState.settings = s }
                        )) {
                            if !ollama.availableModels.isEmpty {
                                ForEach(ollama.availableModels, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            } else {
                                Text(appState.settings.ollamaModel).tag(appState.settings.ollamaModel)
                            }
                        }
                        Button("Refresh") {
                            Task { await ollama.checkConnection(settings: appState.settings) }
                        }
                    }
                }
                .formStyle(.grouped)

                statusBox

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Refinement prompt template").font(.headline)
                        Spacer()
                        Button("Reset to default") {
                            var s = appState.settings
                            s.refinePromptTemplate = AppSettings.defaultRefinePromptTemplate
                            appState.settings = s
                        }
                        .help("Replace the current prompt with the conservative copy-edit default — minimal changes, preserves the creator's voice.")
                    }
                    Text("`{{description}}` is replaced with the clip's raw description. The default is a conservative copy edit (spelling / casing / typos only); the LLM is instructed not to rewrite or paraphrase.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { appState.settings.refinePromptTemplate },
                        set: { var s = appState.settings; s.refinePromptTemplate = $0; appState.settings = s }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 200)
                    .border(.separator)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Test refine")
                        .font(.headline)
                    TextEditor(text: $refineSample)
                        .font(.body)
                        .frame(minHeight: 80)
                        .border(.separator)

                    HStack {
                        Button {
                            runTestRefine()
                        } label: {
                            if refining { ProgressView().controlSize(.small) }
                            else { Text("Refine") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(refining || !setup.canRunRefine)
                        Spacer()
                        if let error = error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }

                    Text("Output")
                        .font(.headline).padding(.top, 6)
                    ScrollView {
                        Text(refineOutput.isEmpty ? "(no output yet)" : refineOutput)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(minHeight: 100)
                    .background(.background.secondary)
                    .border(.separator)
                }
            }
            .padding(20)
        }
        .task {
            await setup.run(settings: appState.settings)
            await ollama.checkConnection(settings: appState.settings)
        }
    }

    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if ollama.isReachable {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
                } else {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.title2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(setup.statusMessage.isEmpty
                         ? (ollama.isReachable ? "Ollama is reachable" : "Ollama is not reachable")
                         : setup.statusMessage)
                        .font(.headline)
                    if !ollama.availableModels.isEmpty {
                        Text("Installed: \(ollama.availableModels.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if ollama.isReachable {
                        Text("Reachable but no models installed yet. Run `ollama pull <model>` in Terminal.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Warn + offer one-click switch when the configured model isn't installed
            if ollama.isReachable, !ollama.availableModels.isEmpty,
               !ollama.availableModels.contains(appState.settings.ollamaModel) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\"\(appState.settings.ollamaModel)\" isn't installed.")
                        .font(.callout)
                    if let first = ollama.availableModels.first {
                        Button("Use \(first)") {
                            var s = appState.settings
                            s.ollamaModel = first
                            appState.settings = s
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func runTestRefine() {
        refining = true
        refineOutput = ""
        error = nil
        Task {
            do {
                try await OllamaService.refine(
                    description: refineSample,
                    promptTemplate: appState.settings.refinePromptTemplate,
                    model: appState.settings.ollamaModel,
                    baseURLString: appState.settings.ollamaBaseURL,
                    onToken: { token in
                        refineOutput += token
                    }
                )
                refining = false
            } catch {
                refining = false
                self.error = error.localizedDescription
            }
        }
    }
}

private extension OllamaSetup {
    var canRunRefine: Bool {
        if case .ready = state { return true }
        return statusMessage.contains("reachable") || statusMessage.isEmpty
    }
}
