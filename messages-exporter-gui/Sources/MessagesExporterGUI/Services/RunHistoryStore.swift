import Foundation
import Combine

/// One row in the run-history file. Captures everything needed to repro
/// the run from the sidebar (click → fill the form) plus enough metadata
/// to render a useful one-liner ("Sallie · 16d", "4h ago", green dot).
///
/// `runFolderPath` may be missing (the user manually deleted the folder
/// after the run completed) — the click-to-fill flow handles that
/// gracefully; we only check existence at click time, not on every load.
struct RunHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var contact: String
    var start: Date?
    var end: Date?
    var mode: ExportMode
    var transcribe: Bool
    var transcribeModel: WhisperModel
    var emoji: EmojiMode
    var completedAt: Date
    var runFolderPath: String?
    var messageCount: Int?
    var attachmentCount: Int?
    var outputBytes: Int64?
    /// True when the underlying CLI exited 0 AND produced an output folder.
    /// False covers both cancellation and CLI failures — we still record
    /// these so the user can see "I tried this and it failed" in the
    /// sidebar without having to dig through a log.
    var exitOK: Bool

    /// "Sallie Wren · 16d" — the headline rendered in the sidebar row.
    var sidebarTitle: String {
        let span = RunStats.formatSpan(start: start, end: end)
        return span == "—" ? contact : "\(contact) · \(span)"
    }
}

/// JSON-backed persistent store of past runs. Keeps the most recent 50;
/// older rows are trimmed on every save so the file size stays bounded
/// regardless of how heavily the app is used.
@MainActor
final class RunHistoryStore: ObservableObject {
    @Published private(set) var entries: [RunHistoryEntry] = []

    /// Cap for retained history. Sidebar only shows the top 5; the full
    /// list is for the "Recent runs" destination once that view ships.
    /// Anything beyond this gets pruned at write time.
    static let maxEntries = 50

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL = AppSupport.runHistoryURL) {
        self.url = url
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        load()
    }

    /// Append a new run and persist. Most-recent-first ordering — the
    /// sidebar reads `entries.prefix(5)` directly.
    func record(_ entry: RunHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    /// Delete a single entry by id. The user can wipe a noisy "I was
    /// testing" run without nuking the whole history.
    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Wipe all history. Used by the Settings → Backup section's
    /// "Clear history" button.
    func clearAll() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let rows = try? decoder.decode([RunHistoryEntry].self, from: data)
        else { return }
        entries = rows
    }

    private func save() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("MessagesExporterGUI: run-history save failed — \(error.localizedDescription)")
        }
    }
}
