import Foundation
import CLibArchive

/// Archive *creation* via libarchive. Handles every multi-file container we
/// can write today (zip with AES-256, tar + gzip/bzip2/xz/zstd). Single-file
/// `.zst` uses the dedicated multithreaded `ZstdEngine` path instead (see
/// `ArchiveWriter`).
public struct LibArchiveWriter: Sendable {
    public init() {}

    /// Create `output` (format inferred from its extension) containing `inputs`.
    /// Directories are walked recursively. Entry names are made relative to
    /// each input's parent so dropping `~/foo` yields `foo/...` in the archive.
    @discardableResult
    public func create(_ output: URL, format: ArchiveFormat, inputs: [URL],
                       options: CompressionOptions, sink: ProgressSink = .none) throws -> Int {
        guard let a = archive_write_new() else {
            throw ArchiveError.readFailed(detail: "archive_write_new failed")
        }
        defer { archive_write_free(a) }

        try configureFormat(a, format: format, options: options)

        let openResult = output.path.withCString { archive_write_open_filename(a, $0) }
        guard openResult == ARCHIVE_OK else {
            throw ArchiveError.readFailed(detail: Self.errorString(a))
        }
        defer { archive_write_close(a) }

        // Build the (sourceURL, archiveName) work list.
        let items = Self.enumerate(inputs, stripMacMetadata: options.stripMacMetadata)
        let total = items.count
        var done = 0
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
        defer { buffer.deallocate() }

        for (src, name) in items {
            if sink.cancelled() { throw CancelledError() }
            try writeEntry(a, source: src, name: name, buffer: buffer)
            done += 1
            sink.report(ArchiveProgress(entriesDone: done, entriesTotal: total,
                                        bytesDone: 0, currentName: name))
        }
        return done
    }

    // MARK: - Format / filter wiring

    private func configureFormat(_ a: OpaquePointer, format: ArchiveFormat,
                                 options: CompressionOptions) throws {
        switch format {
        case .zip:
            archive_write_set_format_zip(a)
            if let pw = options.password, !pw.isEmpty {
                _ = "zip:encryption=aes256".withCString { archive_write_set_options(a, $0) }
                _ = pw.withCString { archive_write_set_passphrase(a, $0) }
            }
        case .tar:
            archive_write_set_format_pax_restricted(a)
        case .tarGz:
            archive_write_set_format_pax_restricted(a); archive_write_add_filter_gzip(a)
        case .tarBz2:
            archive_write_set_format_pax_restricted(a); archive_write_add_filter_bzip2(a)
        case .tarXz:
            archive_write_set_format_pax_restricted(a); archive_write_add_filter_xz(a)
        case .tarZst:
            archive_write_set_format_pax_restricted(a); archive_write_add_filter_zstd(a)
            applyZstdOptions(a, options: options)
        case .gzip:
            archive_write_set_format_raw(a); archive_write_add_filter_gzip(a)
        case .zstd:
            // Single-file raw zstd; ArchiveWriter routes here only for 1 input.
            archive_write_set_format_raw(a); archive_write_add_filter_zstd(a)
            applyZstdOptions(a, options: options)
        case .sevenZip:
            throw ArchiveError.unsupportedFormat(detail: "7z creation lands in Phase 3")
        }
        // Generic compression level (gzip/bzip2/xz honor this; zstd set above).
        if format != .tarZst && format != .zstd {
            let lvl = max(0, min(9, options.level))
            _ = "compression-level=\(lvl)".withCString { archive_write_set_options(a, $0) }
        }
    }

    private func applyZstdOptions(_ a: OpaquePointer, options: CompressionOptions) {
        let lvl = max(1, min(22, options.level == 6 ? 19 : options.level))
        _ = "zstd:compression-level=\(lvl)".withCString { archive_write_set_options(a, $0) }
        // 0 → libzstd picks all cores; this is the multithreaded fast path.
        _ = "zstd:threads=\(options.threads)".withCString { archive_write_set_options(a, $0) }
    }

    // MARK: - Per-entry write

    private func writeEntry(_ a: OpaquePointer, source: URL, name: String,
                            buffer: UnsafeMutableRawPointer) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { return }

        guard let entry = archive_entry_new() else {
            throw ArchiveError.readFailed(detail: "archive_entry_new failed")
        }
        defer { archive_entry_free(entry) }

        _ = name.withCString { archive_entry_set_pathname(entry, $0) }
        let attrs = try? fm.attributesOfItem(atPath: source.path)
        let perm = (attrs?[.posixPermissions] as? NSNumber)?.uint16Value ?? (isDir.boolValue ? 0o755 : 0o644)
        if let mdate = attrs?[.modificationDate] as? Date {
            archive_entry_set_mtime(entry, time_t(mdate.timeIntervalSince1970), 0)
        }

        if isDir.boolValue {
            archive_entry_set_filetype(entry, 0x4000 /* AE_IFDIR */)
            archive_entry_set_perm(entry, mode_t(perm))
            archive_entry_set_size(entry, 0)
            guard archive_write_header(a, entry) == ARCHIVE_OK else {
                throw ArchiveError.readFailed(detail: Self.errorString(a))
            }
            return
        }

        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        archive_entry_set_filetype(entry, 0x8000 /* AE_IFREG */)
        archive_entry_set_perm(entry, mode_t(perm))
        archive_entry_set_size(entry, la_int64_t(size))
        guard archive_write_header(a, entry) == ARCHIVE_OK else {
            throw ArchiveError.readFailed(detail: Self.errorString(a))
        }

        guard let fh = FileHandle(forReadingAtPath: source.path) else {
            throw ArchiveError.readFailed(detail: "cannot read \(source.path)")
        }
        defer { try? fh.close() }
        while true {
            let chunk = fh.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            let written = chunk.withUnsafeBytes { raw -> la_ssize_t in
                archive_write_data(a, raw.baseAddress, chunk.count)
            }
            if written < 0 { throw ArchiveError.readFailed(detail: Self.errorString(a)) }
        }
    }

    // MARK: - Input enumeration

    /// Flatten `inputs` into (fileURL, archive-relative-name) pairs, recursing
    /// into directories. Names are relative to each input's parent directory.
    static func enumerate(_ inputs: [URL], stripMacMetadata: Bool) -> [(URL, String)] {
        let fm = FileManager.default
        var out: [(URL, String)] = []
        for input in inputs {
            let base = input.deletingLastPathComponent().standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: input.path, isDirectory: &isDir) else { continue }
            func relName(_ u: URL) -> String {
                let full = u.standardizedFileURL.path
                let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
                return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : u.lastPathComponent
            }
            func shouldSkip(_ u: URL) -> Bool {
                guard stripMacMetadata else { return false }
                let n = u.lastPathComponent
                return n == ".DS_Store" || n == "__MACOSX"
            }
            if isDir.boolValue {
                out.append((input, relName(input)))
                if let en = fm.enumerator(at: input, includingPropertiesForKeys: [.isDirectoryKey]) {
                    for case let child as URL in en {
                        if shouldSkip(child) { continue }
                        out.append((child, relName(child)))
                    }
                }
            } else if !shouldSkip(input) {
                out.append((input, relName(input)))
            }
        }
        return out
    }

    static func errorString(_ a: OpaquePointer) -> String {
        if let c = archive_error_string(a) { return String(cString: c) }
        return "libarchive write error \(archive_errno(a))"
    }
}
