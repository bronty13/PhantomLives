import Foundation
import Testing
@testable import Ircle

/// The Connections window's hub behavior + the ⌘K/Welcome connect-UX fix: a
/// one-keystroke connect only acts directly for a single server, and connecting
/// the same profile twice never duplicates a session.
@MainActor
@Suite("Connections + connect UX")
struct ConnectionsTests {

    private func makeModel(_ servers: [ServerProfile]) -> IrcleModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SettingsStore(directory: dir, secretStore: InMemorySecretStore())
        store.settings.servers = servers
        return IrcleModel(settingsStore: store, runLaunchBackup: false)
    }

    @Test func quickConnectOnlyForASingleServer() {
        #expect(makeModel([]).canQuickConnect == false)
        #expect(makeModel([ServerProfile(name: "one")]).canQuickConnect == true)
        #expect(makeModel([ServerProfile(name: "a"), ServerProfile(name: "b")]).canQuickConnect == false)
    }

    @Test func connectDefaultIsANoOpForZeroOrManyServers() {
        // 0 servers → nothing to do.
        let m0 = makeModel([])
        m0.connectDefault()
        #expect(m0.sessions.isEmpty)
        // Several servers → don't silently grab the first (the old, confusing
        // behavior); the caller opens the Connections window instead.
        let m2 = makeModel([ServerProfile(name: "a"), ServerProfile(name: "b")])
        m2.connectDefault()
        #expect(m2.sessions.isEmpty)
    }

    @Test func connectingTheSameProfileTwiceYieldsOneSession() {
        let p = ServerProfile(name: "X", host: "example.invalid")
        let m = makeModel([p])
        m.openSession(for: p, autoConnect: false)
        m.openSession(for: p, autoConnect: false)   // dedups (rebuilds, not duplicates)
        #expect(m.sessions.count == 1)
        #expect(m.sessions.first?.profileID == p.id)
    }

    @Test func multipleDistinctServersEachGetASession() {
        let a = ServerProfile(name: "A", host: "a.invalid")
        let b = ServerProfile(name: "B", host: "b.invalid")
        let m = makeModel([a, b])
        m.openSession(for: a, autoConnect: false)
        m.openSession(for: b, autoConnect: false)
        #expect(m.sessions.count == 2)
        #expect(Set(m.sessions.compactMap(\.profileID)) == [a.id, b.id])
    }
}
