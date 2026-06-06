import Foundation
import CLibArchive

/// libarchive-backed reader. This is the broad-coverage backend: zip (+zip64,
/// deflate/store), 7z (read), tar/pax/gnu, the gz/bz2/xz/zstd filter wrappers,
/// cab, rar5 (read), cpio, ar, iso9660, lha, xar and more — everything
/// libarchive's `archive_read_support_format_all` + `_filter_all` recognize.
///
/// Phase 0 implements listing (`list`). Streaming/concurrent extraction and the
/// write side land in Phase 1; this file is the only place that touches the
/// raw libarchive C pointers.
public struct LibArchiveEngine: Sendable {
    /// Block size handed to libarchive for buffered reads.
    private static let blockSize = 1 << 20  // 1 MiB

    public init() {}

    /// Read all entry headers from `url` and return them as `ArchiveEntry`s.
    /// Does not extract data — it skips each entry body after reading metadata.
    public func list(_ url: URL) throws -> [ArchiveEntry] {
        guard let a = archive_read_new() else {
            throw ArchiveError.cannotOpen(path: url.path, detail: "archive_read_new failed")
        }
        defer { archive_read_free(a) }

        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)

        let openResult = url.path.withCString { cPath in
            archive_read_open_filename(a, cPath, Self.blockSize)
        }
        guard openResult == ARCHIVE_OK else {
            throw ArchiveError.cannotOpen(path: url.path, detail: Self.errorString(a))
        }

        var entries: [ArchiveEntry] = []
        var index = 0
        while true {
            var entryPtr: OpaquePointer?
            let r = archive_read_next_header(a, &entryPtr)
            if r == ARCHIVE_EOF { break }
            guard r == ARCHIVE_OK || r == ARCHIVE_WARN, let entry = entryPtr else {
                throw ArchiveError.readFailed(detail: Self.errorString(a))
            }

            entries.append(Self.makeEntry(entry, id: index))
            index += 1

            // We only want metadata for a listing; skip the body efficiently.
            archive_read_data_skip(a)
        }
        return entries
    }

    // MARK: - C → Swift conversion

    private static func makeEntry(_ entry: OpaquePointer, id: Int) -> ArchiveEntry {
        let rawName: [UInt8]
        let components: [String]
        if let cName = archive_entry_pathname(entry) {
            let bytes = Array(UnsafeBufferPointer(
                start: UnsafeRawPointer(cName).assumingMemoryBound(to: UInt8.self),
                count: strlen(cName)))
            rawName = bytes
            let decoded = String(decoding: bytes, as: UTF8.self)
            components = decoded
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
        } else {
            rawName = []
            components = []
        }

        let filetype = archive_entry_filetype(entry)  // S_IF* mask
        let isDir = (filetype & 0xF000) == 0x4000      // S_IFDIR
        let isLink = (filetype & 0xF000) == 0xA000     // S_IFLNK

        let size = archive_entry_size_is_set(entry) != 0 ? Int64(archive_entry_size(entry)) : 0
        let mtime: Date? = archive_entry_mtime_is_set(entry) != 0
            ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
            : nil
        let perms = UInt16(archive_entry_perm(entry) & 0o7777)
        let encrypted = archive_entry_is_encrypted(entry) != 0

        return ArchiveEntry(
            id: id,
            path: components,
            isDirectory: isDir,
            isSymlink: isLink,
            uncompressedSize: size,
            modified: mtime,
            posixPermissions: perms,
            isEncrypted: encrypted,
            rawNameBytes: rawName
        )
    }

    static func errorString(_ a: OpaquePointer) -> String {
        if let c = archive_error_string(a) { return String(cString: c) }
        return "libarchive error \(archive_errno(a))"
    }
}

/// The linked libarchive version, e.g. `"3.7.7"`.
public enum LibArchiveVersion {
    public static var string: String {
        guard let c = archive_version_string() else { return "unknown" }
        // archive_version_string() returns e.g. "libarchive 3.7.7zlib/..."
        let full = String(cString: c)
        return full.split(separator: " ").dropFirst().first.map(String.init) ?? full
    }
}
