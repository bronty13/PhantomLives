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

/// A named set of identifying fields (nick/user/realName/SASL/NickServ) that
/// can be shared across server profiles. Editing one identity updates every
/// server profile that references it; users can flip between personas quickly
/// via the Identity toolbar menu or /identity command.
struct Identity: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New identity"
    var nick: String = ""
    var user: String = ""
    var realName: String = ""
    var saslMechanism: SASLMechanism = .none
    var saslAccount: String = ""
    var saslPassword: String = ""
    var nickServPassword: String = ""
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

    /// Optional link to a global Identity. When non-nil at connect time, the
    /// identity's nick/user/realName/SASL/NickServ fields override whatever's
    /// stored inline on this profile.
    var identityID: UUID? = nil

    /// Optional per-network theme override. When non-nil and the id
    /// resolves (built-in or user theme), `ChatModel.theme` returns
    /// this instead of `settings.themeID` for buffers belonging to
    /// connections of this profile. Empty / unresolvable ids fall
    /// back to the global theme silently.
    var themeOverrideID: String? = nil

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

    /// `servers` sorted by display name, case-insensitive ascending. Used for
    /// every list/picker so the on-disk order doesn't affect what the user sees.
    static func sortedByName(_ list: [ServerProfile]) -> [ServerProfile] {
        list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Well-known public IRC networks, pre-populated on first launch so users
    /// don't have to hunt down hostnames. All entries default to TLS/6697
    /// unless the network historically doesn't offer it on that port.
    static func defaultServers() -> [ServerProfile] {
        func make(_ name: String, _ host: String, port: Int = 6697, tls: Bool = true) -> ServerProfile {
            ServerProfile(name: name, host: host, port: port, useTLS: tls)
        }
        // Older networks (Undernet, EFnet, IRCnet) don't reliably offer TLS
        // on 6697 across all hubs, so they default to plaintext 6667 — the
        // value that actually connects out of the box. Users can enable TLS
        // in Setup if the hub they pick supports it.
        return [
            make("Libera Chat",  "irc.libera.chat"),
            make("OFTC",         "irc.oftc.net"),
            make("EFnet",        "irc.efnet.org",    port: 6667, tls: false),
            make("Undernet",     "irc.undernet.org", port: 6667, tls: false),
            make("DALnet",       "irc.dal.net"),
            make("IRCnet",       "open.ircnet.net",  port: 6667, tls: false),
            make("QuakeNet",     "irc.quakenet.org", port: 6667, tls: false),
            make("Rizon",        "irc.rizon.net"),
            make("EsperNet",     "irc.esper.net"),
            make("SwiftIRC",     "irc.swiftirc.net"),
            make("GameSurge",    "irc.gamesurge.net", port: 6667, tls: false),
            make("GeekShed",     "irc.geekshed.net"),
            make("Snoonet",      "irc.snoonet.org"),
            make("Hackint",      "irc.hackint.org"),
            make("freenode",     "irc.freenode.net"),
            make("2600net",      "irc.2600.net"),
            make("AfterNET",     "irc.afternet.org"),
            make("SorceryNet",   "irc.sorcery.net",  port: 9999),
        ]
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
        self.identityID     = try c.decodeIfPresent(UUID.self, forKey: .identityID)
        self.themeOverrideID = try c.decodeIfPresent(String.self, forKey: .themeOverrideID)
    }

    /// Returns a copy of this profile with `identity`'s fields layered on top
    /// (nick/user/realName/SASL/NickServ). Used at connect time so the
    /// connection sees the effective identity values without mutating the
    /// user-edited profile stored in settings.
    func applyingIdentity(_ identity: Identity?) -> ServerProfile {
        guard let identity else { return self }
        var out = self
        if !identity.nick.isEmpty { out.nick = identity.nick }
        if !identity.user.isEmpty { out.user = identity.user }
        if !identity.realName.isEmpty { out.realName = identity.realName }
        out.saslMechanism = identity.saslMechanism
        out.saslAccount = identity.saslAccount
        out.saslPassword = identity.saslPassword
        out.nickServPassword = identity.nickServPassword
        return out
    }
}

