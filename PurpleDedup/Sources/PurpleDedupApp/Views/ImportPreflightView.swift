import SwiftUI
import PurpleDedupCore

/// Confirmation sheet shown before importing missing files into Photos. Modeled
/// on `PreflightView` but with additive, non-destructive semantics: import
/// copies originals into the library and never moves or deletes anything on disk.
struct ImportPreflightView: View {
    let toImport: [URL]
    let albumName: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var photoCount: Int {
        toImport.filter { FileKind.photoExtensions.contains($0.pathExtension.lowercased()) }.count
    }
    private var videoCount: Int {
        toImport.filter { FileKind.videoExtensions.contains($0.pathExtension.lowercased()) }.count
    }
    private var otherCount: Int { toImport.count - photoCount - videoCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import \(toImport.count) file(s) into Photos?")
                        .font(.headline)
                    if let albumName {
                        Text("Added to the \"\(albumName)\" album")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if photoCount > 0 { Label("\(photoCount) photo(s)", systemImage: "photo") }
                if videoCount > 0 { Label("\(videoCount) video(s)", systemImage: "film") }
                if otherCount > 0 { Label("\(otherCount) file(s) will be skipped (unsupported)", systemImage: "doc") }
            }
            .font(.callout)

            Text("Files are copied into your Photos library. The originals on disk are not moved or deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

            if !toImport.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(toImport.prefix(20), id: \.self) { u in
                            Text(u.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if toImport.count > 20 {
                            Text("+\(toImport.count - 20) more…")
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
                Button { onConfirm() } label: {
                    Label("Import to Photos", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
