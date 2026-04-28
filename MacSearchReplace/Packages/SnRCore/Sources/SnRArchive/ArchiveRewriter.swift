import Foundation
import SnRReplace

/// Search-and-replace inside ZIP-family archives (`.zip`, `.docx`, `.xlsx`,
/// `.pptx`, `.epub`, etc.).
///
/// **Implementation note (P2 baseline):** to avoid pulling in libarchive as a
/// C dependency on the first iteration, we shell out to `/usr/bin/unzip` and
/// `/usr/bin/zip`, which ship on every supported macOS. A future revision will
/// swap in `libarchive` for in-process performance and to handle large
/// archives without round-tripping to a temp directory.
public actor ArchiveRewriter {

    public init() {}

    /// Rewrite text-bearing entries inside the archive in place.
    /// Non-text entries (binaries, images) are passed through unmodified.
    public func rewrite(
        archive: URL,
        replaceSpec: ReplaceSpec,
        entryPredicate: (String) -> Bool = { _ in true }
    ) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("snr-archive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        // 1. Unzip
        try run("/usr/bin/unzip", ["-o", archive.path, "-d", workDir.path])

        // 2. Walk extracted files; rewrite text entries
        let enumerator = fm.enumerator(at: workDir, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = url.path.replacingOccurrences(of: workDir.path + "/", with: "")
            guard entryPredicate(relative) else { continue }
            do {
                try Replacer.applySync(
                    spec: replaceSpec,
                    fileURL: url,
                    acceptedHits: nil,
                    backups: nil
                )
            } catch ReplaceError.encodingFailed {
                // Skip non-text entries.
            }
        }

        // 3. Repack to a sibling temp file, then atomic-replace the original.
        let repacked = archive.deletingLastPathComponent()
            .appendingPathComponent(".\(archive.lastPathComponent).snr-tmp-\(UUID().uuidString)")
        // -X strips extra attrs; -r recursive. Run zip from inside workDir so paths are relative.
        try run("/bin/sh", ["-c", "cd \(shellQuote(workDir.path)) && /usr/bin/zip -rq -X \(shellQuote(repacked.path)) ."])
        _ = try fm.replaceItemAt(archive, withItemAt: repacked)
    }

    private func run(_ executable: String, _ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ArchiveError.processFailed(executable, task.terminationStatus, msg)
        }
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

public enum ArchiveError: Error, CustomStringConvertible {
    case processFailed(String, Int32, String)
    public var description: String {
        switch self {
        case .processFailed(let cmd, let code, let stderr):
            return "\(cmd) exited \(code): \(stderr)"
        }
    }
}
