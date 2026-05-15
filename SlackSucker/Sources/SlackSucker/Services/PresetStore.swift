import Foundation
import Combine

/// A named, reusable archive configuration. Snapshot semantics: the
/// dates stored are the literal values that were on the form when the
/// user pressed Save preset. Applying restores those exact dates rather
/// than recomputing a relative range.
struct ArchivePreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var request: ArchiveRequest
    var createdAt: Date = Date()
}

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [ArchivePreset] = []

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

    func upsert(_ preset: ArchivePreset) {
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

    func rename(id: UUID, to newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = newName
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let rows = try? decoder.decode([ArchivePreset].self, from: data)
        else { return }
        presets = rows
    }

    private func save() {
        do {
            let data = try encoder.encode(presets)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("SlackSucker: preset save failed — \(error.localizedDescription)")
        }
    }
}
