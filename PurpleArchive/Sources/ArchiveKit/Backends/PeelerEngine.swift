import Foundation
import CPeeler

/// Legacy-Macintosh backend (the formats libarchive can't read): StuffIt
/// (`.sit`, methods 13/14/15), Compact Pro (`.cpt`), BinHex (`.hqx`), and
/// MacBinary (`.bin`), plus nested wraps like `.sit.hqx`. Wraps the vendored
/// MIT C library `peeler`. Read-only — these formats are for *opening* the
/// archives Windows/Linux users and old Mac downloads still send.
///
/// peeler decompresses the whole archive into memory; legacy Mac archives are
/// historically small, so that's fine. This is the only file that touches the
/// peeler C API.
public struct PeelerEngine: Sendable {
    public init() {}

    /// Formats peeler claims (matches `peel_detect`).
    public static let handledExtensions: Set<String> = ["sit", "cpt", "hqx", "bin"]

    /// True if this looks like a peeler-handled format (by header magic, with an
    /// extension fallback). Cheap — reads only the first bytes.
    public func canHandle(_ url: URL) -> Bool {
        if let fh = try? FileHandle(forReadingFrom: url) {
            defer { try? fh.close() }
            let head = fh.readData(ofLength: 512)
            if !head.isEmpty {
                let detected = head.withUnsafeBytes { raw -> String? in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress,
                          let c = peel_detect(base, head.count) else { return nil }
                    return String(cString: c)
                }
                if detected != nil { return true }
            }
        }
        return Self.handledExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - List

    public func list(_ url: URL) throws -> [ArchiveEntry] {
        try withPeeled(url) { files in
            files.enumerated().map { idx, f in
                Self.entry(from: f, id: idx)
            }
        }
    }

    // MARK: - Extract

    @discardableResult
    public func extract(_ url: URL, options: ExtractOptions, sink: ProgressSink = .none) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: options.destination, withIntermediateDirectories: true)
        let root = options.destination.standardizedFileURL.resolvingSymlinksInPath()

        return try withPeeled(url) { files in
            var count = 0
            for (idx, f) in files.enumerated() {
                if sink.cancelled() { throw CancelledError() }
                let rel = Self.relativePath(from: f)
                guard let dest = LibArchiveEngine.safeDestination(rel, under: root) else {
                    throw ArchiveError.readFailed(detail: "unsafe path “\(rel)”")
                }
                try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                // Data fork → the file itself.
                let data = Self.bufData(f.data_fork)
                try data.write(to: dest, options: .atomic)
                // Resource fork → AppleDouble sidecar `._name` (classic Mac).
                let rsrc = Self.bufData(f.resource_fork)
                if !rsrc.isEmpty {
                    let ad = AppleDouble.encode(resourceFork: rsrc,
                                                macType: f.meta.mac_type,
                                                macCreator: f.meta.mac_creator,
                                                finderFlags: f.meta.finder_flags)
                    let sidecar = dest.deletingLastPathComponent()
                        .appendingPathComponent("._" + dest.lastPathComponent)
                    try? ad.write(to: sidecar, options: .atomic)
                }
                count += 1
                sink.report(ArchiveProgress(entriesDone: count, entriesTotal: files.count,
                                            bytesDone: 0, currentName: rel))
            }
            return count
        }
    }

    // MARK: - peeler bridging

    /// Run `body` over the peeled file list, guaranteeing the C allocation is
    /// freed. Throws an `ArchiveError` carrying peeler's message on failure.
    private func withPeeled<T>(_ url: URL, _ body: ([peel_file_t]) throws -> T) throws -> T {
        var err: OpaquePointer?
        var list = url.path.withCString { peel_path($0, &err) }
        defer { peel_file_list_free(&list); if err != nil { peel_err_free(err) } }
        if let err {
            let msg = peel_err_msg(err).map { String(cString: $0) } ?? "peeler failed"
            throw ArchiveError.cannotOpen(path: url.path, detail: msg)
        }
        guard let filesPtr = list.files, list.count > 0 else { return try body([]) }
        let files = Array(UnsafeBufferPointer(start: filesPtr, count: Int(list.count)))
        return try body(files)
    }

    private static func entry(from f: peel_file_t, id: Int) -> ArchiveEntry {
        let rel = relativePath(from: f)
        let comps = rel.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return ArchiveEntry(
            id: id,
            path: comps,
            isDirectory: false,
            uncompressedSize: Int64(f.data_fork.size),
            modified: nil,
            posixPermissions: 0o644,
            rawNameBytes: Array(rel.utf8))
    }

    /// peeler returns classic-Mac names; the path separator is ':'. Convert to
    /// POSIX '/' and drop any leading "./".
    private static func relativePath(from f: peel_file_t) -> String {
        var meta = f.meta
        var name = withUnsafePointer(to: &meta.name) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        name = name.replacingOccurrences(of: ":", with: "/")
        while name.hasPrefix("./") { name.removeFirst(2) }
        while name.hasPrefix("/") { name.removeFirst() }
        return name.isEmpty ? "untitled" : name
    }

    private static func bufData(_ buf: peel_buf_t) -> Data {
        guard let d = buf.data, buf.size > 0 else { return Data() }
        return Data(bytes: d, count: buf.size)
    }
}
