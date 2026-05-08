import SwiftUI
import AppKit

/// Frosted card that contains the CLI's stdout, plus the post-run open-
/// the-output-files chip row. Replaces the older bare-list LogPane look
/// with the Mission Control aesthetic — same data, same actions, but
/// styled to match the rest of the new layout.
struct LiveOutputCard: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner

    private static let bottomAnchorID = "log-bottom-anchor"
    private var joined: String { runner.logLines.joined(separator: "\n") }

    var body: some View {
        GlassCard(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header
                if let lastError = runner.lastError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(t.red)
                        Text(lastError)
                            .font(MissionFont.sans(12))
                            .foregroundStyle(t.red)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                logScroll
                if runner.runFolder != nil {
                    actionRow
                }
            }
            .padding(14)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(headerDot)
                .frame(width: 6, height: 6)
                .shadow(color: headerDot.opacity(0.55), radius: 4)
            Text("Live output")
                .font(MissionFont.sans(12, weight: .semibold))
                .foregroundStyle(t.ink)
            Spacer()
            ChipButton(label: "Copy", icon: "doc.on.doc",
                       disabled: runner.logLines.isEmpty) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(joined, forType: .string)
            }
            ChipButton(label: "Open log", icon: "text.alignleft",
                       disabled: runner.runFolder == nil) {
                guard let dir = runner.runFolder else { return }
                let url = dir.appendingPathComponent("transcript.txt")
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var headerDot: Color {
        if runner.isRunning           { return t.amber }
        if runner.lastError != nil    { return t.red   }
        if runner.runFolder != nil    { return t.green }
        return t.inkMute
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if runner.logLines.isEmpty {
                        Text("Output will appear here once a run starts.")
                            .font(MissionFont.mono(11))
                            .foregroundStyle(t.inkMute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        Text(joined)
                            .font(MissionFont.mono(11))
                            .foregroundStyle(t.inkDim)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    Color.clear.frame(height: 0).id(Self.bottomAnchorID)
                }
            }
            .frame(minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(t.cardFillStrong.opacity(t.isDark ? 1 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(t.ruleSoft, lineWidth: 1)
            )
            .onChange(of: runner.logLines.count) { _, count in
                guard count > 0 else { return }
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if let runFolder = runner.runFolder {
            FlowChips {
                ChipButton(label: "Reveal", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([runFolder])
                }
                fileChip(name: "transcript.txt",  label: "Transcript", icon: "text.alignleft", in: runFolder)
                fileChip(name: "summary.txt",     label: "Summary",    icon: "doc.text",       in: runFolder)
                fileChip(name: "manifest.json",   label: "Manifest",   icon: "curlybraces",    in: runFolder)
                fileChip(name: "metadata.json",   label: "Metadata",   icon: "info.circle",    in: runFolder)
                fileChip(name: "chain_of_custody.log",
                                                  label: "Custody log",icon: "checkmark.seal", in: runFolder)
            }
        }
    }

    @ViewBuilder
    private func fileChip(name: String, label: String, icon: String, in dir: URL) -> some View {
        let url = dir.appendingPathComponent(name)
        let exists = FileManager.default.fileExists(atPath: url.path)
        ChipButton(label: label, icon: icon, disabled: !exists) {
            NSWorkspace.shared.open(url)
        }
        .help(exists ? url.path : "\(name) not present in run folder")
    }
}

/// Compact pill button used across Mission Control. Light translucent
/// fill, hairline border, faint icon — matches the chip buttons in the
/// design (`Save preset`, `Reveal output`, `Copy`, `Open log`).
struct ChipButton: View {
    @Environment(\.missionTheme) private var t

    let label: String
    var icon: String? = nil
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(MissionFont.sans(12, weight: .medium))
            }
            .foregroundStyle(t.inkDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule()
                    .strokeBorder(t.ruleSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// Wrap chips so they line-break instead of clipping when the action row
/// is wider than the card. macOS 14's Layout protocol gives a clean
/// implementation; falls back to a single HStack on the unlikely chance
/// the API isn't available.
struct FlowChips<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        FlowLayout(spacing: 6) { content() }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, totalW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                y += lineH + spacing
                x = 0; lineH = 0
            }
            x += s.width + spacing
            totalW = max(totalW, x)
            lineH = max(lineH, s.height)
        }
        return CGSize(width: min(maxWidth, totalW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let maxX = bounds.maxX
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxX, x > bounds.minX {
                y += lineH + spacing
                x = bounds.minX; lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
