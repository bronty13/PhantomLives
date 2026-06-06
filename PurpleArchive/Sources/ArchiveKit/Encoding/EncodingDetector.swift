import Foundation

/// Filename-encoding detection — the cross-platform pain point no other Mac tool
/// nails. Archives created on Windows/Linux often store filenames in a legacy
/// codepage (CP437, Shift-JIS, GBK, EUC-KR, Big5, KOI8-R, windows-125x) with no
/// UTF-8 flag, so a naïve UTF-8 decode produces mojibake like `æ–‡å­—`.
///
/// libarchive hands us the raw on-disk name bytes (`ArchiveEntry.rawNameBytes`).
/// We score those bytes against a candidate set and pick the most plausible
/// encoding for the *whole archive*, then let the user override it live — the
/// GUI re-decodes the listing in place with no re-extraction.
public enum EncodingDetector {

    /// Candidate encodings, in rough priority order. UTF-8 first (modern zips),
    /// then the common legacy codepages seen in the wild.
    public static let candidates: [DetectedEncoding] = [
        DetectedEncoding(.utf8, "UTF-8"),
        cf(.dosLatinUS, "CP437 (DOS Latin US)"),
        cf(.dosLatin1,  "CP850 (DOS Latin 1)"),
        DetectedEncoding(.shiftJIS, "Shift-JIS (Japanese)"),
        cf(.dosJapanese, "CP932 (Japanese)"),
        DetectedEncoding(.japaneseEUC, "EUC-JP (Japanese)"),
        cf(.dosChineseSimplif, "GBK (Simplified Chinese)"),
        cf(.dosChineseTrad, "Big5 (Traditional Chinese)"),
        cf(.dosKorean, "EUC-KR (Korean)"),
        DetectedEncoding(.windowsCP1251, "Windows-1251 (Cyrillic)"),
        cf(.KOI8_R, "KOI8-R (Cyrillic)"),
        DetectedEncoding(.windowsCP1252, "Windows-1252 (Western)"),
        DetectedEncoding(.isoLatin1, "ISO-8859-1 (Latin-1)"),
    ]

    /// Pick the most plausible encoding for an archive given all of its raw
    /// entry-name byte strings. Returns UTF-8 when every name is pure ASCII (the
    /// common, unambiguous case) — there's nothing to fix.
    public static func detect(rawNames: [[UInt8]]) -> DetectedEncoding {
        let nonAscii = rawNames.filter { $0.contains { $0 >= 0x80 } }
        guard !nonAscii.isEmpty else { return candidates[0] }   // all ASCII → UTF-8

        // Valid UTF-8 is authoritative: a name whose bytes form well-formed
        // UTF-8 is overwhelmingly likely to *be* UTF-8 (the modern default and
        // the zip "UTF-8 flag" convention). Legacy codepages that happen to also
        // be valid UTF-8 are vanishingly rare for real filenames.
        if nonAscii.allSatisfy({ decode($0, using: .utf8) != nil }) {
            return candidates[0]
        }

        // Otherwise score the legacy candidates by AVERAGE per-character quality
        // (so an encoding isn't rewarded just for splitting bytes into more
        // glyphs) and pick the best. Earlier (higher-priority) candidates win
        // ties via the strict `>`.
        var best = candidates[0]
        var bestScore = -Double.greatestFiniteMagnitude
        for candidate in candidates where candidate.encoding != .utf8 {
            var total = 0.0
            var decodable = true
            for name in nonAscii {
                guard let score = score(name, encoding: candidate.encoding) else {
                    decodable = false; break
                }
                total += score
            }
            guard decodable else { continue }
            let avg = total / Double(nonAscii.count)
            if avg > bestScore {
                bestScore = avg
                best = candidate
            }
        }
        return best
    }

