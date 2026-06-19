import Foundation
import Testing
import IRCKit
@testable import Ircle

/// Smaller quality-of-life additions: /away state tracking and the
/// notifications setting.
@MainActor
@Suite("Away state + notifications setting")
struct QualityOfLifeTests {

    private func makeSession() -> IrcleSession {
        let cfg = IRCConnectionConfig(host: "irc.example.org", port: 6697, useTLS: true,
                                      nick: "me", user: "me", realName: "Me")
        return IrcleSession(config: cfg, displayName: "Example")
    }

    @Test func awayStateTracksUnawayAndNowAway() {
        let s = makeSession()
        #expect(!s.isAway)
        s.ingest(":server 306 me :You have been marked as away")  // RPL_NOWAWAY
        #expect(s.isAway)
        s.ingest(":server 305 me :You are no longer marked as away") // RPL_UNAWAY
        #expect(!s.isAway)
    }

    @Test func notificationsEnabledDefaultsTrueAndRoundTrips() throws {
        #expect(AppSettings().notificationsEnabled)
        var s = AppSettings()
        s.notificationsEnabled = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(!back.notificationsEnabled)
    }

    @Test func legacyDocumentDefaultsNotificationsOn() throws {
        let legacy = #"{"fontSize":12}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(s.notificationsEnabled)
    }
}
