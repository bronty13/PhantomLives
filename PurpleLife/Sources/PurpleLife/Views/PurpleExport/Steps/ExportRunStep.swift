import SwiftUI

/// Step 7 — progress + result. Phase 4's runner doesn't stream
/// granular row events (yet) so the wizard just spins a progress
/// indicator until the `finished` summary lands.
struct ExportRunStep: View {
    @ObservedObject var model: ExportWizardModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text("Writing export…").font(.headline)
            ProgressView().progressViewStyle(.linear).frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

struct ExportDoneStep: View {
    @ObservedObject var model: ExportWizardModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Export complete").font(.title3).bold()
            if let s = model.summary {
                Text("\(s.recordCount) record\(s.recordCount == 1 ? "" : "s") · \(byteCountFormatted(s.bytesOnDisk))")
                    .foregroundStyle(.secondary)
                Text(s.fileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([s.fileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    Button {
                        NSWorkspace.shared.open(s.fileURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                }
                .controlSize(.small)
                .padding(.top, 6)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func byteCountFormatted(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}

struct ExportErrorStep: View {
    @ObservedObject var model: ExportWizardModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text("Export failed").font(.title3).bold()
            if let err = model.lastError {
                Text(err)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
