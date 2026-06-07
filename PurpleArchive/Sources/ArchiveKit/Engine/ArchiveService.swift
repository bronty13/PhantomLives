import Foundation

/// The high-level entry point both the GUI and `parc` call. Today it routes
/// everything through the libarchive backend; as more engines land
/// (XADMaster/unrar/7z-write in later phases) this gains an `EngineRouter` that
/// picks a backend per format. Keeping callers on this facade means that change
/// never touches call sites.
public struct ArchiveService: Sendable {
    private let reader = LibArchiveEngine()
    private let writer = LibArchiveWriter()
    private let editor = LibArchiveEditor()
    private let legacy = PeelerEngine()   // StuffIt/Compact Pro/BinHex/MacBinary
    private let unrar = UnrarEngine()     // RAR/RAR5 (authoritative over libarchive's reader)

    public init() {}

    // MARK: Read

    public func list(_ url: URL) throws -> [ArchiveEntry] {
        try resolvingVolumes(url) { real in
            if unrar.canHandle(real) { return try unrar.list(real) }
            return legacy.canHandle(real) ? try legacy.list(real) : try reader.list(real)
        }
    }

    /// If `url` is one part of a raw split set (.001/.002/…), reassemble the
    /// volumes into a temp file and run `body` on that; otherwise run on `url`.
    private func resolvingVolumes<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        guard let parts = MultiVolume.volumeParts(for: url), parts.count > 1 else {
            return try body(url)
        }
        let assembled = try MultiVolume.assemble(parts)
        defer { try? FileManager.default.removeItem(at: assembled) }
        return try body(assembled)
    }

    public func tree(_ url: URL) throws -> ArchiveEntryNode {
        ArchiveEntryTree.build(from: try list(url))
    }

    /// List entries, re-decoding filenames with `encoding` (the live encoding
    /// override). Pass `nil` to keep the default decode. Routes through the
    /// engine-agnostic `list(_:)` so legacy (peeler) formats work here too.
    public func list(_ url: URL, encoding: String.Encoding?) throws -> [ArchiveEntry] {
        let entries = try list(url)
        guard let encoding else { return entries }
        return entries.map { $0.reDecoded(using: encoding) }
    }

    /// Guess the archive's dominant filename encoding from its raw entry-name
    /// bytes — the fix for mojibake names in zips made on Windows/Linux.
    public func detectEncoding(_ url: URL) throws -> DetectedEncoding {
        EncodingDetector.detect(rawNames: try list(url).map(\.rawNameBytes))
    }

    public func info(_ url: URL) throws -> ArchiveInfo {
        let entries = try list(url)
        let files = entries.filter { !$0.isDirectory }
        return ArchiveInfo(
            url: url,
            entryCount: entries.count,
            fileCount: files.count,
            totalUncompressedSize: files.reduce(0) { $0 + $1.uncompressedSize },
            compressedSize: (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil,
            isEncrypted: entries.contains { $0.isEncrypted })
    }

    // MARK: Extract / verify

    @discardableResult
    public func extract(_ url: URL, options: ExtractOptions,
                        sink: ProgressSink = .none) throws -> Int {
        try resolvingVolumes(url) { real in
            if unrar.canHandle(real) { return try unrar.extract(real, options: options, sink: sink) }
            return legacy.canHandle(real)
                ? try legacy.extract(real, options: options, sink: sink)
                : try reader.extract(real, options: options, sink: sink)
        }
    }

    /// Extract a single entry (by archive path) to `dest`, streaming just that
    /// file. Returns false if not found. Routes legacy formats + split volumes.
    @discardableResult
    public func extractEntry(_ url: URL, entryPath: String, to dest: URL,
                             password: String? = nil) throws -> Bool {
        try resolvingVolumes(url) { real in
            if legacy.canHandle(real) || unrar.canHandle(real) {
                // These backends extract whole; stage to a temp dir, move the one out.
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pa-one-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                let opts = ExtractOptions(destination: staging, password: password)
                if unrar.canHandle(real) { try unrar.extract(real, options: opts) }
                else { try legacy.extract(real, options: opts) }
                let src = staging.appendingPathComponent(entryPath)
                guard FileManager.default.fileExists(atPath: src.path) else { return false }
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: src, to: dest)
                return true
            }
            return try reader.extractEntry(real, entryPath: entryPath, to: dest, password: password)
        }
    }

    /// Extract one entry to a fresh temp file named after the entry (for
    /// drag-out to Finder). Returns the temp file URL.
    public func extractEntryToTemp(_ url: URL, entry: ArchiveEntry, password: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pa-drag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(entry.name.isEmpty ? "file" : entry.name)
        guard try extractEntry(url, entryPath: entry.displayPath, to: dest, password: password) else {
            throw ArchiveError.readFailed(detail: "entry not found: \(entry.displayPath)")
        }
        return dest
    }

    /// Best-effort recovery from a damaged archive — salvages every readable
    /// entry and reports whether the whole archive came through.
    @discardableResult
    public func recover(_ url: URL, options: ExtractOptions,
                        sink: ProgressSink = .none) throws -> LibArchiveEngine.RecoveryResult {
        try reader.recover(url, options: options, sink: sink)
    }

    /// Integrity test: read every entry's data through libarchive (verifying
    /// CRCs / decompression) without writing anything to disk.
    public func test(_ url: URL, password: String? = nil,
                     sink: ProgressSink = .none) throws -> Bool {
        return try resolvingVolumes(url) { real in
            if unrar.canHandle(real) { return try unrar.verify(real, password: password) }
            if legacy.canHandle(real) {
                // peeler fully decompresses on list, so a clean list == integrity OK.
                _ = try legacy.list(real)
                return true
            }
            return try reader.verify(real, password: password, sink: sink)
        }
    }

    // MARK: Create

    /// Create `output` from `inputs`; format is inferred from the output's
    /// extension (override with `format`).
    @discardableResult
    public func create(_ output: URL, inputs: [URL],
                       format explicitFormat: ArchiveFormat? = nil,
                       options: CompressionOptions = .default,
                       sink: ProgressSink = .none) throws -> Int {
        guard let format = explicitFormat ?? ArchiveFormat.forFilename(output.lastPathComponent) else {
            throw ArchiveError.unsupportedFormat(detail: "can't infer format from “\(output.lastPathComponent)”")
        }
        guard format.canCreate else {
            throw ArchiveError.unsupportedFormat(detail: "\(format.displayName) creation isn't supported yet")
        }
        if !format.isMultiFileContainer {
            // .zst / .gz wrap exactly one file.
            var isDir: ObjCBool = false
            guard inputs.count == 1,
                  FileManager.default.fileExists(atPath: inputs[0].path, isDirectory: &isDir),
                  !isDir.boolValue else {
                throw ArchiveError.unsupportedFormat(
                    detail: "\(format.displayName) holds a single file; use tar.\(format.preferredExtension) for folders")
            }
        }
        return try writer.create(output, format: format, inputs: inputs,
                                 options: options, sink: sink)
    }

    // MARK: Convert (transcode)

    /// Transcode `src` → `dst` (format inferred from `dst`'s extension) in one
    /// step — extract to a temp dir, then re-create. Beats the manual
    /// extract-then-recompress dance. Returns the entry count written.
    @discardableResult
    public func convert(from src: URL, to dst: URL,
                        password: String? = nil,
                        options: CompressionOptions = .default,
                        sink: ProgressSink = .none) throws -> Int {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pa-convert-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try extract(src, options: ExtractOptions(destination: staging, password: password), sink: sink)
        // Re-archive the staging dir's top-level children so the internal
        // structure is preserved (not wrapped in the temp dir name).
        let inputs = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        guard !inputs.isEmpty else {
            throw ArchiveError.readFailed(detail: "nothing to convert (source extracted empty)")
        }
        return try create(dst, inputs: inputs, options: options, sink: sink)
    }

    // MARK: Edit (in place)

    /// Apply add/rename/delete operations to an existing archive, rewriting it
    /// in the same format and atomically replacing the original. Read-only
    /// formats (RAR, legacy Mac) can't be edited.
    @discardableResult
    public func edit(_ url: URL, operations: [EditOperation],
                     password: String? = nil,
                     options: CompressionOptions = .default,
                     sink: ProgressSink = .none) throws -> Int {
        if legacy.canHandle(url) {
            throw ArchiveError.unsupportedFormat(
                detail: "this is a read-only format — extract it and create a new archive instead")
        }
        return try editor.edit(url, operations: operations, password: password,
                               options: options, sink: sink)
    }

    // MARK: Hash

    public func hash(_ url: URL, algorithm: HashAlgorithm) throws -> String {
        try Hasher.hash(url, algorithm: algorithm)
    }
}

/// Summary metadata for `parc info` and the GUI header.
public struct ArchiveInfo: Sendable {
    public let url: URL
    public let entryCount: Int
    public let fileCount: Int
    public let totalUncompressedSize: Int64
    public let compressedSize: Int64?
    public let isEncrypted: Bool

    /// Compressed ÷ uncompressed, when both are known.
    public var ratio: Double? {
        guard let c = compressedSize, totalUncompressedSize > 0 else { return nil }
        return Double(c) / Double(totalUncompressedSize)
    }
}
