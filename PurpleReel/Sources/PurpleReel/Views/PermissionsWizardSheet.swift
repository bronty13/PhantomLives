import SwiftUI

/// First-launch (and re-runnable) Privacy & Security walk-through.
///
/// macOS 15+ (Sequoia / Tahoe) treats Files & Folders, Full Disk
/// Access, Removable Volumes, and Network Volumes as four DISTINCT
/// permission classes. FDA does NOT automatically cover Removable
/// or Network Volumes — each needs its own grant.
///
/// **Files & Folders / FDA** we can probe statically by attempting
/// a directory listing on representative paths (`~/Movies`,
/// `~/Downloads`, `~/Documents`, `/private/var/db`). The matching
/// rows in System Settings → Privacy & Security exist pre-populated
/// once an app has them in its entitlements, so the "Open…"
/// deep-link is useful here.
///
/// **Removable + Network Volumes** are *consent-on-first-use* on
/// macOS 15+: the System Settings entry doesn't even exist until
/// PurpleReel has tried to read from a real mount, at which point
/// macOS fires an Allow/Deny dialog inline. There's nothing for the
/// user to manually grant ahead of time — the previous "open Settings
/// then tick the checkbox" flow simply doesn't model that. Instead
/// we offer a *Trigger prompt…* action that fires the OS dialog
/// on demand (open-panel on `/Volumes/` for Removable, Finder
/// Connect-to-Server for Network), and a *Don't remind me* checkbox
/// that's purely a nag-dismissal flag — it grants nothing.
struct PermissionsWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: PermissionsCheck.Result = PermissionsCheck.run()
    @State private var checkedAt: Date = Date()
    @State private var removableStatus: TriggerStatus = .idle
    @State private var networkStatus: TriggerStatus = .idle

    /// User-facing "stop reminding me about this row" flags. These do
    /// NOT grant any permission — macOS handles the actual grant via
    /// the consent-on-first-use prompt. We persist these so re-
    /// opening the wizard doesn't keep nagging once the user has
    /// either granted, opted out, or doesn't use that volume class.
    @AppStorage("permissionsRemovableDismissed") private var removableDismissed: Bool = false
    @AppStorage("permissionsNetworkDismissed")   private var networkDismissed: Bool = false

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
        .frame(width: 600, height: 660)
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
                      : "macOS 15+ uses four separate permission classes for PurpleReel. Files & Folders and Full Disk Access are auto-detected. Removable and Network Volumes use consent-on-first-use — macOS prompts when PurpleReel touches a drive or share, and there's nothing for you to set up in System Settings ahead of time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var allDone: Bool {
        result.hasMinimumViable && removableDismissed && networkDismissed
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
                       rationale: "Optional catch-all. Covers Movies / Downloads / Documents above, but does NOT cover Removable or Network Volumes — those are separate classes on macOS 15+.",
                       emphasizeGrant: false)
        }
    }

    @ViewBuilder
    private var manualGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Consent-on-first-use")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("On macOS 15+ there's no entry in System Settings to grant these ahead of time — macOS only adds the row once an app actually touches a removable or network volume. PurpleReel will get the prompt automatically the first time you load from a USB drive or NAS. If you'd rather grant access proactively, use Trigger prompt… to pick a volume now and fire the dialog.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            manualRow(
                title: "Removable Volumes",
                blurb: "USB sticks, SD cards, and camera-card mounts. Separate from Full Disk Access on macOS 15+.",
                status: $removableStatus,
                dismissed: $removableDismissed,
                trigger: { removableStatus = .running
                            let outcome = PermissionsCheck.triggerRemovableVolumePrompt()
                            removableStatus = .finished(outcome)
                            if case .granted = outcome { removableDismissed = true } }
            )
            manualRow(
                title: "Network Volumes",
                blurb: "SMB / AFP / NFS mounts. Required if your workspace lives on a NAS.",
                status: $networkStatus,
                dismissed: $networkDismissed,
                trigger: { networkStatus = .running
                            let outcome = PermissionsCheck.triggerNetworkVolumePrompt()
                            networkStatus = .finished(outcome)
                            if case .granted = outcome { networkDismissed = true } }
            )
        }
    }

    @ViewBuilder
    private var relaunchHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
            Text("If you grant a Files & Folders or Full Disk Access permission while PurpleReel is running, you may need to quit and relaunch for the new grant to take effect — macOS doesn't always apply TCC changes to a live process. Use Re-check below to refresh the auto-detected rows.")
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

    /// Consent-on-first-use row: explains the model, offers a
    /// `Trigger prompt…` action that fires the OS dialog inline,
    /// plus a *Don't remind me* checkbox that just hides the
    /// reminder (no permission is granted by ticking it).
    @ViewBuilder
    private func manualRow(title: String,
                            blurb: String,
                            status: Binding<TriggerStatus>,
                            dismissed: Binding<Bool>,
                            trigger: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: dismissed.wrappedValue
                  ? "checkmark.circle.fill"
                  : "questionmark.circle")
                .font(.title3)
                .foregroundStyle(dismissed.wrappedValue ? .green : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = status.wrappedValue.statusLine {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(status.wrappedValue.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Don't remind me", isOn: dismissed)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .help("Hides this row on future launches. Does NOT grant the permission — macOS will still ask the first time PurpleReel touches this volume class.")
            }
            Spacer()
            Button("Trigger prompt…") { trigger() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
                .disabled(status.wrappedValue == .running)
        }
    }

    /// Per-row state for the Trigger-prompt action so we can echo
    /// success / failure back to the user without an alert.
    enum TriggerStatus: Equatable {
        case idle
        case running
        case finished(PermissionsCheck.TriggerOutcome)

        var statusLine: String? {
            switch self {
            case .idle:     return nil
            case .running:  return "Waiting for you to pick a volume…"
            case .finished(.granted):
                return "macOS allowed the read — access is granted."
            case .finished(.cancelled):
                return "Cancelled. No prompt was issued."
            case .finished(.denied(let reason)):
                return "Read failed: \(reason)"
            }
        }

        var tint: Color {
            switch self {
            case .idle:                return .secondary
            case .running:             return .secondary
            case .finished(.granted):  return .green
            case .finished(.cancelled): return .secondary
            case .finished(.denied):   return .orange
            }
        }
    }
}
