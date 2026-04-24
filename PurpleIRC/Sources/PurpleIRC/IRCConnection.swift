import Foundation
import Combine

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
}

/// One IRC connection: owns its `IRCClient`, its buffers, its watchlist,
/// reconnect bookkeeping, and a `PassthroughSubject` of events. ChatModel
/// holds a list of these; each event always carries the network id.
@MainActor
final class IRCConnection: ObservableObject, Identifiable {
    let id: UUID = UUID()

    @Published var profile: ServerProfile
    @Published var state: IRCConnectionState = .disconnected
    @Published var nick: String = ""
    @Published var buffers: [Buffer] = []
    @Published var selectedBufferID: Buffer.ID?
    @Published var rawLog: [String] = []

    /// Shared across all connections — ChatModel owns the single instance and
    /// routes its delegate calls to the right connection. Keeping one service
    /// means the watched-list, presence, and recent-hits log are global (what
    /// the UI wants) without trying to merge state from N sources.
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

    /// True while a configured SASL handshake is in progress so ChatModel
    /// can surface status. Cleared on CAP END success/failure numerics.
    private(set) var saslActive = false

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
            saslPassword: profile.saslPassword
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
        buffers[bufIdx].appendLine(ChatLine(
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

    /// Let ChatModel push settings-driven flags in (alert toggles + highlight).
    /// Highlight-on-own-nick is stored here for use inside `handlePrivmsg`.
    var highlightOnOwnNick: Bool = true
    func applyAlertOptions(sound: Bool, dock: Bool, banner: Bool, highlight: Bool) {
        watchlist.playSound = sound
        watchlist.bounceDock = dock
        watchlist.systemNotifications = banner
        highlightOnOwnNick = highlight
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
                    buffers[i].appendLine(ChatLine(
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

        if !isNotice {
            watchlist.handleObservedActivity(nick: from, reason: "message")
        }

        let isToSelf = target.lowercased() == self.nick.lowercased()
        let bufferName = isToSelf ? from : target
        let kind: Buffer.Kind = target.hasPrefix("#") ? .channel : .query

        let plainForMatch = IRCFormatter.stripCodes(text)
        let mention = !isNotice
            && from.lowercased() != self.nick.lowercased()
            && highlightOnOwnNick
            && Self.containsOwnNick(self.nick, in: plainForMatch)

        // CTCP ACTION
        if text.hasPrefix("\u{01}ACTION "), text.hasSuffix("\u{01}") {
            text = String(text.dropFirst(8).dropLast())
            let bIdx = indexOfOrCreateBuffer(name: bufferName, kind: kind)
            buffers[bIdx].appendLine(ChatLine(
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
            return
        }

        let bIdx = indexOfOrCreateBuffer(name: bufferName, kind: kind)
        if isNotice {
            buffers[bIdx].appendLine(ChatLine(
                timestamp: Date(),
                kind: .notice(from: from),
                text: text
            ))
            emit(.notice(from: from, target: bufferName, text: text))
        } else {
            buffers[bIdx].appendLine(ChatLine(
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
            buffers[bIdx].appendInfo("You joined \(chan)")
            selectedBufferID = buffers[bIdx].id
        } else {
            watchlist.handleObservedActivity(nick: who, reason: "JOIN \(chan)")
            buffers[bIdx].appendLine(ChatLine(
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
            buffers[bIdx].appendInfo("You left \(chan)")
            buffers[bIdx].users.removeAll()
        } else {
            buffers[bIdx].appendLine(ChatLine(
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
            buffers[i].appendLine(ChatLine(
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
                buffers[i].appendLine(ChatLine(
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
        buffers[i].appendLine(ChatLine(
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
        buffers[i].appendInfo(text)
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
        buffers[i].appendLine(ChatLine(
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
            buffers[bIdx].appendLine(ChatLine(
                timestamp: Date(),
                kind: .privmsg(nick: nick, isSelf: true),
                text: text))
            selectedBufferID = buffers[bIdx].id
        case "me":
            guard let target = currentBufferName(), !rest.isEmpty else { return }
            let ctcp = "\u{01}ACTION \(rest)\u{01}"
            client.send("PRIVMSG \(target) :\(ctcp)")
            if let bIdx = buffers.firstIndex(where: { $0.name == target }) {
                buffers[bIdx].appendLine(ChatLine(
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

    /// Run auto-join for saved channels belonging to this profile. ChatModel
    /// drives this so it can read the shared saved-channel list.
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

    private func appendInfo(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        buffers[i].appendInfo(text)
    }

    private func appendError(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        buffers[i].appendError(text)
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
}
