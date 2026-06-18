import Foundation
import Combine
import IRCKit

/// Top-level app store. For the MVP it drives a single `IrcleSession`, owns the
/// selected buffer, routes the input line to a command or a message, and runs
/// the launch-time backup. Multi-session support slots in by promoting
/// `session` to an array.
@MainActor
final class IrcleModel: ObservableObject {
    @Published var session: IrcleSession?
    @Published var selectedBufferID: UUID?

    let settingsStore: SettingsStore
    private var cancellables: Set<AnyCancellable> = []

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        // Repo standard: auto-backup on launch (before we touch live data much).
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
    }

    // MARK: - Connection

    /// Connect using the first saved server profile.
    func connectDefault() {
        guard let profile = settingsStore.settings.servers.first else { return }
        connect(to: profile)
    }

    func connect(to profile: ServerProfile) {
        // Tear down any prior session.
        session?.disconnect()
        cancellables.removeAll()

        let s = IrcleSession(config: profile.makeConfig(),
                             displayName: profile.name,
                             autoJoin: profile.autoJoin)
        // Re-publish the session's changes so SwiftUI views observing the model
        // refresh when buffers/lines mutate.
        s.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        session = s
        selectedBufferID = s.serverBuffer.id
        s.focusedBuffer = s.serverBuffer
        s.connect()
    }

    func disconnect() {
        session?.disconnect()
    }

    // MARK: - Selection

    var buffers: [IrcleBuffer] { session?.buffers ?? [] }

    var selectedBuffer: IrcleBuffer? {
        guard let id = selectedBufferID else { return session?.serverBuffer }
        return session?.buffers.first { $0.id == id } ?? session?.serverBuffer
    }

    func select(_ buffer: IrcleBuffer) {
        selectedBufferID = buffer.id
        buffer.clearUnread()
        session?.focusedBuffer = buffer
    }

    func closeBuffer(_ buffer: IrcleBuffer) {
        guard let session else { return }
        let wasSelected = buffer.id == selectedBufferID
        session.closeBuffer(buffer)
        if wasSelected {
            let target = session.buffers.last ?? session.serverBuffer
            select(target)
        }
    }

    // MARK: - Input routing

    /// Send whatever the user typed in the input bar of `buffer`.
    func submitInput(_ text: String, in buffer: IrcleBuffer) {
        guard let session else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//") {
            session.runCommand(trimmed, in: buffer)
        } else {
            // "//" escapes a literal leading slash.
            let body = trimmed.hasPrefix("//") ? String(trimmed.dropFirst()) : trimmed
            session.sendText(body, to: buffer)
        }
    }
}
