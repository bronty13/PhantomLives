import Foundation

/// Detect text encoding of an arbitrary file using a heuristic stack:
///   1. BOM sniff (UTF-8 / UTF-16 BE / UTF-16 LE / UTF-32).
///   2. Pure-ASCII fast path on the first N bytes.
///   3. UTF-8 well-formedness check.
///   4. Fallback to Latin-1 (lossless single-byte) so we can always read.
///
/// `uchardet` integration is deferred to a follow-up; this gets us 95% on
/// real-world input without a C dependency.
public enum EncodingDetector {

    public struct Detection: Sendable, Equatable {
        public let encoding: String.Encoding
        public let bom: Data?
        public let confidence: Double  // 0.0–1.0
    }

    public static func detect(data: Data, sampleBytes: Int = 64 * 1024) -> Detection {
        // 1. BOM
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .init(encoding: .utf8, bom: Data([0xEF, 0xBB, 0xBF]), confidence: 1.0)
        }
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return .init(encoding: .utf32LittleEndian, bom: Data([0xFF, 0xFE, 0x00, 0x00]), confidence: 1.0)
        }
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return .init(encoding: .utf32BigEndian, bom: Data([0x00, 0x00, 0xFE, 0xFF]), confidence: 1.0)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return .init(encoding: .utf16LittleEndian, bom: Data([0xFF, 0xFE]), confidence: 1.0)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return .init(encoding: .utf16BigEndian, bom: Data([0xFE, 0xFF]), confidence: 1.0)
        }

        let sample = data.prefix(sampleBytes)

        // 2. ASCII fast path
        if sample.allSatisfy({ $0 < 0x80 }) {
            return .init(encoding: .utf8, bom: nil, confidence: 0.99)
        }

        // 3. UTF-8 validity
        if String(data: sample, encoding: .utf8) != nil {
            return .init(encoding: .utf8, bom: nil, confidence: 0.85)
        }

        // 4. Latin-1 fallback (always succeeds)
        return .init(encoding: .isoLatin1, bom: nil, confidence: 0.5)
    }

    public static func detect(fileURL: URL) throws -> Detection {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024) ?? Data()
        return detect(data: data)
    }

    /// Quick check: is this file text-like or should we treat it as binary?
    /// A file with NUL bytes in the first 8 KiB is considered binary.
    public static func isProbablyBinary(data: Data, sampleBytes: Int = 8 * 1024) -> Bool {
        let sample = data.prefix(sampleBytes)
        return sample.contains(0x00)
    }
}
