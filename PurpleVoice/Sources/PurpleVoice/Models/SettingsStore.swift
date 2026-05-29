import Foundation
import SwiftUI

/// User-facing knobs persisted via UserDefaults. Tiny surface area —
/// output directory, format, profile, enhancement toggle, auto-play.
/// Anything more advanced (custom filter strings, per-clip overrides)
/// is a future-version concern.
final class SettingsStore: ObservableObject {

    @AppStorage("outputDirectoryPath") private var storedOutputPath: String = ""
    @AppStorage("outputFormatRaw")     private var storedFormatRaw: String = OutputFormat.m4a.rawValue
    @AppStorage("processingProfileRaw") private var storedProfileRaw: String = ProcessingProfile.medium.rawValue

    // v0.2: engine + filter additions.
    @AppStorage("processingEngineRaw") private var storedEngineRaw: String = ProcessingEngine.ffmpegOnly.rawValue
    @AppStorage("loudnessTargetRaw")   private var storedLoudnessRaw: String = LoudnessTarget.none.rawValue

    // v0.3: fine-tune overrides for individual filter parameters.
    // Stored as JSON in a single key — adding new tunables doesn't
    // require new UserDefaults keys or a migration. As of v0.4 the
    // knobs are always-live (no master gate): a nil field inherits the
    // profile default, a set field overrides it.
    @AppStorage("filterTuningJSON")    private var storedTuningJSON: String = ""

    // Toggles + path/preset state. These are computed wrappers over a
    // private `@AppStorage` so their setters can fire `objectWillChange`
    // — `@AppStorage` inside an `ObservableObject` doesn't publish on
    // its own, and dependent views (e.g. a knob whose enabled-state
    // tracks `deEsserEnabled`) must re-render when these flip.
    @AppStorage("enhancementEnabled")     private var storedEnhancement: Bool = true
    @AppStorage("autoPlayAfterProcess")   private var storedAutoPlay: Bool = false
    @AppStorage("autoRevealAfterProcess") private var storedAutoReveal: Bool = false
    @AppStorage("deEsserEnabled")         private var storedDeEsser: Bool = false
    @AppStorage("deClickerEnabled")       private var storedDeClicker: Bool = false
    @AppStorage("preserveStereo")         private var storedPreserveStereo: Bool = false
    @AppStorage("dereverbEnabled")        private var storedDereverb: Bool = false
    @AppStorage("deepFilterPathOverride") private var storedDeepFilterPath: String = ""
    // v0.4: which preset is currently applied (empty = none / custom).
    // Drives the preset bar's title + the "(Modified)" indicator.
    @AppStorage("activePresetID")         private var storedActivePresetID: String = ""

    var enhancementEnabled: Bool {
        get { storedEnhancement }
        set { storedEnhancement = newValue; objectWillChange.send() }
    }
    var autoPlayAfterProcess: Bool {
        get { storedAutoPlay }
        set { storedAutoPlay = newValue; objectWillChange.send() }
    }
    var autoRevealAfterProcess: Bool {
        get { storedAutoReveal }
        set { storedAutoReveal = newValue; objectWillChange.send() }
    }
    var deEsserEnabled: Bool {
        get { storedDeEsser }
        set { storedDeEsser = newValue; objectWillChange.send() }
    }
    var deClickerEnabled: Bool {
        get { storedDeClicker }
        set { storedDeClicker = newValue; objectWillChange.send() }
    }
    var preserveStereo: Bool {
        get { storedPreserveStereo }
        set { storedPreserveStereo = newValue; objectWillChange.send() }
    }
    var dereverbEnabled: Bool {
        get { storedDereverb }
        set { storedDereverb = newValue; objectWillChange.send() }
    }
    /// Optional override for the `deep-filter` binary. Empty string
    /// means "let DeepFilterNetLocator search the standard paths."
    var deepFilterPathOverride: String {
        get { storedDeepFilterPath }
        set { storedDeepFilterPath = newValue; objectWillChange.send() }
    }
    var activePresetIDRaw: String {
        get { storedActivePresetID }
        set { storedActivePresetID = newValue; objectWillChange.send() }
    }

