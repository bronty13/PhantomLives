import XCTest
@testable import PurpleLife

/// JSON import/export for `UserTheme`. The UI surface (NSSavePanel /
/// NSOpenPanel) isn't unit-tested — only the encode/decode/sanitize
/// pure functions live here. Same coverage shape as ExportServiceTests.
final class ThemeIOTests: XCTestCase {

    // MARK: - Filename sanitization

    func testSanitizedFilenameStripsPathSeparators() {
        XCTAssertEqual(ThemeIO.sanitizedFilename(for: "My / Theme"), "My  Theme")
        XCTAssertEqual(ThemeIO.sanitizedFilename(for: "C:\\evil"), "Cevil")
    }

    func testSanitizedFilenameStripsLeadingDots() {
        XCTAssertEqual(ThemeIO.sanitizedFilename(for: ".hidden"), "hidden")
        XCTAssertEqual(ThemeIO.sanitizedFilename(for: "..."), "theme",
                       "all-dots collapses to the fallback rather than producing an empty / hidden filename")
    }

    func testSanitizedFilenameFallsBackOnEmpty() {
        XCTAssertEqual(ThemeIO.sanitizedFilename(for: ""), "theme")
        XCTAssertEqual(ThemeIO.sanitizedFilename(for: "   "), "theme")
    }

    func testDefaultFilenameUsesExtension() {
        let t = UserTheme.duplicate(of: .lavender, name: "Bedtime")
        XCTAssertEqual(ThemeIO.defaultFilename(for: t), "Bedtime.purplelifetheme.json")
    }

    // MARK: - Roundtrip

    func testEncodeProducesPrettySortedJSON() throws {
        let theme = UserTheme.duplicate(of: .royalPurple, name: "Stable")
        let data = try ThemeIO.encode(theme)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\n"), "pretty-printed output should contain newlines")
        // Sorted keys: `accent` must appear before `bg` lexicographically.
        if let accent = s.range(of: "\"accent\""),
           let bg = s.range(of: "\"bg\"") {
            XCTAssertTrue(accent.lowerBound < bg.lowerBound,
                          "JSON keys must be alphabetically sorted")
        } else {
            XCTFail("expected both accent and bg keys in output")
        }
    }

    func testDecodeAssignsFreshUUID() throws {
        let original = UserTheme.duplicate(of: .plum, name: "Plummy")
        let data = try ThemeIO.encode(original)
        let imported = try ThemeIO.decode(from: data)

        XCTAssertNotEqual(imported.id, original.id,
                          "re-importing the same theme must produce a new id so it doesn't collide")
        XCTAssertEqual(imported.name, original.name, "name preserved")
        XCTAssertEqual(imported.basedOn, original.basedOn, "basedOn preserved")
        XCTAssertEqual(imported.bg.light, original.bg.light, "slot values preserved")
        XCTAssertEqual(imported.bg.dark, original.bg.dark)
        XCTAssertEqual(imported.accent.light, original.accent.light)
    }

    func testWriteAndReadRoundtripsThroughDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-\(UUID().uuidString).purplelifetheme.json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = UserTheme.duplicate(of: .heather, name: "From Disk")
        try ThemeIO.write(original, to: tmp)

        let imported = try ThemeIO.read(from: tmp)
        XCTAssertEqual(imported.name, "From Disk")
        XCTAssertEqual(imported.basedOn, "heather")
        XCTAssertNotEqual(imported.id, original.id, "fresh UUID after read")
    }

    // MARK: - Failure modes

    func testDecodeRejectsCorruptJSON() {
        let bad = Data("not-json-at-all".utf8)
        XCTAssertThrowsError(try ThemeIO.decode(from: bad))
    }

    func testDecodeRejectsValidJSONMissingRequiredKeys() {
        // Valid JSON, but missing the slot keys UserTheme needs.
        let bad = Data(#"{"name":"X","createdAt":"2026-01-01T00:00:00Z"}"#.utf8)
        XCTAssertThrowsError(try ThemeIO.decode(from: bad))
    }

    func testReadFailsCleanlyOnMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-not-a-file-\(UUID().uuidString).json")
        XCTAssertThrowsError(try ThemeIO.read(from: missing))
    }
}
