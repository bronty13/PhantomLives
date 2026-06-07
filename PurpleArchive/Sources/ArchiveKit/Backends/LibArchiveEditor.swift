import Foundation
import CLibArchive

/// One mutation to apply to an archive.
public enum EditOperation: Sendable, Equatable {
    /// Remove the entry at this archive path.
    case delete(path: String)
    /// Move/rename an entry from one archive path to another.
    case rename(from: String, to: String)
    /// Add a filesystem file into the archive at the given path.
    case add(fileURL: URL, at: String)
}

/// In-place archive editing. No mainstream format truly mutates in place, so this
/// streams every surviving entry (data + metadata, no disk extract) from the
/// source into a fresh archive of the same format — applying renames/deletes —
/// appends the new files, then atomically replaces the original. The
/// BetterZip-style "edit without repacking by hand". Read-only backends
/// (RAR/legacy Mac via peeler) can't be edited.
public struct LibArchiveEditor: Sendable {
    public init() {}

    @discardableResult
    public func edit(_ url: URL, operations: [EditOperation],
                     password: String? = nil,
                     options: CompressionOptions = .default,
                     sink: ProgressSink = .none) throws -> Int {
        guard let format = ArchiveFormat.forFilename(url.lastPathComponent),
              format.canCreate, format.isMultiFileContainer else {
            throw ArchiveError.unsupportedFormat(
                detail: "editing isn’t supported for “\(url.lastPathComponent)” — extract and re-create instead")
        }

        // Build fast lookups from the operations.
        var deletes = Set<String>()
        var renames = [String: String]()
        var adds = [(URL, String)]()
        for op in operations {
            switch op {
            case .delete(let p): deletes.insert(normalize(p))
            case .rename(let from, let to): renames[normalize(from)] = to
            case .add(let f, let at): adds.append((f, at))
            }
        }

        // Re-encryption: carry the password into the rewrite for zip.
        var writeOptions = options
        if let password { writeOptions.password = password }

        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".pa-edit-\(UUID().uuidString).\(format.preferredExtension)")

        guard let r = archive_read_new() else {
            throw ArchiveError.cannotOpen(path: url.path, detail: "archive_read_new failed")
        }
        guard let w = archive_write_new() else {
            archive_read_free(r)
            throw ArchiveError.readFailed(detail: "archive_write_new failed")
        }
        defer { archive_read_free(r); archive_write_free(w) }

        archive_read_support_filter_all(r)
        archive_read_support_format_all(r)
        if let password { _ = password.withCString { archive_read_add_passphrase(r, $0) } }
        guard url.path.withCString({ archive_read_open_filename(r, $0, 1 << 20) }) == ARCHIVE_OK else {
            throw ArchiveError.cannotOpen(path: url.path, detail: LibArchiveEngine.errorString(r))
        }

        try LibArchiveWriter.configureFormat(w, format: format, options: writeOptions)
        guard tmp.path.withCString({ archive_write_open_filename(w, $0) }) == ARCHIVE_OK else {
            throw ArchiveError.readFailed(detail: LibArchiveWriter.errorString(w))
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
        defer { buffer.deallocate() }
        var kept = 0
        do {
            // Copy surviving entries, reusing the read entry for the write header
            // so all metadata (perms/mtime/symlink) carries over untouched.
            while true {
                if sink.cancelled() { throw CancelledError() }
                var entry: OpaquePointer?
                let rc = archive_read_next_header(r, &entry)
                if rc == ARCHIVE_EOF { break }
                if rc == ARCHIVE_FATAL { throw ArchiveError.readFailed(detail: LibArchiveEngine.errorString(r)) }
                guard let entry, let cName = archive_entry_pathname(entry) else { continue }
                let name = normalize(String(cString: cName))

                if deletes.contains(name) { archive_read_data_skip(r); continue }
                if let newName = renames[name] {
                    _ = newName.withCString { archive_entry_set_pathname(entry, $0) }
                }
                guard archive_write_header(w, entry) == ARCHIVE_OK else {
                    throw ArchiveError.readFailed(detail: LibArchiveWriter.errorString(w))
                }
                try copyData(from: r, to: w, buffer: buffer)
                kept += 1
                sink.report(ArchiveProgress(entriesDone: kept, entriesTotal: nil,
                                            bytesDone: 0, currentName: name))
            }

            // Append the new files.
            for (fileURL, at) in adds {
                try LibArchiveWriter.writeEntry(w, source: fileURL, name: at, buffer: buffer)
                kept += 1
            }
        } catch {
            archive_write_close(w)
            try? fm.removeItem(at: tmp)
            throw error
        }

        archive_write_close(w)

        // Atomically swap the rebuilt archive in for the original.
        _ = try fm.replaceItemAt(url, withItemAt: tmp)
        return kept
    }

    /// Stream one entry's data from the read archive to the write archive.
    /// (Uses the buffered `archive_read_data`/`archive_write_data` API — the
    /// block/offset API is only valid for libarchive's disk writer.)
    private func copyData(from r: OpaquePointer, to w: OpaquePointer,
                          buffer: UnsafeMutableRawPointer) throws {
        while true {
            let n = archive_read_data(r, buffer, 1 << 20)
            if n == 0 { return }
            if n < 0 { throw ArchiveError.readFailed(detail: LibArchiveEngine.errorString(r)) }
            var remaining = n
            var ptr = UnsafeRawPointer(buffer)
            while remaining > 0 {
                let wn = archive_write_data(w, ptr, remaining)
                if wn < 0 { throw ArchiveError.readFailed(detail: LibArchiveWriter.errorString(w)) }
                if wn == 0 { break }
                remaining -= wn
                ptr = ptr.advanced(by: wn)
            }
        }
    }

    /// Normalize an archive path for matching (strip leading "./" and slashes).
    private func normalize(_ p: String) -> String {
        var s = p
        while s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasPrefix("/") { s.removeFirst() }
        return s
    }
}
