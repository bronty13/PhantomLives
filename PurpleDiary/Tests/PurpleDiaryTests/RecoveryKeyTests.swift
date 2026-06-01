import XCTest
@testable import PurpleDiary

final class RecoveryKeyTests: XCTestCase {

    func testGenerateProduces24ValidWords() {
        let words = RecoveryKey.generate()
        XCTAssertEqual(words.count, 24)
        for w in words {
            XCTAssertNotNil(BIP39Wordlist.indexByWord[w], "'\(w)' must be in the BIP39 wordlist")
        }
    }

    func testGeneratedPhraseRoundTrips() throws {
        let words = RecoveryKey.generate()
        let entropy = try RecoveryKey.entropy(from: words)
        let reencoded = try RecoveryKey.encode(entropy: entropy)
        XCTAssertEqual(words, reencoded)
    }

    /// Canonical BIP39 reference vector: 32 zero bytes → 23×"abandon" + "art".
    func testAllZeroEntropyMatchesReferenceVector() throws {
        let words = try RecoveryKey.encode(entropy: Data(repeating: 0, count: 32))
        XCTAssertEqual(words.count, 24)
        XCTAssertEqual(Array(words.prefix(23)), Array(repeating: "abandon", count: 23))
        XCTAssertEqual(words.last, "art")
    }

    func testDecodeToleratesWhitespaceAndCase() throws {
        let words = RecoveryKey.generate()
        let messy = "   " + words.map { $0.uppercased() }.joined(separator: "   ") + "  "
        XCTAssertNoThrow(try RecoveryKey.entropy(from: messy))
    }

    func testDecodeRejectsWrongWordCount() {
        XCTAssertThrowsError(try RecoveryKey.entropy(from: "abandon abandon abandon"))
    }

    func testDecodeRejectsUnknownWord() {
        var words = RecoveryKey.generate()
        words[5] = "notabip39word"
        XCTAssertThrowsError(try RecoveryKey.entropy(from: words))
    }

    /// A single-word change (to another valid word) almost always breaks the
    /// checksum — the property that catches transcription typos.
    func testSingleWordTypoFailsChecksum() throws {
        var words = try RecoveryKey.encode(entropy: Data(repeating: 0, count: 32)) // …abandon art
        words[0] = "ability" // valid word, wrong entropy
        XCTAssertThrowsError(try RecoveryKey.entropy(from: words)) { err in
            XCTAssertEqual(err as? RecoveryKey.RecoveryKeyError, .checksumMismatch)
        }
    }

    func testIsValidMatchesDecoding() {
        XCTAssertTrue(RecoveryKey.isValid(RecoveryKey.format(RecoveryKey.generate())))
        XCTAssertFalse(RecoveryKey.isValid("clearly not a recovery phrase"))
    }

    // MARK: - candidatePhrases (paste-back tolerance)

    func testCandidateFromCleanLine() {
        let words = RecoveryKey.generate()
        let hits = RecoveryKey.candidatePhrases(in: RecoveryKey.format(words))
        XCTAssertEqual(hits.first, words)
    }

    func testCandidateFromNumberedList() {
        let words = RecoveryKey.generate()
        // The save-to-file body: "1. word\n2. word\n…"
        let hits = RecoveryKey.candidatePhrases(in: RecoveryKey.formatNumbered(words))
        XCTAssertTrue(hits.contains(words), "a numbered list still yields the 24 words")
    }

    func testCandidateFromSavedFileWithProseHeader() {
        let words = RecoveryKey.generate()
        // Mirror the actual saved-file format: prose header + numbered words.
        let file = """
        PurpleDiary — recovery key for the “Secret” vault
        Generated 2026-06-01T00:00:00Z

        Anyone holding this key can open this vault. Store it as carefully as a seed phrase.

        \(RecoveryKey.formatNumbered(words))
        """
        let hits = RecoveryKey.candidatePhrases(in: file)
        XCTAssertTrue(hits.contains(words), "pasting the whole saved file recovers the phrase despite prose")
    }

    func testCandidateRejectsGarbage() {
        XCTAssertTrue(RecoveryKey.candidatePhrases(in: "just some random sentence without a key").isEmpty)
        XCTAssertTrue(RecoveryKey.candidatePhrases(in: "").isEmpty)
    }
}
