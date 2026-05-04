import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var ollamaSetup: OllamaSetup
    @EnvironmentObject var characterStore: CharacterStore
    @State private var showingResetConfirm = false

    var body: some View {
        Form {
            Section("Ollama") {
                HStack {
                    Text("Connection")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ollamaService.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(ollamaService.isConnected ? "Connected" : "Offline")
                            .foregroundStyle(ollamaService.isConnected ? .green : .red)
                    }
                }

                Button("Refresh") {
                    Task {
                        await ollamaService.checkConnection()
                        await ollamaSetup.run()
                    }
                }
            }

            Section {
                if ollamaService.availableModels.isEmpty {
                    Text(ollamaService.isConnected ? "No models installed yet — install one below." : "Start Ollama to see installed models.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Picker("Active Model", selection: Binding(
                        get: { ollamaService.selectedModel },
                        set: { ollamaService.setModel($0) }
                    )) {
                        ForEach(ollamaService.availableModels) { model in
                            ModelPickerRow(model: model).tag(model.name)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("This is the default model. Each character can override it in their editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Active Model")
            }

            Section {
                ForEach(OllamaModel.recommended) { rec in
                    RecommendedModelRow(rec: rec)
                    if rec.id != OllamaModel.recommended.last?.id { Divider() }
                }
            } header: {
                Text("Install Models")
            } footer: {
                Text("Models are pulled directly via Ollama. The first download for each is a few GB; afterwards they're available offline. **Tip:** if the active model is still adding safety warnings, install one of the green **Uncensored** models above and switch to it.")
                    .font(.caption)
            }

            Section("Characters") {
                Button("Reset All Built-in Characters") {
                    showingResetConfirm = true
                }
                .foregroundStyle(.orange)
                Text("Restores all built-in bots to their original personalities and names.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack {
                    Text("SizzleBot requires")
                    Link("Ollama", destination: URL(string: "https://ollama.com")!)
                    Text("running locally on port 11434.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .navigationTitle("Settings")
        .confirmationDialog("Reset all built-in characters?",
                            isPresented: $showingResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset All", role: .destructive) { characterStore.resetAllBuiltIns() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All built-in bots will be restored to their original personalities. This cannot be undone.")
        }
    }
}

/// One row inside the Active Model picker — shows name, size, and an alignment chip
/// when the model is in the recommended list.
private struct ModelPickerRow: View {
    let model: OllamaModel

    var body: some View {
        HStack(spacing: 8) {
            Text(model.displayName)
            if let rec = OllamaModel.recommendation(for: model.name) {
                if rec.kind == .vision { VisionChip() }
                AlignmentChip(alignment: rec.alignment)
            }
            if !model.sizeString.isEmpty {
                Text(model.sizeString)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

/// One row inside the "Install Models" section — name, alignment chip,
/// description, and either an Install button, an in-progress bar, or an
/// "Installed" / "Active" state indicator.
private struct RecommendedModelRow: View {
    let rec: OllamaModel.Recommendation
    @EnvironmentObject var ollamaService: OllamaService
    @EnvironmentObject var ollamaSetup: OllamaSetup

    private var isInstalled: Bool {
        ollamaService.availableModels.contains { $0.displayName == rec.id }
    }

    private var isActive: Bool {
        (ollamaService.selectedModel.components(separatedBy: ":").first ?? ollamaService.selectedModel) == rec.id
    }

    private var progress: Double? {
        ollamaSetup.pullProgress[rec.id]
    }

    private var pullStatus: String? {
        ollamaSetup.pullStatus[rec.id]
    }

    private var pullError: String? {
        ollamaSetup.pullErrors[rec.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(rec.name).fontWeight(.medium)
                if rec.kind == .vision { VisionChip() }
                AlignmentChip(alignment: rec.alignment)
                Spacer()
                trailingControl
            }
            Text(rec.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let status = pullStatus {
                HStack(spacing: 8) {
                    if let p = progress, p > 0 {
                        ProgressView(value: p).progressViewStyle(.linear).frame(maxWidth: 220)
                        Text("\(Int(p * 100))%").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let err = pullError {
                Text("Failed: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isActive {
            Label("Active", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
                .font(.caption)
        } else if isInstalled {
            HStack(spacing: 8) {
                Label("Installed", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("Use") { ollamaService.setModel(rec.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        } else if progress != nil {
            Button(role: .cancel) { } label: {
                Text("Installing…").font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(true)
        } else {
            Button("Install") {
                Task { await ollamaSetup.pullModelOnDemand(rec.id, then: ollamaService) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

private struct VisionChip: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.fill").font(.caption2)
            Text("Vision").font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.purple.opacity(0.18))
        .foregroundStyle(Color.purple)
        .clipShape(Capsule())
    }
}

private struct AlignmentChip: View {
    let alignment: OllamaModel.Alignment

    private var color: Color {
        switch alignment {
        case .uncensored: return .green
        case .lightlyAligned: return .yellow
        case .aligned: return .orange
        }
    }

    var body: some View {
        Text(alignment.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
