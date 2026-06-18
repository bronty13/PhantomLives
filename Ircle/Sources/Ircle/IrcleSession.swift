import Foundation
import Combine
import IRCKit

/// One IRC connection's worth of session state, built on IRCKit's wire-level
/// `IRCClient`. This is Ircle's purpose-built equivalent of PurpleIRC's
/// `IRCConnection`: it turns the raw inbound `IRCMessage` stream into channel /
/// query buffers, nick lists, topics, and self-state — exactly the model the
/// nostalgic Channelbar + message window need, and nothing more.
///
/// IRCKit's `IRCClient` already drives CAP/SASL and registration; this layer
/// owns the *application* semantics (PING/PONG, PRIVMSG routing, NAMES, JOIN/
/// PART/QUIT/NICK bookkeeping, command parsing).
@MainActor
final class IrcleSession: ObservableObject, Identifiable {
    let id = UUID()

    @Published private(set) var state: IRCConnectionState = .disconnected
    @Published private(set) var nick: String
    /// Buffers for this session. `buffers[0]` is always the server console.
    @Published private(set) var buffers: [IrcleBuffer] = []
    /// Rolling raw protocol log for the server-console "raw" view.
    @Published private(set) var rawLog: [String] = []

    /// The buffer the UI currently has focused, so unread accounting can skip
    /// the active window. Set by the model when selection changes.
    weak var focusedBuffer: IrcleBuffer?

    let serverBuffer: IrcleBuffer
    private let client = IRCClient()
    private var config: IRCConnectionConfig
    let displayName: String
    /// Channels to JOIN automatically once registration completes (RPL_WELCOME).
    private let autoJoinChannels: [String]

    private static let maxRawLines = 2_000

    init(config: IRCConnectionConfig, displayName: String, autoJoin: [String] = []) {
        self.config = config
        self.displayName = displayName
        self.autoJoinChannels = autoJoin
        self.nick = config.nick
        let srv = IrcleBuffer(kind: .server, name: displayName)
        self.serverBuffer = srv
        self.buffers = [srv]
        wireClient()
    }

    // MARK: - Connection lifecycle

    func connect() {
        system(serverBuffer, "Connecting to \(config.host):\(config.port)…")
        client.connect(config: config)
    }

    func disconnect(_ quitMessage: String = "Ircle") {
        client.disconnect(quitMessage: quitMessage)
    }

    /// True when the session is connected and registered enough to send.
    var isConnected: Bool { state == .connected }

    private func wireClient() {
        client.onState = { [weak self] st in
            Task { @MainActor in self?.handleState(st) }
        }
        client.onMessage = { [weak self] msg in
            Task { @MainActor in self?.handle(msg) }
        }
        client.onRaw = { [weak self] line, outbound in
            Task { @MainActor in self?.appendRaw(line, outbound: outbound) }
        }
    }

    private func handleState(_ st: IRCConnectionState) {
        state = st
        switch st {
        case .connecting:  system(serverBuffer, "Connecting…")
        case .connected:   system(serverBuffer, "Connected. Registering…")
        case .disconnected:
            system(serverBuffer, "Disconnected.")
            for b in buffers where b.kind == .channel { b.joined = false }
        case .failed(let reason):
            line(serverBuffer, .error, text: reason)
        }
    }

    private func appendRaw(_ line: String, outbound: Bool) {
        rawLog.append((outbound ? "» " : "« ") + line)
        if rawLog.count > Self.maxRawLines {
            rawLog.removeFirst(rawLog.count - Self.maxRawLines)
        }
    }

    // MARK: - Inbound dispatch

    /// Test/replay seam: parse a raw server line and run it through the same
    /// dispatch the live `IRCClient` callback uses. Mirrors the production path
    /// minus the socket. (IRCKit's `IRCClient` handles CAP/SASL internally; this
    /// covers the application-level routing.)
    func ingest(_ rawLine: String) {
        if let msg = IRCMessage.parse(rawLine) { handle(msg) }
    }

    private func handle(_ msg: IRCMessage) {
        switch msg.command {
        case "PING":
            client.send("PONG :" + (msg.params.last ?? ""))
        case "PRIVMSG": handlePrivmsg(msg)
        case "NOTICE":  handleNotice(msg)
        case "JOIN":    handleJoin(msg)
        case "PART":    handlePart(msg)
        case "QUIT":    handleQuit(msg)
        case "NICK":    handleNick(msg)
        case "KICK":    handleKick(msg)
        case "TOPIC":   handleTopic(msg)
        case "MODE":    handleMode(msg)
        case "ERROR":   line(serverBuffer, .error, text: msg.params.last ?? "ERROR")
        default:
            handleNumeric(msg)
        }
    }

