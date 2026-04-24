import Foundation
import Combine
import AppKit

/// Forward-compat event stream. Every inbound IRC message, every state
/// transition, and the outbound lines we emit fan out through this enum so
/// the eventual PurpleBot scripting host (and any future listeners) can
/// subscribe without touching core dispatch. Kept `Sendable` so a bot context
/// off the main actor can consume events safely.
enum IRCConnectionEvent: Sendable {
    case state(IRCConnectionState)
    case inbound(IRCMessage)
    case outbound(String)
    case ownNickChanged(String)
    case privmsg(from: String, target: String, text: String, isAction: Bool, isMention: Bool)
    case notice(from: String, target: String, text: String)
    case join(nick: String, channel: String, isSelf: Bool)
    case part(nick: String, channel: String, reason: String?, isSelf: Bool)
    case quit(nick: String, reason: String?)
    case topic(channel: String, topic: String, setter: String?)
    case ctcpRequest(from: String, target: String, command: String, args: String)
    case awayChanged(isAway: Bool, reason: String?)
    case ignoredMessage(from: String, target: String)
}

/// One IRC connection: owns its `IRCClient`, its buffers, its watchlist
/// reference, reconnect bookkeeping, and a `PassthroughSubject` of events.
/// ChatModel holds a list of these; each event always carries the network id.
@MainActor
final class IRCConnection: ObservableObject, Identifiable {
    let id: UUID = UUID()

    @Published var profile: ServerProfile
    @Published var state: IRCConnectionState = .disconnected
    @Published var nick: String = ""
    @Published var buffers: [Buffer] = []
    @Published var selectedBufferID: Buffer.ID?
    @Published var rawLog: [String] = []

    /// Away state for this network.
    @Published private(set) var isAway: Bool = false
    @Published private(set) var awayReason: String?

    /// Shared across all connections — ChatModel owns the single instance and
    /// routes its delegate calls to the right connection.
    let watchlist: WatchlistService

    /// Fanout of everything that happens on this connection. PurpleBot's
    /// scripting host will subscribe to this later. The stream keeps no
    /// replay buffer — late subscribers miss older events.
    let events = PassthroughSubject<(UUID, IRCConnectionEvent), Never>()

    /// Label shown in the sidebar. Falls back to host when profile name is empty.
    var displayName: String {
        profile.name.isEmpty ? profile.host : profile.name
    }

    private let client = IRCClient()
    private var serverBufferID: Buffer.ID?
    private var haveRegisteredWatchlist = false

    private var userInitiatedDisconnect = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    private(set) var saslActive = false

    // Tier 2 knobs — ChatModel pushes these in from settings.
    var highlightOnOwnNick: Bool = true
    var ignoreMatchers: [IgnoreEntry] = []
    var ctcpRepliesEnabled: Bool = true
    var ctcpVersionString: String = "PurpleIRC"
    var autoReplyWhenAway: Bool = true
    var awayAutoReply: String = ""

    // Log writer. ChatModel injects a shared LogStore; nil means no logging.
    var logStore: LogStore?
    var loggingEnabled: Bool = false
    var logNoisyLines: Bool = false

    /// DCC service. ChatModel injects the shared instance so /dcc and
    /// incoming CTCP DCC offers can route to the transfers window.
    weak var dcc: DCCService?

    // Throttle for away auto-replies so a spammer can't DoS us.
    private var lastAwayReplyAt: [String: Date] = [:]
    private static let awayReplyInterval: TimeInterval = 120 // seconds per-nick

    init(profile: ServerProfile, watchlist: WatchlistService) {
        self.profile = profile
        self.watchlist = watchlist
        self.nick = profile.nick
        client.onMessage = { [weak self] msg in
            Task { @MainActor in self?.handle(msg) }
        }
        client.onState = { [weak self] s in
            Task { @MainActor in self?.handleState(s) }
        }
        client.onRaw = { [weak self] line, outbound in
            Task { @MainActor in
                guard let self else { return }
                let prefix = outbound ? ">> " : "<< "
                self.rawLog.append(prefix + line)
                if self.rawLog.count > 2000 {
                    self.rawLog.removeFirst(self.rawLog.count - 2000)
                }
                if outbound {
                    self.emit(.outbound(line))
                }
            }
        }
    }

    // MARK: - Public control

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        userInitiatedDisconnect = false

        guard let portNum = UInt16(exactly: profile.port) else {
            appendError("Invalid port on \(profile.name): \(profile.port)")
            return
        }
        self.nick = profile.nick
        appendInfo("Connecting to \(profile.name) (\(profile.host):\(portNum), TLS=\(profile.useTLS))…")
        if profile.saslMechanism != .none {
            appendInfo("SASL \(profile.saslMechanism.rawValue) will be attempted after CAP negotiation.")
        }

