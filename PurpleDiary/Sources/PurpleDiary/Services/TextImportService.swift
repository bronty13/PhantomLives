import Foundation
import UniformTypeIdentifiers
import AppKit

/// Imports the *contents* of a text file (Markdown, plain text, RTF) directly
/// into an entry's body — unlike `FileImportService`, this does not create an
/// attachment; the text becomes part of the entry itself. Reading is local and
/// the bytes never leave the Mac.
@MainActor
enum TextImportService {

    /// File types the open panel offers: plain text, Markdown, and RTF.
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType("net.daringfireball.markdown") { types.append(md) }
        types.append(.rtf)
        return types
    }

    /// Read a text-ish file as a String: RTF is flattened to its plain string;
    /// everything else is decoded as UTF-8 with a Latin-1 / lossy fallback.
    /// Returns nil if the file can't be read at all.
    static func readText(from url: URL) -> String? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)

        if let type, type.conforms(to: .rtf) {
            guard let data = try? Data(contentsOf: url),
                  let attr = try? NSAttributedString(
                      data: data,
                      options: [.documentType: NSAttributedString.DocumentType.rtf],
                      documentAttributes: nil) else { return nil }
            return attr.string
        }

        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin1) { return s }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Smart merge of imported text into an existing body:
    /// - empty body → the imported text becomes the body
    /// - non-empty body → existing, then a `---` separator, then the imported text
    /// Both sides are trimmed of surrounding whitespace so we never produce
    /// runaway blank lines. Empty/whitespace-only imports leave the body as-is.
    static func mergedBody(existing: String, imported: String) -> String {
        let cleanImported = imported.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanImported.isEmpty else { return existing }
        let cleanExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanExisting.isEmpty { return cleanImported }
        return cleanExisting + "\n\n---\n\n" + cleanImported
    }
}
