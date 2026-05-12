import SwiftUI
import MasterClipperCore

struct CategoriesSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var newName: String = ""
    @State private var error: String?
    @State private var unusedCount: Int = 0
    @State private var showingCleanupConfirm: Bool = false
    @State private var lastCleanupMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Categories")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let msg = lastCleanupMessage {
                    Text(msg).font(.caption).foregroundStyle(.green)
                }
                Button {
                    showingCleanupConfirm = true
                } label: {
                    Label(
                        unusedCount > 0
                            ? "Archive unused (\(unusedCount))…"
                            : "Archive unused",
                        systemImage: "archivebox"
                    )
                }
                .disabled(unusedCount == 0)
                .help(unusedCount == 0
                      ? "Every active category is in use"
                      : "Archive every category that isn't currently attached to any clip — reversible from this table")
            }
            Text("Categories are reusable tags shown as chips on each clip. Add new ones here, then pick them in the clip editor.")
                .font(.caption).foregroundStyle(.secondary)

            Table(appState.categories) {
                TableColumn("Name") { c in
                    Text(c.name)
                }

                // The Order column exposes raw `sort_order` values — useful
                // for debugging chip-picker ordering, noise for everyday
                // use. Only shown when debugMode is on.
                TableColumn("Order") { c in
                    Text("\(c.sortOrder)").font(.caption.monospacedDigit())
                }
                .width(min: 60, ideal: 70)
                .defaultVisibility(appState.settings.debugMode ? .automatic : .hidden)

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
                        let cat = ClipCategory(id: nil, name: trimmed,
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
        .onAppear { refreshUnusedCount() }
        .onChange(of: appState.clips.count)      { _, _ in refreshUnusedCount() }
        .onChange(of: appState.categories.count) { _, _ in refreshUnusedCount() }
        .confirmationDialog(
            "Archive \(unusedCount) unused categor\(unusedCount == 1 ? "y" : "ies")?",
            isPresented: $showingCleanupConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive \(unusedCount)", role: .destructive) {
                runCleanup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Categories not currently attached to any clip will be hidden from pickers. They stay in the table — flip the Archived toggle to bring one back, or attach it to a clip and it un-archives automatically.")
        }
    }

    private func refreshUnusedCount() {
        unusedCount = (try? DatabaseService.shared.unusedActiveCategoryCount()) ?? 0
    }

    private func runCleanup() {
        do {
            let n = try DatabaseService.shared.archiveUnusedCategories()
            appState.reloadCategories()
            refreshUnusedCount()
            lastCleanupMessage = "Archived \(n) categor\(n == 1 ? "y" : "ies")."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                lastCleanupMessage = nil
            }
        } catch {
            self.error = "Cleanup failed: \(error.localizedDescription)"
        }
    }
}