    private func handlePrivmsg(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let from = msg.nickFromPrefix ?? "?"
        let target = msg.params[0]
        let body = msg.params[1]
        let isSelf = IRCCase.equal(from, nick)

        // CTCP — wrapped in \u{01}.
        if body.hasPrefix("\u{01}") && body.hasSuffix("\u{01}") && body.count >= 2 {
            let inner = String(body.dropFirst().dropLast())
            let parts = inner.split(separator: " ", maxSplits: 1).map(String.init)
            let verb = parts.first?.uppercased() ?? ""
            let args = parts.count > 1 ? parts[1] : ""
            if verb == "ACTION" {
                let buf = bufferForTarget(target, peer: from)
                let mention = mentions(args)
                line(buf, .action, sender: from, text: args, isSelf: isSelf, isMention: mention)
                return
            }
            // Answer the common CTCP queries; surface the rest in the console.
            handleCTCP(verb: verb, args: args, from: from, isSelf: isSelf)
            return
        }

        let buf = bufferForTarget(target, peer: from)
        let mention = !isSelf && (mentions(body) || IRCCase.equal(target, nick))
        // body kept raw (renderer strips mIRC codes at draw time).
        line(buf, .message, sender: from, text: body, isSelf: isSelf, isMention: mention)
    }

    private func handleCTCP(verb: String, args: String, from: String, isSelf: Bool) {
        switch verb {
        case "VERSION":
            if !isSelf { client.send("NOTICE \(from) :\u{01}VERSION Ircle (PhantomLives) — IRCKit\u{01}") }
        case "PING":
            if !isSelf { client.send("NOTICE \(from) :\u{01}PING \(args)\u{01}") }
        case "TIME":
            if !isSelf {
                let f = DateFormatter(); f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
                client.send("NOTICE \(from) :\u{01}TIME \(f.string(from: Date()))\u{01}")
            }
        default:
            break
        }
        system(serverBuffer, "[CTCP \(verb) from \(from)]")
    }

    private func handleNotice(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let from = msg.nickFromPrefix ?? "?"
        let target = msg.params[0]
        let body = msg.params[1]
        // Server notices (no nick!user@host prefix, or to "*") go to console.
        let buf: IrcleBuffer
        if msg.prefix == nil || msg.nickFromPrefix == config.host || target == "*" {
            buf = serverBuffer
        } else if IRCCase.equal(target, nick) {
            buf = bufferForTarget(target, peer: from)
        } else {
            buf = bufferForTarget(target, peer: from)
        }
        line(buf, .notice, sender: from, text: body)
    }

    private func handleJoin(_ msg: IRCMessage) {
        let who = msg.nickFromPrefix ?? "?"
        guard let channel = msg.params.first else { return }
        if IRCCase.equal(who, nick) {
            let buf = ensureChannel(channel)
            buf.joined = true
            system(buf, "Now talking in \(channel)")
        } else if let buf = channelBuffer(channel) {
            buf.addUser(who)
            line(buf, .join, sender: who, text: "\(who) has joined \(channel)")
        }
    }

    private func handlePart(_ msg: IRCMessage) {
        let who = msg.nickFromPrefix ?? "?"
        guard let channel = msg.params.first, let buf = channelBuffer(channel) else { return }
        let reason = msg.params.count > 1 ? msg.params[1] : ""
        if IRCCase.equal(who, nick) {
            buf.joined = false
            system(buf, "You have left \(channel)")
        } else {
            buf.removeUser(who)
            let suffix = reason.isEmpty ? "" : " (\(reason))"
            line(buf, .part, sender: who, text: "\(who) has left \(channel)\(suffix)")
        }
    }

    private func handleQuit(_ msg: IRCMessage) {
        let who = msg.nickFromPrefix ?? "?"
        let reason = msg.params.last ?? ""
        let suffix = reason.isEmpty ? "" : " (\(reason))"
        for buf in buffers where buf.kind == .channel && buf.hasUser(who) {
            buf.removeUser(who)
            line(buf, .quit, sender: who, text: "\(who) has quit\(suffix)")
        }
    }

