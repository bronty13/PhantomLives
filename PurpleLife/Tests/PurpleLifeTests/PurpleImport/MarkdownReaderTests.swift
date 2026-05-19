import XCTest
@testable import PurpleLife

final class MarkdownReaderTests: XCTestCase {

    private func source(_ s: String) -> PurpleImport.SourceInput {
        .data(s.data(using: .utf8)!, filenameHint: "test.md")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    // MARK: - GFM tables

    func testGFMTableHeaderAndRows() async throws {
        let md = """
        # Title

        | name | age |
        | --- | --- |
        | Ada | 36 |
        | Grace | 72 |

        Some text after.
        """
        let reader = MarkdownReader()
        let p = try await reader.preview(source(md), sampleSize: 10)
        if case .tabular(let cols, _) = p.shape {
            XCTAssertEqual(cols, ["name", "age"])
        } else {
            XCTFail("Expected tabular")
        }
        XCTAssertEqual(p.sampleRows.count, 2)
        XCTAssertEqual(p.sampleRows[0].cell(at: .column("name")) as? String, "Ada")
        XCTAssertEqual(p.sampleRows[1].cell(at: .column("age")) as? String, "72")
    }

    func testTableWithAlignmentColons() async throws {
        let md =
            "| Left | Right | Center |\n" +
            "| :--- | ---: | :---: |\n" +
            "| a | b | c |\n"
        let reader = MarkdownReader()
        let rows = try await collect(reader.read(source(md)))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cell(at: .column("Left")) as? String, "a")
    }

    func testTableIndexPicksLaterTable() async throws {
        let md = """
        | a | b |
        | --- | --- |
        | 1 | 2 |

        Some prose.

        | x | y |
        | --- | --- |
        | 10 | 20 |
        """
        let reader = MarkdownReader()
        reader.setOptions(["tableIndex": 1])
        let p = try await reader.preview(source(md), sampleSize: 10)
        if case .tabular(let cols, _) = p.shape {
            XCTAssertEqual(cols, ["x", "y"])
        } else {
            XCTFail("Expected tabular")
        }
        XCTAssertEqual(p.sampleRows.first?.cell(at: .column("x")) as? String, "10")
    }

    // MARK: - Frontmatter

    func testYAMLFrontmatter() async throws {
        let md = """
        ---
        title: Hello
        author: Ada
        published: 2024-01-15
        ---

        # Body heading
        Some content here.
        """
        let reader = MarkdownReader()
        let p = try await reader.preview(source(md), sampleSize: 10)
        if case .tree(let paths) = p.shape {
            XCTAssertTrue(paths.contains("$.title"))
            XCTAssertTrue(paths.contains("$.author"))
            XCTAssertTrue(paths.contains("$.published"))
            XCTAssertTrue(paths.contains("$._body"))
        } else {
            XCTFail("Expected tree")
        }
        XCTAssertEqual(p.sampleRows.count, 1)
        XCTAssertEqual(p.sampleRows[0].cell(at: .path("$.title")) as? String, "Hello")
        XCTAssertEqual(p.sampleRows[0].cell(at: .path("$.author")) as? String, "Ada")
    }

    func testFrontmatterQuotedValuesStripped() async throws {
        let md = """
        ---
        title: "Quoted Title"
        tag: 'single'
        ---

        body
        """
        let reader = MarkdownReader()
        let p = try await reader.preview(source(md), sampleSize: 10)
        XCTAssertEqual(p.sampleRows[0].cell(at: .path("$.title")) as? String, "Quoted Title")
        XCTAssertEqual(p.sampleRows[0].cell(at: .path("$.tag")) as? String, "single")
    }

    // MARK: - Plain document fallback

    func testPlainDocumentSurfacesAsSingleBody() async throws {
        let md = "Just some text. No tables or frontmatter here.\n\nAnother paragraph."
        let reader = MarkdownReader()
        let p = try await reader.preview(source(md), sampleSize: 10)
        if case .document(let body) = p.shape {
            XCTAssertTrue(body.contains("Just some text"))
        } else {
            XCTFail("Expected document shape, got \(p.shape)")
        }
    }

    // MARK: - Auto-detect priority

    func testAutoDetectPrefersFrontmatterOverTable() async throws {
        let md = """
        ---
        a: 1
        ---

        | name | age |
        | --- | --- |
        | Ada | 36 |
        """
        let reader = MarkdownReader()
        let p = try await reader.preview(source(md), sampleSize: 10)
        if case .tree = p.shape { /* ok */ }
        else { XCTFail("Auto should prefer frontmatter when both are present") }
    }

    func testForcedTableModeBypassesFrontmatter() async throws {
        let md = """
        ---
        a: 1
        ---

        | name | age |
        | --- | --- |
        | Ada | 36 |
        """
        let reader = MarkdownReader()
        reader.setOptions(["mode": "table"])
        let p = try await reader.preview(source(md), sampleSize: 10)
        if case .tabular = p.shape { /* ok */ }
        else { XCTFail("Forced table mode should ignore frontmatter") }
    }
}
