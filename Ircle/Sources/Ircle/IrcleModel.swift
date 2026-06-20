import Foundation
import Combine
import AppKit
import IRCKit

/// Top-level app store. Owns the open IRC connections (one `IrcleSession` per
/// server — classic Ircle did up to ten), the selected buffer across all of
/// them, input routing, and the launch-time backup.
@MainActor
final class IrcleModel: ObservableObject {
    @Published private(set) var sessions: [IrcleSession] = []
    @Published var selectedBufferID: UUID?
    /// Transient: the Connections window's "Edit…" sets this so the Settings
    /// Servers tab pre-selects that profile when it opens. Cleared once consumed.
    @Published var pendingEditServerID: UUID?

    let settingsStore: SettingsStore
    /// Inbound DCC transfers (offered + active). Surfaced in the DCC window.
    let dcc = IrcleDCC()
    /// One republish subscription per session, keyed by identity so it can be
    /// torn down when a session is removed.
    private var subs: [ObjectIdentifier: AnyCancellable] = [:]
    private var settingsSub: AnyCancellable?

    init(settingsStore: SettingsStore, runLaunchBackup: Bool = true) {
        self.settingsStore = settingsStore
        // Repo standard: auto-backup on launch (before we touch live data much).
        // Tests pass `false` so they don't zip Application Support into Downloads.
        if runLaunchBackup {
            BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        }
        // Let AppleScript commands reach the live model.
        IrcleAppleScriptBridge.register(host: self)
        // Push per-connection settings (notify list, notification toggle) to
        // every live session whenever settings change — from the Settings UI,
        // the Notify tab, or `/notify`. One sync path; guarded so unrelated
        // settings edits don't trigger spurious ISON re-polls.
        settingsSub = settingsStore.$settings.sink { [weak self] s in
            self?.pushPerSessionSettings(s)
        }
    }

    private func pushPerSessionSettings(_ s: AppSettings) {
        LogService.shared.enabled = s.loggingEnabled
        for sess in sessions {
            if sess.notifyNicks != s.notifyNicks { sess.notifyNicks = s.notifyNicks }
            sess.notificationsEnabled = s.notificationsEnabled
            sess.ignoreMasks = s.ignoreMasks
            sess.ctcpSoundsEnabled = s.ctcpSoundsEnabled
            sess.eventSoundsEnabled = s.eventSoundsEnabled
            sess.eventSounds = s.eventSounds
        }
    }

    // MARK: - Connection

    /// One-keystroke connect: only acts directly when there's exactly ONE saved
    /// server. With none (nothing to do) or several (don't silently grab the
    /// first — the old, confusing behavior), the caller should open the
    /// Connections window instead; see `canQuickConnect`.
    func connectDefault() {
        guard settingsStore.settings.servers.count == 1,
              let only = settingsStore.settings.servers.first else { return }
        connect(to: only)
    }

    /// Whether ⌘K / the Welcome "Connect" button should connect directly (a
    /// single configured server) vs. open the Connections window to choose.
    var canQuickConnect: Bool { settingsStore.settings.servers.count == 1 }

    /// Open (or focus) a connection for `profile`. If a session for this profile
    /// already exists it is selected — and reconnected if it had dropped —
    /// rather than duplicated.
    @discardableResult
    func connect(to profile: ServerProfile) -> IrcleSession {
        openSession(for: profile, autoConnect: true)
    }

