import Foundation
import SwiftUI
import Combine

struct ChatLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let text: String
    var isMention: Bool = false

    enum Kind: Equatable {
        case info
        case error
        case motd
        case privmsg(nick: String, isSelf: Bool)
        case action(nick: String)
        case notice(from: String)
        case join(nick: String)
        case part(nick: String, reason: String?)
        case quit(nick: String, reason: String?)
        case nick(old: String, new: String)
        case topic(setter: String?)
        case raw
    }
}

struct Buffer: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var kind: Kind
    var lines: [ChatLine] = []
    var users: [String] = []
    var topic: String = ""
    var unread: Int = 0

    enum Kind: Equatable {
        case server
        case channel
        case query
    }

    var isChannel: Bool { kind == .channel }
    var displayName: String { name }
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var buffers: [Buffer] = []
    @Published var selectedBufferID: Buffer.ID?
    @Published var connectionState: IRCConnectionState = .disconnected
    @Published var nick: String = ""

    @Published var showRawLog: Bool = false
    @Published var rawLog: [String] = []
    @Published var showWatchlist: Bool = false
    @Published var showSetup: Bool = false

    let watchlist = WatchlistService()
    let settings = SettingsStore()

    private let client = IRCClient()
    private var serverBufferID: Buffer.ID?
    private var haveRegisteredWatchlist = false
    private var settingsCancellable: AnyCancellable?

    // Reconnect bookkeeping
    private var userInitiatedDisconnect = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    init() {
        watchlist.setDelegate(self)
        client.onMessage = { [weak self] msg in
            Task { @MainActor in self?.handle(msg) }
        }
        client.onState = { [weak self] state in
            Task { @MainActor in self?.handleState(state) }
        }
        client.onRaw = { [weak self] line, outbound in
            Task { @MainActor in
                guard let self else { return }
                let prefix = outbound ? ">> " : "<< "
                self.rawLog.append(prefix + line)
                if self.rawLog.count > 2000 {
                    self.rawLog.removeFirst(self.rawLog.count - 2000)
                }
            }
        }
        applySettings()
        settingsCancellable = settings.$settings.sink { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        }
    }

    private func applySettings() {
        watchlist.setWatchedList(settings.watchedFromAddressBook)
        watchlist.playSound           = settings.settings.playSoundOnWatchHit
        watchlist.bounceDock          = settings.settings.bounceDockOnWatchHit
        watchlist.systemNotifications = settings.settings.systemNotificationsOnWatchHit
    }

    // MARK: - Connection

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        userInitiatedDisconnect = false

        guard let profile = settings.selectedServer() else {
            let id = ensureServerBufferID()
            buffers[idx(of: id)].appendError("No server profile — open Setup (⌘,) and add one.")
            return
        }
        guard let portNum = UInt16(exactly: profile.port) else {
            let id = ensureServerBufferID()
            buffers[idx(of: id)].appendError("Invalid port on \(profile.name): \(profile.port)")
            return
        }
        self.nick = profile.nick
        let serverID = ensureServerBufferID()
        buffers[idx(of: serverID)].appendInfo("Connecting to \(profile.name) (\(profile.host):\(portNum), TLS=\(profile.useTLS))…")
        if profile.saslMechanism != .none {
            buffers[idx(of: serverID)].appendInfo("SASL \(profile.saslMechanism.rawValue) will be attempted after CAP negotiation.")
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

    func sendInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("/") {
            handleCommand(String(trimmed.dropFirst()))
            return
        }

        guard let bufID = selectedBufferID,
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

    private func handleCommand(_ raw: String) {
        var parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return }
        let cmd = parts.removeFirst().lowercased()
        let rest = parts.first ?? ""

        switch cmd {
        case "connect":
            connect()
        case "disconnect", "quit":
            userInitiatedDisconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            if rest.isEmpty {
                client.disconnect()
            } else {
                client.disconnect(quitMessage: rest)
            }
        case "join", "j":
            let target = rest.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return }
            client.send("JOIN \(target)")
        case "part":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            let target = bits.first ?? currentBufferName() ?? ""
            let reason = bits.count > 1 ? bits[1] : nil
            guard !target.isEmpty else { return }
            if let r = reason {
                client.send("PART \(target) :\(r)")
            } else {
                client.send("PART \(target)")
            }
        case "msg":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard bits.count == 2 else { return }
            let target = bits[0]
            let text = bits[1]
            client.send("PRIVMSG \(target) :\(text)")
            let bIdx = indexOfOrCreateBuffer(name: target, kind: target.hasPrefix("#") ? .channel : .query)
            buffers[bIdx].appendLine(ChatLine(
                timestamp: Date(),
                kind: .privmsg(nick: nick, isSelf: true),
                text: text
            ))
            selectedBufferID = buffers[bIdx].id
        case "me":
            guard let target = currentBufferName(), !rest.isEmpty else { return }
            let ctcp = "\u{01}ACTION \(rest)\u{01}"
            client.send("PRIVMSG \(target) :\(ctcp)")
            if let bIdx = buffers.firstIndex(where: { $0.name == target }) {
                buffers[bIdx].appendLine(ChatLine(
                    timestamp: Date(),
                    kind: .action(nick: nick),
                    text: rest
                ))
            }
        case "nick":
            guard !rest.isEmpty else { return }
            client.send("NICK \(rest)")
        case "topic":
            guard let target = currentBufferName() else { return }
            if rest.isEmpty {
                client.send("TOPIC \(target)")
            } else {
                client.send("TOPIC \(target) :\(rest)")
            }
        case "raw", "quote":
            client.send(rest)
        case "close":
            closeCurrentBuffer()
        case "names":
            if let target = currentBufferName() { client.send("NAMES \(target)") }
        case "whois":
            guard !rest.isEmpty else { return }
            client.send("WHOIS \(rest)")
        case "watch":
            let nick = rest.trimmingCharacters(in: .whitespaces)
            guard !nick.isEmpty else {
                watchlistPostInfo("Watchlist: " + (watchlist.watched.isEmpty ? "(empty)" : watchlist.watched.joined(separator: ", ")))
                return
            }
            if let i = settings.settings.addressBook.firstIndex(where: { $0.nick.caseInsensitiveCompare(nick) == .orderedSame }) {
                settings.settings.addressBook[i].watch = true
            } else {
                settings.settings.addressBook.append(AddressEntry(nick: nick, watch: true))
            }
            watchlistPostInfo("Now watching \(nick)")
        case "unwatch":
            let nick = rest.trimmingCharacters(in: .whitespaces)
            guard !nick.isEmpty else { return }
            if let i = settings.settings.addressBook.firstIndex(where: { $0.nick.caseInsensitiveCompare(nick) == .orderedSame }) {
                settings.settings.addressBook[i].watch = false
            }
            watchlistPostInfo("Stopped watching \(nick)")
        case "watchlist":
            showWatchlist = true
        case "setup", "settings":
            showSetup = true
        default:
            client.send("\(cmd.uppercased()) \(rest)")
        }
    }

    private func currentBufferName() -> String? {
        guard let id = selectedBufferID, let buf = buffers.first(where: { $0.id == id }) else { return nil }
        return buf.kind == .server ? nil : buf.name
    }

    // MARK: - State handling

    private func handleState(_ state: IRCConnectionState) {
        connectionState = state
        let i = idx(of: ensureServerBufferID())
        switch state {
        case .connecting: buffers[i].appendInfo("Connecting…")
        case .connected:  buffers[i].appendInfo("TCP established. Authenticating…")
        case .disconnected:
            buffers[i].appendInfo("Disconnected.")
            haveRegisteredWatchlist = false
            watchlist.onDisconnected()
            scheduleReconnectIfNeeded()
        case .failed(let err):
            buffers[i].appendError("Connection failed: \(err)")
            haveRegisteredWatchlist = false
            watchlist.onDisconnected()
            scheduleReconnectIfNeeded()
        }
    }

    // MARK: - Auto-reconnect

    private func scheduleReconnectIfNeeded() {
        if userInitiatedDisconnect { return }
        guard let profile = settings.selectedServer(), profile.autoReconnect else { return }

        reconnectAttempt = min(reconnectAttempt + 1, 6)
        let base: Double = [0, 2, 4, 8, 16, 30, 30][reconnectAttempt]
        let jitter = Double.random(in: 0.75...1.25)
        let delay = base * jitter

        let serverID = ensureServerBufferID()
        buffers[idx(of: serverID)].appendInfo(
            String(format: "Reconnecting in %.1fs (attempt %d)…", delay, reconnectAttempt)
        )

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
            let i = idx(of: ensureServerBufferID())
            buffers[i].appendError("ERROR: \(txt)")
        case "CAP", "AUTHENTICATE":
            logNumeric(msg) // already handled in IRCClient; this just logs for visibility
        case "001":
            if msg.params.count >= 1 { self.nick = msg.params[0] }
            logNumeric(msg)
            // successful handshake → reset reconnect counter
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
                .split(separator: " ")
                .map { String($0) }
                .filter { !$0.isEmpty }
            watchlist.handleISON(names)
        case "730":
            watchlist.handleMonitorOnline(monitorTargets(from: msg))
        case "731":
            watchlist.handleMonitorOffline(monitorTargets(from: msg))
        case "732", "733", "734":
            logNumeric(msg)
        case "900", "901", "902", "903", "904", "905", "906", "907":
            // SASL numerics — IRCClient drives CAP END, we just surface them.
            logNumeric(msg)
        case "433":
            let i = idx(of: ensureServerBufferID())
            let alt = self.nick + "_"
            buffers[i].appendError("Nickname in use. Trying \(alt)")
            client.send("NICK \(alt)")
        default:
            logNumeric(msg)
        }
    }

    private func monitorTargets(from msg: IRCMessage) -> [String] {
        guard let payload = msg.params.last else { return [] }
        return payload
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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

        // Own-nick highlight: matches when our nick appears as a word anywhere
        // in the text, for both channel messages and private queries.
        let mention = !isNotice
            && from.lowercased() != self.nick.lowercased()
            && settings.settings.highlightOnOwnNick
            && Self.containsOwnNick(self.nick, in: text)

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
            if mention {
                watchlist.fireHighlightAlert(nick: from, channel: bufferName, text: "* \(from) \(text)")
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
        } else {
            buffers[bIdx].appendLine(ChatLine(
                timestamp: Date(),
                kind: .privmsg(nick: from, isSelf: false),
                text: text,
                isMention: mention
            ))
        }
        markUnread(at: bIdx)

        if mention {
            watchlist.fireHighlightAlert(nick: from, channel: bufferName, text: text)
        }
    }

    /// True if `nick` appears as a standalone token in `text` (case-insensitive).
    /// Word characters are letters, digits, and IRC-nick-legal chars `-_[]{}\`|^`
    /// so that `^someone:` treats `someone` as the word.
    private static func containsOwnNick(_ nick: String, in text: String) -> Bool {
        guard !nick.isEmpty else { return false }
        let lowerText = text.lowercased()
        let lowerNick = nick.lowercased()
        guard var searchStart = lowerText.range(of: lowerNick)?.lowerBound else { return false }

        while searchStart < lowerText.endIndex {
            guard let r = lowerText.range(of: lowerNick, range: searchStart..<lowerText.endIndex) else {
                return false
            }
            let before = r.lowerBound == lowerText.startIndex ? nil : lowerText[lowerText.index(before: r.lowerBound)]
            let after = r.upperBound == lowerText.endIndex ? nil : lowerText[r.upperBound]
            if !isNickChar(before) && !isNickChar(after) {
                return true
            }
            searchStart = lowerText.index(after: r.lowerBound)
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
        if who.lowercased() == self.nick.lowercased() {
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
    }

    private func handlePart(_ msg: IRCMessage) {
        guard let chan = msg.params.first, let who = msg.nickFromPrefix else { return }
        let reason = msg.params.count > 1 ? msg.params[1] : nil
        guard let bIdx = buffers.firstIndex(where: { $0.name == chan }) else { return }
        if who.lowercased() == self.nick.lowercased() {
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
    }

    private func handleNickChange(_ msg: IRCMessage) {
        guard let old = msg.nickFromPrefix, let new = msg.params.first else { return }
        if old.lowercased() == self.nick.lowercased() {
            self.nick = new
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

    // MARK: - Post-registration

    private func runPostWelcome() {
        guard let profile = settings.selectedServer() else { return }

        // NickServ fallback (only if SASL disabled — otherwise SASL is authoritative)
        if profile.saslMechanism == .none, !profile.nickServPassword.isEmpty {
            client.send("PRIVMSG NickServ :IDENTIFY \(profile.nickServPassword)")
            watchlistPostInfo("Sent NickServ IDENTIFY.")
        }

        // Perform-on-connect lines — support raw IRC lines and slash commands.
        let lines = profile.performOnConnect
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            if line.hasPrefix("/") {
                handleCommand(String(line.dropFirst()))
            } else {
                client.send(line)
            }
        }

        autoJoinIfNeeded()
    }

    private func autoJoinIfNeeded() {
        let serverID = settings.selectedServer()?.id
        let profileChans = (settings.selectedServer()?.autoJoin ?? "")
            .split { $0 == "," || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let bookChans = settings.settings.savedChannels
            .filter { $0.serverID == nil || $0.serverID == serverID }
            .map { $0.name }
        var seen = Set<String>()
        for raw in profileChans + bookChans {
            let name = raw.hasPrefix("#") ? raw : "#" + raw
            guard seen.insert(name.lowercased()).inserted else { continue }
            client.send("JOIN \(name)")
        }
    }

    func quickJoin(_ channel: String) {
        let name = channel.hasPrefix("#") ? channel : "#" + channel
        if connectionState == .connected {
            client.send("JOIN \(name)")
        } else {
            let id = ensureServerBufferID()
            buffers[idx(of: id)].appendError("Not connected — connect first.")
        }
    }

    // MARK: - Buffer helpers

    @discardableResult
    private func ensureServerBufferID() -> Buffer.ID {
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

    func selectBuffer(_ id: Buffer.ID) {
        selectedBufferID = id
        if let i = buffers.firstIndex(where: { $0.id == id }) {
            buffers[i].unread = 0
        }
    }

    func closeCurrentBuffer() {
        guard let id = selectedBufferID,
              let i = buffers.firstIndex(where: { $0.id == id }) else { return }
        let buf = buffers[i]
        guard buf.kind != .server else { return }
        if buf.kind == .channel, connectionState == .connected {
            client.send("PART \(buf.name) :closed")
        }
        buffers.remove(at: i)
        selectedBufferID = buffers.first?.id
    }
}

private extension Buffer {
    mutating func appendLine(_ l: ChatLine) {
        lines.append(l)
        if lines.count > 5000 {
            lines.removeFirst(lines.count - 5000)
        }
    }

    mutating func appendInfo(_ text: String) {
        appendLine(ChatLine(timestamp: Date(), kind: .info, text: text))
    }

    mutating func appendError(_ text: String) {
        appendLine(ChatLine(timestamp: Date(), kind: .error, text: text))
    }
}

extension ChatModel: WatchlistDelegate {
    func watchlistSendRaw(_ line: String) {
        guard connectionState == .connected else { return }
        client.send(line)
    }

    func watchlistPostInfo(_ text: String) {
        let i = idx(of: ensureServerBufferID())
        buffers[i].appendInfo(text)
    }
}
