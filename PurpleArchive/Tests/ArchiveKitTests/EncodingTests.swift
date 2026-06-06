import XCTest
@testable import ArchiveKit

/// Filename-encoding detection — the cross-platform differentiator. Drives the
/// detector with the exact legacy-codepage byte sequences that real Windows /
/// Linux zips embed, and asserts we recover the correct Unicode names.
final class EncodingTests: XCTestCase {

    func testPureASCIIStaysUTF8() {
        let names: [[UInt8]] = [Array("hello.txt".utf8), Array("a/b/c.dat".utf8)]
        XCTAssertEqual(EncodingDetector.detect(rawNames: names).encoding, .utf8)
    }

    func testValidUTF8IsDetected() {
        // "café.txt" as UTF-8 (é = 0xC3 0xA9).
        let utf8: [UInt8] = Array("café.txt".utf8)
        let detected = EncodingDetector.detect(rawNames: [utf8])
        XCTAssertEqual(EncodingDetector.decode(utf8, using: detected.encoding), "café.txt")
    }

    func testShiftJISJapanese() {
        // "日本.txt" in Shift-JIS: 日=0x93 0xFA, 本=0x96 0x7B.
        let sjis: [UInt8] = [0x93, 0xFA, 0x96, 0x7B] + Array(".txt".utf8)
        let detected = EncodingDetector.detect(rawNames: [sjis])
        let decoded = EncodingDetector.decode(sjis, using: detected.encoding)
        XCTAssertEqual(decoded, "日本.txt", "got \(decoded ?? "nil") via \(detected.label)")
    }

    func testCP437AccentBeatsWindows1252() {
        // "café.txt" in CP437: é = 0x82 (in windows-1252 0x82 is a low quote, so
        // CP437 should score higher and win).
        let cp437: [UInt8] = [0x63, 0x61, 0x66, 0x82] + Array(".txt".utf8)
        let detected = EncodingDetector.detect(rawNames: [cp437])
        XCTAssertEqual(EncodingDetector.decode(cp437, using: detected.encoding), "café.txt",
                       "decoded via \(detected.label)")
    }

    func testWindows1251Cyrillic() {
        // "привет" in windows-1251.
        let cp1251: [UInt8] = [0xEF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]
        let detected = EncodingDetector.detect(rawNames: [cp1251])
        XCTAssertEqual(EncodingDetector.decode(cp1251, using: detected.encoding), "привет",
                       "decoded via \(detected.label)")
    }

    func testEntryReDecode() {
        // An entry whose raw bytes are Shift-JIS but were naïvely UTF-8'd at list
        // time re-decodes correctly through reDecoded(using:).
        let sjis: [UInt8] = [0x93, 0xFA, 0x96, 0x7B]   // 日本
        let entry = ArchiveEntry(id: 0, path: ["garbled"], isDirectory: false,
                                 uncompressedSize: 1, modified: nil, posixPermissions: nil,
                                 rawNameBytes: sjis)
        let fixed = entry.reDecoded(using: .shiftJIS)
        XCTAssertEqual(fixed.path, ["日本"])
    }
}
