import Foundation

/// Knobs for an archive-creation job.
public struct CompressionOptions: Sendable {
    /// 0 = store/fastest, higher = smaller/slower. Interpreted per-format
    /// (clamped to each codec's valid range at write time).
    public var level: Int
    /// Optional password → AES-256 (zip). `nil` = no encryption.
    public var password: String?
    /// Worker threads for codecs that parallelize (zstd). 0 = all cores.
    public var threads: Int
    /// Strip macOS resource forks / `.DS_Store` / `__MACOSX` so the archive is
    /// clean on Windows/Linux. (Phase 1 strips `.DS_Store`; full Windows-safe
    /// name sanitizing is Phase 2.)
    public var stripMacMetadata: Bool

    public init(level: Int = 6, password: String? = nil, threads: Int = 0,
                stripMacMetadata: Bool = true) {
        self.level = level
        self.password = password
        self.threads = threads
        self.stripMacMetadata = stripMacMetadata
    }

    public static let `default` = CompressionOptions()
}

/// How to resolve filename collisions when extracting.
public enum OverwritePolicy: Sendable {
    case overwrite
    case skip
    case fail
}

/// Options for an extraction job.
public struct ExtractOptions: Sendable {
    public var destination: URL
    public var password: String?
    /// Flatten the archive's top-level directory if it has exactly one
    /// (the "extract here without a wrapper folder" nicety). Phase 1: off.
    public var stripTopLevel: Bool
    public var overwrite: OverwritePolicy

    public init(destination: URL, password: String? = nil,
                stripTopLevel: Bool = false, overwrite: OverwritePolicy = .overwrite) {
        self.destination = destination
        self.password = password
        self.stripTopLevel = stripTopLevel
        self.overwrite = overwrite
    }
}