    /// Create or focus a session for `profile`. `autoConnect: false` registers
    /// the session without opening a socket (used by tests).
    @discardableResult
    func openSession(for profile: ServerProfile, autoConnect: Bool = true) -> IrcleSession {
        if let existing = sessions.first(where: { $0.profileID == profile.id }) {
            // A live connection: just focus it (don't disrupt it).
            if existing.isConnected {
                select(existing.serverBuffer)
                return existing
            }
            // Not connected: the session captured its config (host/port/nick/…)
            // when it was created, so reusing it would reconnect with the OLD
            // settings even after the user edited the profile. Drop it and fall
            // through to build a fresh session from the current profile.
            removeSession(existing)
        }
        let s = IrcleSession(config: profile.makeConfig(),
                             displayName: profile.name,
                             autoJoin: profile.autoJoin,
                             profileID: profile.id)
        s.notifyNicks = settingsStore.settings.notifyNicks
        s.notificationsEnabled = settingsStore.settings.notificationsEnabled
        s.ignoreMasks = settingsStore.settings.ignoreMasks
        s.ctcpSoundsEnabled = settingsStore.settings.ctcpSoundsEnabled
        s.eventSoundsEnabled = settingsStore.settings.eventSoundsEnabled
        s.eventSounds = settingsStore.settings.eventSounds
        s.onDCCOffer = { [weak self] offer, from in self?.dcc.addOffer(offer, from: from) }
        // Re-publish the session's changes so SwiftUI views observing the model
        // refresh when buffers/lines mutate.
        subs[ObjectIdentifier(s)] = s.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        sessions.append(s)
        select(s.serverBuffer)
        if autoConnect { s.connect() }
        return s
    }

    /// Disconnect the session that owns the selected buffer (keeps it in the
    /// list so it can be reconnected).
    func disconnectSelected() {
        selectedSession?.disconnect()
    }

    /// Disconnect and remove a whole session (e.g. closing its server buffer).
    func removeSession(_ session: IrcleSession) {
        session.disconnect()
        subs[ObjectIdentifier(session)] = nil
        let wasSelected = selectedSession === session
        sessions.removeAll { $0 === session }
        if wasSelected {
            if let next = sessions.last { select(next.serverBuffer) }
            else { selectedBufferID = nil }
        }
    }

    // MARK: - Selection

    /// All buffers across every session, in session order.
    var allBuffers: [IrcleBuffer] { sessions.flatMap { $0.buffers } }

    /// The session that owns `buffer`, if any.
    func session(for buffer: IrcleBuffer) -> IrcleSession? {
        sessions.first { session in session.buffers.contains { $0.id == buffer.id } }
    }

    /// The session that owns the currently-selected buffer.
    var selectedSession: IrcleSession? {
        guard let id = selectedBufferID else { return sessions.first }
        return sessions.first { session in session.buffers.contains { $0.id == id } }
    }

    var selectedBuffer: IrcleBuffer? {
        guard let id = selectedBufferID else { return sessions.first?.serverBuffer }
        return allBuffers.first { $0.id == id }
    }

    func select(_ buffer: IrcleBuffer) {
        selectedBufferID = buffer.id
        buffer.clearUnread()
        // Only the owning session focuses this buffer; every other session has
        // no focused buffer, so background activity still accrues unread counts.
        let owner = session(for: buffer)
        for s in sessions { s.focusedBuffer = (s === owner) ? buffer : nil }
    }

    func closeBuffer(_ buffer: IrcleBuffer) {
        guard let session = session(for: buffer) else { return }
        // Closing a server buffer tears down the whole connection.
        if buffer.kind == .server {
            removeSession(session)
            return
        }
        let wasSelected = buffer.id == selectedBufferID
        session.closeBuffer(buffer)
        if wasSelected { select(session.buffers.last ?? session.serverBuffer) }
    }

    // MARK: - Input routing

