import Foundation
import Testing
@testable import PurpleIRC

@Suite("Highlight rule matcher")
@MainActor
struct HighlightMatcherTests {

    private func rule(_ pattern: String,
                      isRegex: Bool = false,
                      caseSensitive: Bool = false,
                      networks: [UUID] = [],
                      enabled: Bool = true,
                      name: String = "test") -> HighlightRule {
        var r = HighlightRule()
        r.name = name
        r.pattern = pattern
        r.isRegex = isRegex
        r.caseSensitive = caseSensitive
        r.networks = networks
        r.enabled = enabled
        return r
    }

    @Test func literalMatchCaseInsensitive() {
        let m = HighlightMatcher()
        let hits = m.evaluate(rules: [rule("swift")],
                              text: "Learning Swift today",
                              networkID: UUID())
        #expect(hits.count == 1)
        #expect(hits[0].ranges.count == 1)
    }

    @Test func literalMatchHasWordBoundaries() {
        // "foo" should match "foo bar" but NOT "foobar" — word boundaries.
        let m = HighlightMatcher()
        let hits1 = m.evaluate(rules: [rule("foo")], text: "foo bar", networkID: UUID())
        let hits2 = m.evaluate(rules: [rule("foo")], text: "foobar baz", networkID: UUID())
        #expect(hits1.count == 1)
        #expect(hits2.count == 0)
    }

    @Test func literalCaseSensitiveHonored() {
        let m = HighlightMatcher()
        let hits = m.evaluate(rules: [rule("Swift", caseSensitive: true)],
                              text: "learning swift today",
                              networkID: UUID())
        #expect(hits.count == 0)
    }

    @Test func disabledRuleIsSkipped() {
        let m = HighlightMatcher()
        let hits = m.evaluate(rules: [rule("swift", enabled: false)],
                              text: "Learning Swift today",
                              networkID: UUID())
        #expect(hits.count == 0)
    }

    @Test func networkFilterExcludesOtherNetworks() {
        let m = HighlightMatcher()
        let allowedNet = UUID()
        let otherNet = UUID()
        let r = rule("swift", networks: [allowedNet])

        #expect(m.evaluate(rules: [r], text: "Swift rules", networkID: allowedNet).count == 1)
        #expect(m.evaluate(rules: [r], text: "Swift rules", networkID: otherNet).count == 0)
    }

    @Test func emptyNetworksListMeansAllNetworks() {
        let m = HighlightMatcher()
        let r = rule("swift", networks: [])
        #expect(m.evaluate(rules: [r], text: "Swift rules", networkID: UUID()).count == 1)
        #expect(m.evaluate(rules: [r], text: "Swift rules", networkID: UUID()).count == 1)
    }

    @Test func regexWithCaptureGroups() {
        let m = HighlightMatcher()
        let hits = m.evaluate(
            rules: [rule(#"issue\s+#(\d+)"#, isRegex: true)],
            text: "See issue #42 for details",
            networkID: UUID())
        #expect(hits.count == 1)
        #expect(hits[0].ranges.count == 1)
    }

    @Test func invalidRegexIsTreatedAsNoMatchNotCrash() {
        let m = HighlightMatcher()
        // Unmatched bracket — invalid.
        let hits = m.evaluate(rules: [rule("[unclosed", isRegex: true)],
                              text: "some text",
                              networkID: UUID())
        #expect(hits.count == 0)
    }

    @Test func strippedCodesAreMatchedAgainst() {
        // Incoming message with mIRC codes should still match on the stripped text.
        let m = HighlightMatcher()
        let raw = "\u{02}Swift\u{02} is a language"
        let hits = m.evaluate(rules: [rule("swift")], text: raw, networkID: UUID())
        #expect(hits.count == 1)
    }

    @Test func multipleRulesAllMatchAndPreserveOrder() {
        let m = HighlightMatcher()
        let r1 = rule("swift", name: "first")
        let r2 = rule("language", name: "second")
        let hits = m.evaluate(rules: [r1, r2],
                              text: "Swift is a great language",
                              networkID: UUID())
        #expect(hits.count == 2)
        #expect(hits[0].rule.name == "first")
        #expect(hits[1].rule.name == "second")
    }

    @Test func multipleOccurrencesProduceMultipleRanges() {
        let m = HighlightMatcher()
        let hits = m.evaluate(rules: [rule("foo")],
                              text: "foo bar foo baz foo",
                              networkID: UUID())
        #expect(hits.count == 1)
        #expect(hits[0].ranges.count == 3)
    }

    @Test func emptyPatternIsSkipped() {
        let m = HighlightMatcher()
        let hits = m.evaluate(rules: [rule("")],
                              text: "anything",
                              networkID: UUID())
        #expect(hits.count == 0)
    }

    @Test func cacheInvalidationAfterClearCache() {
        // Compile once, clear, match again — just proves clearCache doesn't break things.
        let m = HighlightMatcher()
        _ = m.evaluate(rules: [rule("swift")], text: "Swift", networkID: UUID())
        m.clearCache()
        let hits = m.evaluate(rules: [rule("swift")], text: "Swift", networkID: UUID())
        #expect(hits.count == 1)
    }
}
