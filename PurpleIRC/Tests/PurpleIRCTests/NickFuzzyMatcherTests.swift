import Foundation
import Testing
@testable import PurpleIRC

/// `NickFuzzyMatcher` — the fuzzy nick logic behind the sidebar "Find … in
/// logs" action. Covers normalisation, the prefix-weighted similarity score,
/// the variant-matching predicate at different fuzziness thresholds, and
/// author extraction from persisted log-line bodies.
@Suite("Nick fuzzy matcher")
struct NickFuzzyMatcherTests {

    /// The Find sheet's default fuzziness (see NickFindView.threshold).
    private let defaultThreshold = 0.84

    // MARK: - Normalisation

    @Test func normalizeStripsDecorationDigitsAndAway() {
        #expect(NickFuzzyMatcher.normalize("john_doe") == "johndoe")
        #expect(NickFuzzyMatcher.normalize("johndoe1") == "johndoe")
        #expect(NickFuzzyMatcher.normalize("johnny1") == "johnny")
        #expect(NickFuzzyMatcher.normalize("jdough1") == "jdough")
        #expect(NickFuzzyMatcher.normalize("[John]") == "john")
        #expect(NickFuzzyMatcher.normalize("john|away") == "john")
        #expect(NickFuzzyMatcher.normalize("Bob`") == "bob")
    }

    // MARK: - Similarity ordering

    @Test func similarityRewardsSharedPrefix() {
        // johndoe is a closer variant of johnny than of jdough — the shared
        // "john" prefix should make that ordering hold.
        let toJohnny = NickFuzzyMatcher.similarity("john_doe", "johnny1")
        let toJdough = NickFuzzyMatcher.similarity("john_doe", "jdough1")
        #expect(toJohnny > toJdough)
        #expect(NickFuzzyMatcher.similarity("john_doe", "johndoe") == 1.0) // identical roots
        #expect(NickFuzzyMatcher.similarity("john_doe", "") == 0.0)
    }

    // MARK: - matches() at the default fuzziness

    @Test func defaultThresholdCatchesCommonVariants() {
        #expect(NickFuzzyMatcher.matches(target: "john_doe", candidate: "johndoe", threshold: defaultThreshold))
        #expect(NickFuzzyMatcher.matches(target: "john_doe", candidate: "johndoe1", threshold: defaultThreshold))
        #expect(NickFuzzyMatcher.matches(target: "john_doe", candidate: "johnny1", threshold: defaultThreshold))
    }

    @Test func defaultThresholdExcludesDistantVariant() {
        // jdough1 is too far at the default — only a looser slider reaches it.
        #expect(!NickFuzzyMatcher.matches(target: "john_doe", candidate: "jdough1", threshold: defaultThreshold))
    }

    @Test func looseThresholdReachesDistantVariant() {
        #expect(NickFuzzyMatcher.matches(target: "john_doe", candidate: "jdough1", threshold: 0.50))
    }

    @Test func unrelatedNicksNeverMatch() {
        #expect(!NickFuzzyMatcher.matches(target: "john_doe", candidate: "zelda", threshold: 0.50))
        #expect(!NickFuzzyMatcher.matches(target: "john_doe", candidate: "", threshold: 0.0))
    }

    // MARK: - Author extraction from log-line bodies

    @Test func authorFromMessageShapes() {
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "<alice> hello") == ["alice"])
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "→alice→ my own line") == ["alice"])
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "-alice- a notice") == ["alice"])
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "* alice waves") == ["alice"])
    }

    @Test func authorFromJoinPartQuitRename() {
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "→ alice joined") == ["alice"])
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "← bob left (bye)") == ["bob"])
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "← bob quit (ping timeout)") == ["bob"])
        // Rename surfaces both the old and new nick.
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "alice → alice_") == ["alice", "alice_"])
    }

    @Test func authorlessKindsYieldNothing() {
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "MOTD welcome to the server").isEmpty)
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "! connection error").isEmpty)
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "alice set topic: hi").isEmpty)
        #expect(NickFuzzyMatcher.authors(ofLogLineBody: "").isEmpty)
    }
}
