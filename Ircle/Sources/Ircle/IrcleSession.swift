import Foundation
import Combine
import AppKit
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

    /// Notify (friends) list for this connection — kept in sync with the global
    /// `settings.notifyNicks` by the model. Their online presence is polled via
    /// ISON and reflected in `onlineFriends`.
    @Published var notifyNicks: [String] = [] {
        didSet { if registered { pollNotify() } }
    }
    /// Case-folded nicks from the notify list currently reported online by ISON.
    @Published private(set) var onlineFriends: Set<String> = []
    /// Whether we're marked /away on this connection (tracked from 305/306).
    @Published private(set) var isAway = false
    /// Mirror of `settings.notificationsEnabled`, kept in sync by the model.
    var notificationsEnabled = true
    /// Set by the model to receive validated inbound DCC offers.
    var onDCCOffer: ((DCC.Offer, String) -> Void)?
    private var notifyTimer: Timer?
    /// How often to re-poll friend presence (seconds).
    static let notifyPollInterval: TimeInterval = 45

    /// The buffer the UI currently has focused, so unread accounting can skip
    /// the active window. Set by the model when selection changes.
    weak var focusedBuffer: IrcleBuffer?

    let serverBuffer: IrcleBuffer
    private let client = IRCClient()
    private var config: IRCConnectionConfig
    let displayName: String
    /// The saved `ServerProfile` this session was started from, so the model
    /// can avoid opening a duplicate session for the same profile.
    let profileID: UUID?
    /// Channels to JOIN automatically once registration completes (RPL_WELCOME).
    private let autoJoinChannels: [String]

    private static let maxRawLines = 2_000

    init(config: IRCConnectionConfig, displayName: String,
         autoJoin: [String] = [], profileID: UUID? = nil) {
        self.config = config
        self.displayName = displayName
        self.autoJoinChannels = autoJoin
        self.profileID = profileID
        self.nick = config.nick
        let srv = IrcleBuffer(kind: .server, name: displayName)
        self.serverBuffer = srv
        self.buffers = [srv]
        wireClient()
    }

    // MARK: - Connection lifecycle

    /// Set on RPL_WELCOME (001). Distinguishes "socket up" (`state == .connected`)
    /// from "registration complete" — the two differ during the CAP/NICK/USER
    /// handshake, which is exactly when ERR_NICKNAMEINUSE (433) must auto-bump
    /// the nick. Reset whenever a fresh connection starts.
    private var registered = false
    private var nickBumps = 0
    private static let maxNickBumps = 6

    func connect() {
        registered = false
        nickBumps = 0
        system(serverBuffer, "Connecting to \(config.host):\(config.port)…")
        client.connect(config: config)
    }

    func disconnect(_ quitMessage: String = "Ircle") {
        client.disconnect(quitMessage: quitMessage)
    }

    /// True when the session is connected and registered enough to send.
    var isConnected: Bool { state == .connected }

    // MARK: - Notify (friends) presence

    /// The ISON line that polls friend presence, or nil if the list is empty.
    func isonCommand() -> String? {
        let names = notifyNicks.map { $0.trimmingCharacters(in: .whitespaces) }
                               .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return "ISON " + names.joined(separator: " ")
    }

    /// Ask the server who on the notify list is online (RPL_ISON / 303 reply).
    func pollNotify() {
        guard registered, let cmd = isonCommand() else { return }
        client.send(cmd)
    }

    private func startNotifyPolling() {
        notifyTimer?.invalidate()
        pollNotify()   // immediate, so the Notify tab fills in right after connect
        notifyTimer = Timer.scheduledTimer(withTimeInterval: Self.notifyPollInterval,
                                            repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollNotify() }
        }
    }

    private func stopNotifyPolling() {
        notifyTimer?.invalidate()
        notifyTimer = nil
        onlineFriends.removeAll()
    }

    /// True if `nick` is on the notify list and currently reported online.
    func isFriendOnline(_ nick: String) -> Bool {
        onlineFriends.contains(IRCCase.fold(nick))
    }

    /// Post a client-generated system line (e.g. command feedback) to a buffer,
    /// defaulting to the server console.
    func announce(_ text: String, in buffer: IrcleBuffer? = nil) {
        system(buffer ?? serverBuffer, text)
    }

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
            registered = false
            stopNotifyPolling()
            system(serverBuffer, "Disconnected.")
            for b in buffers where b.kind == .channel { b.joined = false }
        case .failed(let reason):
            registered = false
            stopNotifyPolling()
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
        case "DCC":
            if !isSelf { handleDCCOffer(args: args, from: from) }
            return   // DCC has its own surfacing; skip the generic CTCP line
        default:
            break
        }
        system(serverBuffer, "[CTCP \(verb) from \(from)]")
    }

    /// Surface an inbound DCC offer safely. The peer address and filename are
    /// validated/sanitized by IRCKit's `DCC` engine (SSRF + path-traversal
    /// guards). Accepting/transferring is not wired yet — Stage 2.
    private func handleDCCOffer(args: String, from: String) {
        switch DCC.parseOffer(args) {
        case .offer(let o):
            switch o.kind {
            case .chat:
                line(serverBuffer, .notice, sender: from,
                     text: "wants to start a DCC chat (\(o.host):\(o.port)). "
                         + "DCC chat isn't available yet — coming soon.")
            case .send:
                let sz = ByteCountFormatter.string(fromByteCount: Int64(o.size ?? 0), countStyle: .file)
                line(serverBuffer, .notice, sender: from,
                     text: "offers a file via DCC SEND: “\(o.filename ?? "?")” (\(sz)) "
                         + "from \(o.host):\(o.port). Open DCC Transfers (⌘⇧D) to accept.")
                onDCCOffer?(o, from)
            }
            NSApplication.shared.requestUserAttention(.informationalRequest)
        case .rejectedUnsafeAddress(let token):
            line(serverBuffer, .error,
                 text: "Ignored a DCC offer from \(from): unsafe or invalid peer address (\(token)).")
        case .unsupported:
            system(serverBuffer, "[CTCP DCC from \(from): \(args)]")
        }
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
            // Ask the server for the channel modes so the Classic mode-toggle
            // row reflects current state (replies as numeric 324).
            client.send("MODE \(channel)")
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
        let chanBuf = channelBuffer(target)
        let buf = chanBuf ?? serverBuffer
        line(buf, .mode, sender: by, text: "\(by) sets mode: \(rest)")
        // Track channel-flag modes (the Classic mode-toggle row). The mode token
        // is params[1]; parameter args (params[2…]) are ignored by the parser.
        if let chanBuf, msg.params.count >= 2 {
            chanBuf.applyModeChange(msg.params[1])
        }
    }

    private func handleNumeric(_ msg: IRCMessage) {
        switch msg.command {
        case "001":
            // Server may have adjusted our nick during registration.
            if let assigned = msg.params.first { nick = assigned }
            registered = true
            line(serverBuffer, .motd, text: msg.params.last ?? "")
            // Registration is complete — fire the auto-join list.
            for chan in autoJoinChannels where !chan.isEmpty {
                client.send("JOIN \(chan)")
            }
            // Begin polling friend presence (Notify tab).
            startNotifyPolling()
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
        case "324": // RPL_CHANNELMODEIS: <me> <#chan> <modestring> [args]
            if msg.params.count >= 3, let buf = channelBuffer(msg.params[1]) {
                buf.setModes(msg.params[2])
            }
        case "329": // RPL_CREATIONTIME — ignore
            break
        case "303": // RPL_ISON: trailing param = space-separated online nicks
            let online = (msg.params.last ?? "")
                .split(separator: " ").map { IRCCase.fold(String($0)) }
            onlineFriends = Set(online)
        case "305": // RPL_UNAWAY — no longer marked away
            isAway = false
            system(serverBuffer, msg.params.last ?? "You are no longer marked as away.")
        case "306": // RPL_NOWAWAY — now marked away
            isAway = true
            system(serverBuffer, msg.params.last ?? "You have been marked as away.")
        case "375", "372", "376", "002", "003", "004", "005", "251", "252",
             "253", "254", "255", "265", "266", "250", "375L":
            line(serverBuffer, .motd, text: msg.params.last ?? "")
        case "433": // ERR_NICKNAMEINUSE
            let attempted = msg.params.count > 1 ? msg.params[1] : nick
            // Auto-bump the nick during registration (before RPL_WELCOME) — this
            // is the common case when a second server reuses a nick already
            // taken on that network. Without this, registration stalls and the
            // connection never completes. Bump a bounded number of times, then
            // give up and surface the error so the user can pick another nick.
            if !registered && nickBumps < Self.maxNickBumps {
                nickBumps += 1
                let alt = attempted + "_"
                nick = alt
                line(serverBuffer, .error, text: "Nickname \(attempted) is in use — trying \(alt)…")
                client.send("NICK \(alt)")
            } else {
                line(serverBuffer, .error, text: "Nickname \(attempted) is in use.")
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
        case "AWAY":
            // `/away <msg>` marks away; bare `/away` clears it. Server confirms
            // via 306 (now away) / 305 (no longer away).
            if rest.isEmpty { client.send("AWAY") }
            else { client.send("AWAY :\(rest)") }
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
        let focused = buffer === focusedBuffer
        buffer.append(l, focused: focused)
        maybeNotify(kind: kind, buffer: buffer, sender: sender, text: text,
                    isSelf: isSelf, isMention: isMention, focused: focused)
        // Persist channel/query transcripts (server-console noise is skipped).
        if buffer.kind != .server {
            LogService.shared.log(network: displayName, target: buffer.name,
                                  line: MessageRow.plain(l, showTimestamps: false))
        }
    }

    /// Post a macOS notification for a mention or a private message that arrives
    /// while you're not actively looking at it (different buffer, or app in the
    /// background). Gated on the global setting (mirrored into `notificationsEnabled`).
    private func maybeNotify(kind: LineKind, buffer: IrcleBuffer, sender: String?,
                             text: String, isSelf: Bool, isMention: Bool, focused: Bool) {
        guard notificationsEnabled, kind == .message, !isSelf else { return }
        let isPM = buffer.kind == .query
        guard isMention || isPM else { return }
        // If you're already reading this buffer in the frontmost window, stay quiet.
        if focused && NSApplication.shared.isActive { return }
        let who = sender ?? "?"
        let title = isPM ? "Private message — \(who)" : "\(who) in \(buffer.name)"
        NotificationService.post(title: title,
                                 body: IRCText.stripFormatting(text),
                                 id: "ircle.\(buffer.id.uuidString)")
    }

    private func system(_ buffer: IrcleBuffer, _ text: String) {
        line(buffer, .system, text: text)
    }
}
