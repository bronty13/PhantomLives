import Foundation

/// Stable, case-normalised key for any per-buffer dictionary that needs
/// to address a buffer on a specific network. Couples the network slug
/// (the same one used in `SeenStore.slug(for:)` and the on-disk log
/// directory layout) with the buffer's name folded to lowercase, so
/// case-only differences (`#Swift` vs `#swift`) hash and compare equal.
///
/// On-disk wire format is the same string `"<slug>/<name-lower>"` that
/// `AppSettings.messageFiltersByBuffer` has stored since 1.0.130 — the
/// `description` property is the single source of truth for that
/// representation and Codable round-trip is unchanged. The struct is
/// purely a runtime API improvement: it eliminates the manual
/// interpolation and lowercasing that every call site had to remember.
struct BufferKey: Hashable, CustomStringConvertible {
    let networkSlug: String
    /// Stored lowercased — match the historical key format byte-for-byte.
    let bufferName: String

    init(networkSlug: String, bufferName: String) {
        self.networkSlug = networkSlug
        self.bufferName = bufferName.lowercased()
    }

    /// `<slug>/<name-lower>`. Identical to the legacy
    /// `MessageKindFilter.key(networkSlug:bufferName:)` output so the
    /// dictionary entries written to `settings.json` by earlier builds
    /// continue to address the same logical buffer after the upgrade.
    var description: String { "\(networkSlug)/\(bufferName)" }
}

/// Per-buffer + per-app toggle set for which `ChatLine.Kind` cases should
/// be rendered. The buffer view consults `MessageKindFilter.includes(_:)`
/// before adding a line to its rendered-rows pipeline; an `false` toggle
/// just hides the line — it stays in `Buffer.lines` so a later toggle can
/// bring it back without a relog.
///
/// `MessageKindFilter()` produces the "show everything" baseline. The Setup
/// → Behavior tab edits `AppSettings.messageFilterDefaults`; per-channel
/// overrides live in `AppSettings.messageFiltersByBuffer`, keyed by
/// `<network-slug>/<buffer-name>`. The actual chat lines (privmsg / action)
/// always render — toggling them off would silently swallow the
/// conversation, which is never what the user wants.
struct MessageKindFilter: Codable, Equatable {
    var info: Bool = true
    var error: Bool = true
    var motd: Bool = true
    var notice: Bool = true
    var join: Bool = true
    var part: Bool = true
    var quit: Bool = true
    var nickChange: Bool = true
    var topic: Bool = true

    /// Decide whether a given `ChatLine.Kind` should render under this
    /// filter. PRIVMSG / ACTION / RAW always render — those are the
    /// content the user actually came for; suppressing them would feel
    /// like data loss.
    func includes(_ kind: ChatLine.Kind) -> Bool {
        switch kind {
        case .privmsg, .action, .raw:
            return true
        case .info:    return info
        case .error:   return error
        case .motd:    return motd
        case .notice:  return notice
        case .join:    return join
        case .part:    return part
        case .quit:    return quit
        case .nick:    return nickChange
        case .topic:   return topic
        }
    }

    init(info: Bool = true,
         error: Bool = true,
         motd: Bool = true,
         notice: Bool = true,
         join: Bool = true,
         part: Bool = true,
         quit: Bool = true,
         nickChange: Bool = true,
         topic: Bool = true) {
        self.info = info
        self.error = error
        self.motd = motd
        self.notice = notice
        self.join = join
        self.part = part
        self.quit = quit
        self.nickChange = nickChange
        self.topic = topic
    }

    /// Forward-compatible decode: any new field defaults to `true` so an
    /// old payload doesn't accidentally hide a category we added later.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.info       = try c.decodeIfPresent(Bool.self, forKey: .info) ?? true
        self.error      = try c.decodeIfPresent(Bool.self, forKey: .error) ?? true
        self.motd       = try c.decodeIfPresent(Bool.self, forKey: .motd) ?? true
        self.notice     = try c.decodeIfPresent(Bool.self, forKey: .notice) ?? true
        self.join       = try c.decodeIfPresent(Bool.self, forKey: .join) ?? true
        self.part       = try c.decodeIfPresent(Bool.self, forKey: .part) ?? true
        self.quit       = try c.decodeIfPresent(Bool.self, forKey: .quit) ?? true
        self.nickChange = try c.decodeIfPresent(Bool.self, forKey: .nickChange) ?? true
        self.topic      = try c.decodeIfPresent(Bool.self, forKey: .topic) ?? true
    }
}

/// Display order + label + tooltip metadata for the checkbox grid in the
/// header popover and in Setup → Behavior. Centralized so the two UIs
/// stay in lockstep — adding a new kind in `MessageKindFilter` is a
/// one-line addition here and both UIs pick it up automatically.
enum MessageKindToggle: String, CaseIterable, Identifiable {
    case info
    case error
    case motd
    case notice
    case join
    case part
    case quit
    case nickChange
    case topic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .info:       return "System / info"
        case .error:      return "Errors"
        case .motd:       return "MOTD"
        case .notice:     return "Notices"
        case .join:       return "Joins"
        case .part:       return "Parts"
        case .quit:       return "Quits"
        case .nickChange: return "Nick changes"
        case .topic:      return "Topic changes"
        }
    }

    var help: String {
        switch self {
        case .info:       return "PurpleIRC's own informational lines (\"Connecting…\", \"You joined\", etc.)"
        case .error:      return "Connection / command errors emitted to the buffer"
        case .motd:       return "Server message-of-the-day banners"
        case .notice:     return "NOTICE messages from the server, ChanServ, NickServ, etc."
        case .join:       return "Other users joining the channel"
        case .part:       return "Other users leaving the channel"
        case .quit:       return "Other users disconnecting from IRC"
        case .nickChange: return "Other users changing their nickname"
        case .topic:      return "Channel topic changes"
        }
    }

    /// Pull the live value from a filter for binding-style UI use.
    func get(from f: MessageKindFilter) -> Bool {
        switch self {
        case .info:       return f.info
        case .error:      return f.error
        case .motd:       return f.motd
        case .notice:     return f.notice
        case .join:       return f.join
        case .part:       return f.part
        case .quit:       return f.quit
        case .nickChange: return f.nickChange
        case .topic:      return f.topic
        }
    }

    /// Set the live value on a filter; counterpart to `get(from:)`.
    func set(_ value: Bool, on f: inout MessageKindFilter) {
        switch self {
        case .info:       f.info = value
        case .error:      f.error = value
        case .motd:       f.motd = value
        case .notice:     f.notice = value
        case .join:       f.join = value
        case .part:       f.part = value
        case .quit:       f.quit = value
        case .nickChange: f.nickChange = value
        case .topic:      f.topic = value
        }
    }
}
