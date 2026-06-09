import SwiftUI
import AppKit
import PurpleDedupCore

/// One row in the audit results list: a compact thumbnail + filename/path +
/// an in/not-in-Photos status badge. Missing rows carry a selection checkbox
/// that feeds the bulk-import set.
struct AuditRow: View {
    let file: AuditEngine.AuditedFile
    /// Whether this (missing) file is selected for import. Nil for non-missing
    /// rows, which have no checkbox.
    let isSelected: Bool
    let onToggleSelected: () -> Void

    private var isMissing: Bool {
        if case .missing = file.classification { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            if isMissing {
                Button(action: onToggleSelected) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Select for import")
            } else {
                // Keep alignment with missing rows.
                Color.clear.frame(width: 16, height: 16)
            }

            ThumbnailView(url: file.url, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.callout).lineLimit(1).truncationMode(.middle)
                Text(parentDirectoryDisplay(file.url))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            if file.inPhotosHidden {
                badge("Hidden", systemImage: "eye.slash.fill", color: .pink)
                    .help("This file is in your Photos library but only as a HIDDEN item.")
            }
            statusBadge
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { QuickLookCoordinator.shared.preview(file.url) }
        .contextMenu {
            Button("Quick Look") { QuickLookCoordinator.shared.preview(file.url) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch file.classification {
        case .inPhotosExact:
            badge("In Photos", systemImage: "checkmark.seal.fill", color: .purple)
        case .likelyInPhotosPerceptual(let d):
            badge("Likely · d=\(d)", systemImage: "photo.on.rectangle.angled", color: .indigo)
                .help("A visually similar photo is already in your library (Hamming distance \(d)).")
        case .likelyInPhotosFilename(let name):
            badge("Same name", systemImage: "doc.on.doc", color: .teal)
                .help("\(name) matches a filename already in your library — likely an iCloud-optimised copy.")
        case .missing:
            badge("Not in Photos", systemImage: "exclamationmark.circle", color: .orange)
        }
    }

    private func badge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func parentDirectoryDisplay(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if dir == home || dir.hasPrefix(home + "/") {
            return "~" + dir.dropFirst(home.count) + "/"
        }
        return dir + "/"
    }
}
