import SwiftUI
import AppKit
import PurpleDedupCore

/// One file in the comparison grid: thumbnail with corner badges, filename
/// row, parent path, size, and the Keep/Delete decision controls. Reads its
/// effective decision from `DecisionStore`, lookup-hit / metadata flags from
/// the host's `MetadataLoader`.
///
/// All visible state flows through bindings on `DecisionStore` — tapping
/// Keep/Delete mutates the host's `manualOverrides` directly; no local state.
struct FileCard: View {
    let file: DiscoveredFile
    let selection: ClusterSelection
    let thumbSize: CGFloat
    let inLookupHits: Bool
    let isHiddenInPhotos: Bool
    let decisions: DecisionStore
    let onRequestTrashOne: (DiscoveredFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(url: file.url, size: thumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderColor, lineWidth: 2)
                    )
                decisionBadge
                    .padding(6)
                if inLookupHits { inPhotosBadge.padding(6) }
                if isHiddenInPhotos { hiddenBadge.padding(6) }
            }
            .contextMenu { contextMenuItems }
            .onTapGesture(count: 2) { QuickLookCoordinator.shared.preview(file.url) }

            // Filename + tiny Reveal-in-Finder button. Path location matters
            // when deciding which copy to keep ("the one in /Originals/ wins
            // over the one in /Downloads/"); the parent-directory line below
            // surfaces this without a context-menu trip.
            HStack(spacing: 4) {
                Text(file.url.lastPathComponent)
                    .font(.caption.bold()).lineLimit(1).truncationMode(.middle)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                } label: {
                    Image(systemName: "arrow.right.square")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .frame(width: thumbSize, alignment: .leading)

            Text(parentDirectoryDisplay(file.url))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(width: thumbSize, alignment: .leading)
                .help(file.url.path)

            Text(formatBytes(file.sizeBytes))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            decisionControls

            if let reason = decisions.decisionReason(for: file.url, in: selection) {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - badges

    @ViewBuilder
    private var decisionBadge: some View {
        if let d = decisions.decision(for: file.url, in: selection) {
            let manual = decisions.isManualOverride(url: file.url, in: selection)
            switch d {
            case .keep:
                decisionPill(
                    label: manual ? "KEEP" : "Suggested keep",
                    color: .green,
                    strong: manual
                )
            case .delete:
                decisionPill(
                    label: manual ? "DELETE" : "Suggested delete",
                    color: .red,
                    strong: manual
                )
            }
        }
    }

    /// Pill that distinguishes the engine's recommendation ("Suggested keep")
    /// from the user's manual override ("KEEP"). Recommendations render with
    /// softer fill + sentence case — advisory, not assertive. Overrides render
    /// with strong fill + uppercase + a small hand icon so the user can see at
    /// a glance which decisions they own versus which came from the engine.
    @ViewBuilder
    private func decisionPill(label: String, color: Color, strong: Bool) -> some View {
        HStack(spacing: 3) {
            if strong {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(label).font(.caption2.bold())
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(strong ? 0.95 : 0.65))
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(strong ? 0.22 : 0.12), radius: strong ? 3 : 1, y: 1)
    }

    /// "Also in Photos library" badge — bottom-leading so it doesn't fight the
    /// KEEP/DELETE chip on the top-right.
    private var inPhotosBadge: some View {
        VStack {
            Spacer()
            HStack {
                Label("In Photos", systemImage: "photo.on.rectangle.angled")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                Spacer()
            }
        }
    }

    /// "Hidden" badge — top-leading so it stays visible alongside the
    /// KEEP/DELETE decision chip (top-right) and the "In Photos" capsule
    /// (bottom-leading).
    private var hiddenBadge: some View {
        VStack {
            HStack {
                Label("Hidden", systemImage: "eye.slash.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - decision controls

    @ViewBuilder
    private var decisionControls: some View {
        let current = decisions.decision(for: file.url, in: selection)
        let isManual = decisions.isManualOverride(url: file.url, in: selection)
        HStack(spacing: 4) {
            Button {
                decisions.setManual(.keep(reason: "manual"), for: file.url, in: selection)
            } label: {
                Label("Keep", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.bold())
                    .foregroundStyle(isKeepActive(current) ? .white : .green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(isKeepActive(current) ? Color.green : Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Keep this file (overrides the engine's recommendation if needed)")

            Button {
                decisions.setManual(.delete(reason: "manual"), for: file.url, in: selection)
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.bold())
                    .foregroundStyle(isDeleteActive(current) ? .white : .red)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(isDeleteActive(current) ? Color.red : Color.red.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Mark this file for trashing")

            if isManual {
                Button {
                    decisions.clearManual(for: file.url, in: selection)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Reset to engine recommendation")
            }
        }
        .frame(width: thumbSize, alignment: .leading)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Mark KEEP")  { decisions.setManual(.keep(reason: "manual"), for: file.url, in: selection) }
        Button("Mark DELETE") { decisions.setManual(.delete(reason: "manual"), for: file.url, in: selection) }
        Button("Use recommendation") { decisions.clearManual(for: file.url, in: selection) }
        Divider()
        Button("Trash this file now…", role: .destructive) {
            onRequestTrashOne(file)
        }
        Divider()
        Button("Quick Look") { QuickLookCoordinator.shared.preview(file.url) }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        }
        Button("Open in default app") { NSWorkspace.shared.open(file.url) }
    }

    // MARK: - helpers

    /// Thumbnail border picks up the decision colour, with engine
    /// recommendations rendering at a softer alpha than manual overrides.
    /// Mirrors the pill treatment so border + pill always read consistently.
    private var borderColor: Color {
        let decision = decisions.decision(for: file.url, in: selection)
        let manual = decisions.isManualOverride(url: file.url, in: selection)
        switch decision {
        case .keep:   return .green.opacity(manual ? 0.75 : 0.40)
        case .delete: return .red.opacity(manual ? 0.75 : 0.40)
        case nil:     return .secondary.opacity(0.3)
        }
    }

    private func isKeepActive(_ d: Decision?) -> Bool {
        if case .keep = d { return true }
        return false
    }

    private func isDeleteActive(_ d: Decision?) -> Bool {
        if case .delete = d { return true }
        return false
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter(); bcf.allowedUnits = [.useAll]; bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }

    /// Compact parent-directory display. Replaces the user's home directory
    /// with `~` (so `/Users/bronty/Pictures/foo/` renders `~/Pictures/foo/`).
    private func parentDirectoryDisplay(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if dir == home || dir.hasPrefix(home + "/") {
            return "~" + dir.dropFirst(home.count) + "/"
        }
        return dir + "/"
    }
}
