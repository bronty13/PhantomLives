import Foundation

enum SASLMechanism: String, Codable, CaseIterable, Identifiable {
    case none = "NONE"
    case plain = "PLAIN"
    case external = "EXTERNAL"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "None"
        case .plain: return "PLAIN (account + password)"
        case .external: return "EXTERNAL (client cert)"
        }
    }
}

struct ServerProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Server"
    var host: String = "irc.libera.chat"
    var port: Int = 6697
    var useTLS: Bool = true
    var nick: String = "purple-user"
    var user: String = "purpleirc"
    var realName: String = "PurpleIRC"
    var password: String = ""
    var autoJoin: String = ""

    // SASL (preferred authentication)
    var saslMechanism: SASLMechanism = .none
    var saslAccount: String = ""   // empty → falls back to nick
    var saslPassword: String = ""  // used for PLAIN

    // NickServ fallback (used when SASL is disabled but this is set)
    var nickServPassword: String = ""

    // Lines sent after registration completes (one per line, may include /commands).
    var performOnConnect: String = ""

    var autoReconnect: Bool = true

    // Proxy (SOCKS5 / HTTP CONNECT). Type .none = connect directly.
    var proxyType: ProxyType = .none
    var proxyHost: String = ""
    var proxyPort: Int = 1080
    var proxyUsername: String = ""
    var proxyPassword: String = ""

    init(id: UUID = UUID(),
         name: String = "New Server",
         host: String = "irc.libera.chat",
         port: Int = 6697,
         useTLS: Bool = true,
         nick: String = "purple-user",
         user: String = "purpleirc",
         realName: String = "PurpleIRC",
         password: String = "",
         autoJoin: String = "",
         saslMechanism: SASLMechanism = .none,
         saslAccount: String = "",
         saslPassword: String = "",
         nickServPassword: String = "",
         performOnConnect: String = "",
         autoReconnect: Bool = true,
         proxyType: ProxyType = .none,
         proxyHost: String = "",
         proxyPort: Int = 1080,
         proxyUsername: String = "",
         proxyPassword: String = "") {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.nick = nick
        self.user = user
        self.realName = realName
        self.password = password
        self.autoJoin = autoJoin
        self.saslMechanism = saslMechanism
        self.saslAccount = saslAccount
        self.saslPassword = saslPassword
        self.nickServPassword = nickServPassword
        self.performOnConnect = performOnConnect
        self.autoReconnect = autoReconnect
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername
        self.proxyPassword = proxyPassword
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id             = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name           = try c.decodeIfPresent(String.self, forKey: .name) ?? "New Server"
        self.host           = try c.decodeIfPresent(String.self, forKey: .host) ?? "irc.libera.chat"
        self.port           = try c.decodeIfPresent(Int.self, forKey: .port) ?? 6697
        self.useTLS         = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
        self.nick           = try c.decodeIfPresent(String.self, forKey: .nick) ?? "purple-user"
        self.user           = try c.decodeIfPresent(String.self, forKey: .user) ?? "purpleirc"
        self.realName       = try c.decodeIfPresent(String.self, forKey: .realName) ?? "PurpleIRC"
        self.password       = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        self.autoJoin       = try c.decodeIfPresent(String.self, forKey: .autoJoin) ?? ""
        self.saslMechanism  = try c.decodeIfPresent(SASLMechanism.self, forKey: .saslMechanism) ?? .none
        self.saslAccount    = try c.decodeIfPresent(String.self, forKey: .saslAccount) ?? ""
        self.saslPassword   = try c.decodeIfPresent(String.self, forKey: .saslPassword) ?? ""
        self.nickServPassword = try c.decodeIfPresent(String.self, forKey: .nickServPassword) ?? ""
        self.performOnConnect = try c.decodeIfPresent(String.self, forKey: .performOnConnect) ?? ""
        self.autoReconnect  = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        self.proxyType      = try c.decodeIfPresent(ProxyType.self, forKey: .proxyType) ?? .none
        self.proxyHost      = try c.decodeIfPresent(String.self, forKey: .proxyHost) ?? ""
        self.proxyPort      = try c.decodeIfPresent(Int.self, forKey: .proxyPort) ?? 1080
        self.proxyUsername  = try c.decodeIfPresent(String.self, forKey: .proxyUsername) ?? ""
        self.proxyPassword  = try c.decodeIfPresent(String.self, forKey: .proxyPassword) ?? ""
    }
}

