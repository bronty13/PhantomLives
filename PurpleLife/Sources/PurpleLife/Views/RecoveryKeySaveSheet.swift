import SwiftUI
import AppKit

/// First-launch (and Phase B migration) mandatory save-recovery-key
/// screen. Replaces the entire window contents while
/// `AppState.pendingRecoveryKey` is non-nil — the user *cannot*
/// reach the main app UI without going through this flow.
///
/// **Why mandatory.** A recovery key the user doesn't know about is
/// no recovery key at all. We considered a dismissable banner /
/// non-modal nag, but data-loss incident #4 (2026-05-15) made it
/// clear that any "you can always read it later" affordance reduces
/// to "the user never sees it." The recovery key only exists in
/// memory for the duration of this screen; once
/// `AppState.confirmRecoveryKeySaved()` fires, the value is gone
/// for good. That's the same threat model as a Bitcoin seed phrase
/// or an iCloud Recovery Key — and the same UX answer those
/// products converged on.
///
/// **Confirmation typeback.** Three randomly-picked words must be
/// re-typed in the right slot to dismiss. Forces the user to
/// actually read the phrase rather than mash "I saved it" reflex-
/// style. Three positions out of 24 isn't fool-proof (a determined
/// user can click around it) but it raises the friction enough
/// that anyone who skips obviously meant to.
struct RecoveryKeySaveSheet: View {
    let words: [String]
    let onConfirmed: () -> Void

    /// Indices of the 3 words the user is asked to re-type. Picked
    /// once at view appearance so the asks stay stable while the
    /// user types.
    @State private var challenges: [Int] = []
    @State private var responses: [String: String] = [:]
    @State private var copied: Bool = false
    @State private var savedToFileAt: URL? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                wordsGrid
                Divider()
                actionsRow
                Divider()
                confirmation
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Pick three challenge indices on first appearance, then
            // keep them stable. Random across the full phrase so the
            // user has to read the whole thing, not just the first
            // or last few words.
            if challenges.isEmpty {
                challenges = pickChallenges(count: 3, from: words.count)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 26))
                Text("Save your recovery key")
                    .font(.title2).bold()
            }
            Text("PurpleLife has generated a 24-word recovery key that can unlock your data if the Mac Keychain entry is ever lost.")
                .foregroundStyle(.secondary)
            Text("Write it down on paper, save it to your password manager, or print it. **Anyone with this key can read your data**, so treat it like a Bitcoin seed phrase.")
                .foregroundStyle(.secondary)
            Text("After you confirm, the key is gone — PurpleLife does not store it anywhere except inside your already-encrypted database.")
                .foregroundStyle(.tertiary).font(.callout)
        }
    }

    // MARK: - Words

    private var wordsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                wordRow(index: idx, word: word)
            }
        }
    }

    private func wordRow(index: Int, word: String) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            Text(word)
                .font(.system(.body, design: .monospaced).bold())
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                copyToClipboard()
            } label: {
                Label(copied ? "Copied" : "Copy to clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            Button {
                saveToFile()
            } label: {
                Label("Save to file…", systemImage: "square.and.arrow.down")
            }
            if let url = savedToFileAt {
                Text("Saved to \(url.lastPathComponent)")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
        }
    }

    // MARK: - Confirmation typeback

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm you've saved it")
                .font(.headline)
            Text("Type these specific words to prove you have the phrase in front of you. (We pick three at random so you have to read the whole list, not just the ends.)")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(challenges, id: \.self) { idx in
                challengeRow(index: idx)
            }

            HStack {
                Spacer()
                Button {
                    onConfirmed()
                } label: {
                    Label("I've saved my recovery key", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 8).padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allChallengesMatch)
                .keyboardShortcut(allChallengesMatch ? .defaultAction : nil)
            }
        }
    }

    private func challengeRow(index: Int) -> some View {
        let expected = words[index]
        let response = responses[String(index)] ?? ""
        let matches = response.trimmingCharacters(in: .whitespaces).lowercased() == expected
        return HStack(spacing: 10) {
            Text("Word #\(index + 1):")
                .font(.callout.monospaced())
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField("Re-type word #\(index + 1)", text: Binding(
                get: { responses[String(index)] ?? "" },
                set: { responses[String(index)] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            if matches {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if !response.isEmpty {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
    }

    private var allChallengesMatch: Bool {
        for idx in challenges {
            let resp = (responses[String(idx)] ?? "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if resp != words[idx] { return false }
        }
        return !challenges.isEmpty
    }

    // MARK: - Helpers

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(RecoveryKey.format(words), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    /// Write the recovery key to `~/Downloads/PurpleLife/<stamp>-recovery-key.txt`
    /// per the PhantomLives default output location convention. The
    /// user can move / archive / shred the file as they prefer.
    private func saveToFile() {
        let panel = NSSavePanel()
        panel.title = "Save recovery key"
        panel.message = "Choose where to save your 24-word recovery key. Anyone with the file can read your data — treat it like a password."
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "PurpleLife-recovery-key.txt"
        let downloadsRoot = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let downloadsRoot {
            let dir = downloadsRoot.appendingPathComponent("PurpleLife", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            panel.directoryURL = dir
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body =
            "PurpleLife recovery key — generated \(ISO8601DateFormatter().string(from: Date()))\n\n" +
            "Anyone holding this key can read your PurpleLife data. Store it as carefully as you would store a Bitcoin seed phrase.\n\n" +
            RecoveryKey.formatNumbered(words) + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            savedToFileAt = url
        } catch {
            NSLog("PurpleLife: recovery-key save failed — \(error.localizedDescription)")
        }
    }

    /// Pick `count` distinct indices in `[0, total)` without bias.
    /// Uses `SystemRandomNumberGenerator` so the same dialog never
    /// asks the same three words twice on the same machine; subtle
    /// defense against the "user memorizes positions to skip
    /// reading" failure mode.
    private func pickChallenges(count: Int, from total: Int) -> [Int] {
        var pool = Array(0..<total)
        var picks: [Int] = []
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<min(count, total) {
            let idx = Int.random(in: 0..<pool.count, using: &rng)
            picks.append(pool.remove(at: idx))
        }
        return picks.sorted()
    }
}
