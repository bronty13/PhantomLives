import Foundation
import CryptoKit

/// Walks a run folder's media subdirectories and emits per-file
/// checksums into `hashes.txt` at the run-folder root. Idempotent —
/// re-running just overwrites the file with current values.
///
/// Algorithms come from the `ArchiveRequest`. SHA-256 is the modern
/// default; MD5 / SHA-1 stay available because cross-referencing
/// against older third-party catalogues (forensic tooling, Slack data-
/// export auditors, legacy DAM systems) still relies on them.
///
/// Output format is the standard `<hash>  <relative-path>` shape
/// emitted by GNU coreutils' `md5sum` / `sha256sum`, grouped by
/// algorithm — verifiable from the CLI with
///
///     (cd <run-folder> && sha256sum -c <(awk '/^# SHA-256/{f=1;next}/^# /{f=0}f' hashes.txt))
enum HashService {

    struct Result {
        var fileCount: Int
        var byAlgo: [HashAlgorithm: Int]
        var bytesRead: Int64
        var errors: [String]
        var outputPath: URL?
    }

    /// Roots inside the run folder that get hashed. FileOrganizer has
    /// already moved everything into these by the time we run.
    static let mediaSubdirs = ["Videos", "Photos", "Audio", "Other"]

    @discardableResult
    static func run(runFolder: URL, algorithms: Set<HashAlgorithm>) -> Result {
        guard !algorithms.isEmpty else {
            return Result(fileCount: 0, byAlgo: [:], bytesRead: 0,
                          errors: ["no algorithms selected"], outputPath: nil)
        }

        var files: [URL] = []
        for sub in mediaSubdirs {
            let dir = runFolder.appendingPathComponent(sub, isDirectory: true)
            files.append(contentsOf: filesUnder(dir))
        }
        files.sort { $0.path < $1.path }

        var perAlgoLines: [HashAlgorithm: [String]] = [:]
        var perAlgoCount: [HashAlgorithm: Int] = [:]
        var bytesRead: Int64 = 0
        var errors: [String] = []

        for url in files {
            let rel = url.path.replacingOccurrences(of: runFolder.path + "/", with: "")
            switch hash(file: url, algorithms: algorithms) {
            case .failure(let err):
                errors.append("\(rel): \(err)")
            case .success(let hashes, let bytes):
                bytesRead += bytes
                for algo in algorithms.sorted(by: { $0.rawValue < $1.rawValue }) {
                    if let hex = hashes[algo] {
                        perAlgoLines[algo, default: []].append("\(hex)  \(rel)")
                        perAlgoCount[algo, default: 0] += 1
                    }
                }
            }
        }

        let outURL = runFolder.appendingPathComponent("hashes.txt")
        var body = "# SlackSucker hash manifest\n"
        body += "# Run folder: \(runFolder.lastPathComponent)\n"
        body += "# Files: \(files.count)\n"
        body += "# Bytes: \(bytesRead)\n"
        body += "# Algorithms: \(algorithms.sorted(by: { $0.rawValue < $1.rawValue }).map(\.label).joined(separator: ", "))\n"
        body += "# Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        for algo in algorithms.sorted(by: { $0.rawValue < $1.rawValue }) {
            body += "# \(algo.label)\n"
            for line in perAlgoLines[algo] ?? [] {
                body += line + "\n"
            }
            body += "\n"
        }
        do {
            try body.write(to: outURL, atomically: true, encoding: .utf8)
        } catch {
            errors.append("write hashes.txt: \(error.localizedDescription)")
            return Result(fileCount: files.count, byAlgo: perAlgoCount,
                          bytesRead: bytesRead, errors: errors, outputPath: nil)
        }

        return Result(fileCount: files.count, byAlgo: perAlgoCount,
                      bytesRead: bytesRead, errors: errors, outputPath: outURL)
    }

    /// Recursively enumerate regular files under `root`. Hidden files
    /// (dotfiles like `.DS_Store`) and symlinks are skipped.
    nonisolated static func filesUnder(_ root: URL) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                     options: [.skipsHiddenFiles])
        else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if values?.isRegularFile == true { out.append(url) }
        }
        return out
    }

    /// One-shot outcome of hashing a single file.
    enum HashOutcome {
        case success(hashes: [HashAlgorithm: String], bytes: Int64)
        case failure(String)
    }

    /// Stream-hash a single file with each requested algorithm in one
    /// pass over the bytes. Reading once and feeding all three hashers
    /// is dramatically faster than three sequential reads.
    private static func hash(file: URL, algorithms: Set<HashAlgorithm>) -> HashOutcome {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return .failure("open failed")
        }
        defer { try? handle.close() }

        var md5     = algorithms.contains(.md5)    ? Insecure.MD5()  : nil
        var sha1    = algorithms.contains(.sha1)   ? Insecure.SHA1() : nil
        var sha256_ = algorithms.contains(.sha256) ? SHA256()        : nil
        var bytes: Int64 = 0
        let chunkSize = 1024 * 1024
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                return .failure("read failed: \(error.localizedDescription)")
            }
            if chunk.isEmpty { break }
            bytes += Int64(chunk.count)
            chunk.withUnsafeBytes { raw in
                if md5     != nil { md5!.update(bufferPointer: raw) }
                if sha1    != nil { sha1!.update(bufferPointer: raw) }
                if sha256_ != nil { sha256_!.update(bufferPointer: raw) }
            }
        }
        var out: [HashAlgorithm: String] = [:]
        if let m = md5     { out[.md5]    = m.finalize().map { String(format: "%02x", $0) }.joined() }
        if let s1 = sha1   { out[.sha1]   = s1.finalize().map { String(format: "%02x", $0) }.joined() }
        if let s2 = sha256_{ out[.sha256] = s2.finalize().map { String(format: "%02x", $0) }.joined() }
        return .success(hashes: out, bytes: bytes)
    }
}
