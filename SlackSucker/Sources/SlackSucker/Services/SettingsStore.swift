import Foundation
import Combine

/// Structured user settings persisted to `settings.json`. The simple
/// primitive-typed settings (theme, debug, backup config) ride on top of
/// `@AppStorage`/`UserDefaults` via `BackupService.BackupKeys` and the
/// `theme` / `debugLogging` keys below — JSON here is for state that is
/// either nested (default archive options) or wants to round-trip cleanly
/// across machines via the launch-time backup standard.
@MainActor
final class SettingsStore: ObservableObject {

    @Published var defaultArchiveOptions: ArchiveOptions
    @Published var selectedWorkspace: String?
    @Published var outputDirOverride: String?

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL = AppSupport.settingsURL) {
        self.url = url
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let loaded = Self.loadOrDefault(url: url, decoder: dec)
        self.defaultArchiveOptions = loaded.defaultArchiveOptions
        self.selectedWorkspace     = loaded.selectedWorkspace
        self.outputDirOverride     = loaded.outputDirOverride
    }

    /// User-visible output root. Honors override; otherwise the
    /// PhantomLives-standard `~/Downloads/SlackSucker/`.
    var resolvedOutputDir: URL {
        if let raw = outputDirOverride, !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return AppSupport.defaultOutputDir
    }

    func save() {
        let snapshot = Snapshot(
            defaultArchiveOptions: defaultArchiveOptions,
            selectedWorkspace: selectedWorkspace,
            outputDirOverride: outputDirOverride
        )
        do {
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("SlackSucker: settings save failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence shape

    /// On-disk representation. Kept private so callers can't reach in
    /// past the @Published properties.
    private struct Snapshot: Codable {
        var defaultArchiveOptions: ArchiveOptions
        var selectedWorkspace: String?
        var outputDirOverride: String?
    }

    private static func loadOrDefault(url: URL, decoder: JSONDecoder) -> Snapshot {
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let snap = try? decoder.decode(Snapshot.self, from: data)
        else {
            return Snapshot(defaultArchiveOptions: .default,
                            selectedWorkspace: nil,
                            outputDirOverride: nil)
        }
        return snap
    }
}

/// The toggles a user wants applied by default when starting a new
/// archive. Per-run UI can still override on a single invocation.
///
/// `organizeFiles` runs the `FileOrganizer` post-processing pass after
/// slackdump exits — sorting `__uploads/<ID>/<name>` into
/// `Videos/`, `Photos/`, `Audio/`, `Other/` subfolders at the run-
/// folder root. Off = leave slackdump's native layout in place
/// (compatible with `slackdump view`).
struct ArchiveOptions: Codable, Equatable {
    var includeFiles: Bool
    var includeAvatars: Bool
    var memberOnly: Bool
    var organizeFiles: Bool

    static let `default` = ArchiveOptions(
        includeFiles: true,
        includeAvatars: false,
        memberOnly: false,
        organizeFiles: true
    )

    /// Tolerate older settings.json files that pre-date the
    /// `organizeFiles` field — decode it as `true` when absent so the
    /// new behavior is the default after upgrading.
    init(includeFiles: Bool, includeAvatars: Bool, memberOnly: Bool, organizeFiles: Bool) {
        self.includeFiles = includeFiles
        self.includeAvatars = includeAvatars
        self.memberOnly = memberOnly
        self.organizeFiles = organizeFiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.includeFiles   = try c.decode(Bool.self, forKey: .includeFiles)
        self.includeAvatars = try c.decode(Bool.self, forKey: .includeAvatars)
        self.memberOnly     = try c.decode(Bool.self, forKey: .memberOnly)
        self.organizeFiles  = try c.decodeIfPresent(Bool.self, forKey: .organizeFiles) ?? true
    }
}
