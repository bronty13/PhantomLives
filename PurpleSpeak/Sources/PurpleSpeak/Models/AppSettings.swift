import Foundation

/// User-tunable settings, persisted as JSON in
/// ~/Library/Application Support/PurpleSpeak/settings.json.
struct AppSettings: Codable, Equatable {
    // Playback
    var defaultVoiceIdentifier: String?          // AVSpeechSynthesisVoice.identifier
    var speechRateMultiplier: Double = 1.0       // 0.5…4.0, 1.0 = system default
    var speechPitch: Double = 1.0                // 0.5…2.0
    var highlightSentence: Bool = true           // highlight the whole sentence too

    // Reading comfort
    var readerFontSize: Double = 19.0
    var readerLineSpacing: Double = 6.0
    var lineFocusEnabled: Bool = false

    // Output
    var outputDirectory: String = "~/Downloads/PurpleSpeak"
    var preferredAudioFormat: String = "m4a"     // "m4a" | "mp3"

    // Transcription
    var sttEngine: String = "whispercpp"         // "whispercpp" | "mlx"
    var whisperModel: String = "ggml-large-v3-turbo.bin"
    var transcriptionLanguage: String = "auto"

    // Backup (PhantomLives auto-backup-on-launch standard)
    var autoBackupEnabled: Bool = true
    var backupDirectory: String = "~/Downloads/PurpleSpeak backup"
    var backupRetentionDays: Int = 14
    var lastBackupAt: String?                     // ISO-8601
}

/// Loads/saves `AppSettings` and exposes resolved (tilde-expanded) URLs.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { save() } }
    }

    init() {
        if let data = try? Data(contentsOf: SupportPaths.settingsFile),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: SupportPaths.settingsFile, options: .atomic)
    }

    /// Resolved output directory, created on demand.
    var resolvedOutputPath: URL {
        let url = SupportPaths.expand(settings.outputDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Resolved backup directory (NOT auto-created here — BackupService does it).
    var resolvedBackupPath: URL {
        SupportPaths.expand(settings.backupDirectory)
    }
}
