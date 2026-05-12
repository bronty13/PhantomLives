import Foundation
import Testing
@testable import PurpleIRC

@Suite("SASL negotiator state machine")
struct SASLNegotiatorTests {

    // MARK: - Helpers

    private func makeConfig(mechanism: SASLMechanism = .none,
                            nick: String = "purple-user",
                            user: String = "purpleirc",
                            realName: String = "PurpleIRC",
                            serverPassword: String? = nil,
                            saslAccount: String = "",
                            saslPassword: String = "") -> IRCConnectionConfig {
        IRCConnectionConfig(
            host: "irc.example.org",
            port: 6697,
            useTLS: true,
            nick: nick,
            user: user,
            realName: realName,
            serverPassword: serverPassword,
            saslMechanism: mechanism,
            saslAccount: saslAccount,
            saslPassword: saslPassword
        )
    }

    private func parse(_ line: String) -> IRCMessage {
        guard let m = IRCMessage.parse(line) else {
            Issue.record("Test line failed to parse: \(line)")
            fatalError("unreachable")
        }
        return m
    }

    // MARK: - Registration burst

    @Test func registrationAlwaysOpensCAPNegotiation() {
        // Even without SASL we want server-time / multi-prefix / etc., so
        // the negotiator no longer emits CAP END inline. It always parks
        // in .awaitingLS until the server's LS reply arrives.
        let n = SASLNegotiator(config: makeConfig(mechanism: .none))
        let lines = n.registrationCommands()
        #expect(lines == [
            "CAP LS 302",
            "NICK purple-user",
            "USER purpleirc 0 * :PurpleIRC"
        ])
        #expect(n.phase == .awaitingLS)
    }

    @Test func registrationWithSASLDoesNotCloseCAPYet() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain,
                                                  saslAccount: "alice",
                                                  saslPassword: "hunter2"))
        let lines = n.registrationCommands()
        #expect(lines == [
            "CAP LS 302",
            "NICK purple-user",
            "USER purpleirc 0 * :PurpleIRC"
        ])
        #expect(n.phase == .awaitingLS)
    }

    @Test func registrationIncludesPASSWhenServerPasswordSet() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .none, serverPassword: "topsecret"))
        let lines = n.registrationCommands()
        #expect(lines[0] == "CAP LS 302")
        #expect(lines[1] == "PASS topsecret")
        #expect(lines[2] == "NICK purple-user")
        #expect(lines[3] == "USER purpleirc 0 * :PurpleIRC")
    }

    @Test func emptyServerPasswordDoesNotEmitPASS() {
        let n = SASLNegotiator(config: makeConfig(serverPassword: ""))
        let lines = n.registrationCommands()
        #expect(!lines.contains { $0.hasPrefix("PASS ") })
    }

    // MARK: - SASL PLAIN happy path

    @Test func saslPlainFullHandshake() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain,
                                                  saslAccount: "alice",
                                                  saslPassword: "hunter2"))
        _ = n.registrationCommands()
        #expect(n.phase == .awaitingLS)

        // Server advertises sasl + multi-prefix; we request the intersection.
        var out = n.handle(parse(":server CAP * LS :multi-prefix sasl=PLAIN,EXTERNAL"))
        #expect(out.count == 1)
        #expect(out[0].hasPrefix("CAP REQ :"))
        // REQ payload includes both caps in some order.
        let reqCaps = Set(out[0]
            .replacingOccurrences(of: "CAP REQ :", with: "")
            .split(separator: " ").map(String.init))
        #expect(reqCaps == Set(["sasl", "multi-prefix"]))
        #expect(n.phase == .awaitingACK)

        // Server acks the sasl cap (only sasl matters for the auth path).
        out = n.handle(parse(":server CAP * ACK :sasl multi-prefix"))
        #expect(out == ["AUTHENTICATE PLAIN"])
        #expect(n.phase == .authenticating)

        // Server says "+" — send the base64 credentials blob.
        out = n.handle(parse("AUTHENTICATE +"))
        #expect(out.count == 1)
        let line = out[0]
        #expect(line.hasPrefix("AUTHENTICATE "))
        let b64 = String(line.dropFirst("AUTHENTICATE ".count))
        let decoded = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        #expect(decoded == "alice\u{0}alice\u{0}hunter2")

        // 903 RPL_SASLSUCCESS → CAP END.
        out = n.handle(parse(":server 903 purple-user :SASL authentication successful"))
        #expect(out == ["CAP END"])
        #expect(n.phase == .done)
    }

    @Test func saslPlainFallsBackToNickWhenAccountBlank() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain,
                                                  nick: "bob",
                                                  saslAccount: "",
                                                  saslPassword: "pw"))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :sasl"))
        _ = n.handle(parse(":s CAP * ACK :sasl"))
        let out = n.handle(parse("AUTHENTICATE +"))
        let b64 = String(out[0].dropFirst("AUTHENTICATE ".count))
        let decoded = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) }
        #expect(decoded == "bob\u{0}bob\u{0}pw")
    }

    // MARK: - SASL EXTERNAL

    @Test func saslExternalSendsPlusToken() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .external))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :sasl"))
        var out = n.handle(parse(":s CAP * ACK :sasl"))
        #expect(out == ["AUTHENTICATE EXTERNAL"])
        out = n.handle(parse("AUTHENTICATE +"))
        #expect(out == ["AUTHENTICATE +"])
    }

    // MARK: - Server refuses / doesn't support SASL

    @Test func capNAKEndsNegotiation() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :sasl"))
        let out = n.handle(parse(":s CAP * NAK :sasl"))
        #expect(out == ["CAP END"])
        #expect(n.phase == .done)
    }

    @Test func lsWithoutSASLStillRequestsOtherCaps() {
        // No sasl in the LS reply, but multi-prefix + account-notify are on
        // our wishlist — request them anyway, then complete CAP on ACK.
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        let out = n.handle(parse(":s CAP * LS :multi-prefix chghost account-notify"))
        #expect(out.count == 1)
        #expect(out[0].hasPrefix("CAP REQ :"))
        let reqCaps = Set(out[0]
            .replacingOccurrences(of: "CAP REQ :", with: "")
            .split(separator: " ").map(String.init))
        #expect(reqCaps == Set(["multi-prefix", "account-notify"]))
        #expect(n.phase == .awaitingACK)

        // Server ACKs both — no sasl available, so we close CAP without auth.
        let after = n.handle(parse(":s CAP * ACK :multi-prefix account-notify"))
        #expect(after == ["CAP END"])
        #expect(n.phase == .done)
    }

    @Test func lsWithNoOverlappingCapsClosesNegotiation() {
        // Server only offers caps PurpleIRC isn't asking for → CAP END.
        let n = SASLNegotiator(config: makeConfig(mechanism: .none))
        _ = n.registrationCommands()
        let out = n.handle(parse(":s CAP * LS :inspircd.org/some-extension cool-thing"))
        #expect(out == ["CAP END"])
        #expect(n.phase == .done)
    }

    @Test func lsContinuationWithoutSASLIsNoOp() {
        // "CAP * LS *" with no sasl token means "more LS frames coming" — wait.
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        let out = n.handle(parse(":s CAP * LS * :multi-prefix chghost"))
        #expect(out == [])
        #expect(n.phase == .awaitingLS)
    }

    @Test func multiFrameLSEventuallyTriggersREQ() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        // First frame: continuation with multi-prefix → buffer, no-op.
        _ = n.handle(parse(":s CAP * LS * :multi-prefix chghost"))
        #expect(n.phase == .awaitingLS)
        // Second frame: terminating LS that advertises sasl + account-notify
        // → REQ for the union of all desired matched caps.
        let out = n.handle(parse(":s CAP * LS :account-notify sasl=PLAIN"))
        #expect(out.count == 1)
        #expect(out[0].hasPrefix("CAP REQ :"))
        let reqCaps = Set(out[0]
            .replacingOccurrences(of: "CAP REQ :", with: "")
            .split(separator: " ").map(String.init))
        #expect(reqCaps == Set(["sasl", "multi-prefix", "account-notify"]))
        #expect(n.phase == .awaitingACK)
    }

    // MARK: - SASL failure numerics (902/904/905/906/907)

    @Test(arguments: ["902", "904", "905", "906", "907"])
    func saslFailureNumericClosesCAP(numeric: String) {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :sasl"))
        _ = n.handle(parse(":s CAP * ACK :sasl"))
        let out = n.handle(parse(":s \(numeric) purple-user :SASL failed"))
        #expect(out == ["CAP END"])
        #expect(n.phase == .done)
    }

    @Test func saslFailureNumericIsNoOpWhenAlreadyDone() {
        // Drive the negotiator to .done by having the server offer no caps
        // we want, then send a 904 — should be ignored since we're already
        // past the CAP/SASL phase.
        let n = SASLNegotiator(config: makeConfig(mechanism: .none))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :random-thing"))
        #expect(n.phase == .done)
        let out = n.handle(parse(":s 904 purple-user :SASL failed"))
        #expect(out == [])
    }

    // MARK: - Robustness

    @Test func authenticateWithNonPlusTokenIsIgnored() {
        // Server sent a non-'+' challenge; state machine should not send credentials.
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :sasl"))
        _ = n.handle(parse(":s CAP * ACK :sasl"))
        let out = n.handle(parse("AUTHENTICATE somethingElse"))
        #expect(out == [])
        #expect(n.phase == .authenticating)
    }

    @Test func handleIgnoresUnrelatedCommands() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        #expect(n.handle(parse("PING :x")) == [])
        #expect(n.handle(parse(":s NOTICE * :hi")) == [])
        #expect(n.phase == .awaitingLS)
    }

    @Test func ackWhileNotAwaitingACKIsIgnored() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        // Skip LS → ACK arrives out of order → ignored.
        let out = n.handle(parse(":s CAP * ACK :sasl"))
        #expect(out == [])
        #expect(n.phase == .awaitingLS)
    }

    // MARK: - 903 success without CAP END already sent

    @Test func numeric903ClosesCAPEvenIfAUTHENTICATEWasSkipped() {
        let n = SASLNegotiator(config: makeConfig(mechanism: .plain, saslPassword: "pw"))
        _ = n.registrationCommands()
        _ = n.handle(parse(":s CAP * LS :sasl"))
        _ = n.handle(parse(":s CAP * ACK :sasl"))
        // Skip the AUTHENTICATE + turn, straight to 903 (e.g. pre-authenticated).
        let out = n.handle(parse(":s 903 purple-user :ok"))
        #expect(out == ["CAP END"])
        #expect(n.phase == .done)
    }

    // MARK: - chunkedAuthenticate (400-byte SASL payload splitter)
    //
    // The contract pinned here is the IRCv3 SASL chunking rule:
    //   - empty payload  → `AUTHENTICATE +` (signals "no payload")
    //   - 1..399 bytes   → single `AUTHENTICATE <b64>` line, no terminator
    //   - >= 400 bytes   → N×400-byte chunks; if the total IS an exact
    //                      multiple of 400 we MUST append a trailing
    //                      `AUTHENTICATE +` so the server knows the
    //                      message ended (otherwise it waits for more).
    // Renaming, re-splitting, or dropping the terminator silently breaks
    // SASL against strict servers; these tests catch each regression.

    @Test func chunkerEmitsPlusForEmptyPayload() {
        #expect(SASLNegotiator.chunkedAuthenticate("") == ["AUTHENTICATE +"])
    }

    @Test func chunkerFitsShortPayloadInOneLineWithNoTerminator() {
        let payload = String(repeating: "a", count: 50)
        #expect(SASLNegotiator.chunkedAuthenticate(payload)
                == ["AUTHENTICATE \(payload)"])
    }

    @Test func chunkerHandlesExactly399BytesAsOneChunk() {
        // 399 < 400 — single line, no terminator.
        let payload = String(repeating: "x", count: 399)
        let out = SASLNegotiator.chunkedAuthenticate(payload)
        #expect(out.count == 1)
        #expect(out[0] == "AUTHENTICATE \(payload)")
    }

    @Test func chunkerSplitsAtExactly400BytesAndAppendsTerminator() {
        // Exact-400 must split into one 400-byte chunk PLUS a trailing
        // `AUTHENTICATE +` so the server doesn't keep waiting on more
        // chunks. This was the original RFC-correctness fix in 1.0.92.
        let payload = String(repeating: "y", count: 400)
        let out = SASLNegotiator.chunkedAuthenticate(payload)
        #expect(out.count == 2)
        #expect(out[0] == "AUTHENTICATE \(payload)")
        #expect(out[1] == "AUTHENTICATE +")
    }

    @Test func chunkerSplitsLongPayloadAndOmitsTerminatorWhenLastChunkIsShort() {
        // 401-byte payload: 400-byte chunk + 1-byte chunk. The last chunk
        // is short, which itself signals end-of-message — no `+` needed.
        let payload = String(repeating: "z", count: 401)
        let out = SASLNegotiator.chunkedAuthenticate(payload)
        #expect(out.count == 2)
        #expect(out[0] == "AUTHENTICATE \(String(repeating: "z", count: 400))")
        #expect(out[1] == "AUTHENTICATE z")
    }

    @Test func chunkerAppendsTerminatorWhenLengthIsExactMultipleOf400() {
        // 1200 bytes = three 400-byte chunks, all "full"; needs trailing +.
        let payload = String(repeating: "q", count: 1200)
        let out = SASLNegotiator.chunkedAuthenticate(payload)
        #expect(out.count == 4)
        for i in 0..<3 {
            #expect(out[i] == "AUTHENTICATE \(String(repeating: "q", count: 400))")
        }
        #expect(out[3] == "AUTHENTICATE +")
    }
}
