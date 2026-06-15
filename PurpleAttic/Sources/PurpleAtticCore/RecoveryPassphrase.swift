import Foundation
import Security

/// Generates a strong, human-transcribable **recovery passphrase** for the restic repo's second
/// key — the one written on paper and stored in a physical safe. It is word-based (diceware-style)
/// so it survives handwriting and stressed re-typing, and every word is drawn from the system
/// CSPRNG (`SecRandomCopyBytes`) with rejection sampling — never a biased or seedable RNG.
///
/// Doing this in-app (vs. a shell one-liner, or having an assistant generate it) is the secure
/// choice: the passphrase is created on the Mac, shown once for transcription, and handed to
/// `restic key add` via a 0600 temp file — it never enters a shell history, a log, or a transcript.
public enum RecoveryPassphrase {

    public struct Generated: Equatable {
        public let phrase: String      // hyphen-joined, e.g. "river-cotton-…"
        public let words: [String]
        public let bits: Int           // entropy estimate (floor)
    }

    public enum GenError: Error, CustomStringConvertible {
        case noWordlist
        case rng
        public var description: String {
            switch self {
            case .noWordlist:
                return "No system wordlist was found to build a passphrase. Type your own recovery passphrase instead."
            case .rng:
                return "The secure random generator was unavailable."
            }
        }
    }

    /// Candidate words: the system dictionary filtered to plain lowercase a–z words of typeable
    /// length (4–7 letters), de-duplicated. Present on stock macOS; if absent we throw so the UI
    /// can fall back to a user-typed passphrase.
    static func loadWordlist() -> [String] {
        for path in ["/usr/share/dict/words", "/usr/share/dict/web2"] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var seen = Set<String>()
            var words: [String] = []
            for raw in text.split(separator: "\n") {
                let w = String(raw).trimmingCharacters(in: .whitespaces)
                guard w.count >= 4, w.count <= 7,
                      w.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) else { continue }
                if seen.insert(w).inserted { words.append(w) }
            }
            if words.count >= 1024 { return words }
        }
        return []
    }

    /// A uniform random Int in `0..<bound` via rejection sampling over CSPRNG bytes (no modulo bias).
    static func secureIndex(below bound: Int) throws -> Int {
        precondition(bound > 0 && bound <= Int(UInt32.max))
        let range = UInt32(bound)
        let limit = UInt32.max - (UInt32.max % range)   // largest multiple of range, exclusive tail rejected
        while true {
            var raw: UInt32 = 0
            let ok = withUnsafeMutableBytes(of: &raw) {
                SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) == errSecSuccess
            }
            guard ok else { throw GenError.rng }
            if raw < limit { return Int(raw % range) }
        }
    }

    /// Generate a passphrase with at least `targetBits` of entropy (default 100 ≈ uncrackable).
    /// Word count adapts to the actual wordlist size so the entropy target holds regardless of
    /// how many words the system dictionary yields.
    public static func generate(targetBits: Int = 100) throws -> Generated {
        let list = loadWordlist()
        guard !list.isEmpty else { throw GenError.noWordlist }
        let bitsPerWord = log2(Double(list.count))
        let count = max(6, Int(ceil(Double(targetBits) / bitsPerWord)))
        var chosen: [String] = []
        chosen.reserveCapacity(count)
        for _ in 0..<count {
            chosen.append(list[try secureIndex(below: list.count)])
        }
        return Generated(phrase: chosen.joined(separator: "-"),
                         words: chosen,
                         bits: Int(Double(count) * bitsPerWord))
    }
}
