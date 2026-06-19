import Foundation
import Testing
@testable import Ircle

/// Multi-server model behavior: several sessions at once, selection + focus
/// across them, dedup per profile, removal, and input routing to the owning
/// session. Uses `openSession(autoConnect: false)` so no sockets are opened.
@MainActor
@Suite("IrcleModel multi-server")
struct ModelMultiServerTests {

    private func makeModel() -> IrcleModel {
        // runLaunchBackup: false so tests never zip Application Support into
        // ~/Downloads. We don't exercise connectDefault, so settings content
        // doesn't matter here.
        IrcleModel(settingsStore: SettingsStore(), runLaunchBackup: false)
    }

    private func profile(_ name: String, host: String) -> ServerProfile {
        var p = ServerProfile()
        p.name = name
        p.host = host
        p.nick = "me"          // so ":me!u@h JOIN" reads as a self-join
        p.autoJoin = []
        return p
    }

    @Test func opensMultipleSessions() {
        let m = makeModel()
        m.openSession(for: profile("Libera", host: "irc.libera.chat"), autoConnect: false)
        m.openSession(for: profile("OFTC", host: "irc.oftc.net"), autoConnect: false)
        #expect(m.sessions.count == 2)
        // Both server buffers present across the flattened buffer list.
        #expect(m.allBuffers.filter { $0.kind == .server }.count == 2)
    }

    @Test func sameProfileIsNotDuplicated() {
        let m = makeModel()
        let p = profile("Libera", host: "irc.libera.chat")
        _ = m.openSession(for: p, autoConnect: false)
        let b = m.openSession(for: p, autoConnect: false)
        // No duplicate accumulates. (A not-connected session is rebuilt rather
        // than reused, so the latest instance is the one that survives.)
        #expect(m.sessions.count == 1)
        #expect(m.sessions.first === b)
    }

    @Test func selectionAndFocusTrackTheOwningSession() {
        let m = makeModel()
        let s1 = m.openSession(for: profile("A", host: "a.example"), autoConnect: false)
        let s2 = m.openSession(for: profile("B", host: "b.example"), autoConnect: false)

        m.select(s1.serverBuffer)
        #expect(m.selectedSession === s1)
        #expect(s1.focusedBuffer === s1.serverBuffer)
        #expect(s2.focusedBuffer == nil)            // background session unfocused

        m.select(s2.serverBuffer)
        #expect(m.selectedSession === s2)
        #expect(s2.focusedBuffer === s2.serverBuffer)
        #expect(s1.focusedBuffer == nil)
    }

    @Test func sessionLookupFindsOwner() {
        let m = makeModel()
        let s1 = m.openSession(for: profile("A", host: "a.example"), autoConnect: false)
        let s2 = m.openSession(for: profile("B", host: "b.example"), autoConnect: false)
        s2.ingest(":me!u@h JOIN #b")
        let chanB = s2.buffers.first { $0.kind == .channel }!
        #expect(m.session(for: chanB) === s2)
        #expect(m.session(for: s1.serverBuffer) === s1)
    }

    @Test func removingSessionDropsItAndReselects() {
        let m = makeModel()
        let s1 = m.openSession(for: profile("A", host: "a.example"), autoConnect: false)
        let s2 = m.openSession(for: profile("B", host: "b.example"), autoConnect: false)
        m.select(s2.serverBuffer)
        m.removeSession(s2)
        #expect(m.sessions.count == 1)
        #expect(m.sessions.first === s1)
        // Selection moved back to the surviving session.
        #expect(m.selectedSession === s1)
    }

    @Test func closingServerBufferRemovesItsSession() {
        let m = makeModel()
        _ = m.openSession(for: profile("A", host: "a.example"), autoConnect: false)
        let s2 = m.openSession(for: profile("B", host: "b.example"), autoConnect: false)
        m.closeBuffer(s2.serverBuffer)
        #expect(m.sessions.count == 1)
        #expect(!m.sessions.contains { $0 === s2 })
    }

    @Test func reconnectAfterEditRebuildsFromUpdatedProfile() {
        // A not-connected session must be replaced when the profile is edited,
        // so the new host/port/nick take effect (the stale-config bug: editing
        // the port still reconnected to the old one).
        let m = makeModel()
        var p = profile("Undernet", host: "irc.undernet.org")
        let s1 = m.openSession(for: p, autoConnect: false)
        #expect(s1.displayName == "Undernet")

        p.name = "Undernet (plain)"            // same id, edited profile
        let s2 = m.openSession(for: p, autoConnect: false)
        #expect(s2 !== s1)                      // stale session dropped
        #expect(m.sessions.count == 1)          // not duplicated
        #expect(s2.displayName == "Undernet (plain)")   // new profile applied
        #expect(s2.serverBuffer.name == "Undernet (plain)")
    }

    @Test func inputRoutesToTheBuffersOwnSession() {
        let m = makeModel()
        let s1 = m.openSession(for: profile("A", host: "a.example"), autoConnect: false)
        let s2 = m.openSession(for: profile("B", host: "b.example"), autoConnect: false)
        s1.ingest(":me!u@h JOIN #shared")
        s2.ingest(":me!u@h JOIN #shared")
        let chanA = s1.buffers.first { $0.kind == .channel }!
        let chanB = s2.buffers.first { $0.kind == .channel }!

        // Disconnected ⇒ no echo-message ⇒ local echo lands in the right buffer.
        m.submitInput("hello B", in: chanB)
        #expect(chanB.lines.contains { $0.isSelf && $0.text == "hello B" })
        #expect(!chanA.lines.contains { $0.isSelf && $0.text == "hello B" })
    }
}
