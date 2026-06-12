import Foundation

/// Reads a markdown file off the main thread and decodes it with encoding
/// detection — UTF-8 first (BOM-aware), then UTF-16 via BOM, then system
/// detection, then Latin-1 as the never-fails fallback. Pure `decode` is
/// unit-tested.
enum FileLoader {
    struct Loaded {
        let text: String
        let encoding: String.Encoding
        let byteSize: Int
    }

    /// Files at or under this size load synchronously on open (a few ms);
    /// larger files load in the background behind a progress overlay.
    static let syncLoadLimit = 2_000_000

    /// Decodes file bytes into text. Never fails: Latin-1 maps every byte.
    static func decode(_ data: Data) -> Loaded {
        let size = data.count

        // UTF-8 BOM — strip it so it doesn't land in the editor.
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let s = String(data: data.dropFirst(3), encoding: .utf8) {
            return Loaded(text: s, encoding: .utf8, byteSize: size)
        }
        // UTF-16 BOM (either endianness) — .utf16 detects and strips the BOM.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) {
            return Loaded(text: s, encoding: .utf16, byteSize: size)
        }

        if let s = String(data: data, encoding: .utf8) {
            return Loaded(text: s, encoding: .utf8, byteSize: size)
        }

        // Let Foundation guess (BOM-less UTF-16, legacy encodings).
        var converted: NSString?
        let raw = NSString.stringEncoding(
            for: data, encodingOptions: [.allowLossyKey: false],
            convertedString: &converted, usedLossyConversion: nil)
        if raw != 0, let converted {
            return Loaded(text: converted as String,
                          encoding: String.Encoding(rawValue: raw), byteSize: size)
        }

        // Latin-1 maps every byte sequence, so this always succeeds.
        let s = String(data: data, encoding: .isoLatin1) ?? ""
        return Loaded(text: s, encoding: .isoLatin1, byteSize: size)
    }

    /// Reads + decodes. Call from a background task for large files.
    static func load(_ url: URL) throws -> Loaded {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return decode(data)
    }
}