        let proxyPort = UInt16(exactly: profile.proxyPort) ?? 0
        if profile.proxyType != .none {
            appendInfo("Via \(profile.proxyType.displayName) proxy \(profile.proxyHost):\(profile.proxyPort).")
        }
        let config = IRCConnectionConfig(
            host: profile.host,
            port: portNum,
            useTLS: profile.useTLS,
            nick: profile.nick,
            user: profile.user.isEmpty ? "purpleirc" : profile.user,
            realName: profile.realName.isEmpty ? "PurpleIRC" : profile.realName,
            serverPassword: profile.password.isEmpty ? nil : profile.password,
            saslMechanism: profile.saslMechanism,
            saslAccount: profile.saslAccount,
            saslPassword: profile.saslPassword,
            proxyType: profile.proxyType,
            proxyHost: profile.proxyHost,
            proxyPort: proxyPort,
            proxyUsername: profile.proxyUsername,
            proxyPassword: profile.proxyPassword
        )
        client.connect(config: config)
    }

    func disconnect() {
        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        client.disconnect(quitMessage: "PurpleIRC signing off")
    }

    /// Public outbound. Bot scripting will call this path.
    func sendRaw(_ line: String) {
        client.send(line)
    }

    func sendInput(_ text: String, from selectedBuffer: Buffer.ID?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("/") {
            handleCommand(String(trimmed.dropFirst()), selection: selectedBuffer)
            return
        }

        guard let bufID = selectedBuffer,
              let bufIdx = buffers.firstIndex(where: { $0.id == bufID }) else {
            return
        }
        let buf = buffers[bufIdx]
        guard buf.kind != .server else {
            buffers[bufIdx].appendInfo("Cannot send message in server buffer. Use a channel or /msg <nick> <text>.")
            return
        }
        client.send("PRIVMSG \(buf.name) :\(trimmed)")
        appendTo(bufferIndex: bufIdx, line: ChatLine(
            timestamp: Date(),
            kind: .privmsg(nick: nick, isSelf: true),
            text: trimmed
        ))
    }

    func closeBuffer(id: Buffer.ID) {
        guard let i = buffers.firstIndex(where: { $0.id == id }) else { return }
        let buf = buffers[i]
        guard buf.kind != .server else { return }
        if buf.kind == .channel, state == .connected {
            client.send("PART \(buf.name) :closed")
        }
        buffers.remove(at: i)
        if selectedBufferID == id { selectedBufferID = buffers.first?.id }
    }

    func quickJoin(_ channel: String) {
        let name = channel.hasPrefix("#") ? channel : "#" + channel
        if state == .connected {
            client.send("JOIN \(name)")
        } else {
            appendError("Not connected — connect first.")
        }
    }

    func selectBuffer(_ id: Buffer.ID) {
        selectedBufferID = id
        if let i = buffers.firstIndex(where: { $0.id == id }) {
            buffers[i].unread = 0
        }
    }

    func applyAlertOptions(sound: Bool, dock: Bool, banner: Bool, highlight: Bool) {
        watchlist.playSound = sound
        watchlist.bounceDock = dock
        watchlist.systemNotifications = banner
        highlightOnOwnNick = highlight
    }

    /// Convenience used by the channel-mode UI. Sends a MODE line for the
    /// target channel and mode string, or no-op if not in a channel.
    func setMode(on channel: String, modes: String, arg: String? = nil) {
        guard state == .connected else { return }
        if let arg {
            client.send("MODE \(channel) \(modes) \(arg)")
        } else {
            client.send("MODE \(channel) \(modes)")
        }
    }

    // MARK: - Away

    /// Set or clear the away state on this network. Empty/nil reason clears.
    func setAway(reason: String?) {
        if let reason, !reason.trimmingCharacters(in: .whitespaces).isEmpty {
            isAway = true
            awayReason = reason
            client.send("AWAY :\(reason)")
            appendInfo("You are marked AWAY: \(reason)")
        } else {
            isAway = false
            awayReason = nil
            client.send("AWAY")
            appendInfo("You are no longer away.")
        }
        emit(.awayChanged(isAway: isAway, reason: awayReason))
    }

    // MARK: - State handling

    private func handleState(_ s: IRCConnectionState) {
        state = s
        switch s {
        case .connecting: appendInfo("Connecting…")
        case .connected:  appendInfo("TCP established. Authenticating…")
        case .disconnected:
            appendInfo("Disconnected.")
            haveRegisteredWatchlist = false
            watchlist.onDisconnected()
            scheduleReconnectIfNeeded()
        case .failed(let err):
            appendError("Connection failed: \(err)")
            haveRegisteredWatchlist = false
            watchlist.onDisconnected()
            scheduleReconnectIfNeeded()
        }
        emit(.state(s))
    }

    private func scheduleReconnectIfNeeded() {
        if userInitiatedDisconnect { return }
        guard profile.autoReconnect else { return }
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        let base: Double = [0, 2, 4, 8, 16, 30, 30][reconnectAttempt]
        let jitter = Double.random(in: 0.75...1.25)
        let delay = base * jitter

        appendInfo(String(format: "Reconnecting in %.1fs (attempt %d)…", delay, reconnectAttempt))

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                if self.userInitiatedDisconnect { return }
                self.connect()
            }
        }
    }

    // MARK: - Message handling

    private func handle(_ msg: IRCMessage) {
        emit(.inbound(msg))
        switch msg.command {
        case "PING":
            let token = msg.params.first ?? ""
            client.send("PONG :\(token)")
            return
        case "PRIVMSG":
            handlePrivmsg(msg, isNotice: false)
        case "NOTICE":
            handlePrivmsg(msg, isNotice: true)
        case "JOIN":
            handleJoin(msg)
        case "PART":
            handlePart(msg)
        case "QUIT":
            handleQuit(msg)
        case "NICK":
            handleNickChange(msg)
        case "TOPIC":
            handleTopic(msg)
        case "KICK":
            handleKick(msg)
        case "MODE":
            handleMode(msg)
        case "ERROR":
            let txt = msg.params.joined(separator: " ")
            appendError("ERROR: \(txt)")
        case "CAP", "AUTHENTICATE":
            logNumeric(msg)
        case "001":
            if msg.params.count >= 1 {
                self.nick = msg.params[0]
                emit(.ownNickChanged(self.nick))
            }
            logNumeric(msg)
            reconnectAttempt = 0
        case "301":
            // RPL_AWAYMSG — msg.params: [me, nick, "is away: <reason>"]
            if msg.params.count >= 3 {
                let who = msg.params[1]
                let why = msg.params[2]
                appendInfo("\(who) is away: \(why)")
            }
        case "305": // unaway
            isAway = false
            awayReason = nil
            emit(.awayChanged(isAway: false, reason: nil))
            logNumeric(msg)
        case "306": // away set
            isAway = true
            if awayReason == nil {
                awayReason = profile.realName.isEmpty ? "away" : "away"
            }
            emit(.awayChanged(isAway: true, reason: awayReason))
            logNumeric(msg)
        case "353":
            handleNames(msg)
        case "366":
            break
        case "332":
            if msg.params.count >= 3 {
                let chan = msg.params[1]
                let topic = msg.params[2]
                if let i = buffers.firstIndex(where: { $0.name == chan }) {
                    buffers[i].topic = topic
                    appendTo(bufferIndex: i, line: ChatLine(
                        timestamp: Date(),
                        kind: .topic(setter: nil),
                        text: "Topic: \(topic)"
                    ))
                    emit(.topic(channel: chan, topic: topic, setter: nil))
                }
            }
        case "005":
            let tokens = Array(msg.params.dropFirst().dropLast())
            watchlist.handleISupport(tokens)
            logNumeric(msg)
        case "376", "422":
            logNumeric(msg)
            if !haveRegisteredWatchlist {
                haveRegisteredWatchlist = true
                watchlist.onWelcomeCompleted()
                runPostWelcome()
            }
        case "372", "375", "371", "002", "003", "004", "250", "251", "252", "253", "254", "255", "265", "266":
            logNumeric(msg)
        case "303":
            let names = (msg.params.last ?? "")
                .split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            watchlist.handleISON(names)
        case "730":
            watchlist.handleMonitorOnline(monitorTargets(from: msg))
        case "731":
            watchlist.handleMonitorOffline(monitorTargets(from: msg))
        case "732", "733", "734":
            logNumeric(msg)
        case "900", "901", "902", "903", "904", "905", "906", "907":
            logNumeric(msg)
        case "433":
            let alt = self.nick + "_"
            appendError("Nickname in use. Trying \(alt)")
            client.send("NICK \(alt)")
        default:
            logNumeric(msg)
        }
    }

    private func monitorTargets(from msg: IRCMessage) -> [String] {
        guard let payload = msg.params.last else { return [] }
        return payload.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func handlePrivmsg(_ msg: IRCMessage, isNotice: Bool) {
        guard msg.params.count >= 2 else { return }
        let target = msg.params[0]
        var text = msg.params[1]
        let from = msg.nickFromPrefix ?? msg.prefix ?? "?"
        let fullPrefix = msg.prefix ?? from

        let isCTCP = text.hasPrefix("\u{01}") && text.hasSuffix("\u{01}") && text.count >= 2

        // Ignore filter — silently drop matching messages (we still emit an
        // event so future bot scripts see the drop; core UI is unaffected).
        if ignoreMatches(from: from, fullPrefix: fullPrefix,
                         isNotice: isNotice, isCTCP: isCTCP) {
            emit(.ignoredMessage(from: from, target: target))
            return
        }

        if !isNotice {
            watchlist.handleObservedActivity(nick: from, reason: "message")
        }

        // CTCP handling (everything wrapped in \u0001 except ACTION).
        if isCTCP {
            let body = String(text.dropFirst().dropLast())
            let (cmd, args) = splitCTCP(body)
            emit(.ctcpRequest(from: from, target: target, command: cmd, args: args))

            if cmd.uppercased() == "ACTION" {
                // Fall through to the action-rendering path below.
                text = "\u{01}ACTION \(args)\u{01}"
            } else if cmd.uppercased() == "DCC", !isNotice,
                      let svc = dcc,
                      svc.handleIncomingDCC(connection: self, from: from, args: args) {
                // DCC offer consumed; don't echo as a raw CTCP request.
                return
            } else {
                // Respond to a CTCP request (NOT a CTCP reply we received via
                // NOTICE). Requests come as PRIVMSG — NOTICEs carrying \u0001
                // are replies and must not trigger another reply.
                if !isNotice, ctcpRepliesEnabled {
                    sendCTCPReply(to: from, command: cmd, args: args)
                }
                // Log requests/replies to server buffer for visibility.
                let kind = isNotice ? "CTCP reply" : "CTCP request"
                appendInfo("\(kind) \(cmd) from \(from): \(args)")
                return
            }
        }

        let isToSelf = target.lowercased() == self.nick.lowercased()
        let bufferName = isToSelf ? from : target
        let kind: Buffer.Kind = target.hasPrefix("#") ? .channel : .query

        let plainForMatch = IRCFormatter.stripCodes(text)
        let mention = !isNotice
            && from.lowercased() != self.nick.lowercased()
            && highlightOnOwnNick
            && Self.containsOwnNick(self.nick, in: plainForMatch)

        // CTCP ACTION rendering
        if text.hasPrefix("\u{01}ACTION "), text.hasSuffix("\u{01}") {
            text = String(text.dropFirst(8).dropLast())
            let bIdx = indexOfOrCreateBuffer(name: bufferName, kind: kind)
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .action(nick: from),
                text: text,
                isMention: mention
            ))
            markUnread(at: bIdx)
            emit(.privmsg(from: from, target: bufferName, text: text, isAction: true, isMention: mention))
            if mention {
                watchlist.fireHighlightAlert(nick: from, channel: bufferName, text: "* \(from) \(IRCFormatter.stripCodes(text))")
            }
            maybeSendAwayAutoReply(to: from, target: target, isNotice: false)
            return
        }

        let bIdx = indexOfOrCreateBuffer(name: bufferName, kind: kind)
        if isNotice {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .notice(from: from),
                text: text
            ))
            emit(.notice(from: from, target: bufferName, text: text))
        } else {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .privmsg(nick: from, isSelf: false),
                text: text,
                isMention: mention
            ))
            emit(.privmsg(from: from, target: bufferName, text: text, isAction: false, isMention: mention))
        }
        markUnread(at: bIdx)

        if mention {
            watchlist.fireHighlightAlert(nick: from, channel: bufferName, text: IRCFormatter.stripCodes(text))
        }

        // Away auto-reply to direct PMs (not notices, not channel traffic).
        if !isNotice {
            maybeSendAwayAutoReply(to: from, target: target, isNotice: false)
        }
    }

    private func splitCTCP(_ body: String) -> (String, String) {
        if let spaceIdx = body.firstIndex(of: " ") {
            return (String(body[..<spaceIdx]), String(body[body.index(after: spaceIdx)...]))
        }
        return (body, "")
    }

    private func handleDCCCommand(_ rest: String) {
        guard let svc = dcc else {
            appendError("DCC service unavailable.")
            return
        }
        let bits = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard let subRaw = bits.first else {
            appendInfo("Usage: /dcc send <nick> [path]  |  /dcc chat <nick>")
            return
        }
        let sub = subRaw.lowercased()
        switch sub {
        case "send":
            guard bits.count >= 2 else {
                appendInfo("Usage: /dcc send <nick> [path]")
                return
            }
            let nick = bits[1]
            let providedPath = bits.count >= 3 ? bits[2].trimmingCharacters(in: .whitespaces) : ""
            if !providedPath.isEmpty {
                let url = URL(fileURLWithPath: (providedPath as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    appendError("File not found: \(url.path)")
                    return
                }
                svc.offerSend(to: nick, fileURL: url, on: self)
            } else {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.allowsMultipleSelection = false
                panel.begin { [weak self] resp in
                    guard let self, resp == .OK, let url = panel.url else { return }
                    Task { @MainActor in
                        svc.offerSend(to: nick, fileURL: url, on: self)
                    }
                }
            }
        case "chat":
            guard bits.count >= 2 else {
                appendInfo("Usage: /dcc chat <nick>")
                return
            }
            svc.offerChat(to: bits[1], on: self)
        case "list":
            chatModelShowDCC()
        default:
            appendInfo("Usage: /dcc send <nick> [path]  |  /dcc chat <nick>  |  /dcc list")
        }
    }

    private func chatModelShowDCC() {
        dcc?.chatModel?.showDCC = true
    }

    private func sendCTCPReply(to nick: String, command: String, args: String) {
        let up = command.uppercased()
        let reply: String?
        switch up {
        case "VERSION":
            reply = "VERSION \(ctcpVersionString)"
        case "PING":
            // Echo back the args verbatim (usually a timestamp).
            reply = args.isEmpty ? "PING" : "PING \(args)"
        case "TIME":
            let df = DateFormatter()
            df.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            df.locale = Locale(identifier: "en_US_POSIX")
            reply = "TIME \(df.string(from: Date()))"
        case "FINGER":
            reply = "FINGER \(profile.realName.isEmpty ? "PurpleIRC user" : profile.realName)"
        case "SOURCE":
            reply = "SOURCE https://github.com/bronty13/PhantomLives"
        case "USERINFO":
            reply = "USERINFO \(profile.realName.isEmpty ? profile.nick : profile.realName)"
        case "CLIENTINFO":
            reply = "CLIENTINFO ACTION CLIENTINFO FINGER PING SOURCE TIME USERINFO VERSION"
        default:
            reply = nil
        }
        guard let body = reply else { return }
        client.send("NOTICE \(nick) :\u{01}\(body)\u{01}")
    }

    private func maybeSendAwayAutoReply(to from: String, target: String, isNotice: Bool) {
        guard isAway, autoReplyWhenAway, !isNotice else { return }
        // Only for direct PMs (target is our nick), not channel traffic.
        guard target.lowercased() == self.nick.lowercased() else { return }
        guard !from.isEmpty, from.lowercased() != self.nick.lowercased() else { return }
        let now = Date()
        if let last = lastAwayReplyAt[from.lowercased()],
           now.timeIntervalSince(last) < Self.awayReplyInterval { return }
        lastAwayReplyAt[from.lowercased()] = now
        let msg = awayAutoReply.isEmpty ? "I am away." : awayAutoReply
        client.send("NOTICE \(from) :[away] \(msg)")
    }

    /// True when the sender matches any configured ignore entry, honoring
    /// the entry's per-scope toggles (CTCP / notices) and falling back to
    /// "match the nick" when no full prefix is available.
    private func ignoreMatches(from: String, fullPrefix: String,
                               isNotice: Bool, isCTCP: Bool) -> Bool {
        guard !ignoreMatchers.isEmpty else { return false }
        for e in ignoreMatchers {
            let mask = e.mask.trimmingCharacters(in: .whitespaces)
            if mask.isEmpty { continue }
            if !glob(mask.lowercased(), matches: fullPrefix.lowercased())
                && !glob(mask.lowercased(), matches: from.lowercased()) { continue }
            if isCTCP && !e.ignoreCTCP { continue }
            if isNotice && !e.ignoreNotices { continue }
            return true
        }
        return false
    }

    /// Simple glob matcher — supports `*` (any run) and `?` (single char).
    /// Case-insensitive (caller must have already lowercased).
    private func glob(_ pattern: String, matches text: String) -> Bool {
        let p = Array(pattern); let t = Array(text)
        func m(_ pi: Int, _ ti: Int) -> Bool {
            if pi == p.count { return ti == t.count }
            let pc = p[pi]
            if pc == "*" {
                if pi + 1 == p.count { return true }
                var k = ti
                while k <= t.count {
                    if m(pi + 1, k) { return true }
                    k += 1
                }
                return false
            }
            if ti == t.count { return false }
            if pc == "?" || pc == t[ti] { return m(pi + 1, ti + 1) }
            return false
        }
        return m(0, 0)
    }

    private static func containsOwnNick(_ nick: String, in text: String) -> Bool {
        guard !nick.isEmpty else { return false }
        let lowerText = text.lowercased()
        let lowerNick = nick.lowercased()
        var search = lowerText.startIndex
        while search < lowerText.endIndex,
              let r = lowerText.range(of: lowerNick, range: search..<lowerText.endIndex) {
            let before = r.lowerBound == lowerText.startIndex ? nil : lowerText[lowerText.index(before: r.lowerBound)]
            let after = r.upperBound == lowerText.endIndex ? nil : lowerText[r.upperBound]
            if !isNickChar(before) && !isNickChar(after) { return true }
            search = lowerText.index(after: r.lowerBound)
        }
        return false
    }

    private static func isNickChar(_ c: Character?) -> Bool {
        guard let c else { return false }
        if c.isLetter || c.isNumber { return true }
        return "-_[]{}\\|^".contains(c)
    }

    private func handleJoin(_ msg: IRCMessage) {
        guard let chan = msg.params.first, let who = msg.nickFromPrefix else { return }
        let bIdx = indexOfOrCreateBuffer(name: chan, kind: .channel)
        let isSelf = who.lowercased() == self.nick.lowercased()
        if isSelf {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(), kind: .info, text: "You joined \(chan)"))
            selectedBufferID = buffers[bIdx].id
        } else {
            watchlist.handleObservedActivity(nick: who, reason: "JOIN \(chan)")
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .join(nick: who),
                text: "\(who) joined"
            ))
            if !buffers[bIdx].users.contains(who) {
                buffers[bIdx].users.append(who)
                buffers[bIdx].users.sort()
            }
        }
        emit(.join(nick: who, channel: chan, isSelf: isSelf))
    }

    private func handlePart(_ msg: IRCMessage) {
        guard let chan = msg.params.first, let who = msg.nickFromPrefix else { return }
        let reason = msg.params.count > 1 ? msg.params[1] : nil
        guard let bIdx = buffers.firstIndex(where: { $0.name == chan }) else { return }
        let isSelf = who.lowercased() == self.nick.lowercased()
        if isSelf {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(), kind: .info, text: "You left \(chan)"))
            buffers[bIdx].users.removeAll()
        } else {
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .part(nick: who, reason: reason),
                text: "\(who) left" + (reason.map { " (\($0))" } ?? "")
            ))
            buffers[bIdx].users.removeAll(where: { $0 == who })
        }
        emit(.part(nick: who, channel: chan, reason: reason, isSelf: isSelf))
    }

    private func handleQuit(_ msg: IRCMessage) {
        guard let who = msg.nickFromPrefix else { return }
        let reason = msg.params.first
        for i in buffers.indices where buffers[i].users.contains(who) {
            buffers[i].users.removeAll(where: { $0 == who })
            appendTo(bufferIndex: i, line: ChatLine(
                timestamp: Date(),
                kind: .quit(nick: who, reason: reason),
                text: "\(who) quit" + (reason.map { " (\($0))" } ?? "")
            ))
        }
        emit(.quit(nick: who, reason: reason))
    }

    private func handleNickChange(_ msg: IRCMessage) {
        guard let old = msg.nickFromPrefix, let new = msg.params.first else { return }
        if old.lowercased() == self.nick.lowercased() {
            self.nick = new
            emit(.ownNickChanged(new))
        }
        for i in buffers.indices {
            if let u = buffers[i].users.firstIndex(of: old) {
                buffers[i].users[u] = new
                buffers[i].users.sort()
                appendTo(bufferIndex: i, line: ChatLine(
                    timestamp: Date(),
                    kind: .nick(old: old, new: new),
                    text: "\(old) is now known as \(new)"
                ))
            }
        }
    }

    private func handleTopic(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let chan = msg.params[0]
        let topic = msg.params[1]
        let who = msg.nickFromPrefix
        guard let i = buffers.firstIndex(where: { $0.name == chan }) else { return }
        buffers[i].topic = topic
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(),
            kind: .topic(setter: who),
            text: (who.map { "\($0) set topic: " } ?? "Topic: ") + topic
        ))
        emit(.topic(channel: chan, topic: topic, setter: who))
    }

    private func handleKick(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let chan = msg.params[0]
        let target = msg.params[1]
        let reason = msg.params.count > 2 ? msg.params[2] : nil
        let by = msg.nickFromPrefix ?? "?"
        guard let i = buffers.firstIndex(where: { $0.name == chan }) else { return }
        buffers[i].users.removeAll(where: { $0 == target })
        let text = "\(target) was kicked by \(by)" + (reason.map { " (\($0))" } ?? "")
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(), kind: .info, text: text))
    }

    /// We surface mode changes in the affected channel for visibility. The
    /// state of mode flags on individual nicks (op/voice) is not tracked
    /// yet beyond sidebar display; future work.
    private func handleMode(_ msg: IRCMessage) {
        guard msg.params.count >= 2 else { return }
        let target = msg.params[0]
        let modeLine = msg.params.dropFirst().joined(separator: " ")
        let by = msg.nickFromPrefix ?? "server"
        if let i = buffers.firstIndex(where: { $0.name == target }) {
            appendTo(bufferIndex: i, line: ChatLine(
                timestamp: Date(), kind: .info, text: "\(by) sets mode \(modeLine)"))
        } else {
            appendInfo("\(by) sets mode \(target) \(modeLine)")
        }
    }

    private func handleNames(_ msg: IRCMessage) {
        guard msg.params.count >= 4 else { return }
        let chan = msg.params[2]
        let names = msg.params[3].split(separator: " ").map { String($0) }
        guard let i = buffers.firstIndex(where: { $0.name == chan }) else { return }
        let cleaned = names.map { $0.drop(while: { "@+%&~".contains($0) }) }.map(String.init)
        var set = Set(buffers[i].users)
        for n in cleaned { set.insert(n) }
        buffers[i].users = Array(set).sorted()
    }

    private func logNumeric(_ msg: IRCMessage) {
        let i = idx(of: ensureServerBufferID())
        let text = msg.params.dropFirst().joined(separator: " ")
        let kind: ChatLine.Kind = (msg.command == "372" || msg.command == "375" || msg.command == "376") ? .motd : .info
        appendTo(bufferIndex: i, line: ChatLine(
            timestamp: Date(),
            kind: kind,
            text: text.isEmpty ? msg.raw : text
        ))
    }

    // MARK: - Commands

    private func handleCommand(_ raw: String, selection: Buffer.ID?) {
        var parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return }
        let cmd = parts.removeFirst().lowercased()
        let rest = parts.first ?? ""

        func currentBufferName() -> String? {
            guard let id = selection, let buf = buffers.first(where: { $0.id == id }) else { return nil }
            return buf.kind == .server ? nil : buf.name
        }

        switch cmd {
        case "disconnect", "quit":
            userInitiatedDisconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            if rest.isEmpty { client.disconnect() } else { client.disconnect(quitMessage: rest) }
        case "connect":
            connect()
        case "join", "j":
            let target = rest.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return }
            client.send("JOIN \(target)")
        case "part":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let target = bits.first ?? currentBufferName() ?? ""
            let reason = bits.count > 1 ? bits[1] : nil
            guard !target.isEmpty else { return }
            if let r = reason { client.send("PART \(target) :\(r)") }
            else { client.send("PART \(target)") }
        case "msg":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard bits.count == 2 else { return }
            let target = bits[0]; let text = bits[1]
            client.send("PRIVMSG \(target) :\(text)")
            let bIdx = indexOfOrCreateBuffer(name: target, kind: target.hasPrefix("#") ? .channel : .query)
            appendTo(bufferIndex: bIdx, line: ChatLine(
                timestamp: Date(),
                kind: .privmsg(nick: nick, isSelf: true),
                text: text))
            selectedBufferID = buffers[bIdx].id
        case "query":
            let target = rest.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return }
            let bIdx = indexOfOrCreateBuffer(name: target, kind: target.hasPrefix("#") ? .channel : .query)
            selectedBufferID = buffers[bIdx].id
        case "me":
            guard let target = currentBufferName(), !rest.isEmpty else { return }
            let ctcp = "\u{01}ACTION \(rest)\u{01}"
            client.send("PRIVMSG \(target) :\(ctcp)")
            if let bIdx = buffers.firstIndex(where: { $0.name == target }) {
                appendTo(bufferIndex: bIdx, line: ChatLine(
                    timestamp: Date(), kind: .action(nick: nick), text: rest))
            }
        case "nick":
            guard !rest.isEmpty else { return }
            client.send("NICK \(rest)")
        case "topic":
            guard let target = currentBufferName() else { return }
            if rest.isEmpty { client.send("TOPIC \(target)") }
            else { client.send("TOPIC \(target) :\(rest)") }
        case "raw", "quote":
            client.send(rest)
        case "close":
            if let sel = selection { closeBuffer(id: sel) }
        case "names":
            if let target = currentBufferName() { client.send("NAMES \(target)") }
        case "whois":
            guard !rest.isEmpty else { return }
            client.send("WHOIS \(rest)")
        case "away":
            setAway(reason: rest.trimmingCharacters(in: .whitespaces).isEmpty ? nil : rest)
        case "back":
            setAway(reason: nil)
        case "op", "deop", "voice", "devoice":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            let mode: String = {
                switch cmd {
                case "op": return "+o"
                case "deop": return "-o"
                case "voice": return "+v"
                case "devoice": return "-v"
                default: return ""
                }
            }()
            client.send("MODE \(chan) \(mode) \(rest)")
        case "kick":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let who = bits[0]
            if bits.count > 1 {
                client.send("KICK \(chan) \(who) :\(bits[1])")
            } else {
                client.send("KICK \(chan) \(who)")
            }
        case "ban":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            client.send("MODE \(chan) +b \(rest)")
        case "unban":
            guard let chan = currentBufferName(), chan.hasPrefix("#"),
                  !rest.isEmpty else { return }
            client.send("MODE \(chan) -b \(rest)")
        case "mode":
            if rest.isEmpty, let chan = currentBufferName() { client.send("MODE \(chan)") }
            else { client.send("MODE \(rest)") }
        case "ctcp":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard bits.count >= 2 else { return }
            let target = bits[0]
            let body = bits[1]
            client.send("PRIVMSG \(target) :\u{01}\(body)\u{01}")
        case "dcc":
            handleDCCCommand(rest)
        default:
            client.send("\(cmd.uppercased()) \(rest)")
        }
    }

    // MARK: - Post-welcome

    private func runPostWelcome() {
        if profile.saslMechanism == .none, !profile.nickServPassword.isEmpty {
            client.send("PRIVMSG NickServ :IDENTIFY \(profile.nickServPassword)")
            appendInfo("Sent NickServ IDENTIFY.")
        }
        let lines = profile.performOnConnect
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines {
            if line.hasPrefix("/") {
                handleCommand(String(line.dropFirst()), selection: selectedBufferID)
            } else {
                client.send(line)
            }
        }
        autoJoinIfNeeded()
        // Re-assert away status after reconnect.
        if isAway, let reason = awayReason {
            client.send("AWAY :\(reason)")
        }
    }

    private func autoJoinIfNeeded() {
        let profileChans = profile.autoJoin
            .split { $0 == "," || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        for raw in profileChans {
            let name = raw.hasPrefix("#") ? raw : "#" + raw
            guard seen.insert(name.lowercased()).inserted else { continue }
            client.send("JOIN \(name)")
        }
    }

    func joinSavedChannels(_ names: [String]) {
        guard state == .connected else { return }
        var seen = Set<String>()
        for raw in names {
            let name = raw.hasPrefix("#") ? raw : "#" + raw
            guard seen.insert(name.lowercased()).inserted else { continue }
            client.send("JOIN \(name)")
        }
    }

    // MARK: - Buffer helpers

    @discardableResult
    func ensureServerBufferID() -> Buffer.ID {
        if let id = serverBufferID, buffers.contains(where: { $0.id == id }) {
            return id
        }
        let buf = Buffer(name: "*server*", kind: .server)
        buffers.append(buf)
        serverBufferID = buf.id
        if selectedBufferID == nil { selectedBufferID = buf.id }
        return buf.id
    }

    private func indexOfOrCreateBuffer(name: String, kind: Buffer.Kind) -> Int {
        if let i = buffers.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            return i
        }
        let buf = Buffer(name: name, kind: kind)
        buffers.append(buf)
        return buffers.count - 1
    }

    private func idx(of id: Buffer.ID) -> Int {
        buffers.firstIndex(where: { $0.id == id })!
    }

    private func markUnread(at i: Int) {
        if buffers[i].id != selectedBufferID {
            buffers[i].unread += 1
        }
    }

    /// Append a line to a buffer AND, when persistence is enabled, write it
    /// to the on-disk log. The file write happens on a detached Task so it
    /// never blocks the main actor or the buffer mutation.
    private func appendTo(bufferIndex i: Int, line: ChatLine) {
        guard i < buffers.count else { return }
        buffers[i].appendLine(line)
        if loggingEnabled, let store = logStore {
            if !logNoisyLines, line.isNoisyLogKind { return }
            let network = displayName
            let buffer = buffers[i].name
            let text = line.toLogLine()
            Task.detached(priority: .utility) {
                await store.append(network: network, buffer: buffer, line: text)
            }
        }
    }

    private func appendInfo(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        appendTo(bufferIndex: i, line: ChatLine(timestamp: Date(), kind: .info, text: text))
    }

    private func appendError(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        appendTo(bufferIndex: i, line: ChatLine(timestamp: Date(), kind: .error, text: text))
    }

    private func emit(_ event: IRCConnectionEvent) {
        events.send((id, event))
    }
}

extension IRCConnection {
    /// Exposed to ChatModel which is the shared WatchlistDelegate — routes
    /// watchlist-sourced raw lines to this connection when it's the one
    /// currently holding the registered watchlist session.
    func watchlistRouteSendRaw(_ line: String) {
        guard state == .connected else { return }
        client.send(line)
    }
    func watchlistRoutePostInfo(_ text: String) {
        appendInfo(text)
    }

    /// Post an `.info` line to the currently-selected buffer (or the server
    /// buffer if nothing is selected). Used by ChatModel when it intercepts
    /// a slash command like `/ignore` and needs to surface feedback to the
    /// user without going through the IRC send path.
    func appendInfoOnSelected(_ text: String) {
        if let sel = selectedBufferID,
           let i = buffers.firstIndex(where: { $0.id == sel }) {
            appendTo(bufferIndex: i, line: ChatLine(timestamp: Date(), kind: .info, text: text))
        } else {
            appendInfo(text)
        }
    }
}
