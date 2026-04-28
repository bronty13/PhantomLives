import Testing
import Foundation
@testable import SnREncoding

@Suite("EncodingDetector")
struct EncodingDetectorTests {

    @Test func utf8BOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + "hello".data(using: .utf8)!
        let d = EncodingDetector.detect(data: data)
        #expect(d.encoding == .utf8)
        #expect(d.bom?.count == 3)
    }

    @Test func utf16LEBOM() {
        let data = Data([0xFF, 0xFE]) + "hi".data(using: .utf16LittleEndian)!
        let d = EncodingDetector.detect(data: data)
        #expect(d.encoding == .utf16LittleEndian)
    }

    @Test func asciiFastPath() {
        let data = "plain ascii content".data(using: .ascii)!
        let d = EncodingDetector.detect(data: data)
        #expect(d.encoding == .utf8)
        #expect(d.confidence > 0.9)
    }

    @Test func validUTF8WithoutBOM() {
        let data = "café résumé naïve".data(using: .utf8)!
        let d = EncodingDetector.detect(data: data)
        #expect(d.encoding == .utf8)
    }

    @Test func invalidUTF8FallsBackToLatin1() {
        let data = Data([0xC3, 0x28]) // invalid UTF-8 sequence
        let d = EncodingDetector.detect(data: data)
        #expect(d.encoding == .isoLatin1)
    }

    @Test func binaryDetection() {
        #expect(EncodingDetector.isProbablyBinary(data: Data([0x00, 0x01, 0x02, 0x03])))
    }

    @Test func textNotBinary() {
        let data = "hello world\nsecond line".data(using: .utf8)!
        #expect(!EncodingDetector.isProbablyBinary(data: data))
    }
}
