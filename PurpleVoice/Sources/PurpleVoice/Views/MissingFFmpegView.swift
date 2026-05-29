import SwiftUI
import AppKit

/// Shown in the main pane when `FFmpegLocator.find()` returns nil at
/// launch. ffmpeg is the entire processing engine — without it the
/// app can do nothing useful, so block the normal UI behind an
/// actionable install hint rather than letting the user drag a clip
/// in and watch it fail.
struct MissingFFmpegView: View {
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("ffmpeg not found")
                .font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text("PurpleVoice uses **ffmpeg** to denoise and enhance audio. Install it with Homebrew:")
                    .multilineTextAlignment(.leading)
                copyableCommand("brew install ffmpeg")
                Text("Then click **Re-check** below. PurpleVoice searches `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, and your `PATH`.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 480)
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "https://brew.sh") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Install Homebrew…", systemImage: "safari")
                }
                Button {
                    onRecheck()
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyableCommand(_ cmd: String) -> some View {
        HStack(spacing: 8) {
            Text(cmd)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
    }
}