struct AddressEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var nick: String = ""
    /// Short one-liner shown next to the nick in the sidebar / list views.
    /// Kept terse on purpose — anything longer belongs in `richNotes`.
    var note: String = ""
    var watch: Bool = true
    /// Free-form Markdown notes. Rendered with `AttributedString(markdown:)`
    /// in the address-book editor's preview pane, so users can keep
    /// formatted context (bullet lists, links, emphasis) per-contact.
    /// Lives inside `settings.json` and therefore inherits the encrypted
    /// envelope when the keystore is unlocked.
    var richNotes: String = ""
    /// Optional profile photo, stored inline as JPEG/PNG bytes after
    /// being downscaled to ≤ 256×256 by `PhotoUtilities.downscaleAndEncode`
    /// on import so settings.json doesn't bloat. nil = no photo;
    /// the UI falls back to a tinted-circle avatar with the nick's
    /// first character. Encoded as base64 by JSONEncoder.
    var photoData: Data? = nil

    init(id: UUID = UUID(),
         nick: String = "",
         note: String = "",
         watch: Bool = true,
         richNotes: String = "",
         photoData: Data? = nil) {
        self.id = id
        self.nick = nick
        self.note = note
        self.watch = watch
        self.richNotes = richNotes
        self.photoData = photoData
    }

    /// Forward-compatible decoder so older settings.json files (without the
    /// `richNotes` or `photoData` keys) keep loading. Without this, a
    /// single missing key would fail decode of the whole AddressBook array.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = try c.decodeIfPresent(UUID.self,   forKey: .id)        ?? UUID()
        self.nick      = try c.decodeIfPresent(String.self, forKey: .nick)      ?? ""
        self.note      = try c.decodeIfPresent(String.self, forKey: .note)      ?? ""
        self.watch     = try c.decodeIfPresent(Bool.self,   forKey: .watch)     ?? true
        self.richNotes = try c.decodeIfPresent(String.self, forKey: .richNotes) ?? ""
        self.photoData = try c.decodeIfPresent(Data.self,   forKey: .photoData)
    }
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

/// Row-tint rule: when an inbound PRIVMSG/NOTICE matches `pattern`, the row
/// lights up (optionally with per-rule color, sound, dock bounce, notification)
/// and matched words are color-tinted in the chat view. Distinct from the
/// "own-nick mention" path so a user can layer rules on top of mentions.
struct HighlightRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var pattern: String = ""
    var isRegex: Bool = false
    var caseSensitive: Bool = false
    /// Optional #RRGGBB hex; nil falls back to the theme's mention color.
    var colorHex: String? = nil
    var playSound: Bool = true
    var bounceDock: Bool = true
    var systemNotify: Bool = true
    /// Empty = match on all networks; otherwise only these server profile IDs.
    var networks: [UUID] = []
    var enabled: Bool = true
}

/// Where a trigger rule is allowed to fire.
enum TriggerScope: String, Codable, CaseIterable, Identifiable {
    case channel
    case query
    case both
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .channel: return "Channels only"
        case .query:   return "Private queries only"
        case .both:    return "Both"
        }
    }
}

/// Auto-reply rule: when an inbound PRIVMSG matches `pattern`, the app sends
/// `response` back to the originating target. Response supports `$nick`,
/// `$channel`, `$match`, and `$1`–`$9` (regex capture groups).
struct TriggerRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var pattern: String = ""
    var isRegex: Bool = false
    var caseSensitive: Bool = false
    var response: String = ""
    var scope: TriggerScope = .both
    /// Empty = any network.
    var networks: [UUID] = []
    var enabled: Bool = true
}

