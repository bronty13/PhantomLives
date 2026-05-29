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
    @AppStorage("enhancementEnabled")  var enhancementEnabled: Bool = true
    @AppStorage("autoPlayAfterProcess") var autoPlayAfterProcess: Bool = false
    @AppStorage("autoRevealAfterProcess") var autoRevealAfterProcess: Bool = false

    // v0.2: engine + filter additions.
    @AppStorage("processingEngineRaw") private var storedEngineRaw: String = ProcessingEngine.ffmpegOnly.rawValue
    @AppStorage("loudnessTargetRaw")   private var storedLoudnessRaw: String = LoudnessTarget.none.rawValue
    @AppStorage("deEsserEnabled")      var deEsserEnabled: Bool = false
    @AppStorage("deClickerEnabled")    var deClickerEnabled: Bool = false
    @AppStorage("preserveStereo")      var preserveStereo: Bool = false
    @AppStorage("dereverbEnabled")     var dereverbEnabled: Bool = false
    /// Optional override for the `deep-filter` binary. Empty string
    /// means "let DeepFilterNetLocator search the standard paths."
    @AppStorage("deepFilterPathOverride") var deepFilterPathOverride: String = ""

    // v0.3: fine-tune overrides for individual filter parameters.
    // Stored as JSON in a single key — adding new tunables doesn't
    // require new UserDefaults keys or a migration.
    @AppStorage("customTuningEnabled") var customTuningEnabled: Bool = false
    @AppStorage("filterTuningJSON")    private var storedTuningJSON: String = ""

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

    /// Effective tuning for a processing run — `inherited` (all
    /// profile defaults) when the user hasn't opted into custom
    /// tuning, otherwise the persisted overrides.
    var effectiveTuning: FilterTuning {
        customTuningEnabled ? filterTuning : .inherited
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
