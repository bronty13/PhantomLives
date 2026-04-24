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
         autoReconnect: Bool = true) {
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

struct AppSettings: Codable {
    var servers: [ServerProfile] = [ServerProfile(name: "Libera Chat")]
    var addressBook: [AddressEntry] = []
    var savedChannels: [SavedChannel] = []
    var selectedServerID: UUID?
    var playSoundOnWatchHit: Bool = true
    var bounceDockOnWatchHit: Bool = true
    var systemNotificationsOnWatchHit: Bool = true
    var highlightOnOwnNick: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.servers      = try c.decodeIfPresent([ServerProfile].self, forKey: .servers)
            ?? [ServerProfile(name: "Libera Chat")]
        self.addressBook  = try c.decodeIfPresent([AddressEntry].self, forKey: .addressBook) ?? []
        self.savedChannels = try c.decodeIfPresent([SavedChannel].self, forKey: .savedChannels) ?? []
        self.selectedServerID = try c.decodeIfPresent(UUID.self, forKey: .selectedServerID)
        self.playSoundOnWatchHit = try c.decodeIfPresent(Bool.self, forKey: .playSoundOnWatchHit) ?? true
        self.bounceDockOnWatchHit = try c.decodeIfPresent(Bool.self, forKey: .bounceDockOnWatchHit) ?? true
        self.systemNotificationsOnWatchHit = try c.decodeIfPresent(Bool.self, forKey: .systemNotificationsOnWatchHit) ?? true
        self.highlightOnOwnNick = try c.decodeIfPresent(Bool.self, forKey: .highlightOnOwnNick) ?? true
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true)
        let dir = (base ?? fm.temporaryDirectory).appendingPathComponent("PurpleIRC", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
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
}
