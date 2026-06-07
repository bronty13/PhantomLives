import Foundation
import CUnrar

/// RAR / RAR5 reader via RARLAB's unrar (vendored, extract-only). Authoritative
/// for RAR: covers everything libarchive's reader does *plus* the cases it can't
/// (RAR5 with a recovery record) and uses recovery data during extraction.
/// Read-only — RAR creation is not permitted by the unrar license.
public struct UnrarEngine: Sendable {
    public init() {}

    /// True if `url` is a RAR archive (by magic, with an extension fallback).
    public func canHandle(_ url: URL) -> Bool {
        if let fh = try? FileHandle(forReadingFrom: url) {
            defer { try? fh.close() }
            let head = fh.readData(ofLength: 8)
            // "Rar!\x1a\x07\x00" (RAR4) or "Rar!\x1a\x07\x01\x00" (RAR5).
            if head.count >= 7, head.prefix(6).elementsEqual([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) {
                return true
            }
        }
        let ext = url.pathExtension.lowercased()
        return ext == "rar" || ext == "cbr"
    }

    // MARK: List

    public func list(_ url: URL, password: String? = nil) throws -> [ArchiveEntry] {
        try withArchive(url, password: password, forExtract: false) { handle in
            var entries: [ArchiveEntry] = []
            var idx = 0
            while true {
                var raw = CUnrarEntry()
                let r = cunrar_next(handle, &raw)
                if r == 0 { break }
                if r < 0 { throw ArchiveError.readFailed(detail: "unrar: bad header") }
                entries.append(Self.entry(from: raw, id: idx)); idx += 1
                _ = cunrar_skip(handle)
            }
            return entries
        }
    }

    // MARK: Extract

    @discardableResult
    public func extract(_ url: URL, options: ExtractOptions, sink: ProgressSink = .none) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: options.destination, withIntermediateDirectories: true)
        let destDir = options.destination.path
        return try withArchive(url, password: options.password, forExtract: true) { handle in
            var count = 0
            while true {
                if sink.cancelled() { throw CancelledError() }
                var raw = CUnrarEntry()
                let r = cunrar_next(handle, &raw)
                if r == 0 { break }
                if r < 0 { throw ArchiveError.readFailed(detail: "unrar: bad header") }
                let rc = destDir.withCString { cunrar_extract(handle, $0) }
                if rc != 0 {
                    if rc == 22 || rc == 24 { throw ArchiveError.passwordRequired }  // MISSING/BAD_PASSWORD
                    throw ArchiveError.readFailed(detail: "unrar: extract failed (code \(rc))")
                }
                count += 1
                sink.report(ArchiveProgress(entriesDone: count, entriesTotal: nil,
                                            bytesDone: 0, currentName: Self.name(from: raw)))
            }
            return count
        }
    }

    /// Verify by decompressing every entry (no output) — uses recovery records.
    public func verify(_ url: URL, password: String? = nil) throws -> Bool {
        try withArchive(url, password: password, forExtract: true) { handle in
            while true {
                var raw = CUnrarEntry()
                let r = cunrar_next(handle, &raw)
                if r == 0 { break }
                if r < 0 { throw ArchiveError.readFailed(detail: "unrar: bad header") }
                if cunrar_test(handle) != 0 { throw ArchiveError.readFailed(detail: "unrar: data check failed") }
            }
            return true
        }
    }

    // MARK: - Bridging

    private func withArchive<T>(_ url: URL, password: String?, forExtract: Bool,
                                _ body: (UnsafeMutableRawPointer) throws -> T) throws -> T {
        var openResult: Int32 = 0
        let handle = url.path.withCString { cPath -> UnsafeMutableRawPointer? in
            if let pw = password {
                return pw.withCString { cunrar_open(cPath, $0, forExtract ? 1 : 0, &openResult) }
            }
            return cunrar_open(cPath, nil, forExtract ? 1 : 0, &openResult)
        }
        guard let handle else {
            throw ArchiveError.cannotOpen(path: url.path, detail: "unrar open failed (code \(openResult))")
        }
        defer { cunrar_close(handle) }
        return try body(handle)
    }

    private static func entry(from raw: CUnrarEntry, id: Int) -> ArchiveEntry {
        let path = name(from: raw)
        let comps = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return ArchiveEntry(
            id: id, path: comps,
            isDirectory: raw.isDirectory != 0,
            uncompressedSize: Int64(bitPattern: raw.size),
            modified: nil, posixPermissions: 0o644,
            isEncrypted: raw.isEncrypted != 0,
            rawNameBytes: Array(path.utf8))
    }

    private static func name(from raw: CUnrarEntry) -> String {
        var t = raw.name
        return withUnsafePointer(to: &t) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: raw.name)) {
                String(cString: $0)
            }
        }.replacingOccurrences(of: "\\", with: "/")
    }
}
