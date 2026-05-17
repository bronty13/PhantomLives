import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
    }
}

struct BackupSettingsView: View {
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled: Bool = true
    @AppStorage("backupRetentionDays") private var backupRetentionDays: Int = 14

    var body: some View {
        Form {
            Section("Auto-backup") {
                Toggle("Backup on launch", isOn: $autoBackupEnabled)
                Stepper("Retention: \(backupRetentionDays) days",
                        value: $backupRetentionDays, in: 0...365)
                Text("Backups land in ~/Downloads/PurpleReel backup/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AISettingsView: View {
    @AppStorage("whisperScriptPath") private var whisperScriptPath: String = ""
    @AppStorage("whisperModel") private var whisperModel: String = "turbo"
    @AppStorage("ollamaModel") private var ollamaModel: String = OllamaService.defaultModel

    @State private var ollamaReachable: Bool? = nil
    @State private var installedOllamaModels: [String] = []
    @State private var whisperScriptOK: Bool? = nil

    private let whisperModels = ["turbo", "tiny", "base", "small", "medium", "large-v3"]

    var body: some View {
        Form {
            Section("Whisper transcription") {
                HStack {
                    TextField("Script path", text: $whisperScriptPath,
                                prompt: Text(WhisperService.defaultScriptPath))
                    Button("Choose…") { pickScript() }
                    Button("Default") { whisperScriptPath = "" }
                        .disabled(whisperScriptPath.isEmpty)
                }
                Picker("Model", selection: $whisperModel) {
                    ForEach(whisperModels, id: \.self) { Text($0).tag($0) }
                }
                statusLabel(whisperScriptOK,
                             ok: "transcribe.py found",
                             bad: "transcribe.py not found at \(effectiveWhisperPath)")
                Text("First run downloads MLX-Whisper weights (~1 GB for turbo). Subsequent runs reuse them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ollama auto-describe") {
                HStack {
                    if installedOllamaModels.isEmpty {
                        TextField("Model name", text: $ollamaModel)
                    } else {
                        Picker("Model", selection: $ollamaModel) {
                            ForEach(installedOllamaModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Refresh") { refreshOllama() }
                }
                statusLabel(ollamaReachable,
                             ok: "Ollama is running at localhost:11434",
                             bad: "Ollama unreachable. Install from ollama.com and run `ollama serve`.")
                Text("Pull a small model for fast descriptions: `ollama pull llama3.2:1b`.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshOllama()
            checkWhisperScript()
        }
        .onChange(of: whisperScriptPath) { _, _ in checkWhisperScript() }
    }

    private var effectiveWhisperPath: String {
        whisperScriptPath.isEmpty ? WhisperService.defaultScriptPath : whisperScriptPath
    }

    private func pickScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            whisperScriptPath = url.path
        }
    }

    private func checkWhisperScript() {
        whisperScriptOK = FileManager.default.fileExists(atPath: effectiveWhisperPath)
    }

    private func refreshOllama() {
        Task {
            let reachable = await OllamaService.isReachable()
            let models = reachable ? await OllamaService.listInstalledModels() : []
            await MainActor.run {
                self.ollamaReachable = reachable
                self.installedOllamaModels = models
                if reachable, !models.isEmpty, !models.contains(self.ollamaModel) {
                    self.ollamaModel = models.first ?? self.ollamaModel
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ ok: Bool?, ok okText: String, bad badText: String) -> some View {
        if let ok {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(ok ? .green : .red)
                Text(ok ? okText : badText)
                    .font(.caption)
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PurpleReel \(AppVersion.display)").font(.headline)
            Text("Media management for Final Cut Pro, with on-device AI augmentation.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
