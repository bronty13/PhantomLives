import SwiftUI

/// Confirmation sheet for a bulk on-disk delete (imported or skipped files). Shows the
/// count and a sample of filenames, and lets the user choose Trash vs permanent before
/// committing.
struct DeleteConfirmationView: View {
    let kind: DeleteKind
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var permanently = false

    private var candidates: [MediaFile] { appState.deletionCandidates(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.title).font(.title2.weight(.semibold))
            Text(kind.blurb).font(.callout).foregroundStyle(.secondary)

            let files = candidates
            Text("\(files.count) file\(files.count == 1 ? "" : "s") on disk")
                .font(.headline)

            if files.isEmpty {
                Text("Nothing matches — nothing to delete.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(files.prefix(5)) { f in
                        Text("• \(f.fileName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if files.count > 5 {
                        Text("…and \(files.count - 5) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Picker("", selection: $permanently) {
                Text("Move to Trash").tag(false)
                Text("Delete Permanently").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(files.isEmpty)

            if permanently {
                Label("Permanent deletion can't be undone.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(permanently ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                    appState.performDelete(files, permanently: permanently)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
    }
}
