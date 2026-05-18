import SwiftUI

/// First-launch (and re-runnable) Privacy & Security walk-through.
/// Detects which Files & Folders grants PurpleReel currently has via
/// `PermissionsCheck.run()` and lists the ones still needed with a
/// "Open in System Settings…" button per row. The wizard is the
/// single biggest "I'm coming from Kyno and it's already painful"
/// blocker per the research doc (rows 79, 80) — Kyno's FAQ has
/// multiple entries on the same TCC pain so closing it is a clear
/// migration-friction win.
struct PermissionsWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: PermissionsCheck.Result = PermissionsCheck.run()
    @State private var checkedAt: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            statusList
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 580)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy & Security check")
                    .font(.title2.weight(.semibold))
                Text(result.hasMinimumViable
                      ? "You're good — every folder PurpleReel needs is reachable."
                      : "PurpleReel needs a few macOS permissions to browse your media reliably.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusList: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Movies folder", granted: result.movies, pane: .filesAndFolders,
                rationale: "Most camera output + edited masters live under ~/Movies.")
            row("Downloads folder", granted: result.downloads, pane: .filesAndFolders,
                rationale: "PhantomLives apps default their output to ~/Downloads/<App>/. Transcodes, exports, and verified backups land there.")
            row("Documents folder", granted: result.documents, pane: .filesAndFolders,
                rationale: "Project files, FCPXML exports, and many users' workspace roots.")
            Divider().padding(.vertical, 4)
            row("Full Disk Access", granted: result.fullDiskAccess, pane: .fullDiskAccess,
                rationale: "Optional — only needed if you browse media in places macOS hides by default (system folders, other users' homes, etc.). Granting this also covers every individual folder above.",
                emphasizeGrant: false)
            Divider().padding(.vertical, 4)
            informational(
                title: "Removable Volumes",
                pane: .removableVolumes,
                blurb: "Authorize once and PurpleReel can read USB sticks, SD cards, and camera media on mount. Required for the DCIM auto-drilldown behavior in Devices → Removable."
            )
            informational(
                title: "Network Volumes",
                pane: .networkVolumes,
                blurb: "Authorize once and PurpleReel can read SMB / AFP / NFS mounts. Needed if your workspace lives on a NAS."
            )
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
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func row(_ label: String, granted: Bool,
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
            if !granted {
                Button(emphasizeGrant ? "Grant…" : "Open…") {
                    PermissionsCheck.openSettings(pane)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Open…") {
                    PermissionsCheck.openSettings(pane)
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func informational(title: String,
                                 pane: PermissionsCheck.Pane,
                                 blurb: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open…") {
                PermissionsCheck.openSettings(pane)
            }
            .controlSize(.small)
        }
    }
}
