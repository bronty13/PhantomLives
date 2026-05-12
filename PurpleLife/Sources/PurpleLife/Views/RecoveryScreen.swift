import SwiftUI

/// Full-window takeover when the on-disk SQLCipher database is encrypted
/// with a key the app no longer has access to. The most common cause is
/// a Keychain entry getting cleared while the file stays encrypted (a
/// system reset, a manual `security delete-generic-password`, or a
/// migration to a new user account). Without a clear recovery path the
/// app silently boots into a broken state — every query hits the
/// placeholder pool and fails with "no such table: objects".
///
/// We deliberately don't auto-reset. Data loss should be a user
/// decision: they may have a backup of the matching Keychain entry, or
/// they may prefer to copy the file aside and investigate before
/// committing to a destructive reset. The "Reset and start fresh"
/// action *quarantines* — never deletes — the unreadable bytes, so a
/// future recovery is still possible.
struct RecoveryScreen: View {
    let detail: String
    let onReset: () -> Void

    @State private var confirming = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("PurpleLife can't unlock your data")
                .font(.title2.weight(.semibold))

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            Divider().frame(width: 360)

            VStack(alignment: .leading, spacing: 8) {
                Label("Quit and restore from backup", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                Text("If you have a recent backup ZIP from `~/Downloads/PurpleLife backup/` taken while this Mac's Keychain entry was still intact, quit now and restore the matching `Application Support/PurpleLife/` snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("Reset and start fresh", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                Text("Moves the unreadable DB, settings, and attachments into a `.unrecoverable-<timestamp>/` folder inside Application Support, then creates a fresh empty database keyed against the current Keychain entry. Nothing is deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, alignment: .leading)

            HStack(spacing: 12) {
                Button("Quit PurpleLife") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)

                Button("Reset and start fresh", role: .destructive) {
                    confirming = true
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .confirmationDialog(
            "Quarantine the unreadable data and create a fresh database?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { onReset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current database, settings, and attachments are moved into a `.unrecoverable-<timestamp>/` folder inside `~/Library/Application Support/PurpleLife/`. They are not deleted. PurpleLife restarts in this window with an empty database.")
        }
    }
}
