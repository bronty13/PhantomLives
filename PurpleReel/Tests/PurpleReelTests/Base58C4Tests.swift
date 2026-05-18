import XCTest
import CryptoKit
@testable import PurpleReel

/// C4 ID = SHA-512 digest of the file, base58-encoded with the
/// C4 alphabet, prefixed `c4`, zero-padded with the alphabet's
/// "1" digit (the base58 zero) to exactly 90 characters total.
/// Reference spec: https://github.com/Avalanche-io/c4
final class Base58C4Tests: XCTestCase {

    // MARK: - Shape invariants

    func testC4IDIsExactly90Characters() {
        // Spec mandates fixed-width 90 chars (`c4` + 88 base58
        // digits) so two C4 IDs are visually comparable without
        // padding logic in the consumer.
        let digest = Data(SHA512.hash(data: Data("hello".utf8)))
        let id = Base58.c4ID(from: digest)
        XCTAssertEqual(id.count, 90,
            "C4 IDs must be 90 chars; got \(id.count) — '\(id)'")
    }

    func testC4IDStartsWithLowercaseC4() {
        let digest = Data(SHA512.hash(data: Data("hello".utf8)))
        let id = Base58.c4ID(from: digest)
        XCTAssertTrue(id.hasPrefix("c4"),
            "C4 IDs must start with the literal `c4`; got '\(id.prefix(4))'")
    }

    func testC4IDOnlyUsesC4AlphabetCharacters() {
        // The C4 alphabet deliberately excludes the four
        // look-alike characters (0, O, I, l).
        let allowed = Set(Base58.c4Alphabet) // already contains everything legal
        let digest = Data(SHA512.hash(data: Data("the quick brown fox".utf8)))
        let id = Base58.c4ID(from: digest)
        // Drop the literal `c4` prefix and ensure every remaining
        // char is in the alphabet.
        for ch in id.dropFirst(2) {
            XCTAssertTrue(allowed.contains(ch),
                "Character '\(ch)' is not in the C4 base58 alphabet")
        }
    }

    func testForbiddenLookalikeCharactersAreExcluded() {
        // Belt-and-braces: explicitly verify the four illegal
        // characters never appear, no matter what input we feed.
        let inputs: [String] = [
            "", "0", "OOOO", "IIII", "llll",
            "Lorem ipsum dolor sit amet"
        ]
        for s in inputs {
            let digest = Data(SHA512.hash(data: Data(s.utf8)))
            let id = Base58.c4ID(from: digest).dropFirst(2)
            for c in "0OIl" {
                XCTAssertFalse(id.contains(c),
                    "C4 ID for input '\(s)' contained forbidden char '\(c)': \(id)")
            }
        }
    }

    // MARK: - Determinism

    func testSameInputProducesSameC4ID() {
        let payload = Data("PurpleReel test corpus".utf8)
        let d1 = Data(SHA512.hash(data: payload))
        let d2 = Data(SHA512.hash(data: payload))
        XCTAssertEqual(Base58.c4ID(from: d1), Base58.c4ID(from: d2),
            "Equal SHA-512 digests must encode to identical C4 IDs")
    }

    func testDifferentInputsProduceDifferentC4IDs() {
        let a = Data(SHA512.hash(data: Data("a".utf8)))
        let b = Data(SHA512.hash(data: Data("b".utf8)))
        XCTAssertNotEqual(Base58.c4ID(from: a), Base58.c4ID(from: b),
            "Distinct inputs must encode to distinct C4 IDs")
    }

    // MARK: - Edge case: all-zero digest (padding behaviour)

    func testAllZeroDigestEncodesAsAllPaddingDigits() {
        // An all-zero 64-byte digest exercises the pad-loop in
        // the encoder: the bignum loop terminates immediately,
        // so every output character is the "zero" digit (`1`
        // per Bitcoin-derived base58 conventions, which is also
        // the first character of the C4 alphabet).
        let zero = Data(repeating: 0, count: 64)
        let id = Base58.c4ID(from: zero)
        XCTAssertEqual(id.count, 90)
        XCTAssertTrue(id.hasPrefix("c4"))
        // Every char after the prefix is the alphabet's first
        // digit (the "zero").
        let zeroChar = Base58.c4Alphabet.first!
        for ch in id.dropFirst(2) {
            XCTAssertEqual(ch, zeroChar,
                "All-zero digest must encode entirely as pad digits")
        }
    }

    // MARK: - HashingService integration

    func testHashingServiceWithC4ReturnsValidC4ID() throws {
        // End-to-end check: HashingService.hash(file:algorithm:.c4)
        // produces a string that has the C4-ID shape.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-c4-\(UUID().uuidString).bin")
        try Data("the rain in Spain".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let id = try HashingService.hash(file: tmp, algorithm: .c4)
        XCTAssertEqual(id.count, 90)
        XCTAssertTrue(id.hasPrefix("c4"))
        // And it's deterministic against the same input.
        let id2 = try HashingService.hash(file: tmp, algorithm: .c4)
        XCTAssertEqual(id, id2)
    }
}