    var outputDirectory: URL {
        get {
            if !storedOutputPath.isEmpty {
                return URL(fileURLWithPath: storedOutputPath)
            }
            return SettingsStore.defaultOutputDirectory
        }
        set {
            storedOutputPath = newValue.path
            objectWillChange.send()
        }
    }

    var outputFormat: OutputFormat {
        get { OutputFormat(rawValue: storedFormatRaw) ?? .m4a }
        set {
            storedFormatRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var profile: ProcessingProfile {
        get { ProcessingProfile(rawValue: storedProfileRaw) ?? .medium }
        set {
            storedProfileRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var processingEngine: ProcessingEngine {
        get { ProcessingEngine(rawValue: storedEngineRaw) ?? .ffmpegOnly }
        set {
            storedEngineRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var loudnessTarget: LoudnessTarget {
        get { LoudnessTarget(rawValue: storedLoudnessRaw) ?? .none }
        set {
            storedLoudnessRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    /// Custom per-filter overrides. Decoded lazily from the JSON
    /// store; encoded back on every set. Any decode failure (corrupt
    /// JSON, etc.) silently falls back to `inherited` rather than
    /// blocking the app on a settings issue.
    var filterTuning: FilterTuning {
        get {
            guard !storedTuningJSON.isEmpty,
                  let data = storedTuningJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(FilterTuning.self, from: data)
            else { return .inherited }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                storedTuningJSON = json
            } else {
                storedTuningJSON = ""
            }
            objectWillChange.send()
        }
    }

    /// Effective tuning for a processing run. The knobs are always
    /// live as of v0.4, so this is just the persisted overrides — any
    /// nil field still inherits the profile default inside
    /// `FilterChainBuilder`. Kept as a named accessor so call sites
    /// (the queue) read intent rather than reaching for the raw store.
    var effectiveTuning: FilterTuning { filterTuning }

    // MARK: - Presets

    /// The current live settings expressed as a `Preset`. Used to save
    /// a new preset and to compare against the applied one. `builtIn`
    /// is false and `name` is a placeholder — callers set the real
    /// name when saving.
    var liveSnapshot: Preset {
        Preset(id: UUID(),
               name: "Custom",
               builtIn: false,
               profile: profile,
               enhancementEnabled: enhancementEnabled,
               engine: processingEngine,
               loudnessTarget: loudnessTarget,
               deEsserEnabled: deEsserEnabled,
               deClickerEnabled: deClickerEnabled,
               preserveStereo: preserveStereo,
               dereverbEnabled: dereverbEnabled,
               tuning: filterTuning)
    }

    /// Write every sound-affecting field from `preset` into the live
    /// settings and remember it as the active preset.
    func apply(_ preset: Preset) {
        profile = preset.profile
        enhancementEnabled = preset.enhancementEnabled
        processingEngine = preset.engine
        loudnessTarget = preset.loudnessTarget
        deEsserEnabled = preset.deEsserEnabled
        deClickerEnabled = preset.deClickerEnabled
        preserveStereo = preset.preserveStereo
        dereverbEnabled = preset.dereverbEnabled
        filterTuning = preset.tuning
        activePresetIDRaw = preset.id.uuidString
    }

    /// True when the live settings still equal `preset`'s settings —
    /// i.e. the user hasn't tweaked anything since applying it.
    func matchesLive(_ preset: Preset) -> Bool {
        preset.hasSameSettings(as: liveSnapshot)
    }

    /// Per CLAUDE.md: every PhantomLives tool that writes user-visible
    /// output defaults to `~/Downloads/<project-name>/`.
    static var defaultOutputDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Downloads/PurpleVoice", isDirectory: true)
    }

    /// Resolve where this run should write its output. Honors the user's
    /// chosen output directory; creates it lazily; suffixes the source
    /// stem with `_clean` and the chosen extension. Avoids collisions
    /// with previous runs by appending `_N` when needed.
    func resolveOutputURL(for sourceURL: URL,
                          fileManager: FileManager = .default) throws -> URL {
        let dir = outputDirectory
        try fileManager.createDirectory(at: dir,
                                        withIntermediateDirectories: true)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = outputFormat.fileExtension
        var candidate = dir.appendingPathComponent("\(stem)_clean.\(ext)")
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)_clean_\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
