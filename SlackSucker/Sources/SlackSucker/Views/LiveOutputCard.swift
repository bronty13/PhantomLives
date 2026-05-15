import SwiftUI
import AppKit

/// Scrollable log of the most recent slackdump output. Auto-scrolls to
/// the bottom unless the user has scrolled up. Surface chips along the
/// top let the user copy the buffer, reveal the run folder, or resume
/// a cancelled run.
struct LiveOutputCard: View {
    let lines: [String]
    let runFolder: URL?
    let canResume: Bool
    var onResume: () -> Void

    @State private var autoScroll = true

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("LIVE OUTPUT")
                        .font(AppFont.kicker())
                        .foregroundStyle(.secondary)
                    Spacer()
                    chip("Copy", systemImage: "doc.on.doc") { copyLog() }
                    if let folder = runFolder {
                        chip("Reveal", systemImage: "folder") { reveal(folder) }
                        chip("Open DB", systemImage: "tablecells") {
                            openDB(folder.appendingPathComponent("slackdump.sqlite"))
                        }
                    }
                    if canResume, runFolder != nil {
                        chip("Resume", systemImage: "play.fill", emphasised: true, action: onResume)
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(AppFont.mono(11))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(8)
                    }
                    .frame(minHeight: 140, maxHeight: 240)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: lines.count) { _, _ in
                        if autoScroll { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func chip(_ title: String, systemImage: String, emphasised: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(AppFont.sans(11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(emphasised ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(emphasised ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openDB(_ url: URL) {
        // Prefer DB Browser for SQLite if installed; fall back to the
        // OS default for .sqlite which is usually `open` → reveal.
        let dbBrowser = URL(fileURLWithPath: "/Applications/DB Browser for SQLite.app")
        if FileManager.default.fileExists(atPath: dbBrowser.path) {
            NSWorkspace.shared.open([url], withApplicationAt: dbBrowser,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
