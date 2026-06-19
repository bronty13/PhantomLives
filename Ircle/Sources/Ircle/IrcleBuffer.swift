import Foundation
import Combine

/// One window's worth of state: the server console, a channel, or a query.
/// The classic Ircle "channelbar" is just the list of these across a session.
@MainActor
final class IrcleBuffer: ObservableObject, Identifiable {
    let id = UUID()
    let kind: BufferKind
    /// Display name: the server host (server buffer), `#channel`, or a nick.
    @Published var name: String
    @Published var lines: [IrcleLine] = []
    /// Channel members (channel buffers only), kept sorted for the nick list.
    @Published var users: [IrcleUser] = []
    @Published var topic: String = ""
    /// Unread count since the buffer was last focused — drives the channelbar
    /// badge. `mentioned` flips when our nick appears while unfocused.
    @Published var unread: Int = 0
    @Published var mentioned: Bool = false
    /// Channels we've parted/been kicked from but kept open go inactive (the
    /// channelbar dims them, like classic Ircle).
    @Published var joined: Bool

    /// Channel-flag modes currently active — drives the Classic nick-list
    /// mode-toggle row. Only *presence* is tracked, not values (so `k`/`l`
    /// appear lit when set, without storing the key/limit).
    @Published var channelModes: Set<Character> = []

    init(kind: BufferKind, name: String, joined: Bool = true) {
        self.kind = kind
        self.name = name
        self.joined = joined
    }

    /// The channel-flag mode letters Ircle's Classic mode row surfaces.
    static let trackedModes: Set<Character> = ["t", "n", "i", "p", "s", "m", "l", "k", "r"]

    /// Apply an IRC mode token (e.g. `+nt`, `+l`, `-k`) to `channelModes`.
    /// Parameters and untracked modes (o/v/b/e/I/…) are ignored — we only care
    /// whether each tracked channel flag is on. Pass ONLY the mode token, not
    /// its parameter arguments.
    func applyModeChange(_ token: String) {
        var adding = true
        for ch in token {
            switch ch {
            case "+": adding = true
            case "-": adding = false
            case " ": return          // parameter section begins; stop
            default:
                guard Self.trackedModes.contains(ch) else { continue }
                if adding { channelModes.insert(ch) } else { channelModes.remove(ch) }
            }
        }
    }

    /// Replace the flag set from a RPL_CHANNELMODEIS (324) mode token.
    func setModes(_ token: String) {
        channelModes.removeAll()
        applyModeChange(token.hasPrefix("+") || token.hasPrefix("-") ? token : "+" + token)
    }

    /// Cap retained scrollback so a long-lived channel can't grow unbounded.
    static let maxLines = 5_000

    func append(_ line: IrcleLine, focused: Bool) {
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        if !focused {
            unread += 1
            if line.isMention { mentioned = true }
        }
    }

    func clearUnread() {
        unread = 0
        mentioned = false
    }

    // MARK: - Nick list maintenance (channel buffers)

    func addUser(_ nick: String, prefix: String = "") {
        let folded = IRCCase.fold(stripPrefix(nick))
        let bare = stripPrefix(nick)
        let pfx = prefix.isEmpty ? leadingPrefix(nick) : prefix
        if let idx = users.firstIndex(where: { $0.id == folded }) {
            users[idx].prefix = pfx
        } else {
            users.append(IrcleUser(nick: bare, prefix: pfx))
        }
        users.sort()
    }

    func removeUser(_ nick: String) {
        let folded = IRCCase.fold(stripPrefix(nick))
        users.removeAll { $0.id == folded }
    }

    func renameUser(from oldNick: String, to newNick: String) {
        let folded = IRCCase.fold(oldNick)
        if let idx = users.firstIndex(where: { $0.id == folded }) {
            users[idx].nick = newNick
            users.sort()
        }
    }

    func hasUser(_ nick: String) -> Bool {
        let folded = IRCCase.fold(nick)
        return users.contains { $0.id == folded }
    }

    /// Split a `@nick` / `+nick` / `~&@%+nick` NAMES token into (prefix, nick).
    private func leadingPrefix(_ token: String) -> String {
        let prefixes = Set("~&@%+")
        var pfx = ""
        for ch in token {
            if prefixes.contains(ch) { pfx.append(ch) } else { break }
        }
        // Keep only the single highest-ranked prefix for display.
        return String(pfx.prefix(1))
    }

    private func stripPrefix(_ token: String) -> String {
        let prefixes = Set("~&@%+")
        return String(token.drop(while: { prefixes.contains($0) }))
    }
}
