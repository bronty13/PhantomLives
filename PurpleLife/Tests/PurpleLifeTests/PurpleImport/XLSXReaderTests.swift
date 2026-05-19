import XCTest
@testable import PurpleLife

/// Fixture .xlsx generated via openpyxl:
///   Sheet "People": columns name, age, active.
///   Sheet "Books":  columns title, year.
/// Base64-encoded inline so the test target doesn't need a binary
/// resource on disk — kept under 6 KB so the source impact is small.
final class XLSXReaderTests: XCTestCase {

    private func source() -> PurpleImport.SourceInput {
        let data = Data(base64Encoded: Self.fixtureXLSXBase64, options: .ignoreUnknownCharacters)!
        return .data(data, filenameHint: "fixture.xlsx")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    func testSheetNamesListsAllSheets() throws {
        let names = try XLSXReader.sheetNames(in: source())
        XCTAssertEqual(Set(names), Set(["People", "Books"]))
    }

    func testFirstSheetIsDefault() async throws {
        let reader = XLSXReader()
        let p = try await reader.preview(source(), sampleSize: 10)
        // openpyxl assigns the first appended sheet to be the active
        // (first) one; we test that the default picks it up.
        if case .tabular(let cols, _) = p.shape {
            XCTAssertTrue(cols.contains("name"), "Expected People sheet columns; got \(cols)")
        } else {
            XCTFail("Expected tabular shape")
        }
    }

    func testSheetNameOptionPicksAlternate() async throws {
        let reader = XLSXReader()
        reader.setOptions(["sheetName": "Books"])
        let rows = try await collect(reader.read(source()))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cell(at: .column("title")) as? String, "The Mythical Man-Month")
    }

    func testHeaderRowAndDataRowsParsed() async throws {
        let reader = XLSXReader()
        reader.setOptions(["sheetName": "People"])
        let rows = try await collect(reader.read(source()))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].cell(at: .column("name")) as? String, "Ada")
        XCTAssertEqual(rows[2].cell(at: .column("name")) as? String, "Hedy")
    }

    func testHeaderRowZeroFallsBackToColumnLetters() async throws {
        let reader = XLSXReader()
        reader.setOptions(["sheetName": "People", "headerRow": 0])
        let p = try await reader.preview(source(), sampleSize: 10)
        if case .tabular(let cols, _) = p.shape {
            XCTAssertTrue(cols.contains("col_A"), "Got cols \(cols)")
        } else {
            XCTFail()
        }
    }

    func testStartColumnOptionTrimsLeftColumns() async throws {
        let reader = XLSXReader()
        reader.setOptions(["sheetName": "People", "startColumn": "B"])
        let p = try await reader.preview(source(), sampleSize: 10)
        if case .tabular(let cols, _) = p.shape {
            XCTAssertFalse(cols.contains("name"), "‘name’ (col A) should have been trimmed; got \(cols)")
        } else {
            XCTFail()
        }
    }

    func testEmptyFileGracefullyHandled() throws {
        // Crafted invalid bytes — verify the reader throws cleanly
        // rather than crashing.
        let bogus = Data([0x00, 0x01, 0x02, 0x03])
        let src = PurpleImport.SourceInput.data(bogus, filenameHint: "junk.xlsx")
        XCTAssertThrowsError(try XLSXReader.sheetNames(in: src))
    }

    // MARK: - Fixture

    private static let fixtureXLSXBase64 = """
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
"""
}
