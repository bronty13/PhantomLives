import SwiftUI
import PurpleAtticCore

/// Edits the single `ArchiveProfile`. Observes the store directly so field edits republish.
struct ProfileSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.title3.weight(.semibold))

                sourceCard
                destinationsCard
                formatsCard
                retentionCard

                HStack {
                    Spacer()
                    Button("Save") { store.save() }
                        .keyboardShortcut("s", modifiers: [.command])
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    // MARK: Cards

    private var sourceCard: some View {
        Card(title: "Source") {
            PathField(label: "Photos library (blank = System Photo Library)",
                      path: Binding(get: { store.profile.photosLibraryPath ?? "" },
                                    set: { store.profile.photosLibraryPath = $0.isEmpty ? nil : $0 }),
                      chooser: chooseLibrary,
                      placeholder: "/Users/you/Pictures/Photos Library.photoslibrary")
            Toggle("Download missing originals from iCloud during export",
                   isOn: $store.profile.downloadMissingFromICloud)
            Text("Leave OFF on a Mac set to “Download Originals” (everything is already local). Turn ON only on an Optimize-Storage host.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var destinationsCard: some View {
        Card(title: "Destinations") {
            PathField(label: "Primary archive drive (disk 1)", path: $store.profile.primaryDestination,
                      placeholder: "/Volumes/Vortex4TB")
            TextField("Archive subfolder", text: $store.profile.archiveSubfolder)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            Text("Pick the drive; the archive is nested in this subfolder so the drive root stays tidy. "
                 + "Applies to the primary + mirrors; the Cryptomator vault is exempt (written at its root).")
                .font(.caption).foregroundStyle(.secondary)
            if !store.profile.primaryDestination.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("→ originals at  \(store.profile.primaryArchiveRoot)/originals")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Divider()
            Text("Mirror drives (disk 2+). Kept in lockstep; required before any purge.")
                .font(.subheadline.weight(.medium))
            ForEach(store.profile.mirrorDestinations.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    TextField("/Volumes/Mirror/PhotoArchive", text: $store.profile.mirrorDestinations[i])
                        .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    Button("Choose…") {
                        if let p = chooseDirectory(title: "Mirror") { store.profile.mirrorDestinations[i] = p }
                    }
                    Button(role: .destructive) {
                        store.profile.mirrorDestinations.remove(at: i)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button { store.profile.mirrorDestinations.append("") } label: {
                Label("Add Mirror", systemImage: "plus")
            }
            Divider()
            PathField(label: "Cloud — mounted Cryptomator vault (blank = skip)",
                      path: Binding(get: { store.profile.cloudVaultPath ?? "" },
                                    set: { store.profile.cloudVaultPath = $0.isEmpty ? nil : $0 }),
                      placeholder: "/Volumes/PhotoVault (unlocked Cryptomator drive)")
            vaultStatusLine
        }
    }

    @ViewBuilder
    private var vaultStatusLine: some View {
        let status = VaultStatus.check(path: store.profile.cloudVaultPath)
        let (icon, tint): (String, Color) = {
            switch status {
            case .ready: return ("lock.open.fill", .green)
            case .notMounted: return ("lock.fill", .orange)
            case .notConfigured: return ("minus.circle", .secondary)
            }
        }()
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(tint)
            Text("Vault: \(status.label)").foregroundStyle(.secondary)
            if status == .notMounted {
                Text("— unlock it in Cryptomator before a run, or the cloud copy is skipped (and caught up next run).")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var formatsCard: some View {
        Card(title: "Formats") {
            Toggle("HEIC originals (full fidelity)", isOn: $store.profile.keepHEIC)
            Toggle("JPEG derivatives (universally openable)", isOn: $store.profile.keepJPEG)
            PathField(label: "Folder template (osxphotos --directory)",
                      path: $store.profile.directoryTemplate,
                      chooser: { _ in nil },
                      placeholder: "{created.year}/{created.year}-{created.mm}")
        }
    }

    private var retentionCard: some View {
        Card(title: "Retention (what a future purge would keep)") {
            Stepper(value: $store.profile.retention.keepWindowDays, in: 30...3650, step: 30) {
                Text("Keep window: \(store.profile.retention.keepWindowDays) days "
                     + "(~\(store.profile.retention.keepWindowDays / 365) yr)")
            }
            TextField("Keep albums (comma-separated)", text: csv(\.retention.keepAlbumNames))
                .textFieldStyle(.roundedBorder)
            TextField("Keep keywords (comma-separated)", text: csv(\.retention.keepKeywords))
                .textFieldStyle(.roundedBorder)
            Toggle("Also keep Favorites", isOn: $store.profile.retention.keepFavorites)
            Text("A photo is purge-eligible only when older than the keep window AND not pinned by a keep album, keep keyword, or (if enabled) Favorite.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func csv(_ keyPath: WritableKeyPath<ArchiveProfile, [String]>) -> Binding<String> {
        Binding(
            get: { store.profile[keyPath: keyPath].joined(separator: ", ") },
            set: {
                store.profile[keyPath: keyPath] = $0
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
