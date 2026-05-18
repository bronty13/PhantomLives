import SwiftUI
import AppKit

/// "Transfer Metadata Between Folders" sheet — Kyno 1.8 parity
/// (row 14). When a producer hands off a duplicate folder tree
/// (proxy → master, alternate location, fresh ingest), Kyno mirrors
/// every tag / rating / log field across by matching filename +
/// size. PurpleReel does the same.
///
/// Both folders must be under workspace roots so the catalogue
/// already has rows for the source AND the destination assets —
/// metadata writes go through `addTag` / `setClipMetadata` etc.
/// which key off the destination asset's rowId.
struct TransferMetadataSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var source: URL?
    @State private var dest:   URL?
    @State private var preview: PreviewResult?
    @State private var status: String = ""
    @State private var working: Bool = false

    /// Result of the dry-run pass — how many files match and what
    /// will move. Surfaced in the sheet so the user can verify
    /// before committing.
    struct PreviewResult {
        var matchedPairs: Int
        var unmatchedSource: Int
        var unmatchedDest: Int
        var transferredFieldsPerPair: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            folderPickerRow(label: "From:", binding: $source,
                             helpText: "Folder with the metadata you want to copy.")
            folderPickerRow(label: "To:", binding: $dest,
                             helpText: "Folder that receives the metadata. Must be under a workspace root.")
            Divider()
            previewSection
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 580)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transfer Metadata Between Folders")
                .font(.title3.weight(.semibold))
            Text("Mirror every tag, rating, and Kyno log field from one folder onto matching files in another. Match keys are filename + byte size.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func folderPickerRow(label: String,
                                   binding: Binding<URL?>,
                                   helpText: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label).frame(width: 50, alignment: .trailing)
                Text(binding.wrappedValue?.path ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(binding.wrappedValue == nil ? .secondary : .primary)
                Spacer()
                Button("Choose…") { pickFolder(into: binding) }
            }
            Text(helpText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 58)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let p = preview {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(p.matchedPairs) matching pair\(p.matchedPairs == 1 ? "" : "s") found",
                       systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if p.unmatchedSource > 0 || p.unmatchedDest > 0 {
                    Text("\(p.unmatchedSource) source file(s) without a destination twin · \(p.unmatchedDest) destination file(s) without a source twin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("For each match, PurpleReel will copy title / description / reel / scene / shot / take / angle / camera / audio channels, plus rating, plus every tag (additively — never removes a destination tag the source doesn't carry).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Pick both folders, then Preview to see how many files will receive metadata.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !status.isEmpty {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var footer: some View {
        HStack {
            Button("Preview") {
                runPreview()
            }
            .disabled(source == nil || dest == nil || working)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Apply") {
                runApply()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(source == nil || dest == nil
                      || (preview?.matchedPairs ?? 0) == 0
                      || working)
        }
    }

    // MARK: - Actions

    private func pickFolder(into binding: Binding<URL?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url
            preview = nil
            status = ""
        }
    }

    private func runPreview() {
        guard let src = source, let dst = dest else { return }
        working = true
        Task {
            let r = appState.previewMetadataTransfer(from: src, to: dst)
            await MainActor.run {
                preview = r
                working = false
                if r.matchedPairs == 0 {
                    status = "No matching pairs — verify both folders are under workspace roots and the filenames + sizes line up."
                }
            }
        }
    }

    private func runApply() {
        guard let src = source, let dst = dest else { return }
        working = true
        Task {
            let applied = await appState.applyMetadataTransfer(from: src, to: dst)
            await MainActor.run {
                status = "Transferred metadata onto \(applied) clip(s)."
                working = false
                if applied > 0 { dismiss() }
            }
        }
    }
}
