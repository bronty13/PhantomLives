import Foundation
import SnREncoding
import SnRSearch

/// Streaming, encoding-aware text replacement engine.
///
/// Reads the source file in one pass (current implementation: full read; a
/// future version will line-buffer for files > N MB), applies the regex,
/// writes to a sibling temp file, then atomically renames it over the
/// original after taking a backup.
public struct Replacer: Sendable {

    public init() {}

    /// Apply a replacement to a single file. `acceptedHits` is the subset
    /// the user kept after preview; if nil, all matches are replaced.
    public func apply(
        spec: ReplaceSpec,
        fileURL: URL,
        acceptedHits: [Hit]? = nil,
        backups: BackupManager? = nil
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.applySync(spec: spec, fileURL: fileURL, acceptedHits: acceptedHits, backups: backups)
        }.value
    }

    public static func applySync(
        spec: ReplaceSpec,
        fileURL: URL,
        acceptedHits: [Hit]?,
        backups: BackupManager?
    ) throws {
        let data = try Data(contentsOf: fileURL)

        let newData: Data
        switch spec.mode {
        case .literal, .regex:
            newData = try rewriteText(spec: spec, fileURL: fileURL, data: data, acceptedHits: acceptedHits)
        case .binary:
            newData = try rewriteBinary(spec: spec, data: data)
        }

        if newData == data { return } // no-op

        // Backup first.
        if let backups {
            Task { _ = try await backups.snapshot(fileURL) }
        }

        // Atomic write: tmp + rename.
        let tmp = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).snr-tmp-\(UUID().uuidString)")
        try newData.write(to: tmp, options: [.atomic])

        // Preserve mtime.
        let originalAttrs: [FileAttributeKey: Any]?
        if spec.preserveMtime {
            originalAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        } else {
            originalAttrs = nil
        }

        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)

        if let originalAttrs,
           let mtime = originalAttrs[.modificationDate] {
            try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: fileURL.path)
        }
    }

    // MARK: - Text path

    private static func rewriteText(
        spec: ReplaceSpec,
        fileURL: URL,
        data: Data,
        acceptedHits: [Hit]?
    ) throws -> Data {
        let detection = EncodingDetector.detect(data: data)
        let bodyData = detection.bom == nil ? data : data.dropFirst(detection.bom!.count)
        guard let text = String(data: bodyData, encoding: detection.encoding) else {
            throw ReplaceError.encodingFailed(detection.encoding)
        }

        let pattern: String
        let options: NSRegularExpression.Options
        switch spec.mode {
        case .literal:
            pattern = NSRegularExpression.escapedPattern(for: spec.pattern)
            options = spec.caseInsensitive ? [.caseInsensitive] : []
        case .regex:
            pattern = spec.pattern
            var opts: NSRegularExpression.Options = []
            if spec.caseInsensitive { opts.insert(.caseInsensitive) }
            if spec.multiline       { opts.insert(.dotMatchesLineSeparators) }
            options = opts
        case .binary:
            preconditionFailure("rewriteText called for binary mode")
        }

        let regex = try NSRegularExpression(pattern: pattern, options: options)
        let nsText = NSMutableString(string: text)
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Build replacement template, expanding %FILE% / %PATH% / %BASENAME%
        // up-front (these don't vary per-hit).
        var template = spec.replacement
        if spec.interpolatePathTokens {
            template = template
                .replacingOccurrences(of: "%FILE%", with: fileURL.lastPathComponent)
                .replacingOccurrences(of: "%PATH%", with: fileURL.path)
                .replacingOccurrences(of: "%BASENAME%", with: (fileURL.lastPathComponent as NSString).deletingPathExtension)
        }

        // Counter expansion (optional, per-match)
        if spec.counterEnabled, let counter = CounterToken.parse(template: template) {
            // Walk matches in reverse so indices stay valid.
            let matches = regex.matches(in: nsText as String, range: fullRange).reversed()
            var index = counter.start
            // Reverse iteration → step backwards so first hit gets `start`.
            let total = regex.numberOfMatches(in: nsText as String, range: fullRange)
            index = counter.start + counter.step * (total - 1)
            for m in matches {
                if let accepted = acceptedHits, !accepted.contains(where: { $0.byteStart == m.range.location }) {
                    index -= counter.step
                    continue
                }
                let expanded = counter.render(value: index, template: template)
                let replaced = regex.replacementString(for: m, in: nsText as String, offset: 0, template: expanded)
                nsText.replaceCharacters(in: m.range, with: replaced)
                index -= counter.step
            }
        } else {
            let matches = regex.matches(in: nsText as String, range: fullRange).reversed()
            for m in matches {
                if let accepted = acceptedHits, !accepted.contains(where: { $0.byteStart == m.range.location }) {
                    continue
                }
                nsText.replaceCharacters(in: m.range, with: regex.replacementString(
                    for: m, in: nsText as String, offset: 0, template: template
                ))
            }
        }

        guard let outBody = (nsText as String).data(using: detection.encoding, allowLossyConversion: false) else {
            throw ReplaceError.encodingFailed(detection.encoding)
        }
        if let bom = detection.bom {
            return bom + outBody
        }
        return outBody
    }

    // MARK: - Binary path

    private static func rewriteBinary(spec: ReplaceSpec, data: Data) throws -> Data {
        let needle = try HexBytes.parse(spec.pattern)
        let repl = try HexBytes.parse(spec.replacement)

        if needle.isEmpty { throw ReplaceError.emptyPattern }

        if !spec.allowLengthChangingBinary && needle.count != repl.count {
            throw ReplaceError.lengthChangingBinaryDisallowed
        }

        var out = Data()
        out.reserveCapacity(data.count)
        var i = data.startIndex
        while i < data.endIndex {
            let remaining = data.distance(from: i, to: data.endIndex)
            if remaining >= needle.count,
               data.subdata(in: i..<i + needle.count) == needle {
                out.append(repl)
                i = data.index(i, offsetBy: needle.count)
            } else {
                out.append(data[i])
                i = data.index(after: i)
            }
        }
        return out
    }
}

public enum ReplaceError: Error, CustomStringConvertible {
    case encodingFailed(String.Encoding)
    case lengthChangingBinaryDisallowed
    case emptyPattern
    case invalidHex(String)

    public var description: String {
        switch self {
        case .encodingFailed(let enc): return "Encoding failed: \(enc)"
        case .lengthChangingBinaryDisallowed: return "Length-changing binary replacement requires explicit opt-in (allowLengthChangingBinary)"
        case .emptyPattern: return "Empty search pattern"
        case .invalidHex(let s): return "Invalid hex literal: \(s)"
        }
    }
}
