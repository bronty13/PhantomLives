import SwiftUI
import AppKit

/// Full-window screen shown when `AppState.dbUnrecoverable` is set — the on-disk
/// database is encrypted with a key that's no longer in the Keychain. Offers
/// the two ways forward: enter the 24-word recovery key to unlock, or reset and
/// start fresh (the unreadable data is quarantined, not deleted).
struct RecoveryScreen: View {
    let message: String
    @EnvironmentObject private var appState: AppState

    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    Text("Can't unlock your journal")
                        .font(.title2).bold()
                }
                Text(message)
                    .foregroundStyle(.secondary)
                Divider()

                RecoveryUnlockView(
                    title: "Enter your 24-word recovery key",
                    onUnlock: { phrase in appState.tryRecoveryKeyUnlock(phrase: phrase) },
                    onSuccess: { /* dbUnrecoverable cleared by AppState; view dismisses */ },
                    onCancel: nil
                )
                .environmentObject(appState)

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recovery key?").font(.headline)
                    Text("You can reset and start fresh. Your existing (unreadable) data is moved into a `.unrecoverable-…` folder inside the app's Application Support directory rather than deleted, in case the key turns up later.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("Reset and start fresh…", systemImage: "trash")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Reset and start fresh?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { appState.resetUnrecoverableData() }
        } message: {
            Text("Creates a brand-new empty, encrypted journal and a new recovery key. Your current encrypted data is preserved on disk (quarantined) but won't be visible in the app.")
        }
    }
}

/// Reusable 24-word recovery-phrase entry form. Used by both `RecoveryScreen`
/// (unrecoverable state) and `AppLockScreen` (forgotten passphrase). The
/// `onUnlock` closure returns a `Result` so callers map success/failure to
/// their own flow.
struct RecoveryUnlockView: View {
    let title: String
    let onUnlock: (String) -> Result<Void, Error>
    let onSuccess: () -> Void
    let onCancel: (() -> Void)?

    @State private var phrase = ""
    @State private var error: String?
    @State private var working = false

    /// Checksum-valid 24-word phrases found in whatever was typed/pasted —
    /// tolerant of numbering and prose (e.g. pasting back a saved key file).
    private var candidates: [[String]] {
        RecoveryKey.candidatePhrases(in: phrase)
    }
    private var looksComplete: Bool { !candidates.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text("Type or paste all 24 words. Numbering, line breaks, case, and surrounding text are fine — paste the whole saved key file if you like.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $phrase)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            HStack {
                Button { if let text = RecoveryKeyFile.read() { phrase = text; error = nil } } label: {
                    Label("Read from file…", systemImage: "doc.text")
                }
                Text(looksComplete ? "✓ recovery key detected" : "Enter your 24 words")
                    .font(.caption)
                    .foregroundStyle(looksComplete ? .green : .secondary)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                if let onCancel {
                    Button("Cancel") { onCancel() }
                }
                Button("Unlock") { attempt() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!looksComplete || working)
            }
        }
    }

    private func attempt() {
        working = true
        defer { working = false }
        // Try each checksum-valid candidate; the right one decrypts the envelope.
        for words in candidates {
            if case .success = onUnlock(RecoveryKey.format(words)) {
                error = nil
                onSuccess()
                return
            }
        }
        error = "That recovery key didn't unlock your journal. Check for typos and try again."
    }
}

/// Shared open-panel that loads a saved recovery-key text file and returns its
/// contents. `RecoveryKey.candidatePhrases` then extracts the 24 words from
/// whatever formatting the file uses (numbered list + prose, or a clean line).
enum RecoveryKeyFile {
    static func read() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose recovery key file"
        panel.message = "Pick the recovery-key file you saved (a plain-text file)."
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let dir = downloads.appendingPathComponent("PurpleDiary", isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.path) { panel.directoryURL = dir }
        }
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}