    /// Decode a single raw name with an encoding, or nil if it can't represent
    /// those bytes. UTF-8 is strict (invalid sequences → nil) so it doesn't win
    /// by silently inserting replacement characters.
    public static func decode(_ bytes: [UInt8], using encoding: String.Encoding) -> String? {
        if encoding == .utf8 {
            // Strict: reject invalid UTF-8 rather than lossy-decode.
            var s = ""
            var decoder = UTF8()
            var it = bytes.makeIterator()
            loop: while true {
                switch decoder.decode(&it) {
                case .scalarValue(let v): s.unicodeScalars.append(v)
                case .emptyInput: break loop
                case .error: return nil
                }
            }
            return s
        }
        return String(bytes: bytes, encoding: encoding)
    }

    // MARK: - Scoring

    /// Average per-character plausibility (higher is better), plus a
    /// script-consistency bonus: genuine names keep their non-ASCII characters
    /// in one script (all CJK, all Cyrillic, all accented-Latin), whereas
    /// mojibake from the wrong codepage sprays across unrelated Unicode blocks.
    private static func score(_ bytes: [UInt8], encoding: String.Encoding) -> Double? {
        guard let s = decode(bytes, using: encoding), !s.isEmpty else { return nil }
        var total = 0.0
        var charCount = 0
        var nonASCII = 0
        var scripts = Set<Int>()
        for scalar in s.unicodeScalars {
            charCount += 1
            switch scalar.value {
            case 0xFFFD:                       return nil          // replacement → disqualify
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F:
                total -= 6                                          // control chars: implausible in names
            case 0x80...0x9F:                  total -= 4          // C1 controls
            case 0x20...0x7E:                  total += 1          // ASCII printable
            default:
                if scalar.properties.isAlphabetic {
                    // CJK ideographs score slightly lower than phonetic letters:
                    // arbitrary high-byte pairs decode to *some* valid ideograph
                    // far more readily than to coherent Cyrillic/Latin/kana, so a
                    // double-byte CJK reading deserves marginally less trust. This
                    // breaks ambiguous ties (e.g. cp1251 Cyrillic vs EUC-JP kanji
                    // for the same bytes) toward the phonetic script.
                    let isCJKIdeograph = (0x3400...0x9FFF).contains(scalar.value)
                    total += isCJKIdeograph ? 1.7 : 2
                } else {
                    total += 0.5
                }
                nonASCII += 1
                scripts.insert(scriptBucket(scalar.value))
            }
        }
        var avg = total / Double(max(1, charCount))
        if nonASCII >= 2 && scripts.count == 1 { avg += 1.5 }       // consistent script → likely real
        avg -= Double(max(0, scripts.count - 1)) * 0.75            // spread across scripts → likely mojibake
        return avg
    }

    /// Coarse Unicode script bucket for the consistency heuristic.
    private static func scriptBucket(_ v: UInt32) -> Int {
        switch v {
        case 0x0080...0x024F: return 1   // Latin-1 supplement / extended
        case 0x0370...0x03FF: return 2   // Greek
        case 0x0400...0x04FF: return 3   // Cyrillic
        case 0x3040...0x30FF: return 4   // Hiragana/Katakana
        case 0x3400...0x9FFF: return 5   // CJK ideographs
        case 0xAC00...0xD7AF: return 6   // Hangul
        case 0x2000...0x2BFF: return 7   // punctuation/symbols/box-drawing
        default:              return 9
        }
    }

    private static func cf(_ enc: CFStringEncodings, _ label: String) -> DetectedEncoding {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(enc.rawValue))
        return DetectedEncoding(String.Encoding(rawValue: raw), label)
    }
}

/// An encoding paired with a human label for the GUI picker.
public struct DetectedEncoding: Identifiable, Hashable, Sendable {
    public let encoding: String.Encoding
    public let label: String
    public var id: UInt { encoding.rawValue }
    init(_ encoding: String.Encoding, _ label: String) {
        self.encoding = encoding
        self.label = label
    }
}
