import Foundation
import Testing
@testable import Ircle

/// Model-level invariants behind the Floating ("Workspace") variant: server
/// buffers are never given their own per-buffer window (they live only in the
/// shared Console), and focusing a buffer window selects it.
@MainActor
@Suite("Floating windows model")
struct FloatingWindowsTests {

    private func makeModel(sessions n: Int) -> IrcleModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SettingsStore(directory: dir, secretStore: InMemorySecretStore())
        let profiles = (0..<n).map { ServerProfile(name: "S\($0)", host: "s\($0).invalid") }
        store.settings.servers = profiles
        let m = IrcleModel(settingsStore: store, runLaunchBackup: false)
        for p in profiles { m.openSession(for: p, autoConnect: false) }
        return m
    }

    @Test func everySessionContributesExactlyOneServerBuffer() {
        let m = makeModel(sessions: 2)
        #expect(m.allBuffers.count == 2)
        #expect(m.allBuffers.allSatisfy { $0.kind == .server })
    }

    @Test func serverBuffersAreNeverDetachedIntoTheirOwnWindow() {
        // This is the rule RootView uses to decide which buffers get a window.
        let m = makeModel(sessions: 2)
        let detachable = m.allBuffers.filter { $0.kind != .server }
        #expect(detachable.isEmpty)
    }

    @Test func selectingABufferUpdatesTheSharedSelection() {
        // The Console / Userlist / Inputline all bind to selectedBuffer, so a
        // window's focus → select() is what re-targets them.
        let m = makeModel(sessions: 1)
        let console = m.sessions[0].serverBuffer
        m.select(console)
        #expect(m.selectedBufferID == console.id)
        #expect(m.selectedBuffer?.id == console.id)
        #expect(m.selectedSession === m.sessions[0])
    }
}
