import Foundation

/// One member of an archive, as surfaced by any `ArchiveEngine` backend.
///
/// `path` is kept as components so the GUI can build a directory tree and
/// the CLI can render POSIX paths without re-parsing. `rawNameBytes` is the
/// undecoded on-disk name — retained so PurpleArchive's encoding-detection
/// layer (Phase 2) can re-decode CJK/cyrillic names from Windows/Linux zips
/// without re-reading the archive.
public struct ArchiveEntry: Identifiable, Sendable, Hashable {
    public let id: Int
    public let path: [String]
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let uncompressedSize: Int64
    public let modified: Date?
    public let posixPermissions: UInt16?
    public let isEncrypted: Bool
    public let rawNameBytes: [UInt8]

    public init(
        id: Int,
        path: [String],
        isDirectory: Bool,
        isSymlink: Bool = false,
        uncompressedSize: Int64,
        modified: Date?,
        posixPermissions: UInt16?,
        isEncrypted: Bool = false,
        rawNameBytes: [UInt8] = []
    ) {
        self.id = id
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.uncompressedSize = uncompressedSize
        self.modified = modified
        self.posixPermissions = posixPermissions
        self.isEncrypted = isEncrypted
        self.rawNameBytes = rawNameBytes
    }

    /// POSIX-style joined path (`a/b/c`), with a trailing slash for directories.
    public var displayPath: String {
        let joined = path.joined(separator: "/")
        return isDirectory && !joined.isEmpty ? joined + "/" : joined
    }

    public var name: String { path.last ?? "" }
}
