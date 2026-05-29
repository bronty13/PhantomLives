import Foundation

/// A named, recallable bundle of processing settings — the "sound" you
/// want to apply to a clip. A preset captures everything that affects
/// the *audio character* (profile, engine, enhancement, loudness, the
/// cleanup toggles, and the per-filter `FilterTuning` overrides). It
/// deliberately does NOT capture the output *format* or output folder —
/// those are output preferences that live in `SettingsStore` and stay
/// constant as the user auditions different presets.
///
/// Built-in presets (`builtIns`) ship with the app and are defined in
/// code with stable hardcoded UUIDs, so the persisted "active preset"
/// selection survives relaunches and app updates without a migration.
/// User presets are created/edited at runtime and persisted by
/// `PresetStore` as a single JSON blob in UserDefaults.
struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// True for the code-defined presets below; false for user-saved
    /// ones. Built-ins can't be renamed or deleted (only duplicated).
    var builtIn: Bool

    var profile: ProcessingProfile
    var enhancementEnabled: Bool
    var engine: ProcessingEngine
    var loudnessTarget: LoudnessTarget
    var deEsserEnabled: Bool
    var deClickerEnabled: Bool
    var preserveStereo: Bool
    var dereverbEnabled: Bool
    var tuning: FilterTuning

    /// Equality over everything that affects the sound, ignoring
    /// identity (`id`/`name`/`builtIn`). Used to decide whether the
    /// live settings still match the applied preset (the "(Modified)"
    /// indicator) and to dedupe.
    func hasSameSettings(as other: Preset) -> Bool {
        profile == other.profile
            && enhancementEnabled == other.enhancementEnabled
            && engine == other.engine
            && loudnessTarget == other.loudnessTarget
            && deEsserEnabled == other.deEsserEnabled
            && deClickerEnabled == other.deClickerEnabled
            && preserveStereo == other.preserveStereo
            && dereverbEnabled == other.dereverbEnabled
            && tuning == other.tuning
    }
}

extension Preset {

    /// Convenience builder so the built-in table below reads cleanly.
    /// Everything past `profile` has a sensible default matching the
    /// app's out-of-the-box behavior.
    static func builtIn(_ idString: String,
                        _ name: String,
                        profile: ProcessingProfile,
                        enhancement: Bool = true,
                        engine: ProcessingEngine = .ffmpegOnly,
                        loudness: LoudnessTarget = .none,
                        deEsser: Bool = false,
                        deClicker: Bool = false,
                        stereo: Bool = false,
                        dereverb: Bool = false,
                        tuning: FilterTuning = .inherited) -> Preset {
        Preset(id: UUID(uuidString: idString)!,
               name: name,
               builtIn: true,
               profile: profile,
               enhancementEnabled: enhancement,
               engine: engine,
               loudnessTarget: loudness,
               deEsserEnabled: deEsser,
               deClickerEnabled: deClicker,
               preserveStereo: stereo,
               dereverbEnabled: dereverb,
               tuning: tuning)
    }

    /// The factory presets, in display order. The first entry is the
    /// app's default sound. UUIDs are fixed (and must stay fixed) so a
    /// persisted `activePresetID` keeps resolving across launches.
    static let builtIns: [Preset] = [
        builtIn("00000000-0000-0000-0000-0000000000A1",
                "Voice Memo Cleanup",
                profile: .medium),

        builtIn("00000000-0000-0000-0000-0000000000A2",
                "Podcast",
                profile: .medium,
                loudness: .podcast,
                deEsser: true),

        builtIn("00000000-0000-0000-0000-0000000000A3",
                "Interview / Remote Call",
                profile: .aggressive,
                loudness: .podcast,
                deEsser: true),

        builtIn("00000000-0000-0000-0000-0000000000A4",
                "Lecture / Meeting",
                profile: .medium,
                loudness: .streaming,
                deClicker: true),

        builtIn("00000000-0000-0000-0000-0000000000A5",
                "Audiobook / Narration",
                profile: .medium,
                loudness: .streaming,
                deEsser: true,
                tuning: {
                    var t = FilterTuning.inherited
                    t.compressorThresholdDB = -20
                    t.compressorRatio = 4
                    return t
                }()),

        builtIn("00000000-0000-0000-0000-0000000000A6",
                "Field Recording",
                profile: .light,
                enhancement: false,
                stereo: true),

        builtIn("00000000-0000-0000-0000-0000000000A7",
                "Phone / Voicemail Rescue",
                profile: .aggressive,
                tuning: {
                    var t = FilterTuning.inherited
                    t.highpassHz = 120
                    return t
                }()),

        builtIn("00000000-0000-0000-0000-0000000000A8",
                "Max Denoise (Neural)",
                profile: .medium,
                engine: .deepFilterNet,
                loudness: .podcast,
                dereverb: true),
    ]

    /// The default sound a fresh install lands on.
    static var defaultBuiltIn: Preset { builtIns[0] }
}
