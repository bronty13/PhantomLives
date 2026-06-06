import Foundation

/// Errors surfaced by ArchiveKit. Phase 0 keeps this small; later phases add
/// cases for encryption (wrong/missing password), multi-volume gaps, and
/// repair-recoverable corruption.
public enum ArchiveError: Error, LocalizedError, Equatable {
    /// libarchive (or another backend) could not open the file as an archive.
    case cannotOpen(path: String, detail: String)
    /// A read/extract step failed partway through.
    case readFailed(detail: String)
    /// The archive (or an entry) is encrypted and no usable password was given.
    case passwordRequired
    /// The format was recognized but this build can't handle it yet.
    case unsupportedFormat(detail: String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let path, let detail):
            return "Couldn't open “\(path)”: \(detail)"
        case .readFailed(let detail):
            return "Read failed: \(detail)"
        case .passwordRequired:
            return "This archive is encrypted and needs a password."
        case .unsupportedFormat(let detail):
            return "Unsupported format: \(detail)"
        }
    }
}
