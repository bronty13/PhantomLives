import Foundation
import Testing
@testable import PurpleIRC

@Suite("IRC line / field sanitization")
struct IRCSanitizeTests {

    // MARK: - field(_:)

    @Test func fieldPassesThroughCleanInputUnchanged() {
        #expect(IRCSanitize.field("hello") == "hello")
        #expect(IRCSanitize.field("#channel") == "#channel")
        #expect(IRCSanitize.field("nick!user@host") == "nick!user@host")
        // Identity guarantee: when there's nothing to strip, the helper
        // returns the input unchanged — no allocation, no transformation.
        #expect(IRCSanitize.field("") == "")
    }

    @Test func fieldStripsCRLFNUL() {
        #expect(IRCSanitize.field("a\rb") == "ab")
        #expect(IRCSanitize.field("a\nb") == "ab")
        #expect(IRCSanitize.field("a\0b") == "ab")
        #expect(IRCSanitize.field("a\r\nb") == "ab")
        #expect(IRCSanitize.field("\r\n\0") == "")
    }

    @Test func fieldCollapsesMultilineIntoSingleLine() {
        // Intentional: multi-line PRIVMSG isn't a wire concept; the multi-
        // line paste sheet is the right path for that intent. The
        // sanitizer MUST produce a single line; don't "fix" by injecting
        // spaces or splitting.
        #expect(IRCSanitize.field("first\nsecond") == "firstsecond")
        #expect(IRCSanitize.field("a\r\nb\r\nc") == "abc")
    }

    @Test func fieldLeavesOtherControlBytesAlone() {
        // Tabs, ETX, mIRC color codes — none of these terminate an IRC
        // line, so they're not the sanitizer's job. Leave them for the
        // formatter / renderer to handle.
        #expect(IRCSanitize.field("a\tb") == "a\tb")
        #expect(IRCSanitize.field("\u{0003}04red\u{0003}") == "\u{0003}04red\u{0003}")
    }

    @Test func lineIsAFieldAlias() {
        // `line(_:)` is the wire-seam call; `field(_:)` is the API-boundary
        // call. They share an implementation today, but both names must
        // stay valid — sites that need to read clearly use either.
        #expect(IRCSanitize.line("PRIVMSG #c :hi\r\n") == "PRIVMSG #c :hi")
    }

    // MARK: - maskForDisplay(_:)

    @Test func maskHidesServerPassword() {
        #expect(IRCSanitize.maskForDisplay("PASS hunter2") == "PASS ****")
        #expect(IRCSanitize.maskForDisplay("PASS :hunter two") == "PASS ****")
        #expect(IRCSanitize.maskForDisplay("pass hunter2") == "PASS ****")
    }

    @Test func maskHidesTagOrPrefixedCredentials() {
        // A credential line carrying an IRCv3 tags segment and/or a source
        // prefix must still be masked (the command isn't at column 0).
        #expect(IRCSanitize.maskForDisplay("@time=2024 PASS hunter2") == "@time=2024 PASS ****")
        #expect(IRCSanitize.maskForDisplay(":srv PASS hunter2") == ":srv PASS ****")
        #expect(IRCSanitize.maskForDisplay("@a=b :srv AUTHENTICATE Zm9v") == "@a=b :srv AUTHENTICATE ****")
    }

    @Test func maskLeavesChatBodyMentioningPassAlone() {
        // "PASS" inside a PRIVMSG body is not a credential command — masking
        // the command must not over-match the message text.
        let line = "PRIVMSG #chan :the PASS phrase is secret"
        #expect(IRCSanitize.maskForDisplay(line) == line)
    }

    @Test func maskLeavesAuthenticateControlMarkersVisible() {
        // `+` and `*` carry no secret — they're the SASL "ready for
        // payload" / "abort" control bytes. The viewer must see them so
        // the SASL state-machine is debuggable.
        #expect(IRCSanitize.maskForDisplay("AUTHENTICATE +") == "AUTHENTICATE +")
        #expect(IRCSanitize.maskForDisplay("AUTHENTICATE *") == "AUTHENTICATE *")
        #expect(IRCSanitize.maskForDisplay("authenticate +") == "authenticate +")
    }

    @Test func maskHidesAuthenticatePayload() {
        // The base64-encoded SASL payload is the credential. Mask it.
        #expect(IRCSanitize.maskForDisplay("AUTHENTICATE bm9ib2R5AGFsaWNlAGh1bnRlcg==")
                == "AUTHENTICATE ****")
        // Including a continuation chunk (which is still credential bytes).
        #expect(IRCSanitize.maskForDisplay("AUTHENTICATE Zm9vYmFy") == "AUTHENTICATE ****")
    }

    @Test func maskHidesNickServIdentify() {
        // Outbound (no prefix).
        #expect(IRCSanitize.maskForDisplay("PRIVMSG NickServ :IDENTIFY hunter2")
                == "PRIVMSG NickServ :IDENTIFY ****")
        // Outbound, account-form.
        #expect(IRCSanitize.maskForDisplay("PRIVMSG NickServ :IDENTIFY alice hunter2")
                == "PRIVMSG NickServ :IDENTIFY ****")
        // Inbound echo-message (echo-message cap). The regex looks for
        // the verb anywhere so the `:prefix ` part doesn't hide the secret.
        #expect(IRCSanitize.maskForDisplay(":alice!a@host PRIVMSG NickServ :IDENTIFY hunter2")
                == ":alice!a@host PRIVMSG NickServ :IDENTIFY ****")
    }

    @Test func maskLeavesUnrelatedLinesAlone() {
        // Defence-in-depth: the masker MUST be idempotent and return its
        // input unchanged when no credential pattern matches.
        #expect(IRCSanitize.maskForDisplay("PRIVMSG #chan :hello") == "PRIVMSG #chan :hello")
        #expect(IRCSanitize.maskForDisplay("JOIN #chan") == "JOIN #chan")
        #expect(IRCSanitize.maskForDisplay(":server.example 001 alice :Welcome")
                == ":server.example 001 alice :Welcome")
        // PRIVMSG to *anyone other than NickServ* is normal chat, not a
        // credential — DO NOT mask.
        #expect(IRCSanitize.maskForDisplay("PRIVMSG bob :IDENTIFY is a great song")
                == "PRIVMSG bob :IDENTIFY is a great song")
    }

    @Test func maskDoesNotMutateForCallersWhoAlsoSend() {
        // Sharp edge documented in HANDOFF: `maskForDisplay` is display
        // only; never call on a string that's about to be sent. This test
        // pins the property that masking is a pure transformation (input
        // unchanged) so an inadvertent send of the input doesn't leak —
        // i.e. the original string is preserved when the helper returns.
        let secret = "PASS hunter2"
        _ = IRCSanitize.maskForDisplay(secret)
        #expect(secret == "PASS hunter2")
    }
}
