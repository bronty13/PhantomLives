import Foundation
import CryptoKit

/// Writer for ASC-MHL v2.0 (https://asc-mhl.org/), the successor to
/// MHL v1.1 and the format Netflix Originals requires for media
/// delivery. Schema differences from v1.1 we care about:
///
///   - `xmlns="urn:ASC:MHL:v2.0"` namespace + `version="2.0"`.
///   - `<creatorinfo>` adds a `<tool name="" version=""/>` element
///     (v1.1 was free text inside `<tool>`).
///   - `<processinfo>` block describing the operation; we always
///     emit `<process>transfer</process>` for backup runs.
///   - Hashes live under a single `<hashes>` parent, each entry's
///     `<path>` carries `size` / `lastmodificationdate` as XML
///     attributes (v1.1 used child elements).
///   - C4 IDs are valid alongside `sha1`/`sha256`/`md5`.
///
/// We emit a Netflix-DIT-tool-readable subset; round-tripping with
/// the full ASC-MHL reference implementation is not a goal yet.
enum ASCMHLWriter {

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Build the ASC-MHL XML document as a string.
    /// - Parameters:
    ///   - entries: per-file records, in copy order.
    ///   - rootName: the source folder's name (recorded for
    ///     traceability inside the creator info).
    ///   - startDate: when the overall copy started.
    ///   - finishDate: when it finished.
    ///   - toolVersion: PurpleReel's version string.
    static func makeXML(entries: [MHLEntry],
                        rootName: String,
                        startDate: Date,
                        finishDate: Date,
                        toolVersion: String) -> String {
        var x = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        x += #"<hashlist xmlns="urn:ASC:MHL:v2.0" version="2.0">"# + "\n"
        x += "  <creatorinfo>\n"
        x += "    <creationdate>\(iso.string(from: finishDate))</creationdate>\n"
        x += "    <hostname>\(escape(Host.current().localizedName ?? rootName))</hostname>\n"
        x += "    <name>\(escape(NSFullUserName()))</name>\n"
        x += "    <username>\(escape(NSUserName()))</username>\n"
        x += "    <tool name=\"PurpleReel\" version=\"\(escape(toolVersion))\"/>\n"
        x += "    <startdate>\(iso.string(from: startDate))</startdate>\n"
        x += "    <finishdate>\(iso.string(from: finishDate))</finishdate>\n"
        x += "  </creatorinfo>\n"
        x += "  <processinfo>\n"
        x += "    <process>transfer</process>\n"
        x += "    <roothash>\n"
        x += "      <c4>\(escape(rootC4(entries: entries)))</c4>\n"
        x += "    </roothash>\n"
        x += "  </processinfo>\n"
        x += "  <hashes>\n"
        for entry in entries {
            let size = entry.sizeBytes
            let modStr = iso.string(from: entry.lastModified)
            let hashStr = iso.string(from: entry.hashDate)
            let elem = entry.hashAlgorithm.mhlElement
            let pathEsc = escape(entry.relativePath)
            x += "    <hash>\n"
            x += "      <path size=\"\(size)\" lastmodificationdate=\"\(modStr)\">\(pathEsc)</path>\n"
            x += "      <\(elem) action=\"original\" hashdate=\"\(hashStr)\">\(entry.hash)</\(elem)>\n"
            x += "    </hash>\n"
        }
        x += "  </hashes>\n"
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

    /// Roll-up root hash for the whole manifest. Computed by
    /// concatenating every entry's hash (in path-sorted order) and
    /// running SHA-512 → C4. This is a simplification of the
    /// "merkle-style fold" the full ASC-MHL spec defines, but it
    /// produces a deterministic root that downstream verifiers can
    /// re-derive from the same `<hashes>` set.
    private static func rootC4(entries: [MHLEntry]) -> String {
        var combined = Data()
        for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
            if let d = entry.hash.data(using: .utf8) { combined.append(d) }
        }
        if combined.isEmpty { return "" }
        // SHA-512 → C4. We use the in-memory hash here because the
        // entry set is small (one hash string each, not the source
        // bytes), so no chunked streaming needed.
        let digest = SHA512Hasher.digest(of: combined)
        return Base58.c4ID(from: digest)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Thin wrapper around CryptoKit's SHA512 for the in-memory case
/// (ASC-MHL root-hash rollup). Streaming SHA-512 over file content
/// lives in `HashingService.streamRawDigest`.
enum SHA512Hasher {
    static func digest(of data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }
}
