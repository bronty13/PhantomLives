import SwiftUI

/// The reading pane: a TextKit-backed reading surface (`ReaderTextView`) above
/// the playback transport. The TextKit surface gives word-precise
/// click-to-start, native selection, and synced word + sentence highlighting.
struct ReaderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tts: AVSpeechTTSEngine
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            ReaderTextView(
                text: appState.currentText,
                fontSize: settings.settings.readerFontSize,
                lineSpacing: settings.settings.readerLineSpacing,
                wordRange: tts.spokenWordRange,
                sentenceRange: settings.settings.highlightSentence ? tts.spokenSentenceRange : nil,
                lineFocus: settings.settings.lineFocusEnabled,
                isSpeaking: tts.isSpeaking,
                onClickOffset: { offset in
                    // Click any word → start reading from exactly there.
                    appState.startReading(from: offset)
                }
            )
            PlaybackBar()
        }
    }
}
