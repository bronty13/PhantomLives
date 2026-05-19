import SwiftUI

/// Step 1 — pick the schema type to export from. Mirror of Purple
/// Import's PickTarget but without the "create new type" toggle —
/// you can't export from a type that doesn't exist.
struct PickTypeStep: View {
    @ObservedObject var model: ExportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which type do you want to export?").font(.title3).bold()
            List(selection: $model.draft.typeId) {
                ForEach(appState.schema.visibleTypes, id: \.id) { t in
                    HStack(spacing: 10) {
                        Image(systemName: t.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.body)
                            Text("\(t.fields.count) field\(t.fields.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if t.isVault {
                            Text("Vault").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.purple.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .tag(t.id as String?)
                }
            }
            .frame(minHeight: 240)
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
