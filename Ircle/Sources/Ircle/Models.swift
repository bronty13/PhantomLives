import Foundation

/// What a buffer represents. Mirrors the classic Ircle window taxonomy: the
/// server console, a joined channel, or a one-to-one query.
enum BufferKind: Equatable {
    case server
    case channel
    case query
}

/// The flavor of a single line in a buffer — drives both the icon/prefix the
/// Platinum renderer draws and how the line is colored.
enum LineKind: Equatable {
    case message      // PRIVMSG
    case action       // CTCP ACTION (/me)
    case notice       // NOTICE
    case join
    case part
    case quit
    case nickChange
    case topic
    case mode
    case motd         // server MOTD / numeric text
    case system       // client-generated status ("Connecting…", "Now talking in #x")
    case error
}

/// One rendered line in a buffer. `text` keeps mIRC formatting codes intact;
/// the view strips/renders them at draw time (IRCKit.IRCText for the plain
/// path). Value type so buffers diff cheaply in SwiftUI.
struct IrcleLine: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: LineKind
    /// The nick (for message/action/notice) or actor (join/part/etc.); nil for
    /// pure server/system text.
    let sender: String?
    let text: String
    var isSelf: Bool
    var isMention: Bool

    init(kind: LineKind,
         sender: String? = nil,
         text: String,
         timestamp: Date = Date(),
         isSelf: Bool = false,
         isMention: Bool = false) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        self.sender = sender
        self.text = text
        self.isSelf = isSelf
        self.isMention = isMention
    }
}

/// A channel member, carrying their highest mode prefix for the nick list.
struct IrcleUser: Identifiable, Equatable, Comparable {
    var nick: String
    /// Highest-ranked membership prefix the server reports: `~ & @ % +` or "".
    var prefix: String
    /// `user@host`, populated from a WHO reply (nil until known).
    var host: String? = nil
    /// Network operator (IRCop) — the `*` flag in a WHO reply.
    var isIrcOp: Bool = false

    var id: String { nick.lowercased() }

    /// Rank order for the nick list: ops first, then halfops, voiced, plain.
    /// Lower number sorts higher.
    private var rank: Int {
        switch prefix.first {
        case "~": return 0   // owner
        case "&": return 1   // admin
        case "@": return 2   // op
        case "%": return 3   // halfop
        case "+": return 4   // voice
        default:  return 5
        }
    }

    static func < (lhs: IrcleUser, rhs: IrcleUser) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lhs.nick.localizedCaseInsensitiveCompare(rhs.nick) == .orderedAscending
    }
}

/// IRC casemapping helper. Channel and nick comparisons are case-insensitive;
/// we use a simple ASCII lowercasing (rfc1459 also folds `[]\` ⇄ `{}|`, but
/// plain lowercasing is correct for the common case and avoids surprises).
enum IRCCase {
    static func fold(_ s: String) -> String { s.lowercased() }
    static func equal(_ a: String, _ b: String) -> Bool { fold(a) == fold(b) }
}
