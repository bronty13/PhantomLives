import SwiftUI

/// CRUD for the **Posting exclusion reasons** dropdown — the labels
/// shown when the user marks a clip as "do not post". Three defaults
/// are seeded by the v8 migration; this view lets the user add their
/// own, archive them, or delete unused ones. Reasons are stored as
/// strings on the clip (`exclusion_reason`), so renaming a reason here
/// doesn't retroactively change clips that were already tagged with
/// the old label.
struct PostingSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var newLabel: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posting exclusion reasons")
                .font(.title3.weight(.semibold))
            Text("These labels appear in the dropdown when you mark a clip as \"do not post\" — for clips you sent individually, custom commissions, or anything else you don't want pushed to the public storefronts.")
                .font(.caption).foregroundStyle(.secondary)

            Table(appState.exclusionReasons) {
                TableColumn("Label") { r in
                    Text(r.label)
                }
                TableColumn("Order") { r in
                    Text("\(r.sortOrder)").font(.caption.monospacedDigit())
                }
                .width(min: 60, ideal: 70)
                TableColumn("Archived") { r in
                    Toggle("", isOn: Binding(
                        get: { r.archived },
                        set: { newVal in
                            var copy = r
                            copy.archived = newVal
                            try? DatabaseService.shared.saveExclusionReason(&copy)
                            appState.reloadExclusionReasons()
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .width(min: 80, ideal: 90)
                TableColumn("") { r in
                    Button(role: .destructive) {
                        if let id = r.id {
                            try? DatabaseService.shared.deleteExclusionReason(id: id)
                            appState.reloadExclusionReasons()
                        }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
                .width(40)
            }
            .frame(minHeight: 200)

            Divider()

            HStack {
                TextField("New exclusion reason", text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 280)
                Button("Add") {
                    let trimmed = newLabel.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    do {
                        var r = ExclusionReason(
                            id: nil,
                            label: trimmed,
                            sortOrder: appState.exclusionReasons.count,
                            archived: false
                        )
                        try DatabaseService.shared.saveExclusionReason(&r)
                        appState.reloadExclusionReasons()
                        newLabel = ""
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if let e = error {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(20)
    }
}
