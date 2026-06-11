import SwiftUI
import PurpleAtticCore

/// The guarded purge pane. The delete engine is now wired, but every gate must pass:
/// `purgeEnabled` ON, ≥1 mirror, the candidate is purge-eligible per the retention rule,
/// AND its file is verified present in the primary + a mirror. Even then the user clicks
/// through an in-app confirmation and macOS's own delete dialog.
struct PurgeSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmEnable = false
    @State private var confirmDelete = false

    private var store: SettingsStore { appState.store }
    private var profile: ArchiveProfile { store.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                    Text("Purge").font(.title3.weight(.semibold))
                }

                intentCard
                previewCard
                if let msg = appState.purgeMessage { messageBanner(msg) }
                rulesCard
            }
            .padding(20)
            .textSelection(.enabled)   // let the user select + copy counts, errors, file lists
        }
        .alert("Enable purge?", isPresented: $confirmEnable) {
            Button("Cancel", role: .cancel) { }
            Button("Enable", role: .destructive) { store.profile.purgeEnabled = true; store.save() }
        } message: {
            Text("Turning this on allows PurpleAttic to delete aged, un-pinned photos that are verified in your archive — after you preview them and confirm again (and macOS asks once more). You can turn it off any time.")
        }
        .alert("Delete \(appState.purgePlan?.verified.count ?? 0) photos from Photos?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { appState.executePurge() }
        } message: {
            Text("These are verified present in your primary archive and a mirror. They’ll move to Photos → Recently Deleted for 30 days, and disappear from all your devices. macOS will ask you to confirm once more.")
        }
    }

    // MARK: Intent

    private var intentCard: some View {
        Card(title: "Enable") {
            Toggle("Allow purge", isOn: Binding(
                get: { profile.purgeEnabled },
                set: { newValue in
                    if newValue { confirmEnable = true }
                    else { store.profile.purgeEnabled = false; store.save() }
                }))
            Text(profile.purgeEnabled
                 ? "Purge is ENABLED. Deletion still requires verified candidates + two confirmations."
                 : "Purge is OFF. Preview is always available; nothing can be deleted while this is off.")
                .font(.caption).foregroundStyle(profile.purgeEnabled ? .orange : .secondary)
            if profile.mirrorDestinations.isEmpty {
                Label("Add a mirror in Settings — verification (and therefore deletion) requires a second on-disk copy.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Preview + delete

    private var previewCard: some View {
        Card(title: "Preview & delete") {
            HStack {
                Button {
                    appState.previewPurge()
                } label: { Label("Preview Eligible Photos", systemImage: "eye") }
                    .disabled(appState.isPlanningPurge || appState.isPurging || appState.readiness.osxphotos == nil)
                if appState.isPlanningPurge {
                    ProgressView().controlSize(.small)
                    Text("Scanning library + archive…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let plan = appState.purgePlan {
                planSummary(plan)
            } else if !appState.isPlanningPurge {
                Text("Preview reads your library (photos older than \(profile.retention.keepWindowDays) days, not pinned) and checks each against the archive. Nothing is deleted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planSummary(_ plan: PurgePlan) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
            statRow("Eligible (old + not pinned)", "\(plan.candidates.count)", .primary)
            statRow("Verified in ≥2 copies — deletable", "\(plan.verified.count)", .green)
            statRow("Unverified — will be skipped", "\(plan.unverified.count)", plan.unverified.isEmpty ? .secondary : .orange)
            statRow("Space freed in Photos/iCloud", ByteCountFormatter.string(fromByteCount: Int64(plan.verifiedBytes), countStyle: .file), .secondary)
            if let range = plan.dateRange {
                statRow("Date range", "\(short(range.earliest)) – \(short(range.latest))", .secondary)
            }
        }
        .font(.callout)

        if !plan.unverified.isEmpty {
            Text("Unverified photos are NOT in both archive copies yet (often because their originals aren’t on this Mac, or this Mac’s archive is incomplete). They are never deleted — run the archive on the Mac with originals first.")
                .font(.caption).foregroundStyle(.secondary)
        }

        if !plan.verified.isEmpty {
            DisclosureGroup("Show \(min(plan.verified.count, 25)) of \(plan.verified.count) deletable") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(plan.verified.prefix(25)) { c in
                        HStack {
                            Text(c.filename).font(.system(.caption, design: .monospaced)).lineLimit(1)
                            Spacer()
                            Text(short(c.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete \(plan.verified.count) Verified Photos…", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!profile.purgeEnabled || appState.isPurging || plan.verified.isEmpty)
            if !profile.purgeEnabled {
                Text("Enable purge above to delete.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func messageBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(msg).font(.callout)
            Spacer()
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var rulesCard: some View {
        Card(title: "Safety gates (all must pass)") {
            rule("Photo is OLDER than \(profile.retention.keepWindowDays) days.")
            rule("Not in a keep album (\(list(profile.retention.keepAlbumNames))) or with a keep keyword (\(list(profile.retention.keepKeywords)))\(profile.retention.keepFavorites ? ", and not a Favorite" : "").")
            rule("File present in the primary archive AND a mirror, byte-consistent between them.")
            rule("Purge enabled here + you confirm + macOS confirms.")
            rule("Deletions sit in Photos’ Recently Deleted for 30 days.")
        }
    }

    // MARK: Helpers

    private func statRow(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).foregroundStyle(tint).bold() }
    }
    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield").foregroundStyle(.green).font(.caption)
            Text(text).font(.callout); Spacer()
        }
    }
    private func list(_ items: [String]) -> String { items.isEmpty ? "none" : items.joined(separator: ", ") }
    private func short(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }
}