/// Snapshot of which channels and query buffers were live on a network at the
/// most recent quit. Persisted in `AppSettings.lastSession` (keyed by the
/// server profile's UUID — stable across launches, unlike `IRCConnection.id`)
/// and replayed on the next connect when `restoreOpenBuffersOnLaunch` is on.
struct SessionSnapshot: Codable, Equatable {
    var channels: [String] = []
    var queries: [String] = []
    /// Bare name of the buffer that was selected when the snapshot was taken.
    /// Restored on a best-effort basis after the channels finish JOINing.
    var selected: String? = nil
}

/// Density of chat rows. Pure UI knob — no protocol or persistence
/// implications beyond what the renderer reads at draw time. Switched via
/// `/density` slash command or the Appearance tab.
enum ChatDensity: String, Codable, CaseIterable, Identifiable {
    case compact      // tight rows, minimal vertical padding
    case cozy         // default — modest breathing room
    case comfortable  // generous padding for readability
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .compact:     return "Compact"
        case .cozy:        return "Cozy"
        case .comfortable: return "Comfortable"
        }
    }
    /// Vertical padding multiplier the BufferView applies to chat rows.
    var rowPadding: CGFloat {
        switch self {
        case .compact:     return 1
        case .cozy:        return 3
        case .comfortable: return 6
        }
    }
}

struct AppSettings: Codable {
    var servers: [ServerProfile] = ServerProfile.defaultServers()
    var addressBook: [AddressEntry] = []
    var savedChannels: [SavedChannel] = []
    var ignoreList: [IgnoreEntry] = []
    var selectedServerID: UUID?

    /// User-defined `/alias <name> <expansion>` entries. Looked up in
    /// `ChatModel.sendInput` before built-in commands so user shortcuts
    /// can shadow them. Plain dictionary on disk; not encrypted beyond
    /// the surrounding settings envelope.
    var userAliases: [String: String] = [:]

    /// Chat-row density. Switched live by `/density` or in Appearance.
    var chatDensity: ChatDensity = .cozy

    /// Whole-buffer text zoom multiplier (`/zoom + - reset`). Multiplies
    /// the configured chat font size — kept separate so the setting in
    /// the Appearance tab stays the user's "real" preference and zoom
    /// is treated as an ephemeral lens.
    var viewZoom: Double = 1.0

    // Watchlist / highlight alert channels
    var playSoundOnWatchHit: Bool = true
    var bounceDockOnWatchHit: Bool = true
    var systemNotificationsOnWatchHit: Bool = true
    var highlightOnOwnNick: Bool = true

    // Persistent logs
    var enablePersistentLogs: Bool = false
    var logMotdAndNumerics: Bool = false

