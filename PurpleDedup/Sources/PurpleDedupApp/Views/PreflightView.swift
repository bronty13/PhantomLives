import SwiftUI
import PurpleDedupCore

/// Sheet shown before the user kicks off the actual filesystem moves. Echoes the
/// requirements doc's pre-flight modal: total count + total size + per-type
/// breakdown + a clear "this is logged and reversible" line. The Move-to-Trash
/// button is destructive-styled so it inherits the red treatment macOS gives
/// dangerous actions.
struct PreflightView: View {
    let toDelete: [DiscoveredFile]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var totalBytes: Int64 { toDelete.reduce(Int64(0)) { $0 + $1.sizeBytes } }
    private var photoCount: Int {
        toDelete.filter { FileKind.photoExtensions.contains($0.url.pathExtension.lowercased()) }.count
    }
    private var videoCount: Int {
        toDelete.filter { FileKind.videoExtensions.contains($0.url.pathExtension.lowercased()) }.count
    }
    private var otherCount: Int {
        toDelete.count - photoCount - videoCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Move \(toDelete.count) file(s) to Trash?")
                        .font(.headline)
                    Text("Total size: \(formatBytes(totalBytes))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if photoCount > 0 {
                    Label("\(photoCount) photo(s)", systemImage: "photo")
                }
                if videoCount > 0 {
                    Label("\(videoCount) video(s)", systemImage: "film")
                }
                if otherCount > 0 {
                    Label("\(otherCount) other file(s)", systemImage: "doc")
                }
            }
            .font(.callout)

            Text("Files go to the Finder Trash. Each move is recorded in PurpleDedup's operation log so you can undo the last action from the Edit menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

            // Show the first few paths so the user can sanity-check what's being
            // moved. Long lists collapse into "+N more" — the full set is in the
            // op log if they want to audit.
            if !toDelete.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(toDelete.prefix(20), id: \.url) { f in
                            Text(f.url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if toDelete.count > 20 {
                            Text("+\(toDelete.count - 20) more…")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) { onConfirm() } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter(); bcf.allowedUnits = [.useAll]; bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }
}
