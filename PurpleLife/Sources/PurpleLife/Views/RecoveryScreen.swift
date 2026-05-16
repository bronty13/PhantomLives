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

    /// Phase B.4 (2026-05-15) — optional callback for the "Enter
    /// recovery key" path. When non-nil AND a recovery envelope
    /// exists on disk, the recovery screen shows a third button
    /// that opens a sheet for the user to paste their 24-word
    /// phrase. Returns a Result so the UX can show a specific
    /// error message instead of a generic failure.
    var hasRecoveryEnvelope: Bool = false
    var onRecoveryKey: ((String) -> Result<Void, Error>)? = nil

    @State private var confirming = false
    @State private var showRecoveryKeySheet = false

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
                if hasRecoveryEnvelope && onRecoveryKey != nil {
                    Label("Use your recovery key", systemImage: "key.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("If you saved the 24-word recovery key when you first set up PurpleLife, enter it now to unlock your data. This is the fastest path — your records, schemas, and settings come back exactly as they were.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("Quit and restore from backup", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, (hasRecoveryEnvelope && onRecoveryKey != nil) ? 4 : 0)
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

                if hasRecoveryEnvelope, onRecoveryKey != nil {
                    Button {
                        showRecoveryKeySheet = true
                    } label: {
                        Label("Enter recovery key…", systemImage: "key.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                Button("Reset and start fresh", role: .destructive) {
                    confirming = true
                }
                .keyboardShortcut(hasRecoveryEnvelope && onRecoveryKey != nil ? nil : .defaultAction)
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
        .sheet(isPresented: $showRecoveryKeySheet) {
            if let onRecoveryKey {
                RecoveryKeyEnterSheet(onSubmit: onRecoveryKey)
            }
        }
    }
}

/// Sheet for the recovery screen's "Enter recovery key…" button. The
/// user pastes or types their 24-word phrase, hits Unlock, and on
/// success the sheet dismisses and the underlying recovery screen is
/// replaced by the normal app. On failure we show a specific
/// per-error-case message (wrong word count, unknown word, checksum
/// mismatch from a typo, wrong key entirely) and let the user try
/// again.
private struct RecoveryKeyEnterSheet: View {
    let onSubmit: (String) -> Result<Void, Error>
    @Environment(\.dismiss) private var dismiss

    @State private var input: String = ""
    @State private var errorMessage: String? = nil
    @State private var working: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter your recovery key")
                .font(.title3).bold()
            Text("Paste or type the 24 words you saved when you first set up PurpleLife. The order matters; the last word is a checksum, so a single typo is caught and surfaced as a clear error.")
                .font(.callout).foregroundStyle(.secondary)

            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                .disabled(working)

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage).font(.callout)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button {
                    submit()
                } label: {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func submit() {
        working = true
        errorMessage = nil
        let phrase = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Stay on main actor — the underlying KeyStore + DB work is
        // already main-actor scoped (AppState owns them). Wrapping
        // in a Task lets the spinner render between input update
        // and the sync call.
        Task { @MainActor in
            let result = onSubmit(phrase)
            working = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                errorMessage = friendly(error)
            }
        }
    }

    private func friendly(_ error: Error) -> String {
        if let rk = error as? RecoveryKey.RecoveryKeyError {
            switch rk {
            case .wrongWordCount(let actual):
                return "A recovery key has 24 words; you entered \(actual). Double-check that no words are missing or duplicated."
            case .wordNotInList(let word):
                return "\"\(word)\" isn't in the BIP39 wordlist. Check the spelling and try again."
            case .checksumMismatch:
                return "One of the words doesn't match the rest of the phrase — likely a typo. Re-read each word carefully."
            case .internalError:
                return "Unexpected error decoding the phrase. Please file a bug report."
            }
        }
        if let kse = error as? KeyStore.KeyStoreError {
            switch kse {
            case .passphraseMismatch:
                return "The phrase decoded correctly but doesn't match this Mac's recovery key. Check that you're using the key from THIS install — keys generated on other Macs (or on this Mac before a Reset) won't work."
            case .notSetup:
                return "PurpleLife couldn't find a recovery envelope on disk. This install may pre-date recovery keys, or the envelope file was deleted."
            case .corrupt:
                return "The key unlocked the envelope, but the on-disk database still failed to open. The data file may be damaged."
            default:
                return "Couldn't unlock: \(error.localizedDescription)"
            }
        }
        return "Couldn't unlock: \(error.localizedDescription)"
    }
}
