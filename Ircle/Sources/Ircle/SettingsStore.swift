import Foundation
import IRCKit

/// A saved server connection, the persisted shape of what becomes an
/// `IRCConnectionConfig` at connect time. (Passwords live here for the MVP;
/// a Keychain move is a later hardening step — see README.)
struct ServerProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "Libera.Chat"
    var host: String = "irc.libera.chat"
    var port: Int = 6697
    var useTLS: Bool = true
    var nick: String = "ircle-user"
    var user: String = "ircle"
    var realName: String = "Ircle for Mac"
    var serverPassword: String = ""
    var saslMechanism: SASLMechanism = .none
    var saslAccount: String = ""
    var saslPassword: String = ""
    /// Channels to auto-join after registration.
    var autoJoin: [String] = ["#ircle"]

    func makeConfig() -> IRCConnectionConfig {
        IRCConnectionConfig(
            host: host,
            port: UInt16(clamping: port),
            useTLS: useTLS,
            nick: nick,
            user: user.isEmpty ? "ircle" : user,
            realName: realName.isEmpty ? nick : realName,
            serverPassword: serverPassword.isEmpty ? nil : serverPassword,
            saslMechanism: saslMechanism,
            saslAccount: saslAccount,
            saslPassword: saslPassword
        )
    }
}

/// Platinum-era nostalgia toggle. "Modern comfort" means we also offer a dark
/// variant; the default is the classic light grey Platinum look.
enum IrcleAppearance: String, Codable, CaseIterable, Identifiable {
    case platinum   // classic Mac OS 8/9 light grey
    case graphite   // dark variant (modern comfort)
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .platinum: return "Platinum (classic)"
        case .graphite: return "Graphite (dark)"
        }
    }
}

/// The full persisted settings document.
struct AppSettings: Codable {
    var servers: [ServerProfile] = [ServerProfile()]
    var appearance: IrcleAppearance = .platinum
    var showTimestamps: Bool = true
    var fontSize: Double = 12

    // Auto-backup-on-launch (repo standard field names; see BackupService).
    var autoBackupEnabled: Bool = true
    /// Override for the backup directory; empty = the convention path.
    var backupPath: String = ""
    /// 0 = keep forever.
    var backupRetentionDays: Int = 14
    /// ISO-ish timestamp of the last successful backup; "" = never.
    var lastBackupAt: String = ""

    enum CodingKeys: String, CodingKey {
        case servers, appearance, showTimestamps, fontSize
        case autoBackupEnabled, backupPath, backupRetentionDays, lastBackupAt
    }

    init() {}

    // Tolerate older/partial documents: every field defaults if absent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        servers = (try? c.decode([ServerProfile].self, forKey: .servers)) ?? [ServerProfile()]
        appearance = (try? c.decode(IrcleAppearance.self, forKey: .appearance)) ?? .platinum
        showTimestamps = (try? c.decode(Bool.self, forKey: .showTimestamps)) ?? true
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? 12
        autoBackupEnabled = (try? c.decode(Bool.self, forKey: .autoBackupEnabled)) ?? true
        backupPath = (try? c.decode(String.self, forKey: .backupPath)) ?? ""
        backupRetentionDays = (try? c.decode(Int.self, forKey: .backupRetentionDays)) ?? 14
        lastBackupAt = (try? c.decode(String.self, forKey: .lastBackupAt)) ?? ""
    }
}

/// Observable persistence layer. Reads/writes a single JSON document under
/// Application Support; never throws on the hot path.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    static let appName = "Ircle"

    /// Per repo standard: caches/config live under Application Support.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    /// Per repo standard: user-visible output (logs, DCC) defaults here.
    static var downloadsDirectory: URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    /// Convention backup directory: `~/Downloads/Ircle backup/`.
    static var defaultBackupDirectory: URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("\(appName) backup", isDirectory: true)
    }

    /// Resolved backup directory honoring the user's override.
    var resolvedBackupPath: URL {
        let override = settings.backupPath.trimmingCharacters(in: .whitespaces)
        if override.isEmpty { return Self.defaultBackupDirectory }
        return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The directory this store reads/writes `settings.json` in. Defaults to
    /// Application Support; tests pass a temp dir so they never touch the real
    /// user settings.
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("settings.json") }

    init(directory: URL? = nil) {
        let dir = directory ?? Self.supportDirectory
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    /// Public so BackupService can persist `lastBackupAt` after a run.
    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
