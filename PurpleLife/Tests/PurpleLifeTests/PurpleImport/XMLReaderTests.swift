import XCTest
@testable import PurpleLife

final class XMLReaderTests: XCTestCase {

    private func source(_ s: String) -> PurpleImport.SourceInput {
        .data(s.data(using: .utf8)!, filenameHint: "test.xml")
    }

    private func collect(_ stream: AsyncThrowingStream<PurpleImport.SourceRow, Error>) async throws -> [PurpleImport.SourceRow] {
        var out: [PurpleImport.SourceRow] = []
        for try await row in stream { out.append(row) }
        return out
    }

    func testRepeatingChildElementsAutoDetected() async throws {
        let xml = """
        <?xml version="1.0"?>
        <catalog>
          <book><title>One</title><author>A</author></book>
          <book><title>Two</title><author>B</author></book>
        </catalog>
        """
        let reader = XMLReader()
        let rows = try await collect(reader.read(source(xml)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cell(at: .path("$.title")) as? String, "One")
        XCTAssertEqual(rows[1].cell(at: .path("$.author")) as? String, "B")
    }

    func testAttributesSurfacedAsTopLevelKeys() async throws {
        let xml = """
        <root>
          <item id="a" priority="high"><name>First</name></item>
          <item id="b" priority="low"><name>Second</name></item>
        </root>
        """
        let reader = XMLReader()
        let rows = try await collect(reader.read(source(xml)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cell(at: .path("$.id")) as? String, "a")
        XCTAssertEqual(rows[0].cell(at: .path("$.priority")) as? String, "high")
        XCTAssertEqual(rows[0].cell(at: .path("$.name")) as? String, "First")
    }

    func testExplicitRootPath() async throws {
        let xml = """
        <doc>
          <metadata><exported>now</exported></metadata>
          <entries>
            <entry><k>k1</k></entry>
            <entry><k>k2</k></entry>
          </entries>
        </doc>
        """
        let reader = XMLReader()
        reader.setOptions(["rootPath": "$.doc.entries.entry"])
        let rows = try await collect(reader.read(source(xml)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cell(at: .path("$.k")) as? String, "k1")
    }

    func testSingleElementRootSurfacesAsOneRecord() async throws {
        let xml = """
        <person>
          <name>Ada</name>
          <age>36</age>
        </person>
        """
        let reader = XMLReader()
        let rows = try await collect(reader.read(source(xml)))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cell(at: .path("$.name")) as? String, "Ada")
        XCTAssertEqual(rows[0].cell(at: .path("$.age")) as? String, "36")
    }

    func testMalformedXMLThrows() async throws {
        let xml = "<unclosed><tag>"
        let reader = XMLReader()
        do {
            _ = try await collect(reader.read(source(xml)))
            XCTFail("Should have thrown on malformed XML")
        } catch {
            // ok
        }
    }

    func testPreviewSurfacesPaths() async throws {
        let xml = "<root><item><a>1</a><b>2</b></item><item><a>3</a><b>4</b></item></root>"
        let reader = XMLReader()
        let p = try await reader.preview(source(xml), sampleSize: 10)
        if case .tree(let paths) = p.shape {
            XCTAssertEqual(Set(paths), Set(["$.a", "$.b"]))
        } else {
            XCTFail("Expected tree shape")
        }
    }
}
