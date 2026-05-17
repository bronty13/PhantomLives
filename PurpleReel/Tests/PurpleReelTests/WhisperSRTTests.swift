import XCTest
@testable import PurpleReel

final class WhisperSRTTests: XCTestCase {

    func testParsesBasicSRT() throws {
        let srt = """
        1
        00:00:00,000 --> 00:00:03,500
        Hello, this is the first segment.

        2
        00:00:03,500 --> 00:00:07,250
        And this is the second.
        """
        let segments = try WhisperService.parseSRT(srt)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(segments[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(segments[0].text, "Hello, this is the first segment.")
        XCTAssertEqual(segments[1].start, 3.5, accuracy: 0.001)
        XCTAssertEqual(segments[1].end, 7.25, accuracy: 0.001)
    }

    func testHandlesMultilineSegmentBody() throws {
        let srt = """
        1
        00:00:00,000 --> 00:00:05,000
        Line one of dialog.
        Line two of dialog.
        """
        let segments = try WhisperService.parseSRT(srt)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text,
                        "Line one of dialog.\nLine two of dialog.")
    }

    func testHandlesCRLFLineEndings() throws {
        let srt = "1\r\n00:00:00,000 --> 00:00:01,000\r\nHello.\r\n"
        let segments = try WhisperService.parseSRT(srt)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Hello.")
    }

    func testTimestampMillisecondPrecision() throws {
        let srt = """
        1
        01:02:03,456 --> 01:02:04,789
        Sample.
        """
        let segments = try WhisperService.parseSRT(srt)
        XCTAssertEqual(segments[0].start, 3723.456, accuracy: 0.001)
        XCTAssertEqual(segments[0].end, 3724.789, accuracy: 0.001)
    }

    func testEmptyInputProducesNoSegments() throws {
        XCTAssertEqual(try WhisperService.parseSRT("").count, 0)
        XCTAssertEqual(try WhisperService.parseSRT("\n\n\n").count, 0)
    }
}
