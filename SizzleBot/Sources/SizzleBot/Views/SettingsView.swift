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

                if !ollamaService.availableModels.isEmpty {
                    Picker("Active Model", selection: Binding(
                        get: { ollamaService.selectedModel },
                        set: { ollamaService.setModel($0) }
                    )) {
                        ForEach(ollamaService.availableModels) { model in
                            HStack {
                                Text(model.displayName)
                                if !model.sizeString.isEmpty {
                                    Text(model.sizeString).foregroundStyle(.secondary).font(.caption)
                                }
                            }
                            .tag(model.name)
                        }
                    }
                } else {
                    Text(ollamaService.isConnected ? "No models installed yet." : "Start Ollama to see installed models.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                DisclosureGroup("Recommended Models") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(OllamaModel.recommended, id: \.id) { rec in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(rec.name).fontWeight(.medium)
                                    Spacer()
                                    Text("ollama pull \(rec.id)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Text(rec.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if rec.id != OllamaModel.recommended.last?.id { Divider() }
                        }
                    }
                    .padding(.top, 6)
                }
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
        .frame(width: 500, height: 540)
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