    private func handleNick(_ msg: IRCMessage) {
        let oldNick = msg.nickFromPrefix ?? "?"
        guard let newNick = msg.params.first else { return }
        if IRCCase.equal(oldNick, nick) { nick = newNick }
        for buf in buffers where buf.kind == .channel && buf.hasUser(oldNick) {
            buf.renameUser(from: oldNick, to: newNick)
            line(buf, .nickChange, sender: oldNick, text: "\(oldNick) is now known as \(newNick)")
        }
    }

    private func handleKick(_ msg: IRCMessage) {
        guard msg.params.count >= 2, let buf = channelBuffer(msg.params[0]) else { return }
        let target = msg.params[1]
        let by = msg.nickFromPrefix ?? "?"
        let reason = msg.params.count > 2 ? msg.params[2] : ""
        let suffix = reason.isEmpty ? "" : " (\(reason))"
        if IRCCase.equal(target, nick) {
            buf.joined = false
            line(buf, .part, text: "You were kicked from \(buf.name) by \(by)\(suffix)")
        } else {
            buf.removeUser(target)
            line(buf, .part, sender: by, text: "\(target) was kicked by \(by)\(suffix)")
        }
    }

    private func handleTopic(_ msg: IRCMessage) {
        guard msg.params.count >= 2, let buf = channelBuffer(msg.params[0]) else { return }
        let who = msg.nickFromPrefix ?? "?"
        buf.topic = msg.params[1]
        line(buf, .topic, sender: who, text: "\(who) changed the topic to: \(msg.params[1])")
    }

    private func handleMode(_ msg: IRCMessage) {
        guard let target = msg.params.first else { return }
        let by = msg.nickFromPrefix ?? "?"
        let rest = msg.params.dropFirst().joined(separator: " ")
        let buf = channelBuffer(target) ?? serverBuffer
        line(buf, .mode, sender: by, text: "\(by) sets mode: \(rest)")
    }

    private func handleNumeric(_ msg: IRCMessage) {
        switch msg.command {
        case "001":
            // Server may have adjusted our nick during registration.
            if let assigned = msg.params.first { nick = assigned }
            line(serverBuffer, .motd, text: msg.params.last ?? "")
            // Registration is complete — fire the auto-join list.
            for chan in autoJoinChannels where !chan.isEmpty {
                client.send("JOIN \(chan)")
            }
        case "332": // RPL_TOPIC
            if msg.params.count >= 3, let buf = channelBuffer(msg.params[1]) {
                buf.topic = msg.params[2]
                line(buf, .topic, text: "Topic: \(msg.params[2])")
            }
        case "333": // RPL_TOPICWHOTIME (ignore detail, already have topic)
            break
        case "353": // RPL_NAMREPLY:  <me> = #chan :nick @nick +nick
            if msg.params.count >= 4, let buf = channelBuffer(msg.params[2]) {
                for token in msg.params[3].split(separator: " ") {
                    buf.addUser(String(token))
                }
            }
        case "366": // RPL_ENDOFNAMES — nothing to print
            break
        case "375", "372", "376", "002", "003", "004", "005", "251", "252",
             "253", "254", "255", "265", "266", "250", "375L":
            line(serverBuffer, .motd, text: msg.params.last ?? "")
        case "433": // ERR_NICKNAMEINUSE — auto-bump with an underscore once.
            let attempted = msg.params.count > 1 ? msg.params[1] : nick
            line(serverBuffer, .error, text: "Nickname \(attempted) is in use.")
            if state != .connected || !isConnected {
                let alt = attempted + "_"
                client.send("NICK \(alt)")
            }
        default:
            // Errors (4xx/5xx) and unhandled numerics: dump the trailing text.
            line(serverBuffer, msg.command.first == "4" || msg.command.first == "5" ? .error : .motd,
                 text: msg.params.dropFirst().joined(separator: " "))
        }
    }

    private func mentions(_ text: String) -> Bool {
        let plain = IRCText.stripFormatting(text).lowercased()
        let me = nick.lowercased()
        guard !me.isEmpty else { return false }
        return plain.contains(me)
    }

    // MARK: - Outbound / commands

