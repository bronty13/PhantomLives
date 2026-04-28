import Foundation

/// Parse human-friendly hex byte strings (whitespace ignored, optional 0x prefix
/// and \xNN escapes) into raw `Data`.
public enum HexBytes {

    public static func parse(_ input: String) throws -> Data {
        var cleaned = input
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "\\x", with: "")

        // Allow `:` separators (e.g. CA:FE:BA:BE)
        cleaned = cleaned.replacingOccurrences(of: ":", with: "")

        guard cleaned.count % 2 == 0 else {
            throw ReplaceError.invalidHex(input)
        }
        var data = Data(capacity: cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            let byteStr = cleaned[idx..<next]
            guard let byte = UInt8(byteStr, radix: 16) else {
                throw ReplaceError.invalidHex(input)
            }
            data.append(byte)
            idx = next
        }
        return data
    }

    public static func render(_ data: Data, separator: String = " ") -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}
