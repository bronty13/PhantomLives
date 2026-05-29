import Foundation
import Testing
@testable import PurpleVoice

@Suite("PresetStore CRUD + persistence")
struct PresetStoreTests {

    /// A throwaway UserDefaults suite so tests never touch the real
    /// app defaults or each other.
    private func makeDefaults() -> UserDefaults {
        let name = "PresetStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func sampleUserPreset(_ name: String) -> Preset {
        Preset(id: UUID(), name: name, builtIn: false,
               profile: .medium, enhancementEnabled: true,
               engine: .ffmpegOnly, loudnessTarget: .none,
               deEsserEnabled: false, deClickerEnabled: false,
               preserveStereo: false, dereverbEnabled: false,
               tuning: .inherited)
    }

    @Test("all lists built-ins first, then user presets")
    func ordering() {
        let store = PresetStore(defaults: makeDefaults())
        store.add(sampleUserPreset("Mine"))
        #expect(store.all.count == Preset.builtIns.count + 1)
        #expect(store.all.prefix(Preset.builtIns.count).allSatisfy { $0.builtIn })
        #expect(store.all.last?.name == "Mine")
    }

    @Test("add forces builtIn=false and a fresh id")
    func addSanitizes() {
        let store = PresetStore(defaults: makeDefaults())
        var p = Preset.builtIns[0]   // builtIn == true
        p.name = "Copy of builtin"
        let stored = store.add(p)
        #expect(!stored.builtIn)
        #expect(stored.id != Preset.builtIns[0].id)
        #expect(store.userPresets.count == 1)
    }

    @Test("update replaces a user preset; ignores built-ins and unknowns")
    func update() {
        let store = PresetStore(defaults: makeDefaults())
        let stored = store.add(sampleUserPreset("Editable"))
        var edited = stored
        edited.profile = .aggressive
        store.update(edited)
        #expect(store.preset(id: stored.id)?.profile == .aggressive)

        // Updating a built-in is a no-op (it isn't in userPresets).
        store.update(Preset.builtIns[0])
        #expect(store.userPresets.count == 1)
    }

    @Test("delete and rename")
    func deleteAndRename() {
        let store = PresetStore(defaults: makeDefaults())
        let a = store.add(sampleUserPreset("A"))
        store.rename(id: a.id, to: "A-renamed")
        #expect(store.preset(id: a.id)?.name == "A-renamed")
        store.delete(id: a.id)
        #expect(store.userPresets.isEmpty)
    }

    @Test("duplicate produces a distinctly-named user copy")
    func duplicate() {
        let store = PresetStore(defaults: makeDefaults())
        let dup1 = store.duplicate(Preset.builtIns.first { $0.name == "Podcast" }!)
        #expect(dup1.name == "Podcast copy")
        #expect(!dup1.builtIn)
        let dup2 = store.duplicate(Preset.builtIns.first { $0.name == "Podcast" }!)
        #expect(dup2.name == "Podcast copy 2")
    }

    @Test("preset(named:) is case-insensitive; user wins over same-named built-in")
    func lookupByName() {
        let store = PresetStore(defaults: makeDefaults())
        #expect(store.preset(named: "PODCAST")?.name == "Podcast")
        // Add a user preset shadowing a built-in name.
        var shadow = sampleUserPreset("Podcast")
        shadow.profile = .light
        store.add(shadow)
        #expect(store.preset(named: "podcast")?.profile == .light)
    }

    @Test("user presets persist across store instances")
    func persistence() {
        let defaults = makeDefaults()
        do {
            let store = PresetStore(defaults: defaults)
            store.add(sampleUserPreset("Persisted"))
        }
        let reloaded = PresetStore(defaults: defaults)
        #expect(reloaded.userPresets.count == 1)
        #expect(reloaded.userPresets.first?.name == "Persisted")
    }
}
