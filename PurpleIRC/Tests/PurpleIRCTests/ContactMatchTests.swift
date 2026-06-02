import Foundation
import Testing
@testable import PurpleIRC

/// `ContactMatchResult.matches` — the needle/candidate test behind the
/// address-book "matches in seen/logs" lookup. Fuzzy (substring) matching
/// now requires a needle of at least 3 chars so short nicks don't match
/// every contact that merely contains those letters.
@Suite("Contact matcher")
struct ContactMatchTests {

    @Test func exactMatchAlwaysCounts() {
        #expect(ContactMatchResult.matches(needle: "al", candidate: "al"))
        #expect(ContactMatchResult.matches(needle: "AL", candidate: "al"))   // case-insensitive
        #expect(ContactMatchResult.matches(needle: "bob", candidate: "Bob"))
    }

    @Test func shortNeedleDoesNotFuzzyMatch() {
        // Before the fix these all matched via substring `contains`.
        #expect(!ContactMatchResult.matches(needle: "al", candidate: "Walter"))
        #expect(!ContactMatchResult.matches(needle: "al", candidate: "balance"))
        #expect(!ContactMatchResult.matches(needle: "bo", candidate: "Bob"))
    }

    @Test func longNeedleFuzzyMatches() {
        // needle contained in candidate
        #expect(ContactMatchResult.matches(needle: "bob", candidate: "bob123"))
        #expect(ContactMatchResult.matches(needle: "alice", candidate: "alice_"))
        // candidate (>=3 chars) contained in a longer needle
        #expect(ContactMatchResult.matches(needle: "alice_", candidate: "lic"))
    }

    @Test func emptyNeedleNeverMatches() {
        #expect(!ContactMatchResult.matches(needle: "", candidate: "anything"))
    }
}