struct AddressEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var nick: String = ""
    var note: String = ""
    var watch: Bool = true
}

struct SavedChannel: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "#"
    var note: String = ""
    var serverID: UUID? = nil
}

/// A pattern to silently drop incoming PRIVMSG / NOTICE / CTCP from. The mask
/// is matched against the nick and against `nick!user@host` when available.
/// Glob-style `*` and `?` are supported.
struct IgnoreEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var mask: String = ""
    var note: String = ""
    var ignoreCTCP: Bool = true
    var ignoreNotices: Bool = true
}

struct AppSettings: Codable {
    var servers: [ServerProfile] = [ServerProfile(name: "Libera Chat")]
    var addressBook: [AddressEntry] = []
    var savedChannels: [SavedChannel] = []
    var ignoreList: [IgnoreEntry] = []
    var selectedServerID: UUID?

    // Watchlist / highlight alert channels
    var playSoundOnWatchHit: Bool = true
    var bounceDockOnWatchHit: Bool = true
    var systemNotificationsOnWatchHit: Bool = true
    var highlightOnOwnNick: Bool = true

    // Persistent logs
    var enablePersistentLogs: Bool = false
    var logMotdAndNumerics: Bool = false

    // CTCP
    var ctcpRepliesEnabled: Bool = true
    var ctcpVersionString: String = "PurpleIRC — https://github.com/bronty13/PhantomLives"

    // Away
    var autoAwayEnabled: Bool = false
    var autoAwayIdleMinutes: Int = 15
    var awayReasonDefault: String = "away from keyboard"
    var autoReplyWhenAway: Bool = true
    var awayAutoReply: String = "I am currently away (via PurpleIRC). I'll see your message when I return."

    // DCC (file transfers + chat)
    var dccExternalIP: String = ""
    var dccPortRangeStart: Int = 49152
    var dccPortRangeEnd: Int = 49200

