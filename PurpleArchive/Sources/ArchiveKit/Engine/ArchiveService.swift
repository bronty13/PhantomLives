import Foundation

/// The high-level entry point both the GUI and `parc` call. Today it routes
/// everything through the libarchive backend; as more engines land
/// (XADMaster/unrar/7z-write in later phases) this gains an `EngineRouter` that
/// picks a backend per format. Keeping callers on this facade means that change
/// never touches call sites.
public struct ArchiveService: Sendable {
    private let reader = LibArchiveEngine()
    private let writer = LibArchiveWriter()

    public init() {}

    // MARK: Read

    public func list(_ url: URL) throws -> [ArchiveEntry] {
        try reader.list(url)
    }

    public func tree(_ url: URL) throws -> ArchiveEntryNode {
        ArchiveEntryTree.build(from: try reader.list(url))
    }

    /// List entries, re-decoding filenames with `encoding` (the live encoding
    /// override). Pass `nil` to keep libarchive's default UTF-8 decode.
    public func list(_ url: URL, encoding: String.Encoding?) throws -> [ArchiveEntry] {
        let entries = try reader.list(url)
        guard let encoding else { return entries }
        return entries.map { $0.reDecoded(using: encoding) }
    }

    /// Guess the archive's dominant filename encoding from its raw entry-name
    /// bytes — the fix for mojibake names in zips made on Windows/Linux.
    public func detectEncoding(_ url: URL) throws -> DetectedEncoding {
        EncodingDetector.detect(rawNames: try reader.list(url).map(\.rawNameBytes))
    }

    public func info(_ url: URL) throws -> ArchiveInfo {
        let entries = try reader.list(url)
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
        try reader.extract(url, options: options, sink: sink)
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
        try reader.verify(url, password: password, sink: sink)
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
