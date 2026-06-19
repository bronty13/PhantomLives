import Foundation
import Testing
@testable import IRCKit

@Suite("IRC hostmask matching")
struct IRCMaskTests {

    @Test func bareNickMatchesAnyUserHost() {
        #expect(IRCMask.matches(pattern: "bob", hostmask: "bob!u@some.host"))
        #expect(IRCMask.matches(pattern: "bob", hostmask: "bob!other@elsewhere.net"))
        #expect(!IRCMask.matches(pattern: "bob", hostmask: "alice!u@some.host"))
    }

    @Test func caseInsensitive() {
        #expect(IRCMask.matches(pattern: "Bob", hostmask: "bob!u@h"))
        #expect(IRCMask.matches(pattern: "bob", hostmask: "BOB!U@H"))
    }

    @Test func hostWildcardMatches() {
        #expect(IRCMask.matches(pattern: "*!*@*.spam.com", hostmask: "x!y@mail.spam.com"))
        #expect(IRCMask.matches(pattern: "*!*@*.spam.com", hostmask: "z!q@a.b.spam.com"))
        #expect(!IRCMask.matches(pattern: "*!*@*.spam.com", hostmask: "x!y@good.org"))
    }

    @Test func questionMarkMatchesOneChar() {
        #expect(IRCMask.matches(pattern: "bo?!*@*", hostmask: "bob!u@h"))
        #expect(IRCMask.matches(pattern: "bo?!*@*", hostmask: "boz!u@h"))
        #expect(!IRCMask.matches(pattern: "bo?!*@*", hostmask: "bobby!u@h"))
    }

    @Test func fullMaskExactAndWild() {
        #expect(IRCMask.matches(pattern: "bob!ident@host.net", hostmask: "bob!ident@host.net"))
        #expect(IRCMask.matches(pattern: "bob!*@host.net", hostmask: "bob!anything@host.net"))
        #expect(!IRCMask.matches(pattern: "bob!*@host.net", hostmask: "bob!x@other.net"))
    }

    @Test func starMatchesEmptyAndTrailing() {
        #expect(IRCMask.glob(Array("a*"), Array("a")))
        #expect(IRCMask.glob(Array("a*"), Array("abc")))
        #expect(IRCMask.glob(Array("*"), Array("")))
        #expect(!IRCMask.glob(Array("a?"), Array("a")))
    }
}
