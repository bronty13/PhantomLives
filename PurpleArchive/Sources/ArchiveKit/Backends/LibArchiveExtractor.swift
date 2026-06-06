import Foundation
import CLibArchive

/// Streaming extraction via libarchive. Sequential within a single archive
/// (libarchive reads one stream), zip-slip-safe, restoring permissions, mtimes,
/// and symlinks. Batch/parallel orchestration across multiple archives lives in
/// `ExtractCoordinator`.
extension LibArchiveEngine {

    @discardableResult
    public func extract(_ url: URL, options: ExtractOptions,
                        sink: ProgressSink = .none) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: options.destination, withIntermediateDirectories: true)
        // Canonical destination root for containment checks (resolve symlinks).
        let root = options.destination.standardizedFileURL.resolvingSymlinksInPath()

        guard let a = archive_read_new() else {
            throw ArchiveError.cannotOpen(path: url.path, detail: "archive_read_new failed")
        }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)

        if let pw = options.password {
            _ = pw.withCString { archive_read_add_passphrase(a, $0) }
        }

        let openResult = url.path.withCString {
            archive_read_open_filename(a, $0, 1 << 20)
        }
        guard openResult == ARCHIVE_OK else {
            throw ArchiveError.cannotOpen(path: url.path, detail: Self.errorString(a))
        }

        var count = 0
        var bytesDone: Int64 = 0
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
        defer { buffer.deallocate() }

        while true {
            if sink.cancelled() { throw CancelledError() }

            var entryPtr: OpaquePointer?
            let r = archive_read_next_header(a, &entryPtr)
            if r == ARCHIVE_EOF { break }
            if r == ARCHIVE_FATAL { throw Self.classifyError(a) }
            guard let entry = entryPtr, r == ARCHIVE_OK || r == ARCHIVE_WARN else {
                throw ArchiveError.readFailed(detail: Self.errorString(a))
            }

            guard let cName = archive_entry_pathname(entry) else { continue }
            let relPath = String(cString: cName)
            guard let dest = Self.safeDestination(relPath, under: root) else {
                // Path escapes the destination (zip-slip) — refuse this entry.
                throw ArchiveError.readFailed(detail: "unsafe path “\(relPath)” outside destination")
            }

            let filetype = archive_entry_filetype(entry) & 0xF000
            let perm = mode_t(archive_entry_perm(entry))

            switch Int(filetype) {
            case 0x4000:  // S_IFDIR
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            case 0xA000:  // S_IFLNK
                try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                if let cTarget = archive_entry_symlink(entry) {
                    let target = String(cString: cTarget)
                    try? fm.removeItem(at: dest)
                    try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
                }

            default:      // regular file (and anything else → treat as file)
                try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    switch options.overwrite {
                    case .skip: archive_read_data_skip(a); count += 1; continue
                    case .fail: throw ArchiveError.readFailed(detail: "exists: \(dest.path)")
                    case .overwrite: try? fm.removeItem(at: dest)
                    }
                }
                fm.createFile(atPath: dest.path, contents: nil)
                guard let fh = FileHandle(forWritingAtPath: dest.path) else {
                    throw ArchiveError.readFailed(detail: "cannot create \(dest.path)")
                }
                defer { try? fh.close() }
                while true {
                    if sink.cancelled() { throw CancelledError() }
                    let n = archive_read_data(a, buffer, 1 << 20)
                    if n == 0 { break }
                    if n < 0 {
                        // ARCHIVE_WARN (-20) is recoverable; fatal otherwise.
                        if archive_errno(a) != 0 { throw Self.classifyError(a) }
                        break
                    }
                    fh.write(Data(bytesNoCopy: buffer, count: n, deallocator: .none))
                    bytesDone += Int64(n)
                }
                if perm != 0 {
                    try? fm.setAttributes([.posixPermissions: NSNumber(value: perm)],
                                          ofItemAtPath: dest.path)
                }
                if archive_entry_mtime_is_set(entry) != 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
                    try? fm.setAttributes([.modificationDate: date], ofItemAtPath: dest.path)
                }
            }

            count += 1
            sink.report(ArchiveProgress(entriesDone: count, entriesTotal: nil,
                                        bytesDone: bytesDone, currentName: relPath))
        }
        return count
    }

    /// Read every entry's data through libarchive (verifying CRCs and
    /// decompression) without writing to disk. Returns true if the whole
    /// archive reads cleanly.
    public func verify(_ url: URL, password: String?, sink: ProgressSink = .none) throws -> Bool {
        guard let a = archive_read_new() else {
            throw ArchiveError.cannotOpen(path: url.path, detail: "archive_read_new failed")
        }
        defer { archive_read_free(a) }
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)
        if let pw = password { _ = pw.withCString { archive_read_add_passphrase(a, $0) } }

        let openResult = url.path.withCString { archive_read_open_filename(a, $0, 1 << 20) }
        guard openResult == ARCHIVE_OK else {
            throw ArchiveError.cannotOpen(path: url.path, detail: Self.errorString(a))
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
        defer { buffer.deallocate() }
        var count = 0
        while true {
            if sink.cancelled() { throw CancelledError() }
            var entryPtr: OpaquePointer?
            let r = archive_read_next_header(a, &entryPtr)
            if r == ARCHIVE_EOF { break }
            if r == ARCHIVE_FATAL { throw Self.classifyError(a) }
            guard entryPtr != nil else { continue }
            while true {
                let n = archive_read_data(a, buffer, 1 << 20)
                if n == 0 { break }
                if n < 0 { throw Self.classifyError(a) }
            }
            count += 1
            sink.report(ArchiveProgress(entriesDone: count, entriesTotal: nil,
                                        bytesDone: 0, currentName: ""))
        }
        return true
    }

    // MARK: - Safety

    /// Resolve `relPath` under `root`, returning nil if it would escape (covers
    /// `../` traversal and absolute paths — classic zip-slip).
    static func safeDestination(_ relPath: String, under root: URL) -> URL? {
        // Strip any leading slashes so absolute entries land inside the dest.
        let trimmed = relPath.drop { $0 == "/" }
        let candidate = root.appendingPathComponent(String(trimmed)).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if candidate.path == root.path { return candidate }
        return candidate.path.hasPrefix(rootPath) ? candidate : nil
    }

    static func classifyError(_ a: OpaquePointer) -> ArchiveError {
        let msg = errorString(a)
        let lower = msg.lowercased()
        if lower.contains("passphrase") || lower.contains("password")
            || lower.contains("encrypted") {
            return .passwordRequired
        }
        return .readFailed(detail: msg)
    }
}
