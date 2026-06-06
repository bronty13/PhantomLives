import Foundation

/// A container format + its compression filter, as PurpleArchive thinks about
/// it. Reading is format-agnostic (libarchive auto-detects), so this enum is
/// mostly about **creation**: it pins which libarchive write-format + filter to
/// use and how a user-chosen output extension maps to them.
public enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip            // .zip  — deflate, optional AES-256
    case tar            // .tar  — uncompressed
    case tarGz          // .tar.gz / .tgz
    case tarBz2         // .tar.bz2 / .tbz
    case tarXz          // .tar.xz / .txz
    case tarZst         // .tar.zst — multithreaded zstd filter
    case zstd           // .zst   — single-file zstd (raw, multithreaded)
    case gzip           // .gz    — single-file gzip
    case sevenZip       // .7z    — read-only until Phase 3 (no libarchive write)

    /// All extensions a user might type/drop, longest-match first.
    public static let extensionMap: [(ext: String, format: ArchiveFormat)] = [
        ("tar.zst", .tarZst), ("tar.gz", .tarGz), ("tar.bz2", .tarBz2),
        ("tar.xz", .tarXz), ("tgz", .tarGz), ("tbz", .tarBz2), ("tbz2", .tarBz2),
        ("txz", .tarXz), ("tzst", .tarZst),
        ("zip", .zip), ("7z", .sevenZip), ("tar", .tar),
        ("zst", .zstd), ("gz", .gzip),
    ]

    /// Best-guess format for an output filename (creation side).
    public static func forFilename(_ name: String) -> ArchiveFormat? {
        let lower = name.lowercased()
        return extensionMap.first { lower.hasSuffix("." + $0.ext) }?.format
    }

    /// Canonical file extension for this format.
    public var preferredExtension: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        case .tarXz: return "tar.xz"
        case .tarZst: return "tar.zst"
        case .zstd: return "zst"
        case .gzip: return "gz"
        case .sevenZip: return "7z"
        }
    }

    /// Can PurpleArchive *create* this format today (Phase 1)?
    public var canCreate: Bool {
        switch self {
        case .sevenZip: return false          // libarchive can't write 7z (Phase 3)
        default: return true
        }
    }

    /// Does this format carry multiple files (a true archive) vs. a single
    /// compressed stream (`.gz` / `.zst` of one file)?
    public var isMultiFileContainer: Bool {
        switch self {
        case .zstd, .gzip: return false
        default: return true
        }
    }

    /// Whether PurpleArchive can encrypt-on-create for this format.
    public var supportsEncryption: Bool { self == .zip }   // AES-256 via libarchive

    public var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .tarGz: return "TAR + gzip"
        case .tarBz2: return "TAR + bzip2"
        case .tarXz: return "TAR + xz"
        case .tarZst: return "TAR + zstd"
        case .zstd: return "Zstandard"
        case .gzip: return "gzip"
        case .sevenZip: return "7-Zip"
        }
    }
}
