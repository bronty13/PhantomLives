import Foundation
import CryptoKit

/// BIP39 24-word recovery key. The Phase B addition that lets PurpleDiary
/// recover the user's DEK after a Keychain loss without any iCloud /
/// CloudKit / Time Machine dependency.
///
/// **Encoding.** 256 bits of fresh entropy + 8 bits of SHA-256 checksum
/// = 264 bits, split into 24 groups of 11 bits each, each indexed into
/// `BIP39Wordlist.words`. Standard BIP39; identical wire format to
/// every crypto wallet you've ever used.
///
/// **Decoding.** Words → 11-bit indices → 264 bits → split. Verify the
/// checksum word; if it mismatches, the phrase is rejected as
/// `RecoveryKeyError.checksumMismatch` and the unlock UX surfaces a
/// "this isn't right — check for typos" message. Catches the
/// single-word typo case essentially for free (the checksum word
/// changes with any entropy edit).
///
/// **Why BIP39 and not raw hex.** See HANDOFF.md Phase B.1
/// (2026-05-15). TL;DR: handwriting / dictation / mental model already
/// understood by everyone who's used a crypto wallet or iCloud
/// Recovery Key, plus free typo detection via the checksum word.
enum RecoveryKey {

    enum RecoveryKeyError: Error, Equatable {
        case wrongWordCount(actual: Int)
        case wordNotInList(word: String)
        case checksumMismatch
        case internalError
    }

    /// Number of words in a recovery phrase. Locked at 24 for the
    /// strongest BIP39 entropy tier (256 bits + 8-bit checksum).
    static let wordCount = 24

    /// Entropy size in bytes. 24 words → 256 bits / 32 bytes.
    static let entropyByteCount = 32

    // MARK: - Generation

    /// Generate a fresh recovery phrase. 256 bits of cryptographic
    /// entropy from `Crypto.randomBytes` (which wraps
    /// `SecRandomCopyBytes`), plus the BIP39 checksum word.
    static func generate() -> [String] {
        let entropy = Crypto.randomBytes(entropyByteCount)
        // generate() can't fail at runtime — entropy is well-formed
        // by construction. The throwing variant exists for the
        // testable path where a fixture passes in known entropy.
        return try! encode(entropy: entropy)
    }

    /// Encode arbitrary 32-byte entropy as a 24-word BIP39 phrase.
    /// Exposed primarily for tests that need deterministic phrases
    /// from fixed entropy.
    static func encode(entropy: Data) throws -> [String] {
        guard entropy.count == entropyByteCount else {
            throw RecoveryKeyError.internalError
        }
        // BIP39 checksum: first (entropy_bits / 32) bits of SHA-256.
        // For 256-bit entropy → 8 checksum bits → 264 bits total →
        // 24 × 11-bit groups, one word per group.
        let checksumByte = checksumFirstByte(of: entropy)
        var bits = [UInt8]()
        bits.reserveCapacity(264)
        for byte in entropy {
            for i in (0..<8).reversed() {
                bits.append((byte >> i) & 0x01)
            }
        }
        for i in (0..<8).reversed() {
            bits.append((checksumByte >> i) & 0x01)
        }
        // Group into 11-bit indices.
        var words: [String] = []
        words.reserveCapacity(wordCount)
        for group in 0..<wordCount {
            var index = 0
            for j in 0..<11 {
                index = (index << 1) | Int(bits[group * 11 + j])
            }
            words.append(BIP39Wordlist.words[index])
        }
        return words
    }

    // MARK: - Decoding / validation

    /// Decode a 24-word phrase back to its entropy bytes. Throws on
    /// wrong count, unknown words, or checksum mismatch — never
    /// returns garbage. Whitespace in the input is forgiving:
    /// leading / trailing space stripped, multiple-space sequences
    /// collapsed, case folded to lowercase (BIP39 is lowercase-only
    /// so we normalize for user convenience).
    static func entropy(from phrase: String) throws -> Data {
        let words = phrase
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        return try entropy(from: words)
    }

