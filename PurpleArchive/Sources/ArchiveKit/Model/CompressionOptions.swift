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
    /// Strip macOS `.DS_Store` / `__MACOSX` so the archive is clean elsewhere.
    public var stripMacMetadata: Bool
    /// Sanitize entry names so they extract cleanly on Windows (reserved chars,
    /// device names, trailing dots/spaces). See `WindowsSafeNamer`.
    public var windowsSafeNames: Bool

    public init(level: Int = 6, password: String? = nil, threads: Int = 0,
                stripMacMetadata: Bool = true, windowsSafeNames: Bool = false) {
        self.level = level
        self.password = password
        self.threads = threads
        self.stripMacMetadata = stripMacMetadata
        self.windowsSafeNames = windowsSafeNames
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
