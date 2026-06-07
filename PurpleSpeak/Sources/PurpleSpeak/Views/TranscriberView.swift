import SwiftUI
import AppKit

/// Speech-to-text surface: drop an audio/video file, run Whisper, show an
/// editable timestamped transcript, then export or send it to the reader.
struct TranscriberView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            if let p = providers.first {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { appState.transcribe(fileURL: url) } }
                }
                return true
            }
            return false
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "waveform").foregroundStyle(.purple)
            Text(appState.transcriptSourceName.isEmpty ? "Transcribe" : appState.transcriptSourceName)
                .font(.headline)
            Spacer()
            if appState.transcript != nil {
                Button("Send to Reader") { appState.saveTranscriptAsDocument() }
                Button("Export .txt") { appState.exportTranscript(asSRT: false) }
                Button("Export .srt") { appState.exportTranscript(asSRT: true) }
            }
            Button("Choose File…") { appState.presentTranscribePanel() }
            Button("Back to Reader") { appState.mode = .reader }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let transcript = appState.transcript {
            List(transcript.segments) { seg in
                HStack(alignment: .top, spacing: 10) {
                    Text(timecode(seg.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.purple)
                        .frame(width: 70, alignment: .leading)
                    Text(seg.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 50))
                    .foregroundStyle(.purple.opacity(0.6))
                Text("Drop an audio or video file here")
                    .font(.title3.weight(.semibold))
                Text("On-device transcription with Whisper. The first run downloads the model — set it up in Settings → Transcription.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
                Button { appState.presentTranscribePanel() } label: {
                    Label("Choose Audio / Video…", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent).tint(.purple)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func timecode(_ t: Double) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
