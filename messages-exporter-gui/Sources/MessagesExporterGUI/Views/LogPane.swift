import SwiftUI
import AppKit

/// Scrolling monospaced log of the CLI's stdout. Renders the joined log
/// as a single Text so the user can drag-select across line boundaries
/// and copy with ⌘C; a "Copy log" button copies everything in one shot.
/// An action row exposes Reveal/Open buttons once a run folder has been
/// captured by the runner.
struct LogPane: View {
    let lines: [String]
    let runFolder: URL?
    let lastError: String?

    private static let bottomAnchorID = "log-bottom-anchor"
    private var joined: String { lines.joined(separator: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(lastError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            HStack {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyLogToPasteboard()
                } label: {
                    Label("Copy log", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .disabled(lines.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Text(joined)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        // Stable, zero-height anchor at the bottom. Keeps
                        // the Text view's identity stable so SwiftUI doesn't
                        // tear it down and rebuild on every appended line.
                        Color.clear.frame(height: 0).id(Self.bottomAnchorID)
                    }
                }
                .background(Color.black.opacity(0.05))
                .onChange(of: lines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            actionRow
        }
    }

    private func copyLogToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
    }

    @ViewBuilder
    private var actionRow: some View {
        if let runFolder {
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([runFolder])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                openButton(name: "transcript.txt",
                           label: "Transcript",
                           icon: "text.alignleft",
                           in: runFolder)
                openButton(name: "summary.txt",
                           label: "Summary",
                           icon: "doc.text",
                           in: runFolder)
                openButton(name: "manifest.json",
                           label: "Manifest",
                           icon: "curlybraces",
                           in: runFolder)
                Spacer()
                Text(runFolder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(runFolder.path)
            }
        }
    }

    @ViewBuilder
    private func openButton(name: String, label: String, icon: String, in dir: URL) -> some View {
        let url = dir.appendingPathComponent(name)
        let exists = FileManager.default.fileExists(atPath: url.path)
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(label, systemImage: icon)
        }
        .disabled(!exists)
        .help(exists ? url.path : "\(name) not present in run folder")
    }
}