    /// Send whatever the user typed in the input bar of `buffer`, to the session
    /// that owns it.
    func submitInput(_ text: String, in buffer: IrcleBuffer, depth: Int = 0) {
        guard let session = session(for: buffer) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//") {
            if handleGlobalCommand(trimmed, in: buffer) { return }
            // Built-ins win; otherwise expand a user alias and re-process (with
            // a recursion guard so a self-referential alias can't loop forever).
            if depth < 8, let expanded = aliasExpansion(for: trimmed) {
                submitInput(expanded, in: buffer, depth: depth + 1)
                return
            }
            session.runCommand(trimmed, in: buffer)
        } else {
            // "//" escapes a literal leading slash.
            let body = trimmed.hasPrefix("//") ? String(trimmed.dropFirst()) : trimmed
            session.sendText(body, to: buffer)
        }
    }

    /// If `/name …` names a user alias, return its expansion (which may itself be
    /// a command or text); otherwise nil.
    private func aliasExpansion(for raw: String) -> String? {
        let parts = raw.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let name = parts.first?.lowercased(),
              let template = settingsStore.settings.aliases[name] else { return nil }
        let argStr = parts.count > 1 ? parts[1] : ""
        let args = argStr.isEmpty ? [] : argStr.split(separator: " ").map(String.init)
        return AliasExpander.expand(template, args: args)
    }

    // MARK: - Initiating DCC

    /// Offer a DCC chat to `nick` on `session`: bind a listener, advertise our
    /// IP+port via CTCP, and add the (outgoing) chat to the DCC store.
    func startDCCChat(to nick: String, on session: IrcleSession) {
        guard !isSelfNick(nick, session) else {
            session.announce("You can't DCC yourself — “\(nick)” is your own nick on this server."); return
        }
        guard let ip = DCC.primaryIPv4() else {
            session.announce("Can't offer DCC chat to \(nick): no routable network address found."); return
        }
        guard let (_, port, wildcard) = dcc.offerChat(to: nick, advertiseIP: ip) else {
            session.announce("Can't offer DCC chat to \(nick): no free port in the DCC range."); return
        }
        if wildcard {
            session.announce("⚠️ DCC chat is listening on all interfaces (couldn't bind \(ip)); any host reaching port \(port) could connect before \(nick).")
        }
        session.sendRaw("PRIVMSG \(nick) :\u{01}\(DCC.chatOfferCommand(ip: ip, port: port))\u{01}")
        session.announce("Offered DCC chat to \(nick) (listening on \(ip):\(port)). Open DCC Transfers (⌘⇧D).")
    }

    /// True if `nick` is our own nick on `session` (DCC to self is a no-op).
    private func isSelfNick(_ nick: String, _ session: IrcleSession) -> Bool {
        IRCCase.equal(nick, session.nick)
    }

    /// Pick a file (NSOpenPanel) and offer it to `nick` via DCC SEND.
    func promptAndSendFile(to nick: String, on session: IrcleSession) {
        guard !isSelfNick(nick, session) else {
            session.announce("You can't DCC yourself — “\(nick)” is your own nick on this server."); return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Send"
        panel.message = "Choose a file to send to \(nick) via DCC."
        if panel.runModal() == .OK, let url = panel.url {
            startDCCSend(to: nick, fileURL: url, on: session)
        }
    }

    /// Offer a specific file to `nick`: bind a listener, advertise via CTCP DCC
    /// SEND, and add the outgoing transfer to the DCC store.
    func startDCCSend(to nick: String, fileURL: URL, on session: IrcleSession) {
        guard !isSelfNick(nick, session) else {
            session.announce("You can't DCC yourself — “\(nick)” is your own nick on this server."); return
        }
        guard let ip = DCC.primaryIPv4() else {
            session.announce("Can't send to \(nick): no routable network address found."); return
        }
        guard let (_, port, size, wildcard) = dcc.offerSend(to: nick, fileURL: fileURL, advertiseIP: ip) else {
            session.announce("Can't send \(fileURL.lastPathComponent) to \(nick): no free port in the DCC range."); return
        }
        if wildcard {
            session.announce("⚠️ DCC SEND is listening on all interfaces (couldn't bind \(ip)); any host reaching port \(port) could connect before \(nick).")
        }
        session.sendRaw("PRIVMSG \(nick) :\u{01}\(DCC.sendOfferCommand(filename: fileURL.lastPathComponent, ip: ip, port: port, size: size))\u{01}")
        let sz = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        session.announce("Offering \(fileURL.lastPathComponent) (\(sz)) to \(nick). Open DCC Transfers (⌘⇧D).")
    }

    // MARK: - Notify (friends) list

    /// The global Notify list (friends). Mutating it persists to settings and
    /// re-syncs every live session so ISON polling picks up the change.
    var notifyNicks: [String] { settingsStore.settings.notifyNicks }

    func addNotify(_ nick: String) {
        let n = nick.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty,
              !settingsStore.settings.notifyNicks.contains(where: { IRCCase.equal($0, n) }) else { return }
        settingsStore.settings.notifyNicks.append(n)   // → $settings sink syncs sessions
    }

    func removeNotify(_ nick: String) {
        settingsStore.settings.notifyNicks.removeAll { IRCCase.equal($0, nick) }
    }

    // MARK: - Aliases

    func setAlias(_ name: String, _ expansion: String) {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, !expansion.isEmpty else { return }
        settingsStore.settings.aliases[key] = expansion
    }

    func removeAlias(_ name: String) {
        settingsStore.settings.aliases[name.trimmingCharacters(in: .whitespaces).lowercased()] = nil
    }

    // MARK: - Ignore list

    var ignoreMasks: [String] { settingsStore.settings.ignoreMasks }

    func addIgnore(_ mask: String) {
        let m = mask.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty,
              !settingsStore.settings.ignoreMasks.contains(where: { $0.caseInsensitiveCompare(m) == .orderedSame }) else { return }
        settingsStore.settings.ignoreMasks.append(m)   // → $settings sink syncs sessions
    }

    func removeIgnore(_ mask: String) {
        settingsStore.settings.ignoreMasks.removeAll { $0.caseInsensitiveCompare(mask) == .orderedSame }
    }

    /// Commands handled by the model itself (they touch global settings / every
    /// session) rather than a single connection. Returns true if consumed.
    private func handleGlobalCommand(_ raw: String, in buffer: IrcleBuffer) -> Bool {
        let parts = raw.dropFirst().split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased() else { return false }
        let sub = parts.count > 1 ? parts[1].lowercased() : ""
        let arg = parts.count > 2 ? parts[2] : ""
        switch cmd {
        case "notify":
            switch sub {
            case "add":                 addNotify(arg)
            case "del", "remove", "rm": removeNotify(arg)
            default:                    break   // "list" / unknown → just report below
            }
            let list = settingsStore.settings.notifyNicks
            session(for: buffer)?.announce(
                "Notify list: " + (list.isEmpty ? "(empty)" : list.joined(separator: ", ")),
                in: buffer)
            return true
        case "ignore":
            switch sub {
            case "add":                 addIgnore(arg)
            case "del", "remove", "rm", "un": removeIgnore(arg)
            default:                    break   // "list"/unknown → report below
            }
            let list = settingsStore.settings.ignoreMasks
            session(for: buffer)?.announce(
                "Ignore list: " + (list.isEmpty ? "(empty)" : list.joined(separator: ", ")),
                in: buffer)
            return true
        case "unignore":
            if !sub.isEmpty { removeIgnore(sub) }
            let list = settingsStore.settings.ignoreMasks
            session(for: buffer)?.announce(
                "Ignore list: " + (list.isEmpty ? "(empty)" : list.joined(separator: ", ")),
                in: buffer)
            return true
        case "alias":
            // /alias <name> <expansion…>  ·  /alias del <name>  ·  /alias (list)
            if sub == "del" || sub == "remove" || sub == "rm" {
                if !arg.isEmpty { removeAlias(arg) }
            } else if !sub.isEmpty {
                // Everything after the name is the expansion template.
                let rest = raw.dropFirst().split(separator: " ", maxSplits: 2).map(String.init)
                if rest.count >= 3 { setAlias(sub, rest[2]) }
                else { session(for: buffer)?.announce("Usage: /alias <name> <expansion>   (e.g. /alias j /join)", in: buffer) ; return true }
            }
            let aliases = settingsStore.settings.aliases
            let listing = aliases.isEmpty ? "(none)"
                : aliases.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: "; ")
            session(for: buffer)?.announce("Aliases: \(listing)", in: buffer)
            return true
        case "unalias":
            if !sub.isEmpty { removeAlias(sub) }
            session(for: buffer)?.announce("Removed alias \(sub).", in: buffer)
            return true
        case "dcc":
            guard let session = session(for: buffer) else { return true }
            switch sub {
            case "chat":
                if arg.isEmpty { session.announce("Usage: /dcc chat <nick>", in: buffer) }
                else { startDCCChat(to: arg, on: session) }
            case "send":
                if arg.isEmpty { session.announce("Usage: /dcc send <nick>", in: buffer) }
                else { promptAndSendFile(to: arg, on: session) }
            default:
                session.announce("Usage: /dcc chat <nick>  ·  /dcc send <nick>", in: buffer)
            }
            return true
        default:
            return false
        }
    }
}