    // Sounds + theme
    var soundsEnabled: Bool = true
    /// Map of `SoundEventKind.rawValue` → NSSound name. Empty string = silent.
    var eventSounds: [String: String] = [
        "mention": "Glass",
        "watchlistHit": "Purr",
        "privateMessage": "Ping",
        "connect": "Hero",
        "disconnect": "Basso",
        "ctcp": ""
    ]
    var themeID: String = "classic"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.servers      = try c.decodeIfPresent([ServerProfile].self, forKey: .servers)
            ?? [ServerProfile(name: "Libera Chat")]
        self.addressBook  = try c.decodeIfPresent([AddressEntry].self, forKey: .addressBook) ?? []
        self.savedChannels = try c.decodeIfPresent([SavedChannel].self, forKey: .savedChannels) ?? []
        self.ignoreList   = try c.decodeIfPresent([IgnoreEntry].self, forKey: .ignoreList) ?? []
        self.selectedServerID = try c.decodeIfPresent(UUID.self, forKey: .selectedServerID)
        self.playSoundOnWatchHit = try c.decodeIfPresent(Bool.self, forKey: .playSoundOnWatchHit) ?? true
        self.bounceDockOnWatchHit = try c.decodeIfPresent(Bool.self, forKey: .bounceDockOnWatchHit) ?? true
        self.systemNotificationsOnWatchHit = try c.decodeIfPresent(Bool.self, forKey: .systemNotificationsOnWatchHit) ?? true
        self.highlightOnOwnNick = try c.decodeIfPresent(Bool.self, forKey: .highlightOnOwnNick) ?? true
        self.enablePersistentLogs = try c.decodeIfPresent(Bool.self, forKey: .enablePersistentLogs) ?? false
        self.logMotdAndNumerics = try c.decodeIfPresent(Bool.self, forKey: .logMotdAndNumerics) ?? false
        self.ctcpRepliesEnabled = try c.decodeIfPresent(Bool.self, forKey: .ctcpRepliesEnabled) ?? true
        self.ctcpVersionString = try c.decodeIfPresent(String.self, forKey: .ctcpVersionString)
            ?? "PurpleIRC — https://github.com/bronty13/PhantomLives"
        self.autoAwayEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoAwayEnabled) ?? false
        self.autoAwayIdleMinutes = try c.decodeIfPresent(Int.self, forKey: .autoAwayIdleMinutes) ?? 15
        self.awayReasonDefault = try c.decodeIfPresent(String.self, forKey: .awayReasonDefault) ?? "away from keyboard"
        self.autoReplyWhenAway = try c.decodeIfPresent(Bool.self, forKey: .autoReplyWhenAway) ?? true
        self.awayAutoReply = try c.decodeIfPresent(String.self, forKey: .awayAutoReply)
            ?? "I am currently away (via PurpleIRC). I'll see your message when I return."
        self.dccExternalIP = try c.decodeIfPresent(String.self, forKey: .dccExternalIP) ?? ""
        self.dccPortRangeStart = try c.decodeIfPresent(Int.self, forKey: .dccPortRangeStart) ?? 49152
        self.dccPortRangeEnd = try c.decodeIfPresent(Int.self, forKey: .dccPortRangeEnd) ?? 49200
        self.soundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        self.eventSounds = try c.decodeIfPresent([String: String].self, forKey: .eventSounds)
            ?? [
                "mention": "Glass",
                "watchlistHit": "Purr",
                "privateMessage": "Ping",
                "connect": "Hero",
                "disconnect": "Basso",
                "ctcp": ""
            ]
        self.themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? "classic"
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let fileURL: URL
    let supportDirectoryURL: URL
    let logsDirectoryURL: URL

    init() {
        let fm = FileManager.default
        let base = try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true)
        let dir = (base ?? fm.temporaryDirectory).appendingPathComponent("PurpleIRC", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.supportDirectoryURL = dir
        self.logsDirectoryURL = dir.appendingPathComponent("logs", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }

        if settings.selectedServerID == nil {
            settings.selectedServerID = settings.servers.first?.id
        }
    }

    func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("PurpleIRC: failed to save settings: \(error)")
        }
    }

    var fileURLForDisplay: String { fileURL.path }

    // MARK: - Server helpers

    func selectedServer() -> ServerProfile? {
        guard let id = settings.selectedServerID else { return settings.servers.first }
        return settings.servers.first(where: { $0.id == id }) ?? settings.servers.first
    }

    func upsertServer(_ profile: ServerProfile) {
        if let i = settings.servers.firstIndex(where: { $0.id == profile.id }) {
            settings.servers[i] = profile
        } else {
            settings.servers.append(profile)
        }
    }

    func removeServer(id: UUID) {
        settings.servers.removeAll { $0.id == id }
        if settings.selectedServerID == id {
            settings.selectedServerID = settings.servers.first?.id
        }
    }

    // MARK: - Address book

    func upsertAddress(_ entry: AddressEntry) {
        if let i = settings.addressBook.firstIndex(where: { $0.id == entry.id }) {
            settings.addressBook[i] = entry
        } else {
            settings.addressBook.append(entry)
        }
    }

    func removeAddress(id: UUID) {
        settings.addressBook.removeAll { $0.id == id }
    }

    var watchedFromAddressBook: [String] {
        settings.addressBook.filter { $0.watch }.map { $0.nick }.filter { !$0.isEmpty }
    }

    // MARK: - Channels

    func upsertChannel(_ ch: SavedChannel) {
        if let i = settings.savedChannels.firstIndex(where: { $0.id == ch.id }) {
            settings.savedChannels[i] = ch
        } else {
            settings.savedChannels.append(ch)
        }
    }

    func removeChannel(id: UUID) {
        settings.savedChannels.removeAll { $0.id == id }
    }

    // MARK: - Ignore list

    func upsertIgnore(_ entry: IgnoreEntry) {
        if let i = settings.ignoreList.firstIndex(where: { $0.id == entry.id }) {
            settings.ignoreList[i] = entry
        } else {
            settings.ignoreList.append(entry)
        }
    }

    func removeIgnore(id: UUID) {
        settings.ignoreList.removeAll { $0.id == id }
    }
}
