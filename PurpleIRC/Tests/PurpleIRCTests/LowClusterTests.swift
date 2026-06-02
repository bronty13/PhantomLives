import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

/// Regression coverage for the batch-6 correctness/robustness fixes.
@Suite("LOW cluster fixes")
struct LowClusterTests {

    // MARK: - EncryptedJSON.unwrap on a sliced Data (#33)

    /// `unwrap` must work when handed a `Data` slice whose `startIndex` is
    /// non-zero — the old `suffix(from: magic.count)` used an absolute index
    /// and sliced wrong / trapped. `dropFirst` is index-agnostic.
    @Test func unwrapHandlesNonZeroStartIndexSlice() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("the quick brown fox".utf8)
        let wrapped = try EncryptedJSON.wrap(plain, key: key)

        // Prepend padding then drop it, yielding a slice with startIndex == 2.
        let slice = (Data([0x00, 0x00]) + wrapped).dropFirst(2)
        #expect(slice.startIndex != 0)   // genuinely a non-zero-based slice

        let out = try EncryptedJSON.unwrap(slice, key: key)
        #expect(out == plain)
    }

    // MARK: - IRCv3 tag CR/LF stripping (#44)

    /// `\r` / `\n` escapes in a tag value are dropped so raw line
    /// terminators never enter a parsed value; other escapes still decode.
    @Test func ircv3TagUnescapeStripsCRLF() {
        let msg = IRCMessage.parse(#"@key=a\r\nDANGER PING :x"#)
        let v = msg?.tags["key"]
        #expect(v == "aDANGER")
        #expect(v?.contains("\r") == false)
        #expect(v?.contains("\n") == false)
    }

    @Test func ircv3TagUnescapeKeepsOtherEscapes() {
        // \: -> ;   \s -> space   \\ -> \
        let msg = IRCMessage.parse(#"@k=a\sb\:c\\d PING :x"#)
        #expect(msg?.tags["k"] == "a b;c\\d")
    }

    // MARK: - Settings clamping (#54)

    @Test func chatFontSizeClampedOnDecode() {
        var s = AppSettings()
        s.chatFontSize = 0          // absurd
        let data = try! JSONEncoder().encode(s)
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.chatFontSize == 8)   // clamped up to the floor

        s.chatFontSize = 999
        let data2 = try! JSONEncoder().encode(s)
        let decoded2 = try! JSONDecoder().decode(AppSettings.self, from: data2)
        #expect(decoded2.chatFontSize == 48) // clamped down to the ceiling
    }

    @Test func purgeLogsAfterDaysClampedOnDecode() {
        var s = AppSettings()
        s.purgeLogsAfterDays = -5
        let data = try! JSONEncoder().encode(s)
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.purgeLogsAfterDays == 0)   // negative → keep-forever floor
    }
}
