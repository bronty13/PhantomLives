import SwiftUI

struct CategoriesSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var newName: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.title3.weight(.semibold))
            Text("Categories are reusable tags shown as chips on each clip. Add new ones here, then pick them in the clip editor.")
                .font(.caption).foregroundStyle(.secondary)

            Table(appState.categories) {
                TableColumn("Name") { c in
                    Text(c.name)
                }

                TableColumn("Order") { c in
                    Text("\(c.sortOrder)").font(.caption.monospacedDigit())
                }
                .width(min: 60, ideal: 70)

                TableColumn("Archived") { c in
                    Toggle("", isOn: Binding(
                        get: { c.archived },
                        set: { newVal in
                            var copy = c
                            copy.archived = newVal
                            try? appState.saveCategory(copy)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .width(min: 80, ideal: 90)

                TableColumn("") { c in
                    Button(role: .destructive) {
                        if let id = c.id { try? appState.deleteCategory(id: id) }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
                .width(40)
            }
            .frame(minHeight: 220)

            Divider()

            HStack {
                TextField("New category name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Button("Add") {
                    // Categories are stored uppercase as of v8 — normalise
                    // here so the settings table doesn't round-trip mixed
                    // case rows that won't match `ensureCategory(named:)`.
                    let trimmed = newName
                        .trimmingCharacters(in: .whitespaces)
                        .uppercased()
                    guard !trimmed.isEmpty else { return }
                    do {
                        let cat = Category(id: nil, name: trimmed,
                                           sortOrder: appState.categories.count, archived: false)
                        try appState.saveCategory(cat)
                        newName = ""
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
            }
        }
        .padding(20)
    }
}
