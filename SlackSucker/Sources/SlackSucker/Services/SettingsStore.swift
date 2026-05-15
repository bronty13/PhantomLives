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
    /// Generate per-file checksums (md5/sha1/sha256) at run-folder
    /// root → `hashes.txt`. Algorithms selected by `hashAlgorithms`.
    var generateHashes: Bool
    var hashAlgorithms: Set<HashAlgorithm>
    /// Run `transcribe.py` against every file in Videos/ and Audio/
    /// after archive completes; emit `<name>.txt` next to the source.
    var transcribeMedia: Bool
    var transcribeModel: TranscriptionModel
    /// Strip EXIF / IPTC / XMP metadata from Photos/ via `exiftool`.
    /// Destructive in-place; the slackdump SQLite still has originals.
    var stripPhotoMetadata: Bool
    /// Bake EXIF Orientation tag into pixel data for photos (sips) and
    /// flatten rotation matrix for videos (ffmpeg) so the file looks
    /// the same after metadata strip / re-import / web-share. Runs
    /// *before* stripPhotoMetadata so the orientation isn't lost.
    var bakeOrientation: Bool

    static let `default` = ArchiveOptions(
        includeFiles: true,
        includeAvatars: false,
        memberOnly: false,
        organizeFiles: true,
        generateHashes: false,
        hashAlgorithms: [.sha256],
        transcribeMedia: false,
        transcribeModel: .turbo,
        stripPhotoMetadata: false,
        bakeOrientation: false
    )

    /// Tolerate older settings.json files that pre-date the newer
    /// fields — decode each post-1.0.0 field with a sensible default
    /// when absent so upgrades don't strand previously-saved configs.
    init(includeFiles: Bool, includeAvatars: Bool, memberOnly: Bool, organizeFiles: Bool,
         generateHashes: Bool = false,
         hashAlgorithms: Set<HashAlgorithm> = [.sha256],
         transcribeMedia: Bool = false,
         transcribeModel: TranscriptionModel = .turbo,
         stripPhotoMetadata: Bool = false,
         bakeOrientation: Bool = false) {
        self.includeFiles = includeFiles
        self.includeAvatars = includeAvatars
        self.memberOnly = memberOnly
        self.organizeFiles = organizeFiles
        self.generateHashes = generateHashes
        self.hashAlgorithms = hashAlgorithms
        self.transcribeMedia = transcribeMedia
        self.transcribeModel = transcribeModel
        self.stripPhotoMetadata = stripPhotoMetadata
        self.bakeOrientation = bakeOrientation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.includeFiles      = try c.decode(Bool.self, forKey: .includeFiles)
        self.includeAvatars    = try c.decode(Bool.self, forKey: .includeAvatars)
        self.memberOnly        = try c.decode(Bool.self, forKey: .memberOnly)
        self.organizeFiles     = try c.decodeIfPresent(Bool.self, forKey: .organizeFiles) ?? true
        self.generateHashes    = try c.decodeIfPresent(Bool.self, forKey: .generateHashes) ?? false
        self.hashAlgorithms    = try c.decodeIfPresent(Set<HashAlgorithm>.self, forKey: .hashAlgorithms) ?? [.sha256]
        self.transcribeMedia   = try c.decodeIfPresent(Bool.self, forKey: .transcribeMedia) ?? false
        self.transcribeModel   = try c.decodeIfPresent(TranscriptionModel.self, forKey: .transcribeModel) ?? .turbo
        self.stripPhotoMetadata = try c.decodeIfPresent(Bool.self, forKey: .stripPhotoMetadata) ?? false
        self.bakeOrientation   = try c.decodeIfPresent(Bool.self, forKey: .bakeOrientation) ?? false
    }
}

/// Which checksum algorithms the user wants emitted into `hashes.txt`.
/// Multiple may be selected; each shows up as its own column block in
/// the output. SHA-256 is the most common modern choice; MD5 + SHA-1
/// are still useful for cross-referencing against legacy archives.
enum HashAlgorithm: String, Codable, CaseIterable, Identifiable {
    case md5, sha1, sha256
    var id: String { rawValue }
    var label: String {
        switch self {
        case .md5:    return "MD5"
        case .sha1:   return "SHA-1"
        case .sha256: return "SHA-256"
        }
    }
}

/// Whisper model preset for the transcription post-processor. Mirrors
/// the same set messages-exporter-gui exposes, so a user with both
/// apps installed sees a consistent vocabulary.
enum TranscriptionModel: String, Codable, CaseIterable, Identifiable {
    case tiny, base, small, medium, large, turbo
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tiny:   return "tiny — fastest, lowest quality"
        case .base:   return "base — fast, acceptable"
        case .small:  return "small — balanced"
        case .medium: return "medium — high quality"
        case .large:  return "large — best quality, slowest"
        case .turbo:  return "turbo — near-large at 8x speed (default)"
        }
    }
}