    /// Words-array variant. Most callers use the string form above;
    /// this is exposed for tests + the chip-style UI in Phase B.4
    /// where the user types one word at a time.
    static func entropy(from words: [String]) throws -> Data {
        guard words.count == wordCount else {
            throw RecoveryKeyError.wrongWordCount(actual: words.count)
        }
        var bits = [UInt8]()
        bits.reserveCapacity(264)
        for word in words {
            guard let idx = BIP39Wordlist.indexByWord[word] else {
                throw RecoveryKeyError.wordNotInList(word: word)
            }
            for i in (0..<11).reversed() {
                bits.append(UInt8((idx >> i) & 0x01))
            }
        }
        // Repack the first 256 bits into entropy bytes.
        var entropy = Data(count: entropyByteCount)
        for byteIdx in 0..<entropyByteCount {
            var b: UInt8 = 0
            for j in 0..<8 {
                b = (b << 1) | bits[byteIdx * 8 + j]
            }
            entropy[byteIdx] = b
        }
        // The last 8 bits are the supplied checksum. Verify against
        // the SHA-256 of the entropy we just reconstructed.
        var supplied: UInt8 = 0
        for j in 0..<8 {
            supplied = (supplied << 1) | bits[256 + j]
        }
        guard supplied == checksumFirstByte(of: entropy) else {
            throw RecoveryKeyError.checksumMismatch
        }
        return entropy
    }

    /// Convenience predicate used by the UX (input-time green-checkmark
    /// affordance). Returns true iff `phrase` decodes cleanly.
    static func isValid(_ phrase: String) -> Bool {
        (try? entropy(from: phrase)) != nil
    }

    /// Pull every checksum-valid 24-word phrase out of arbitrary pasted text.
    ///
    /// The user might paste a clean space-separated line, a numbered list
    /// (`1. abandon …`), or a whole saved file with prose around the words.
    /// We tokenize on non-letters (so numbering/punctuation vanish), lowercase,
    /// keep only BIP39 words (so prose that isn't a dictionary word is dropped),
    /// then return each contiguous 24-word window whose checksum passes. Random
    /// prose practically never checksums, so the real phrase is normally the only
    /// hit; callers that need certainty (the actual key must decrypt an envelope)
    /// try each candidate. Returns `[]` when no valid phrase is present.
    static func candidatePhrases(in text: String) -> [[String]] {
        let cleaned = String(text.lowercased().map { $0.isLetter ? $0 : " " })
        let tokens = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { BIP39Wordlist.indexByWord[$0] != nil }
        guard tokens.count >= wordCount else { return [] }
        var out: [[String]] = []
        for start in 0...(tokens.count - wordCount) {
            let window = Array(tokens[start..<(start + wordCount)])
            if (try? entropy(from: window)) != nil, !out.contains(window) {
                out.append(window)
            }
        }
        return out
    }

    // MARK: - KDF helper

    /// Derive a 256-bit KEK from a recovery phrase + salt. Uses the
    /// same PBKDF2-SHA256 / 300k-iteration shape `KeyStore` already
    /// uses for passphrase mode — keeps the crypto surface coherent.
    ///
    /// The recovery key is high-entropy (256 bits) and the KDF here
    /// adds work factor against an attacker who has stolen the
    /// encrypted envelope. Same defense-in-depth pattern as iCloud
    /// Recovery Keys: the input is already strong, the KDF makes
    /// brute force still costly per attempt.
    static func deriveKEK(phrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        try Crypto.deriveKey(passphrase: phrase.lowercased(),
                             salt: salt,
                             iterations: iterations)
    }

    // MARK: - Formatting

    /// Render a 24-word phrase as a single space-separated line. Used
    /// by the copy-to-clipboard affordance.
    static func format(_ words: [String]) -> String {
        words.joined(separator: " ")
    }

    /// Render with explicit numbering ("1. abandon\n2. ability\n…").
    /// Used by the print / save-to-file affordance so the user has
    /// an aid against missing or duplicating a word when transcribing.
    static func formatNumbered(_ words: [String]) -> String {
        words.enumerated()
            .map { idx, word in "\(idx + 1). \(word)" }
            .joined(separator: "\n")
    }

    // MARK: - Internal

    /// First byte of SHA-256(entropy). For 256-bit entropy BIP39
    /// uses the first 8 bits of the digest as the checksum.
    ///
    /// SHA256Digest's `first` is the throwing-closure
    /// `first(where:)` rather than a stored property, so route
    /// through `Data(digest)` to get plain byte access.
    private static func checksumFirstByte(of entropy: Data) -> UInt8 {
        let digest = Data(SHA256.hash(data: entropy))
        return digest.first ?? 0
    }
}
