import SwiftUI

/// First-launch (and re-runnable) Privacy & Security walk-through.
///
/// macOS 15+ treats Files & Folders, Full Disk Access, Removable
/// Volumes, and Network Volumes as four DISTINCT permission classes.
/// FDA does NOT automatically cover Removable or Network Volumes —
/// each needs its own grant. The sheet says this explicitly because
/// it's the #1 thing users miss.
///
/// We can probe Files & Folders / FDA by attempting a directory
/// listing on representative paths (`~/Movies`, `~/Downloads`,
/// `~/Documents`, `/private/var/db`). Removable + Network Volume
/// access can't be statically probed — you'd need an actual mount —
/// so those rows are user-confirmed checkboxes that persist in
/// AppStorage. The user grants in System Settings, then checks the
/// row themselves so PurpleReel stops nagging.
struct PermissionsWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: PermissionsCheck.Result = PermissionsCheck.run()
    @State private var checkedAt: Date = Date()

    /// User-confirmed flags for the two permission classes we can't
    /// auto-detect. Persist across launches so re-opening the
    /// wizard doesn't ask twice.
    @AppStorage("permissionsRemovableConfirmed") private var removableConfirmed: Bool = false
    @AppStorage("permissionsNetworkConfirmed")   private var networkConfirmed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    autoDetectedGroup
                    Divider().padding(.vertical, 4)
                    manualGroup
                    Divider().padding(.vertical, 4)
                    relaunchHint
                }
                .padding(.vertical, 2)
            }
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 600, height: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy & Security check")
                    .font(.title2.weight(.semibold))
                Text(allDone
                      ? "You're good — every permission PurpleReel needs is in place."
                      : "macOS 15+ uses four separate permission classes for PurpleReel. Files & Folders + Full Disk Access are auto-detected; Removable + Network Volumes can't be probed, so you'll mark those yourself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var allDone: Bool {
        result.hasMinimumViable && removableConfirmed && networkConfirmed
    }

    @ViewBuilder
    private var autoDetectedGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Auto-detected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            probedRow("Movies folder", granted: result.movies, pane: .filesAndFolders,
                       rationale: "Most camera output + edited masters live under ~/Movies.")
            probedRow("Downloads folder", granted: result.downloads, pane: .filesAndFolders,
                       rationale: "PhantomLives apps default output to ~/Downloads/<App>/.")
            probedRow("Documents folder", granted: result.documents, pane: .filesAndFolders,
                       rationale: "Project files, FCPXML exports, many users' workspace roots.")
            probedRow("Full Disk Access", granted: result.fullDiskAccess, pane: .fullDiskAccess,
                       rationale: "Optional catch-all. Covers Movies / Downloads / Documents above, but does NOT cover Removable or Network Volumes — those are separate panes.",
                       emphasizeGrant: false)
        }
    }

    @ViewBuilder
    private var manualGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Can't be auto-detected — confirm manually")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("macOS doesn't expose an API to test these without an actual mount. After granting in System Settings, tick the checkbox so PurpleReel stops listing it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            manualRow(
                title: "Removable Volumes",
                blurb: "USB sticks, SD cards, and camera-card mounts. Separate from Full Disk Access on macOS 15+.",
                pane: .removableVolumes,
                confirmed: $removableConfirmed
            )
            manualRow(
                title: "Network Volumes",
                blurb: "SMB / AFP / NFS mounts. Required if your workspace lives on a NAS. Separate from Full Disk Access on macOS 15+.",
                pane: .networkVolumes,
                confirmed: $networkConfirmed
            )
        }
    }

    @ViewBuilder
    private var relaunchHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
            Text("After granting a permission, you may need to quit and relaunch PurpleReel for the new grant to take effect — macOS doesn't always apply TCC changes to a running process. Re-check below to refresh the auto-detected rows.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("Re-check") {
                result = PermissionsCheck.run()
                checkedAt = Date()
            }
            Text("Last checked: \(checkedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit PurpleReel") {
                NSApplication.shared.terminate(nil)
            }
            .help("Quit so a fresh launch picks up newly-granted permissions.")
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Row helpers

    /// Auto-detected row: green check or orange warning + Grant/Open
    /// button to jump to the System Settings sub-pane.
    @ViewBuilder
    private func probedRow(_ label: String,
                            granted: Bool,
                            pane: PermissionsCheck.Pane,
                            rationale: String,
                            emphasizeGrant: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted
                  ? "checkmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            // SwiftUI's `.bordered` and `.borderedProminent` resolve
            // to different concrete `ButtonStyle` types, so we can't
            // conditionally swap them in one expression. Apply
            // prominence-via-modifier instead.
            Button(granted ? "Open…" : (emphasizeGrant ? "Grant…" : "Open…")) {
                PermissionsCheck.openSettings(pane)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(!granted && emphasizeGrant ? Color.accentColor : Color.secondary)
        }
    }

    /// User-confirmed row: open System Settings to the right pane,
    /// then user ticks the checkbox to acknowledge.
    @ViewBuilder
    private func manualRow(title: String,
                            blurb: String,
                            pane: PermissionsCheck.Pane,
                            confirmed: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: confirmed.wrappedValue
                  ? "checkmark.circle.fill"
                  : "questionmark.circle")
                .font(.title3)
                .foregroundStyle(confirmed.wrappedValue ? .green : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("I've granted this in System Settings",
                        isOn: confirmed)
                    .font(.caption)
                    .toggleStyle(.checkbox)
            }
            Spacer()
            Button("Open…") {
                PermissionsCheck.openSettings(pane)
            }
            .controlSize(.small)
        }
    }
}
