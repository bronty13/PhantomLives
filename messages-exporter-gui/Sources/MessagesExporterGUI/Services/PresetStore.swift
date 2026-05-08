import Foundation
import Combine

/// A named, reusable export configuration. Snapshot semantics: the
/// stored dates are the literal values that were on the form when the
/// user pressed Save preset. Applying a preset later restores those
/// exact dates rather than computing a relative range — relative ranges
/// ("last 30 days") would be a useful future enhancement but aren't
/// needed for the v1 stubs-to-real promotion.
///
/// `dateRange` is optional even though the form always has dates: a
/// preset author may explicitly want "all time" semantics by clearing
/// the dates before saving.
struct ExportPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var contact: String
    var start: Date?
    var end: Date?
    var mode: ExportMode
    var transcribe: Bool
    var transcribeModel: WhisperModel
    var emoji: EmojiMode
    var createdAt: Date = Date()
}

/// JSON-backed persistent store of named presets. Insertion-ordered so
/// the sidebar can render them in the order the user created them.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [ExportPreset] = []

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL = AppSupport.presetsURL) {
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

    /// Save (or upsert by id). If a preset with the same id exists, it's
    /// replaced in place. Otherwise it's appended.
    func upsert(_ preset: ExportPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        save()
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    /// Rename in place. UI uses this rather than upsert when only the
    /// name changes so we don't lose ordering.
    func rename(id: UUID, to newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = newName
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let rows = try? decoder.decode([ExportPreset].self, from: data)
        else { return }
        presets = rows
    }

    private func save() {
        do {
            let data = try encoder.encode(presets)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("MessagesExporterGUI: preset save failed — \(error.localizedDescription)")
        }
    }
}
