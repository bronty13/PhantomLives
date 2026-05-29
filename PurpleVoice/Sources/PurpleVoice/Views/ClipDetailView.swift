import SwiftUI
import AppKit

/// Detail pane for one selected clip. Shows filename, status, progress,
/// playback controls with A/B swap, the waveform with trim handles,
/// and the processing knobs from `ProcessingControls`.
struct ClipDetailView: View {
    @ObservedObject var clip: Clip
    @EnvironmentObject var queue: ProcessingQueue
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var player = AudioPlayer()

    /// A/B toggle state — `false` = original, `true` = cleaned.
    /// Read by the play row to render the active label and by `swap()`
    /// to choose the target URL.
    @State private var preferCleaned: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusRow
                WaveformView(clip: clip, player: player)
                playbackRow
                ProcessingControls()
                if clip.status == .failed, let msg = clip.lastError {
                    errorPane(msg: msg)
                }
                Spacer(minLength: 12)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: clip.id) {
            player.stop()
            preferCleaned = false
        }
        .onChange(of: clip.outputURL) { _, newValue in
            // When processing finishes, default the A/B toggle to
            // Cleaned so the user hears the result first when they
            // hit play.
            if newValue != nil { preferCleaned = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.displayName)
                .font(.title2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(clip.sourceURL.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch clip.status {
        case .queued:
            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text("Queued")
            }
            .foregroundStyle(.secondary)
        case .processing:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cleaning…")
                }
                ProgressView(value: clip.progress)
                    .progressViewStyle(.linear)
            }
        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Done")
                Spacer()
                if let url = clip.outputURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                }
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Failed")
                Spacer()
                Button("Retry") {
                    queue.retry(clip, settings: settings)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var playbackRow: some View {
        HStack(spacing: 12) {
            // A/B toggle — picker even when cleaned isn't ready yet,
            // so the user sees the affordance.
            Picker("Source", selection: $preferCleaned) {
                Text("Original").tag(false)
                Text("Cleaned").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .disabled(clip.outputURL == nil)
            .onChange(of: preferCleaned) { _, _ in
                // Mid-playback swap: keep position + play state.
                if let target = activePlaybackURL() {
                    player.swap(to: target)
                }
            }

            Button {
                guard let url = activePlaybackURL() else { return }
                player.toggle(url: url)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName:
                        (player.isPlaying ? "stop.fill" : "play.fill")
                    )
                    Text(player.isPlaying ? "Stop" : "Play")
                }
                .frame(minWidth: 90)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(activePlaybackURL() == nil)
            .keyboardShortcut(.space, modifiers: [])

            Spacer()

            Button(role: .destructive) {
                player.stop()
                queue.remove(clip)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    /// The URL that the play button should currently target. Honors
    /// the A/B toggle and falls back to original when cleaned isn't
    /// available yet.
    private func activePlaybackURL() -> URL? {
        if preferCleaned, let out = clip.outputURL {
            return out
        }
        return clip.sourceURL
    }

    private func errorPane(msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Processing error", systemImage: "exclamationmark.bubble")
                .font(.subheadline)
                .foregroundStyle(.red)
            ScrollView {
                Text(msg)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red.opacity(0.06))
            )
        }
    }
}
