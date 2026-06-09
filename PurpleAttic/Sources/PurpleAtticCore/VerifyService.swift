import Foundation

/// Verifies that a mirror faithfully reproduces the primary archive. This is the evidence
/// the (future) purge stage requires before it will delete anything: a photo is only safe
/// to remove from Photos once its file is present and matching in at least two on-disk
/// copies. Default check is a fast inventory comparison (relative path + byte size); an
/// optional deep mode adds SHA-256 (expensive over a full archive).
public enum VerifyService {

    public struct Discrepancy: Sendable, Equatable {
        public enum Kind: String, Sendable {
            case missingInMirror      // present in primary, absent in mirror
            case sizeMismatch         // present in both, different size
            case hashMismatch         // present in both, different SHA-256 (deep mode)
        }
        public let relativePath: String
        public let kind: Kind
        public let detail: String
    }

    public struct Report: Sendable {
        public let primaryFileCount: Int
        public let mirrorFileCount: Int
        public let discrepancies: [Discrepancy]
        public var matches: Bool { discrepancies.isEmpty }
    }

    /// Compare `primary` against `mirror`. Only files present in `primary` are required to
    /// exist (matching) in `mirror`; extra files in the mirror are not flagged (the mirror
    /// is allowed to retain history). `onProgress` is called periodically with a count.
    public static func compare(
        primary: String,
        mirror: String,
        deep: Bool = false,
        onProgress: ((Int) -> Void)? = nil
    ) -> Report {
        let primaryFiles = inventory(root: primary)
        let mirrorFiles = inventory(root: mirror)

        var discrepancies: [Discrepancy] = []
        var checked = 0

        for (rel, pAttr) in primaryFiles {
            checked += 1
            if checked % 500 == 0 { onProgress?(checked) }

            guard let mAttr = mirrorFiles[rel] else {
                discrepancies.append(.init(relativePath: rel, kind: .missingInMirror,
                                           detail: "absent in mirror"))
                continue
            }
            if pAttr.size != mAttr.size {
                discrepancies.append(.init(relativePath: rel, kind: .sizeMismatch,
                                           detail: "primary \(pAttr.size) B vs mirror \(mAttr.size) B"))
                continue
            }
            if deep {
                let pHash = sha256(path: (primary as NSString).appendingPathComponent(rel))
                let mHash = sha256(path: (mirror as NSString).appendingPathComponent(rel))
                if pHash != mHash {
                    discrepancies.append(.init(relativePath: rel, kind: .hashMismatch,
                                               detail: "SHA-256 differs"))
                }
            }
        }

        return Report(
            primaryFileCount: primaryFiles.count,
            mirrorFileCount: mirrorFiles.count,
            discrepancies: discrepancies
        )
    }

    // MARK: - Internals

    private struct FileAttr { let size: Int64 }

    /// Map of relativePath → attributes for every regular file under `root`.
    private static func inventory(root: String) -> [String: FileAttr] {
        var out: [String: FileAttr] = [:]
        let rootURL = URL(fileURLWithPath: root)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let en = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return out }

        let prefix = rootURL.standardizedFileURL.path + "/"
        for case let url as URL in en {
            guard let vals = try? url.resourceValues(forKeys: Set(keys)),
                  vals.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            let rel = full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
            out[rel] = FileAttr(size: Int64(vals.fileSize ?? 0))
        }
        return out
    }

    /// Streaming SHA-256 via /usr/bin/shasum (avoids pulling in CryptoKit + reading whole
    /// files into memory). Returns nil on failure.
    private static func sha256(path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(separator: " ").first.map(String.init)
        } catch {
            return nil
        }
    }
}
