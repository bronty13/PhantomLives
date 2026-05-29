import Foundation
import Testing
@testable import PurpleVoice

@Suite("Preset model + built-ins")
struct PresetTests {

    @Test("Built-ins are present and well-formed")
    func builtInsWellFormed() {
        #expect(Preset.builtIns.count >= 8)
        // Every built-in is flagged as such, has a non-empty name.
        for p in Preset.builtIns {
            #expect(p.builtIn)
            #expect(!p.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("Built-in names and IDs are unique")
    func builtInsUnique() {
        let names = Preset.builtIns.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count, "built-in names must be unique")
        let ids = Preset.builtIns.map { $0.id }
        #expect(Set(ids).count == ids.count, "built-in IDs must be unique")
    }

    @Test("Preset round-trips through JSON")
    func jsonRoundTrip() throws {
        var t = FilterTuning.inherited
        t.compressorRatio = 4
        let original = Preset(id: UUID(),
                              name: "Test",
                              builtIn: false,
                              profile: .aggressive,
                              enhancementEnabled: false,
                              engine: .deepFilterNet,
                              loudnessTarget: .streaming,
                              deEsserEnabled: true,
                              deClickerEnabled: true,
                              preserveStereo: true,
                              dereverbEnabled: true,
                              tuning: t)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        #expect(decoded == original)
    }

    @Test("hasSameSettings ignores identity but tracks every sound field")
    func hasSameSettingsSemantics() {
        let a = Preset.builtIns[0]
        // Same settings, different identity → equal-by-settings.
        var b = a
        b.id = UUID()
        b.name = "Renamed"
        b.builtIn = false
        #expect(a.hasSameSettings(as: b))
        // Flip a single sound field → no longer equal.
        b.deClickerEnabled.toggle()
        #expect(!a.hasSameSettings(as: b))
    }

    @MainActor
    @Test("SettingsStore.apply writes every field; matchesLive flips on edit")
    func applyAndMatch() {
        let settings = SettingsStore()
        let preset = Preset.builtIns.first { $0.name == "Podcast" }!

        settings.apply(preset)
        #expect(settings.profile == preset.profile)
        #expect(settings.enhancementEnabled == preset.enhancementEnabled)
        #expect(settings.processingEngine == preset.engine)
        #expect(settings.loudnessTarget == preset.loudnessTarget)
        #expect(settings.deEsserEnabled == preset.deEsserEnabled)
        #expect(settings.deClickerEnabled == preset.deClickerEnabled)
        #expect(settings.preserveStereo == preset.preserveStereo)
        #expect(settings.dereverbEnabled == preset.dereverbEnabled)
        #expect(settings.filterTuning == preset.tuning)
        #expect(settings.activePresetIDRaw == preset.id.uuidString)
        #expect(settings.matchesLive(preset))

        // Touch one knob → modified.
        var t = settings.filterTuning
        t.limiterCeiling = 0.8
        settings.filterTuning = t
        #expect(!settings.matchesLive(preset))
    }
}
