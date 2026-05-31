import SwiftUI
import AppKit

/// First-launch mandatory save-recovery-key screen. Replaces the entire window
/// while `AppState.pendingRecoveryKey` is non-nil — the user cannot reach the
/// main app UI without going through this flow.
///
/// A recovery key the user doesn't know about is no recovery key at all. The
/// phrase only exists in memory for the duration of this screen; once
/// `AppState.confirmRecoveryKeySaved()` fires it is gone for good (it lives
/// only inside the already-encrypted recovery envelope). Same threat model as a
/// crypto seed phrase or an iCloud Recovery Key.
///
/// A three-word typeback (random positions) forces the user to actually read
/// the phrase rather than reflexively clicking "I saved it."
struct RecoveryKeySaveSheet: View {
    let words: [String]
    let onConfirmed: () -> Void

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
            if challenges.isEmpty {
                challenges = pickChallenges(count: 3, from: words.count)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 26))
                Text("Save your recovery key")
                    .font(.title2).bold()
            }
            Text("PurpleDiary encrypts your journal on disk and has generated a 24-word recovery key that can unlock it if this Mac's Keychain entry is ever lost.")
                .foregroundStyle(.secondary)
            Text("Write it down on paper, save it to your password manager, or print it. **Anyone with this key can read your journal**, so treat it like a seed phrase.")
                .foregroundStyle(.secondary)
            Text("After you confirm, the key is gone — PurpleDiary stores it nowhere except inside your already-encrypted database.")
                .foregroundStyle(.tertiary).font(.callout)
        }
    }

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

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm you've saved it")
                .font(.headline)
            Text("Type these specific words to prove you have the phrase in front of you. (Three are picked at random so you have to read the whole list.)")
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

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(RecoveryKey.format(words), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    /// Write the recovery key to `~/Downloads/PurpleDiary/…-recovery-key.txt`
    /// per the PhantomLives default-output convention.
    private func saveToFile() {
        let panel = NSSavePanel()
        panel.title = "Save recovery key"
        panel.message = "Choose where to save your 24-word recovery key. Anyone with the file can read your journal — treat it like a password."
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "PurpleDiary-recovery-key.txt"
        if let downloadsRoot = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let dir = downloadsRoot.appendingPathComponent("PurpleDiary", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            panel.directoryURL = dir
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body =
            "PurpleDiary recovery key — generated \(ISO8601DateFormatter().string(from: Date()))\n\n" +
            "Anyone holding this key can read your PurpleDiary journal. Store it as carefully as a seed phrase.\n\n" +
            RecoveryKey.formatNumbered(words) + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            savedToFileAt = url
        } catch {
            NSLog("PurpleDiary: recovery-key save failed — \(error.localizedDescription)")
        }
    }

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
