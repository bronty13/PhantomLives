import Foundation
import Combine

/// Owns the list of user-created presets and exposes the combined
/// (built-in + user) roster the UI and CLI pick from. Built-ins come
/// from `Preset.builtIns` (code-defined); user presets persist as a
/// single JSON array under one UserDefaults key — the same
/// no-migration pattern `SettingsStore` uses for `filterTuningJSON`.
///
/// Injected as an `environmentObject` next to `ProcessingQueue` and
/// `SettingsStore`. The CLI constructs its own instance against the
/// shared `.standard` defaults so `--preset` can resolve user presets
/// too.
final class PresetStore: ObservableObject {

    @Published private(set) var userPresets: [Preset] = []

    private let defaults: UserDefaults
    private let storageKey = "userPresetsJSON"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.userPresets = Self.load(from: defaults, key: storageKey)
    }

    /// Built-ins first, then user presets in creation order.
    var all: [Preset] { Preset.builtIns + userPresets }

    // MARK: - Lookup

    func preset(id: UUID) -> Preset? {
        all.first { $0.id == id }
    }

    /// Case-insensitive name lookup. User presets win over a built-in
    /// of the same name (the user explicitly created it).
    func preset(named name: String) -> Preset? {
        let needle = name.lowercased()
        return userPresets.first { $0.name.lowercased() == needle }
            ?? Preset.builtIns.first { $0.name.lowercased() == needle }
    }

    // MARK: - Mutation (user presets only)

    /// Append a new user preset. Forces `builtIn = false` and mints a
    /// fresh id so a duplicated/saved preset never collides with a
    /// built-in. Returns the stored preset.
    @discardableResult
    func add(_ preset: Preset) -> Preset {
        var copy = preset
        copy.builtIn = false
        copy.id = UUID()
        userPresets.append(copy)
        persist()
        return copy
    }

    /// Replace an existing user preset (matched by id). No-op for
    /// built-ins or unknown ids.
    func update(_ preset: Preset) {
        guard let idx = userPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        userPresets[idx] = preset
        persist()
    }

    func delete(id: UUID) {
        userPresets.removeAll { $0.id == id }
        persist()
    }

    func rename(id: UUID, to name: String) {
        guard let idx = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[idx].name = name
        persist()
    }

    /// Copy any preset (built-in or user) into a new user preset with a
    /// distinct name. Returns the created copy.
    @discardableResult
    func duplicate(_ preset: Preset) -> Preset {
        var copy = preset
        copy.name = uniqueName(basedOn: preset.name)
        return add(copy)
    }

    // MARK: - Helpers

    /// Produce a name not already used by a user preset, e.g.
    /// "Podcast" → "Podcast copy" → "Podcast copy 2".
    private func uniqueName(basedOn base: String) -> String {
        let existing = Set(userPresets.map { $0.name.lowercased() })
        var candidate = "\(base) copy"
        var n = 2
        while existing.contains(candidate.lowercased()) {
            candidate = "\(base) copy \(n)"
            n += 1
        }
        return candidate
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(userPresets),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [Preset] {
        guard let json = defaults.string(forKey: key),
              !json.isEmpty,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data)
        else { return [] }
        return decoded
    }
}
