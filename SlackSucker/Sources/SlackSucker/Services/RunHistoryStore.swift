import Foundation
import Combine

/// One row in the run-history file. Captures the request that produced
/// this run plus enough rendered metadata to make the sidebar useful.
struct RunHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var request: ArchiveRequest
    var completedAt: Date
    var runFolderPath: String?
    var channelCount: Int?
    var messageCount: Int?
    var fileCount: Int?
    var outputBytes: Int64?
    /// True when slackdump exited 0 AND we resolved an output folder. We
    /// still record failures here so the sidebar shows the user's
    /// "I tried that" runs in addition to successes.
    var exitOK: Bool

    /// Headline shown in the sidebar row: "general · 14d".
    var sidebarTitle: String {
        let scopeName = request.scope.humanLabel
        let span: String
        switch request.timeRange {
        case .all:
            span = "all"
        case .range(let from, let to):
            span = RunStats.formatSpan(start: from, end: to)
        }
        return "\(scopeName) · \(span)"
    }
}

/// JSON-backed persistent store of past runs. Caps at `maxEntries`; older
/// rows are trimmed at save time so the file stays bounded.
@MainActor
final class RunHistoryStore: ObservableObject {
    @Published private(set) var entries: [RunHistoryEntry] = []

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

    func record(_ entry: RunHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

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
            NSLog("SlackSucker: run-history save failed — \(error.localizedDescription)")
        }
    }
}
