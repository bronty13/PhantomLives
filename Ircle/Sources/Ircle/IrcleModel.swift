import Foundation
import Combine
import IRCKit

/// Top-level app store. Owns the open IRC connections (one `IrcleSession` per
/// server — classic Ircle did up to ten), the selected buffer across all of
/// them, input routing, and the launch-time backup.
@MainActor
final class IrcleModel: ObservableObject {
    @Published private(set) var sessions: [IrcleSession] = []
    @Published var selectedBufferID: UUID?

    let settingsStore: SettingsStore
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
        }
    }

    // MARK: - Connection

    /// Connect using the first saved server profile.
    func connectDefault() {
        guard let profile = settingsStore.settings.servers.first else { return }
        connect(to: profile)
    }

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
    func submitInput(_ text: String, in buffer: IrcleBuffer) {
        guard let session = session(for: buffer) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//") {
            if handleGlobalCommand(trimmed, in: buffer) { return }
            session.runCommand(trimmed, in: buffer)
        } else {
            // "//" escapes a literal leading slash.
            let body = trimmed.hasPrefix("//") ? String(trimmed.dropFirst()) : trimmed
            session.sendText(body, to: buffer)
        }
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

    /// Commands handled by the model itself (they touch global settings / every
    /// session) rather than a single connection. Returns true if consumed.
    private func handleGlobalCommand(_ raw: String, in buffer: IrcleBuffer) -> Bool {
        let parts = raw.dropFirst().split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased(), cmd == "notify" else { return false }
        let sub = parts.count > 1 ? parts[1].lowercased() : "list"
        let arg = parts.count > 2 ? parts[2] : ""
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
    }
}
