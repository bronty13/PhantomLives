import XCTest
@testable import PurpleLife

final class CSVReaderTests: XCTestCase {

    private func source(_ s: String) -> PurpleImport.SourceInput {
        .data(s.data(using: .utf8)!, filenameHint: "test.csv")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    func testPreviewWithHeader() async throws {
        let reader = CSVReader()
        let p = try await reader.preview(source("name,age\nada,36\ngrace,72\n"), sampleSize: 10)
        XCTAssertEqual(p.sampleRows.count, 2)
        if case .tabular(let cols, _) = p.shape {
            XCTAssertEqual(cols, ["name", "age"])
        } else {
            XCTFail("Expected tabular")
        }
    }

    func testPreviewWithoutHeader() async throws {
        let reader = CSVReader()
        reader.setOptions(["hasHeader": false])
        let p = try await reader.preview(source("ada,36\ngrace,72\n"), sampleSize: 10)
        XCTAssertEqual(p.sampleRows.count, 2)
        if case .tabular(let cols, _) = p.shape {
            XCTAssertEqual(cols, ["col_1", "col_2"])
        } else {
            XCTFail("Expected tabular")
        }
    }

    func testQuotedCellsHandleEmbeddedCommasNewlinesAndQuotes() async throws {
        // Built with concatenation to avoid Swift triple-quoted-string
        // parsing of the doubled-quote CSV escape sequence.
        let csv =
            "name,note\n"
            + "\"Smith, Jr.\",\"line one\nline two\"\n"
            + "\"She said \"\"hi\"\"\",\"ok\"\n"
        let reader = CSVReader()
        let rows = try await collect(reader.read(source(csv)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cell(at: .column("name")) as? String, "Smith, Jr.")
        XCTAssertEqual(rows[0].cell(at: .column("note")) as? String, "line one\nline two")
        XCTAssertEqual(rows[1].cell(at: .column("name")) as? String, "She said \"hi\"")
    }

    func testCRLFLineEndings() async throws {
        let csv = "name,age\r\nada,36\r\ngrace,72\r\n"
        let reader = CSVReader()
        let rows = try await collect(reader.read(source(csv)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].cell(at: .column("name")) as? String, "grace")
    }

    func testUTF8BOMIsStripped() async throws {
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append("name,age\nada,36\n".data(using: .utf8)!)
        let reader = CSVReader()
        let preview = try await reader.preview(.data(bytes, filenameHint: nil), sampleSize: 10)
        if case .tabular(let cols, _) = preview.shape {
            XCTAssertEqual(cols, ["name", "age"])
        } else {
            XCTFail()
        }
    }

    func testCustomDelimiterTab() async throws {
        let reader = CSVReader()
        reader.setOptions(["delimiter": "\t"])
        let rows = try await collect(reader.read(source("a\tb\tc\n1\t2\t3\n")))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cell(at: .column("a")) as? String, "1")
        XCTAssertEqual(rows[0].cell(at: .column("b")) as? String, "2")
        XCTAssertEqual(rows[0].cell(at: .column("c")) as? String, "3")
    }

    func testEncodingFallbackToLatin1ForInvalidUTF8() async throws {
        // 0xFF is invalid in UTF-8 but maps to ÿ in Latin-1. The
        // fallback must never throw.
        var bytes = "name\nada\n".data(using: .utf8)!
        bytes[5] = 0xFF
        let reader = CSVReader()
        let rows = try await collect(reader.read(.data(bytes, filenameHint: nil)))
        XCTAssertGreaterThanOrEqual(rows.count, 1)
    }

    func testEmptyInputProducesEmpty() async throws {
        let reader = CSVReader()
        let rows = try await collect(reader.read(source("")))
        XCTAssertEqual(rows.count, 0)
    }

    func testInferredKindsAreSurfacedInPreview() async throws {
        let reader = CSVReader()
        let p = try await reader.preview(source("name,age,active\nada,36,true\ngrace,72,false\n"), sampleSize: 10)
        if case .tabular(_, let kinds) = p.shape {
            XCTAssertEqual(kinds["age"], .number)
            XCTAssertEqual(kinds["active"], .boolean)
            XCTAssertEqual(kinds["name"], .text)
        } else {
            XCTFail()
        }
    }
}
