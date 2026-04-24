import Foundation
import Testing
@testable import PurpleIRC

@Suite("Trigger rule placeholder expansion")
struct TriggerRuleExpansionTests {

    @Test func expandsNickChannelMatch() {
        let out = BotEngine.expandResponse(
            "$nick asked $match in $channel",
            match: "!rules",
            groups: ["!rules"],
            nick: "alice",
            channel: "#swift"
        )
        #expect(out == "alice asked !rules in #swift")
    }

    @Test func expandsNumberedCaptureGroups() {
        // Simulate a regex that captured digits into $1.
        let out = BotEngine.expandResponse(
            "Issue #$1 — see the tracker",
            match: "issue #42",
            groups: ["issue #42", "42"],
            nick: "alice",
            channel: "#swift"
        )
        #expect(out == "Issue #42 — see the tracker")
    }

    @Test func emptyCaptureExpandsToEmpty() {
        let out = BotEngine.expandResponse(
            "got [$1][$2]",
            match: "x",
            groups: ["x", "a"],   // $2 doesn't exist
            nick: "n",
            channel: "c"
        )
        #expect(out == "got [a][]")
    }

    @Test func unknownPlaceholderIsLeftIntact() {
        // `$foo` isn't a known keyword or a digit → passes through verbatim.
        let out = BotEngine.expandResponse(
            "hello $foo world",
            match: "!x",
            groups: ["!x"],
            nick: "alice",
            channel: "#c"
        )
        #expect(out == "hello $foo world")
    }

    @Test func trailingDollarIsLiteral() {
        let out = BotEngine.expandResponse(
            "cost $",
            match: "",
            groups: [""],
            nick: "n",
            channel: "c"
        )
        #expect(out == "cost $")
    }

    @Test func longestKeywordWins() {
        // $channel should win over $c-anything.
        let out = BotEngine.expandResponse(
            "to $channel and $nick",
            match: "x",
            groups: ["x"],
            nick: "alice",
            channel: "#swift"
        )
        #expect(out == "to #swift and alice")
    }
}
