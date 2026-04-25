import Foundation
import Testing
@testable import PurpleIRC

@Suite("IRCMessage parser")
struct IRCMessageTests {

    // MARK: - Basic shape

    @Test func parsesSimpleCommandWithoutPrefix() {
        let msg = IRCMessage.parse("PING :server.example")
        #expect(msg != nil)
        #expect(msg?.prefix == nil)
        #expect(msg?.command == "PING")
        #expect(msg?.params == ["server.example"])
    }

    @Test func parsesCommandWithPrefixAndParams() {
        let msg = IRCMessage.parse(":nick!user@host PRIVMSG #chan :hello there")
        #expect(msg?.prefix == "nick!user@host")
        #expect(msg?.command == "PRIVMSG")
        #expect(msg?.params == ["#chan", "hello there"])
    }

    @Test func commandIsUppercased() {
        let msg = IRCMessage.parse("privmsg #c :hi")
        #expect(msg?.command == "PRIVMSG")
    }

    @Test func parsesTrailingOnlyWhenPrefixedByColonSpace() {
        // " :" after a token = trailing. Embedded colons in middle params stay attached.
        let msg = IRCMessage.parse(":n MODE #c +o user:with:colons")
        #expect(msg?.params == ["#c", "+o", "user:with:colons"])
    }

    @Test func trailingCanContainSpaces() {
        let msg = IRCMessage.parse(":n PRIVMSG #c :hello world with spaces  ")
        #expect(msg?.params.last == "hello world with spaces  ")
    }

    @Test func trailingCanBeEmpty() {
        let msg = IRCMessage.parse(":n PRIVMSG #c :")
        #expect(msg?.params == ["#c", ""])
    }

    // MARK: - Numerics and server messages

    @Test func parsesNumericReplyWithTargetAndText() {
        let msg = IRCMessage.parse(":irc.example 001 purple-user :Welcome to the network")
        #expect(msg?.command == "001")
        #expect(msg?.prefix == "irc.example")
        #expect(msg?.params == ["purple-user", "Welcome to the network"])
    }

    @Test func parsesCAPSubcommandWithMultipleMiddleParams() {
        let msg = IRCMessage.parse(":server CAP * LS :multi-prefix sasl=PLAIN message-tags")
        #expect(msg?.command == "CAP")
        #expect(msg?.params == ["*", "LS", "multi-prefix sasl=PLAIN message-tags"])
    }

    @Test func parsesCAPContinuationFrame() {
        // "CAP * LS *" (4 middle params, trailing = remainder) signals another frame follows.
        let msg = IRCMessage.parse(":server CAP * LS * :sasl=PLAIN,EXTERNAL chghost")
        #expect(msg?.params.count == 4)
        #expect(msg?.params[2] == "*")
        #expect(msg?.params[3] == "sasl=PLAIN,EXTERNAL chghost")
    }

    // MARK: - Line framing edge cases

    @Test func stripsTrailingCarriageReturnAndNewline() {
        let msg = IRCMessage.parse("PING :x\r\n")
        #expect(msg?.command == "PING")
        #expect(msg?.params == ["x"])
    }

    @Test func emptyLineReturnsNil() {
        #expect(IRCMessage.parse("") == nil)
        #expect(IRCMessage.parse("\r\n") == nil)
    }

    @Test func linePrefixOnlyReturnsNil() {
        // ":prefix" with no space means no command — parser treats as malformed.
        #expect(IRCMessage.parse(":nick!u@h") == nil)
    }

    @Test func collapsesRunsOfSpacesBetweenTokens() {
        // omittingEmptySubsequences = true in parser
        let msg = IRCMessage.parse(":n JOIN    #chan")
        #expect(msg?.command == "JOIN")
        #expect(msg?.params == ["#chan"])
    }

    // MARK: - nickFromPrefix

    @Test func nickFromPrefixExtractsBeforeBang() {
        let msg = IRCMessage.parse(":alice!~alice@example.com PRIVMSG #c :hi")
        #expect(msg?.nickFromPrefix == "alice")
    }

    @Test func nickFromPrefixReturnsWholePrefixWhenNoBang() {
        // Server-source prefix has no '!' — treat entire prefix as the sender name.
        let msg = IRCMessage.parse(":irc.server.example NOTICE * :*** Looking up hostname")
        #expect(msg?.nickFromPrefix == "irc.server.example")
    }

    @Test func nickFromPrefixIsNilWhenNoPrefix() {
        let msg = IRCMessage.parse("PING :x")
        #expect(msg?.nickFromPrefix == nil)
    }

    // MARK: - Preserves raw line

    @Test func rawLineIsPreserved() {
        let line = ":a!b@c PRIVMSG #d :hello"
        #expect(IRCMessage.parse(line)?.raw == line)
    }

    // MARK: - IRCv3 message tags

    @Test func parsesSimpleTagBlock() {
        let msg = IRCMessage.parse("@time=2026-04-25T10:30:45.000Z :a!b@c PRIVMSG #d :hi")
        #expect(msg?.tags["time"] == "2026-04-25T10:30:45.000Z")
        #expect(msg?.command == "PRIVMSG")
        #expect(msg?.params == ["#d", "hi"])
    }

    @Test func parsesMultipleTagsSeparatedBySemicolons() {
        let msg = IRCMessage.parse("@account=alice;msgid=abc-123 :a PRIVMSG #d :hi")
        #expect(msg?.tags["account"] == "alice")
        #expect(msg?.tags["msgid"] == "abc-123")
        #expect(msg?.account == "alice")
        #expect(msg?.msgID == "abc-123")
    }

    @Test func tagWithoutEqualsHasEmptyValue() {
        let msg = IRCMessage.parse("@unset :a PING :x")
        #expect(msg?.tags["unset"] == "")
    }

    @Test func tagValueEscapesAreUnescaped() {
        // \: → ;   \s → space   \\ → \   \r/\n → CR/LF
        let msg = IRCMessage.parse("@k=a\\sb\\:c\\\\d\\r\\n :a PING :x")
        #expect(msg?.tags["k"] == "a b;c\\d\r\n")
    }

    @Test func dropsAccountWhenServerSendsStar() {
        let msg = IRCMessage.parse("@account=* :a PRIVMSG #d :hi")
        #expect(msg?.account == nil)
    }

    @Test func parsesServerTimeIntoDate() {
        let msg = IRCMessage.parse("@time=2026-04-25T10:30:45.123Z :a PRIVMSG #d :hi")
        let date = msg?.serverTime
        #expect(date != nil)
        // Sanity: roundtrip back through the same parser.
        if let date {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, ISO8601DateFormatter.Options.withFractionalSeconds]
            #expect(f.string(from: date) == "2026-04-25T10:30:45.123Z")
        }
    }

    @Test func parsesServerTimeWithoutFractionalSeconds() {
        let msg = IRCMessage.parse("@time=2026-04-25T10:30:45Z :a PRIVMSG #d :hi")
        #expect(msg?.serverTime != nil)
    }

    @Test func batchRefSurfaces() {
        let msg = IRCMessage.parse("@batch=abc;time=2026-01-01T00:00:00Z :a PRIVMSG #d :hi")
        #expect(msg?.batchRef == "abc")
    }

    @Test func untaggedMessageHasEmptyTagsAndNilHelpers() {
        let msg = IRCMessage.parse(":a PRIVMSG #d :hi")
        #expect(msg?.tags.isEmpty == true)
        #expect(msg?.serverTime == nil)
        #expect(msg?.account == nil)
        #expect(msg?.batchRef == nil)
        #expect(msg?.msgID == nil)
    }
}
