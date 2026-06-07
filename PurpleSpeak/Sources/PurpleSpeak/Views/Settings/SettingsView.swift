import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.circle") }
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "textformat.size") }
            TranscriptionSettings()
                .tabItem { Label("Transcription", systemImage: "waveform") }
            OutputSettings()
                .tabItem { Label("Output", systemImage: "folder") }
            BackupSettings()
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.timemachine") }
        }
        .padding(20)
    }
}

// MARK: - Playback

private struct PlaybackSettings: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var tts: AVSpeechTTSEngine

    var body: some View {
        Form {
            Picker("Default voice", selection: Binding(
                get: { settings.settings.defaultVoiceIdentifier ?? "" },
                set: { settings.settings.defaultVoiceIdentifier = $0.isEmpty ? nil : $0 })
            ) {
                Text("System default").tag("")
                ForEach(tts.voicesByLanguage()) { group in
                    Section(group.displayName) {
                        ForEach(group.voices) { v in
                            Text("\(v.name) · \(v.quality)").tag(v.id)
                        }
                    }
                }
            }
            LabeledContent("Speed") {
                HStack {
                    Slider(value: $settings.settings.speechRateMultiplier, in: 0.5...4.0, step: 0.25)
                    Text(String(format: "%.2g×", settings.settings.speechRateMultiplier))
                        .monospacedDigit().frame(width: 40)
                }
            }
            LabeledContent("Pitch") {
                HStack {
                    Slider(value: $settings.settings.speechPitch, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2g", settings.settings.speechPitch))
                        .monospacedDigit().frame(width: 40)
                }
            }
            Toggle("Also highlight the current sentence", isOn: $settings.settings.highlightSentence)
            Text("Premium and Enhanced voices download from System Settings → Accessibility → Spoken Content → System Voices. Speeds above ~2× saturate at the engine's maximum rate.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Reading

private struct ReadingSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            LabeledContent("Font size") {
                HStack {
                    Slider(value: $settings.settings.readerFontSize, in: 12...34, step: 1)
                    Text("\(Int(settings.settings.readerFontSize)) pt").frame(width: 50)
                }
            }
            LabeledContent("Line spacing") {
                HStack {
                    Slider(value: $settings.settings.readerLineSpacing, in: 0...18, step: 1)
                    Text("\(Int(settings.settings.readerLineSpacing))").frame(width: 50)
                }
            }
            Toggle("Line focus (dim everything but the active paragraph)",
                   isOn: $settings.settings.lineFocusEnabled)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Transcription

private struct TranscriptionSettings: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var models: WhisperModelManager

    var body: some View {
        Form {
            Picker("Active model", selection: $settings.settings.whisperModel) {
                ForEach(WhisperModelManager.catalog, id: \.name) { entry in
                    Text(entry.label).tag(entry.name)
                }
            }
            Section("Models") {
                ForEach(WhisperModelManager.catalog, id: \.name) { entry in
                    HStack {
                        Image(systemName: models.isInstalled(entry.name)
                              ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(models.isInstalled(entry.name) ? .green : .secondary)
                        Text(entry.label)
                        Spacer()
                        if models.isInstalled(entry.name) {
                            Text("Installed").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Download") { Task { await models.download(name: entry.name) } }
                                .disabled(models.isDownloading)
                        }
                    }
                }
                if models.isDownloading {
                    ProgressView("Downloading…")
                }
                if let err = models.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            TextField("Language (auto, en, es, fr, …)", text: $settings.settings.transcriptionLanguage)
            Text("Transcription runs fully on-device via whisper.cpp. Models are large and download on demand into ~/Library/Application Support/PurpleSpeak/models/.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Output

private struct OutputSettings: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            LabeledContent("Save audio & transcripts to") {
                HStack {
                    Text(settings.settings.outputDirectory).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseOutput() }
                    Button("Default") { settings.settings.outputDirectory = "~/Downloads/PurpleSpeak" }
                }
            }
            Picker("Audio format", selection: $settings.settings.preferredAudioFormat) {
                Text("M4A (AAC — recommended)").tag("m4a")
                Text("MP3 (needs `lame` on PATH)").tag("mp3")
            }
            Text("Exports default to ~/Downloads/PurpleSpeak/. MP3 falls back to M4A unless Homebrew `lame` is installed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.outputDirectory = url.path
        }
    }
}
