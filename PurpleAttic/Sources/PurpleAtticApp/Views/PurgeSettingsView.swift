import SwiftUI
import PurpleAtticCore

/// The guarded purge pane. In this release the delete ENGINE isn't wired yet — purge runs
/// only once Phase C lands. This pane records intent (the `purgeEnabled` flag) behind an
/// affirmative confirmation and lays out exactly what the future purge will and won't do,
/// so the safety model is visible long before any photo can be deleted.
struct PurgeSettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var confirmEnable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                    Text("Purge").font(.title3.weight(.semibold))
                }

                Card(title: "Status") {
                    Label("Purge is not active in this release.", systemImage: "info.circle")
                        .font(.callout)
                    Text("Archiving runs and is safe to use now. The delete step — removing aged, un-pinned photos from Photos — ships in a later version. The toggle below records your intent; nothing is ever deleted until the purge engine is present AND every safety gate passes.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Card(title: "Intent") {
                    Toggle("Enable purge (when available)", isOn: Binding(
                        get: { store.profile.purgeEnabled },
                        set: { newValue in
                            if newValue {
                                confirmEnable = true        // require explicit confirmation to turn ON
                            } else {
                                store.profile.purgeEnabled = false
                                store.save()
                            }
                        }))
                    if store.profile.mirrorDestinations.isEmpty {
                        Label("Add at least one mirror in Settings first — purge requires a verified second on-disk copy.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Card(title: "What purge will do (when it ships)") {
                    rule("Only touches photos OLDER than \(store.profile.retention.keepWindowDays) days.")
                    rule("Never touches anything in a keep album (\(list(store.profile.retention.keepAlbumNames))) or with a keep keyword (\(list(store.profile.retention.keepKeywords)))\(store.profile.retention.keepFavorites ? ", or Favorites" : "").")
                    rule("Requires each photo present + matching in ≥2 on-disk copies before deleting.")
                    rule("Always previews (dry-run) and uses macOS's own delete confirmation.")
                    rule("Deletions land in Photos’ Recently Deleted for 30 days.")
                }
            }
            .padding(20)
        }
        .alert("Enable purge intent?", isPresented: $confirmEnable) {
            Button("Cancel", role: .cancel) { }
            Button("Enable", role: .destructive) {
                store.profile.purgeEnabled = true
                store.save()
            }
        } message: {
            Text("This only records that you intend to allow purging once the feature ships. No photo can be deleted yet. You can turn it off any time.")
        }
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield").foregroundStyle(.green).font(.caption)
            Text(text).font(.callout)
            Spacer()
        }
    }

    private func list(_ items: [String]) -> String {
        items.isEmpty ? "none" : items.joined(separator: ", ")
    }
}