    /// Send a plain message to the focused buffer's target. Channel/query only.
    func sendText(_ text: String, to buffer: IrcleBuffer) {
        guard buffer.kind != .server else {
            system(serverBuffer, "Not a channel or query — use /commands here.")
            return
        }
        let target = buffer.name
        client.send("PRIVMSG \(target) :\(text)")
        if !client.enabledCaps.contains("echo-message") {
            line(buffer, .message, sender: nick, text: text, isSelf: true)
        }
    }

    /// Handle a slash command typed in `buffer`. Returns silently; output goes
    /// to the relevant buffer.
    func runCommand(_ raw: String, in buffer: IrcleBuffer) {
        var line = raw
        line.removeFirst() // drop leading '/'
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = (parts.first ?? "").uppercased()
        let rest = parts.count > 1 ? parts[1] : ""

        switch cmd {
        case "JOIN", "J":
            if !rest.isEmpty { client.send("JOIN \(rest)") }
        case "PART", "LEAVE":
            let chan = rest.isEmpty ? buffer.name : rest
            client.send("PART \(chan)")
        case "MSG", "QUERY":
            let mp = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard mp.count >= 1, !mp[0].isEmpty else { return }
            let peer = mp[0]
            let buf = ensureQuery(peer)
            if mp.count > 1 {
                client.send("PRIVMSG \(peer) :\(mp[1])")
                if !client.enabledCaps.contains("echo-message") {
                    self.line(buf, .message, sender: nick, text: mp[1], isSelf: true)
                }
            }
        case "ME":
            client.send("PRIVMSG \(buffer.name) :\u{01}ACTION \(rest)\u{01}")
            if !client.enabledCaps.contains("echo-message") {
                self.line(buffer, .action, sender: nick, text: rest, isSelf: true)
            }
        case "NICK":
            if !rest.isEmpty { client.send("NICK \(rest)") }
        case "TOPIC":
            if rest.isEmpty { client.send("TOPIC \(buffer.name)") }
            else { client.send("TOPIC \(buffer.name) :\(rest)") }
        case "QUIT":
            disconnect(rest.isEmpty ? "Ircle" : rest)
        case "RAW", "QUOTE":
            if !rest.isEmpty { client.send(rest) }
        case "WHOIS":
            if !rest.isEmpty { client.send("WHOIS \(rest)") }
        default:
            // Unknown command: pass it straight through to the server.
            client.send(line)
        }
    }

    // MARK: - Buffer plumbing

    private func bufferForTarget(_ target: String, peer: String) -> IrcleBuffer {
        if target.hasPrefix("#") || target.hasPrefix("&") {
            return channelBuffer(target) ?? ensureChannel(target)
        }
        // A query: keyed by the *other* party. If the target is us, it's an
        // incoming query from `peer`; otherwise it's our own echo to `target`.
        let other = IRCCase.equal(target, nick) ? peer : target
        return ensureQuery(other)
    }

    private func channelBuffer(_ name: String) -> IrcleBuffer? {
        buffers.first { $0.kind == .channel && IRCCase.equal($0.name, name) }
    }

    @discardableResult
    private func ensureChannel(_ name: String) -> IrcleBuffer {
        if let b = channelBuffer(name) { return b }
        let b = IrcleBuffer(kind: .channel, name: name)
        buffers.append(b)
        return b
    }

    @discardableResult
    func ensureQuery(_ peer: String) -> IrcleBuffer {
        if let b = buffers.first(where: { $0.kind == .query && IRCCase.equal($0.name, peer) }) {
            return b
        }
        let b = IrcleBuffer(kind: .query, name: peer)
        buffers.append(b)
        return b
    }

    func closeBuffer(_ buffer: IrcleBuffer) {
        guard buffer.kind != .server else { return }
        if buffer.kind == .channel && buffer.joined {
            client.send("PART \(buffer.name)")
        }
        buffers.removeAll { $0.id == buffer.id }
    }

    // MARK: - Line helpers

    private func line(_ buffer: IrcleBuffer, _ kind: LineKind, sender: String? = nil,
                      text: String, isSelf: Bool = false, isMention: Bool = false) {
        let l = IrcleLine(kind: kind, sender: sender, text: text, isSelf: isSelf, isMention: isMention)
        buffer.append(l, focused: buffer === focusedBuffer)
    }

    private func system(_ buffer: IrcleBuffer, _ text: String) {
        line(buffer, .system, text: text)
    }
}
