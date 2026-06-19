import Foundation
import Testing
@testable import Ircle

/// The Classic mode-toggle row reflects `IrcleBuffer.channelModes`, populated by
/// parsing MODE changes and RPL_CHANNELMODEIS (324). The parser must track only
/// the 9 surfaced channel flags, apply +/- correctly, and ignore parameters and
/// untracked modes (op/voice/ban/key-value/etc.).
@MainActor
@Suite("Channel mode tracking")
struct ChannelModeTests {

    private func chan() -> IrcleBuffer { IrcleBuffer(kind: .channel, name: "#test") }

    @Test func applyAddsAndRemovesTrackedFlags() {
        let b = chan()
        b.applyModeChange("+nt")
        #expect(b.channelModes == ["n", "t"])
        b.applyModeChange("-t")
        #expect(b.channelModes == ["n"])
    }

    @Test func mixedSignsInOneToken() {
        let b = chan()
        b.applyModeChange("+ntis")
        b.applyModeChange("+m-is")
        #expect(b.channelModes == ["n", "t", "m"])
    }

    @Test func ignoresUntrackedModesAndParameters() {
        let b = chan()
        // +o/+v/+b are user/list modes (with params) — must NOT enter the flag set.
        b.applyModeChange("+ob")        // op + ban letters: not tracked
        #expect(b.channelModes.isEmpty)
        // A real change with a key + limit; parser sees only the token, and the
        // " param" section is ignored. k and l ARE tracked (presence only).
        b.applyModeChange("+kl")
        #expect(b.channelModes == ["k", "l"])
    }

    @Test func parameterSectionIsNotParsedAsModes() {
        let b = chan()
        // If a caller ever passes the joined token+params, the space halts it so
        // a param like "secret" can't be misread as modes (s, e, …).
        b.applyModeChange("+k secret")
        #expect(b.channelModes == ["k"])
    }

    @Test func setModesReplacesFromChannelModeIs() {
        let b = chan()
        b.applyModeChange("+i")
        b.setModes("+nt")               // 324 reply replaces the whole set
        #expect(b.channelModes == ["n", "t"])
        // tolerates a token without a leading sign
        b.setModes("ntp")
        #expect(b.channelModes == ["n", "t", "p"])
    }
}
