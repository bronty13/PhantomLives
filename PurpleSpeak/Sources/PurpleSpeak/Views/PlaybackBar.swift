import SwiftUI

/// Persistent transport at the bottom of the reader: play/pause, stop,
/// paragraph skip, speed, voice picker, and export-to-audio.
struct PlaybackBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tts: AVSpeechTTSEngine
    @EnvironmentObject var settings: SettingsStore

    private var isPlaying: Bool { tts.isSpeaking && !tts.isPaused }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Button { appState.skip(byParagraphs: -1) } label: {
                    Image(systemName: "backward.end.fill")
                }
                .help("Previous paragraph (⌘←)")
                .disabled(appState.currentText.isEmpty)

                Button { appState.togglePlayPause() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
                .help("Play / Pause (Space)")
                .disabled(appState.currentText.isEmpty)

                Button { appState.skip(byParagraphs: 1) } label: {
                    Image(systemName: "forward.end.fill")
                }
                .help("Next paragraph (⌘→)")
                .disabled(appState.currentText.isEmpty)

                Button { tts.stop() } label: { Image(systemName: "stop.fill") }
                    .help("Stop (⌘.)")
                    .disabled(!tts.isSpeaking && !tts.isPaused)

                Divider().frame(height: 22)

                // Speed
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.settings.speechRateMultiplier,
                           in: 0.5...4.0, step: 0.25)
                        .frame(width: 130)
                    Text(String(format: "%.2g×", settings.settings.speechRateMultiplier))
                        .font(.caption.monospacedDigit())
                        .frame(width: 34, alignment: .leading)
                }

                // Voice
                voicePicker

                Spacer()

                Button { appState.exportCurrentAudio() } label: {
                    Label("Export Audio", systemImage: "square.and.arrow.up")
                }
                .help("Export narration to \(settings.settings.preferredAudioFormat.uppercased()) (⇧⌘E)")
                .disabled(appState.currentText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var voicePicker: some View {
        let voices = tts.availableVoices()
        return Picker("Voice", selection: Binding(
            get: { settings.settings.defaultVoiceIdentifier
                    ?? AVSpeechTTSEngine.systemDefaultVoiceID()
                    ?? voices.first?.id ?? "" },
            set: { settings.settings.defaultVoiceIdentifier = $0 })
        ) {
            ForEach(voices) { v in
                Text("\(v.name) · \(v.quality) · \(v.language)").tag(v.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 230)
    }
}
