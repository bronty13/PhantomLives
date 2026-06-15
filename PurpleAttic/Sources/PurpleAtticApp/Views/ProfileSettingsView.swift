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
                reviewCard
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
            if store.profile.downloadMissingFromICloud {
                Toggle("Use PhotoKit to download (recommended)",
                       isOn: $store.profile.usePhotoKitForDownload)
                    .padding(.leading, 18)
                Text("PhotoKit requests originals from iCloud directly. The alternative (AppleScript) drives Photos and can time out and repeatedly **kill Photos** on slow/indeterminate iCloud items. Leave ON unless you have a reason not to.")
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 18)
            }
            Divider()
            Toggle("Skip “Shared with You” & shared-album items",
                   isOn: $store.profile.excludeSharedAndSyndicated)
            Text("Photos that others shared with you (via Messages or a shared album) aren’t your originals and have no master to download — without this they linger forever as bogus “missing” items. Leave ON. (Your own iCloud Shared Library photos are unaffected.)")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Include the Hidden album", isOn: $store.profile.includeHidden)
            Text("Archive hidden photos too, so a “nothing ever lost” backup doesn’t silently skip them. Hidden ≠ deleted: a photo you actually delete leaves the library and future runs simply don’t see it. Leave ON for a complete archive.")
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
                 + "Applies to the primary + mirrors.")
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
            HStack(spacing: 6) {
                Image(systemName: "lock.icloud").foregroundStyle(.secondary)
                Text("Off-site (encrypted, Backblaze B2) is configured in the **Off-site** tab — it replaced the old Cryptomator vault.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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

    private var reviewCard: some View {
        Card(title: "New-photo review") {
            Toggle("Copy each run's new items to a “NEW PHOTOS TO REVIEW” folder",
                   isOn: $store.profile.reviewNewItems)
            Text("On incremental runs, photos newly added since the last run (originals + JPEG) "
                 + "are also copied into a dated batch under the folder below — so you can hand "
                 + "them off to others or delete them after review, without touching the archive. "
                 + "Skipped on the first/baseline run.")
                .font(.caption).foregroundStyle(.secondary)
            PathField(label: "Review folder",
                      path: Binding(get: { store.profile.reviewFolderPath ?? "" },
                                    set: { store.profile.reviewFolderPath = $0.isEmpty ? nil : $0 }),
                      placeholder: ArchiveProfile.defaultReviewRoot())
                .disabled(!store.profile.reviewNewItems)
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
