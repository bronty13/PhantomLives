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
}