    /// Auto-delete logs older than `purgeLogsAfterDays` on app launch.
    /// Default off; 90 days is the suggested window when the user turns it on.
    var purgeLogsEnabled: Bool = false
    var purgeLogsAfterDays: Int = 90

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
        "ctcp": "",
        "highlight": "Funk"
    ]
    var themeID: String = "classic"

    /// User-built themes — `UserTheme` snapshots with hex color slots
    /// + per-event overrides. Listed alongside built-ins in the
    /// Themes tab and the View → Theme menu; selectable by
    /// `themeID = userTheme.id.uuidString`.
    var userThemes: [UserTheme] = []

    // Appearance / accessibility — applied to every chat-text view.
    /// Pattern fed straight into `DateFormatter.dateFormat` for chat-line
    /// timestamps. Defaults to "HH:mm:ss"; user can pick a preset (or a
    /// custom string) via Setup → Appearance.
    var timestampFormat: String = "HH:mm:ss"

    var chatFontFamily: ChatFontFamily = .systemMono
    /// Base font size in points. The Behavior tab clamps the slider to a
    /// readable range (10–24); below 10 buffers become unscannable.
    var chatFontSize: Double = 13
    /// Bold every chat line. Pairs well with the High Contrast theme.
    var boldChatText: Bool = false
    /// Add extra vertical padding between rows for accessibility.
    var relaxedRowSpacing: Bool = false

    // MARK: - Per-element font style overrides

    /// Chat-body font style. Overrides the legacy `chatFontFamily` /
    /// `chatFontSize` / `boldChatText` fields when its own fields are
    /// non-empty. All-default = pure inheritance from the legacy fields,
    /// which preserves backwards compatibility with old settings.json.
    var chatBodyFont: FontStyle = FontStyle()
    /// Nick column (`<nick>`). Empty = inherit chat-body slot.
    var nickFont: FontStyle = FontStyle()
    /// Leading [HH:mm:ss] timestamp column. Empty = inherit.
    var timestampFont: FontStyle = FontStyle()
    /// System / info / error / join / part / quit / nick lines.
    var systemLineFont: FontStyle = FontStyle()
    /// Collapse runs of consecutive join / part / quit / nick lines into a
    /// single summary row so a netsplit doesn't drown the channel chatter.
    /// Off keeps every line visible (the classic IRC behavior).
    var collapseJoinPart: Bool = true

    /// On launch, re-open the channels and query buffers that were live at
    /// the previous quit. Channel JOINs go through the normal CAP/auto-join
    /// path so server-side ACLs still apply. Off reverts to the classic
    /// "fresh slate every connect" behavior.
    var restoreOpenBuffersOnLaunch: Bool = true

    /// Per-network buffer snapshot from the most recent session. Keyed by the
    /// server profile's UUID string. Empty value = "nothing was open."
    var lastSession: [String: SessionSnapshot] = [:]

    /// Local-LLM assistant configuration. Off by default; enabling it
    /// shows a suggestion strip above the input bar in query buffers.
    var assistant: AssistantSettings = AssistantSettings()
    /// User's persona library — built-ins plus anything they've added.
    /// Populated lazily the first time the assistant is enabled.
    var assistantPersonas: [AssistantPersona] = []

    /// Run a compressed + encrypted backup of the support directory at
    /// every launch. Default ON — it's cheap insurance and the
    /// d0cc021 / assistant-clobber incidents would have been one-click
    /// recoveries with this in place.
    var backupEnabled: Bool = true
    /// Where backups land. Empty = use the default
    /// `~/Downloads/PurpleIRC backup/`. Stored as a string so we can
    /// resolve `~` cleanly via `(NSString as String).expandingTildeInPath`.
    var backupDirectory: String = ""
    /// Retention window in days. Files older than this are reaped at
    /// each backup pass. 0 = keep forever.
    var backupRetentionDays: Int = 30

    // Highlight rules (row tint + matched-word color + per-rule alerts)
    var highlightRules: [HighlightRule] = []

    // Native bot — trigger/response rules and seen-tracker toggle.
    var triggerRules: [TriggerRule] = []
    var seenTrackingEnabled: Bool = false

    /// Prompt before /quit (or /exit) terminates the app. Default on; users
    /// can disable it once they're comfortable with the command.
    var quitConfirmationEnabled: Bool = true

    /// Named identities the user can link to any server profile.
    var identities: [Identity] = []

    /// When true AND the keystore is set up AND biometrics are available,
    /// the launch flow requires Touch ID before the silent Keychain unlock
    /// is allowed to take effect. Doesn't affect the passphrase prompt —
    /// biometrics here are a defence-in-depth layer, not a passphrase
    /// replacement.
    var requireBiometricsOnLaunch: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.servers      = try c.decodeIfPresent([ServerProfile].self, forKey: .servers)
            ?? ServerProfile.defaultServers()
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
        self.purgeLogsEnabled = try c.decodeIfPresent(Bool.self, forKey: .purgeLogsEnabled) ?? false
        self.purgeLogsAfterDays = try c.decodeIfPresent(Int.self, forKey: .purgeLogsAfterDays) ?? 90
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
        self.timestampFormat = try c.decodeIfPresent(String.self, forKey: .timestampFormat) ?? "HH:mm:ss"
        self.chatFontFamily = try c.decodeIfPresent(ChatFontFamily.self, forKey: .chatFontFamily) ?? .systemMono
        self.chatFontSize = try c.decodeIfPresent(Double.self, forKey: .chatFontSize) ?? 13
        self.boldChatText = try c.decodeIfPresent(Bool.self, forKey: .boldChatText) ?? false
        self.relaxedRowSpacing = try c.decodeIfPresent(Bool.self, forKey: .relaxedRowSpacing) ?? false
        self.collapseJoinPart = try c.decodeIfPresent(Bool.self, forKey: .collapseJoinPart) ?? true
        self.restoreOpenBuffersOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .restoreOpenBuffersOnLaunch) ?? true
        self.lastSession = try c.decodeIfPresent([String: SessionSnapshot].self, forKey: .lastSession) ?? [:]
        self.assistant = try c.decodeIfPresent(AssistantSettings.self, forKey: .assistant) ?? AssistantSettings()
        self.assistantPersonas = try c.decodeIfPresent([AssistantPersona].self, forKey: .assistantPersonas) ?? []
        self.backupEnabled = try c.decodeIfPresent(Bool.self, forKey: .backupEnabled) ?? true
        self.backupDirectory = try c.decodeIfPresent(String.self, forKey: .backupDirectory) ?? ""
        self.backupRetentionDays = try c.decodeIfPresent(Int.self, forKey: .backupRetentionDays) ?? 30
        self.highlightRules = try c.decodeIfPresent([HighlightRule].self, forKey: .highlightRules) ?? []
        self.triggerRules = try c.decodeIfPresent([TriggerRule].self, forKey: .triggerRules) ?? []
        self.seenTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .seenTrackingEnabled) ?? false
        self.quitConfirmationEnabled = try c.decodeIfPresent(Bool.self, forKey: .quitConfirmationEnabled) ?? true
        self.identities = try c.decodeIfPresent([Identity].self, forKey: .identities) ?? []
        self.requireBiometricsOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .requireBiometricsOnLaunch) ?? false
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

    /// KeyStore used for envelope encryption. When nil or locked, settings
    /// are written as plaintext JSON. When unlocked, the JSON body is sealed
    /// with AES-GCM via the KeyStore's data-encryption key.
    weak var keyStore: KeyStore?

    /// True iff the on-disk file is currently the encrypted format. The UI
    /// shows this in the Security tab so the user can tell at a glance
    /// whether their metadata is actually encrypted.
    @Published private(set) var isEncryptedOnDisk: Bool = false

    /// Hard guard against the "init-time mutation clobbers encrypted file"
    /// data-loss class. Stays `false` until either:
    ///   - SettingsStore.init successfully decoded a plaintext file, OR
    ///   - reload() successfully decoded an encrypted file post-unlock, OR
    ///   - markAsLoadedForFreshInstall() was called explicitly when the
    ///     file genuinely doesn't exist (first launch).
    /// Save refuses while this is `false` so any didSet → save() that
    /// fires before the user's data lands in memory cannot overwrite the
    /// real on-disk file with empty defaults. Same incident class as
    /// `d0cc021` and the assistant rollout's persona seed.
    private var hasLoadedFromDisk: Bool = false

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
        self.settings = AppSettings()

        // Detect whether the file on disk is encrypted so the UI knows before
        // a load is attempted. Plain JSON starts with '{' / whitespace.
        if let data = try? Data(contentsOf: fileURL) {
            self.isEncryptedOnDisk = EncryptedJSON.hasMagic(data)
            // Only load automatically when the file is plaintext; encrypted
            // files need a keystore unlock first. ChatModel re-tries via
            // `reload()` once the keystore is ready.
            if !self.isEncryptedOnDisk {
                if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                    self.settings = resolveCredentials(in: decoded)
                    self.hasLoadedFromDisk = true
                }
            }
            // Encrypted file present but not yet decoded: hasLoadedFromDisk
            // stays false, so save() refuses until reload() succeeds.
        } else {
            // No file on disk → fresh install. Allow saves so the first
            // user edit persists.
            self.hasLoadedFromDisk = true
        }
        // No selectedServerID-defaulting here: mutating during init would
        // trigger didSet → save() while keyStore is still nil, and that's
        // the path that used to clobber an encrypted settings file with
        // plaintext defaults. selectedServer() falls back to .servers.first
        // when the ID is nil, which is the only place the value is read.
    }

    /// Re-read the settings file. Used by ChatModel after the KeyStore
    /// finishes unlocking an encrypted envelope.
    func reload() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        self.isEncryptedOnDisk = EncryptedJSON.hasMagic(data)
        let key = (keyStore?.isUnlocked == true) ? keyStore?.currentKey : nil
        // If the file is encrypted but the keystore isn't open, leave the
        // in-memory settings as the empty defaults — RootView's lock gate
        // is what actually surfaces this to the user.
        if isEncryptedOnDisk, key == nil { return }
        guard let jsonData = try? EncryptedJSON.unwrap(data, key: key) else {
            NSLog("PurpleIRC: settings envelope decrypt failed")
            return
        }
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: jsonData) {
            self.settings = resolveCredentials(in: decoded)
            self.hasLoadedFromDisk = true
        }
    }

    func save() {
        guard hasLoadedFromDisk else {
            // Pre-load mutation tried to save. Refuse — the user's real
            // data is still on disk encrypted, and writing defaults
            // would clobber it under the same key. Logged so a debug
            // session can spot the call site.
            NSLog("PurpleIRC: settings save skipped — file not yet loaded")
            return
        }
        do {
            // Move any cleartext credentials into Keychain BEFORE encoding so
            // the bytes we write never contain plaintext passwords, even if
            // envelope encryption is off.
            let persistable = persistCredentials(in: settings)

            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try enc.encode(persistable)

            let key = (keyStore?.isUnlocked == true) ? keyStore?.currentKey : nil
            let result = try EncryptedJSON.safeWrite(jsonData, to: fileURL, key: key)
            switch result {
            case .wrote:
                isEncryptedOnDisk = (key != nil)
            case .skippedLockedEncrypted:
                // The file on disk is encrypted but we don't have a key —
                // refuse to overwrite it. This is a hard guarantee against
                // the early-init save and lock-time stale-save cases.
                NSLog("PurpleIRC: skipped settings save (encrypted on disk, no key in hand)")
            }
        } catch {
            NSLog("PurpleIRC: failed to save settings: \(error)")
        }
    }

    // MARK: - Credential transform

    /// For every profile / identity password field on `src`, push the current
    /// cleartext into the Keychain and replace it with a "kc:<uuid>" reference.
    /// Already-referenced values are left alone; empty values delete any
    /// orphan Keychain item so the account doesn't leak after a clear.
    private func persistCredentials(in src: AppSettings) -> AppSettings {
        var out = src
        out.servers = out.servers.map { prof in
            var p = prof
            p.password          = persist(p.password,          account: Self.account(profile: p.id, field: "password"))
            p.saslPassword      = persist(p.saslPassword,      account: Self.account(profile: p.id, field: "sasl"))
            p.nickServPassword  = persist(p.nickServPassword,  account: Self.account(profile: p.id, field: "nickserv"))
            p.proxyPassword     = persist(p.proxyPassword,     account: Self.account(profile: p.id, field: "proxy"))
            return p
        }
        out.identities = out.identities.map { ident in
            var i = ident
            i.saslPassword     = persist(i.saslPassword,     account: Self.account(identity: i.id, field: "sasl"))
            i.nickServPassword = persist(i.nickServPassword, account: Self.account(identity: i.id, field: "nickserv"))
            return i
        }
        return out
    }

    /// Reverse of `persistCredentials`: every "kc:…" reference is resolved
    /// back to its Keychain value for in-memory use. Missing items return
    /// empty string (safer than blocking the whole load on one lost item).
    private func resolveCredentials(in src: AppSettings) -> AppSettings {
        var out = src
        out.servers = out.servers.map { prof in
            var p = prof
            p.password          = resolve(p.password)
            p.saslPassword      = resolve(p.saslPassword)
            p.nickServPassword  = resolve(p.nickServPassword)
            p.proxyPassword     = resolve(p.proxyPassword)
            return p
        }
        out.identities = out.identities.map { ident in
            var i = ident
            i.saslPassword     = resolve(i.saslPassword)
            i.nickServPassword = resolve(i.nickServPassword)
            return i
        }
        return out
    }

    private func persist(_ value: String, account: String) -> String {
        if CredentialRef.isReference(value) { return value }
        if value.isEmpty {
            try? KeychainStore.delete(account: account)
            return ""
        }
        try? KeychainStore.setString(value, for: account)
        return CredentialRef.makeReference(for: account)
    }

    private func resolve(_ raw: String) -> String {
        guard let account = CredentialRef.account(in: raw) else { return raw }
        return KeychainStore.getString(for: account) ?? ""
    }

    private static func account(profile: UUID, field: String) -> String {
        "profile.\(profile.uuidString).\(field)"
    }
    private static func account(identity: UUID, field: String) -> String {
        "identity.\(identity.uuidString).\(field)"
    }

    var fileURLForDisplay: String { fileURL.path }

    /// Filesystem location of settings.json. Exposed so the main toolbar menu
    /// can "Reveal in Finder" the file.
    var settingsFileURL: URL { fileURL }

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
        // Evict any orphan credentials so the Keychain doesn't accumulate
        // entries for profiles that no longer exist.
        for field in ["password", "sasl", "nickserv", "proxy"] {
            try? KeychainStore.delete(account: Self.account(profile: id, field: field))
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

    // MARK: - Highlight rules

    func upsertHighlight(_ rule: HighlightRule) {
        if let i = settings.highlightRules.firstIndex(where: { $0.id == rule.id }) {
            settings.highlightRules[i] = rule
        } else {
            settings.highlightRules.append(rule)
        }
    }

    func removeHighlight(id: UUID) {
        settings.highlightRules.removeAll { $0.id == id }
    }

    // MARK: - Trigger rules

    func upsertTrigger(_ rule: TriggerRule) {
        if let i = settings.triggerRules.firstIndex(where: { $0.id == rule.id }) {
            settings.triggerRules[i] = rule
        } else {
            settings.triggerRules.append(rule)
        }
    }

    func removeTrigger(id: UUID) {
        settings.triggerRules.removeAll { $0.id == id }
    }

    // MARK: - Identities

    func identity(withID id: UUID?) -> Identity? {
        guard let id else { return nil }
        return settings.identities.first { $0.id == id }
    }

    func upsertIdentity(_ identity: Identity) {
        if let i = settings.identities.firstIndex(where: { $0.id == identity.id }) {
            settings.identities[i] = identity
        } else {
            settings.identities.append(identity)
        }
    }

    func removeIdentity(id: UUID) {
        settings.identities.removeAll { $0.id == id }
        // Any server profiles referencing this identity revert to their own
        // inline fields. No need to surface an error — UX is forgiving.
        for i in settings.servers.indices where settings.servers[i].identityID == id {
            settings.servers[i].identityID = nil
        }
        for field in ["sasl", "nickserv"] {
            try? KeychainStore.delete(account: Self.account(identity: id, field: field))
        }
    }
}
