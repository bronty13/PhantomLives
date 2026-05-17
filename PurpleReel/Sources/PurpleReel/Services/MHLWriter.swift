import Foundation

/// Per-file entry in a Media Hash List.
struct MHLEntry {
    let relativePath: String   // path relative to the MHL's root
    let sizeBytes: Int64
    let lastModified: Date
    let hash: String           // hex digest
    let hashAlgorithm: HashAlgorithm
    let hashDate: Date
}

/// Writer for ASC Media Hash List v1.1
/// (https://mediahashlist.org/) — the XML manifest format used by DITs
/// to verify camera-card ingest. We emit a small, conformant subset:
/// `<hashlist>` with `<creatorinfo>` and one `<hash>` per file.
enum MHLWriter {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Build the MHL XML document as a string.
    /// - Parameters:
    ///   - entries: per-file records, in copy order.
    ///   - rootName: name of the source folder (used inside
    ///     `<creatorinfo>/<hostname>` for traceability).
    ///   - startDate: when the overall copy started.
    ///   - finishDate: when it finished.
    ///   - toolVersion: PurpleReel version string for `<tool>`.
    static func makeXML(entries: [MHLEntry],
                        rootName: String,
                        startDate: Date,
                        finishDate: Date,
                        toolVersion: String) -> String {
        var x = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        x += #"<hashlist version="1.1">"# + "\n"
        x += "  <creatorinfo>\n"
        x += "    <name>\(escape(NSFullUserName()))</name>\n"
        x += "    <username>\(escape(NSUserName()))</username>\n"
        x += "    <hostname>\(escape(Host.current().localizedName ?? rootName))</hostname>\n"
        x += "    <tool>PurpleReel \(escape(toolVersion))</tool>\n"
        x += "    <startdate>\(isoFormatter.string(from: startDate))</startdate>\n"
        x += "    <finishdate>\(isoFormatter.string(from: finishDate))</finishdate>\n"
        x += "  </creatorinfo>\n"

        for entry in entries {
            x += "  <hash>\n"
            x += "    <file>\(escape(entry.relativePath))</file>\n"
            x += "    <size>\(entry.sizeBytes)</size>\n"
            x += "    <lastmodificationdate>\(isoFormatter.string(from: entry.lastModified))</lastmodificationdate>\n"
            x += "    <\(entry.hashAlgorithm.mhlElement)>\(entry.hash)</\(entry.hashAlgorithm.mhlElement)>\n"
            x += "    <hashdate>\(isoFormatter.string(from: entry.hashDate))</hashdate>\n"
            x += "  </hash>\n"
        }

        x += "</hashlist>\n"
        return x
    }

    /// Convenience: build XML and write to disk atomically.
    static func write(entries: [MHLEntry],
                      rootName: String,
                      startDate: Date,
                      finishDate: Date,
                      toolVersion: String,
                      to url: URL) throws {
        let xml = makeXML(entries: entries, rootName: rootName,
                          startDate: startDate, finishDate: finishDate,
                          toolVersion: toolVersion)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
