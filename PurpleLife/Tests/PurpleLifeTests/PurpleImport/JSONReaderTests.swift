import XCTest
@testable import PurpleLife

final class JSONReaderTests: XCTestCase {

    private func source(_ s: String) -> PurpleImport.SourceInput {
        .data(s.data(using: .utf8)!, filenameHint: "test.json")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    // MARK: - Path evaluation

    func testEvaluateRootIsIdentity() throws {
        let root: Any = ["a": 1]
        let r = try JSONReader.evaluatePath("$", on: root)
        XCTAssertNotNil(r as? [String: Any])
    }

    func testEvaluateDottedKey() throws {
        let root: Any = ["a": ["b": 42]]
        let r = try JSONReader.evaluatePath("$.a.b", on: root) as? Int
        XCTAssertEqual(r, 42)
    }

    func testEvaluateArrayIndex() throws {
        let root: Any = ["items": [10, 20, 30]]
        let r = try JSONReader.evaluatePath("$.items[1]", on: root) as? Int
        XCTAssertEqual(r, 20)
    }

    func testEvaluateBracketedStringKey() throws {
        // "Full Name" can't be expressed via dot syntax; bracket-
        // quoted form is the escape hatch.
        let root: Any = ["Full Name": "Ada"]
        let r = try JSONReader.evaluatePath("$[\"Full Name\"]", on: root) as? String
        XCTAssertEqual(r, "Ada")
    }

    func testEvaluateMissingKeyThrows() {
        let root: Any = ["a": 1]
        XCTAssertThrowsError(try JSONReader.evaluatePath("$.b", on: root))
    }

    // MARK: - Array-of-objects shape

    func testReadTopLevelArrayOfObjects() async throws {
        let json = #"[{"name":"Ada","age":36},{"name":"Grace","age":72}]"#
        let reader = JSONReader()
        let rows = try await collect(reader.read(source(json)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cell(at: .path("$.name")) as? String, "Ada")
        XCTAssertEqual(rows[1].cell(at: .path("$.age")) as? Int, 72)
    }

    func testReadNestedRootPath() async throws {
        let json = #"{"results":{"records":[{"id":1},{"id":2}]}}"#
        let reader = JSONReader()
        reader.setOptions(["rootPath": "$.results.records"])
        let rows = try await collect(reader.read(source(json)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cell(at: .path("$.id")) as? Int, 1)
    }

    // MARK: - NDJSON

    func testNDJSONOnePerLine() async throws {
        let ndj = """
        {"name":"Ada"}
        {"name":"Grace"}
        {"name":"Hedy"}
        """
        let reader = JSONReader()
        let rows = try await collect(reader.read(source(ndj)))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[2].cell(at: .path("$.name")) as? String, "Hedy")
    }

    // MARK: - Preview

    func testPreviewSurfacesTopLevelKeysAndKinds() async throws {
        let json = #"[{"name":"Ada","age":36,"active":true},{"name":"Grace","age":72,"active":false}]"#
        let reader = JSONReader()
        let p = try await reader.preview(source(json), sampleSize: 10)
        XCTAssertEqual(p.sampleRows.count, 2)
        if case .tree(let paths) = p.shape {
            XCTAssertEqual(Set(paths), Set(["$.name", "$.age", "$.active"]))
        } else {
            XCTFail()
        }
    }
}
