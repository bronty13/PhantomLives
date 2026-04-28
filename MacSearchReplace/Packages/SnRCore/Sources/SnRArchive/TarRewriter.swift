import Foundation
import SnRReplace
import SnREncoding

/// Search-and-replace inside TAR-family archives (`.tar`, `.tar.gz`, `.tgz`,
/// `.tar.Z`, `.taz`). Shells out to `/usr/bin/tar` which ships on every macOS.
public actor TarRewriter {

    public init() {}

    public static let supportedExtensions: Set<String> = [
        "tar", "tgz", "taz", "gz", "z"
    ]

    public static func looksLikeTar(_ url: URL) -> Bool {
        let n = url.lastPathComponent.lowercased()
        return n.hasSuffix(".tar") || n.hasSuffix(".tar.gz") || n.hasSuffix(".tgz")
            || n.hasSuffix(".tar.z") || n.hasSuffix(".taz")
    }

    /// Rewrite text-bearing entries in place. Repacks with the same compression
    /// the original used (gzip detected by extension).
    public func rewrite(
        archive: URL,
        replaceSpec: ReplaceSpec,
        entryPredicate: @Sendable (String) -> Bool = { _ in true }
    ) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("snr-tar-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let isGzip = archive.lastPathComponent.lowercased().hasSuffix(".gz")
            || archive.lastPathComponent.lowercased().hasSuffix(".tgz")
            || archive.lastPathComponent.lowercased().hasSuffix(".taz")
            || archive.lastPathComponent.lowercased().hasSuffix(".tar.z")

        let unpackArgs = isGzip
            ? ["-xzf", archive.path, "-C", workDir.path]
            : ["-xf",  archive.path, "-C", workDir.path]
        try Self.run("/usr/bin/tar", unpackArgs)

        let enumerator = fm.enumerator(at: workDir, includingPropertiesForKeys: [.isRegularFileKey])!
        while let any = enumerator.nextObject() {
            guard let url = any as? URL else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = url.path.replacingOccurrences(of: workDir.path + "/", with: "")
            guard entryPredicate(relative) else { continue }
            do {
                try Replacer.applySync(spec: replaceSpec, fileURL: url, acceptedHits: nil, backups: nil)
            } catch ReplaceError.encodingFailed { /* skip non-text */ }
        }

        let repacked = archive.deletingLastPathComponent()
            .appendingPathComponent(".\(archive.lastPathComponent).snr-tmp-\(UUID().uuidString)")
        let packArgs = isGzip
            ? ["-czf", repacked.path, "-C", workDir.path, "."]
            : ["-cf",  repacked.path, "-C", workDir.path, "."]
        try Self.run("/usr/bin/tar", packArgs)
        _ = try fm.replaceItemAt(archive, withItemAt: repacked)
    }

    /// List entries in the archive without modifying it.
    public func listEntries(archive: URL) throws -> [String] {
        let isGzip = archive.lastPathComponent.lowercased().hasSuffix(".gz")
            || archive.lastPathComponent.lowercased().hasSuffix(".tgz")
        let args = isGzip ? ["-tzf", archive.path] : ["-tf", archive.path]
        let out = try Self.runCapturing("/usr/bin/tar", args)
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasSuffix("/") }
    }

    private static func run(_ exec: String, _ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exec)
        task.arguments = args
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ArchiveError.processFailed(exec, task.terminationStatus, msg)
        }
    }

    private static func runCapturing(_ exec: String, _ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exec)
        task.arguments = args
        let out = Pipe(); let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ArchiveError.processFailed(exec, task.terminationStatus, msg)
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
