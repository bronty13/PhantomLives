import Foundation
import Darwin

/// APFS-aware backup manager. Uses `clonefile(2)` for instant zero-cost
/// snapshots on APFS volumes and falls back to byte-copy elsewhere.
///
/// Layout:
///   <root>/<timestamp>/manifest.json
///   <root>/<timestamp>/<sha-of-original-path>/<basename>
public actor BackupManager {

    public struct Manifest: Codable, Sendable {
        public var createdAt: Date
        public var entries: [Entry]
        public struct Entry: Codable, Sendable {
            public let originalPath: String
            public let backupPath: String
            public let originalMtime: Date?
        }
    }

    public nonisolated let sessionRoot: URL
    private var entries: [Manifest.Entry] = []

    public init(parentRoot: URL? = nil) throws {
        let root = parentRoot ?? Self.defaultParentRoot()
        let ts = Self.timestamp()
        self.sessionRoot = root.appendingPathComponent(ts, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
    }

    public static func defaultParentRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MacSearchReplace", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// Snapshot the file. Returns the backup URL.
    public func snapshot(_ original: URL) throws -> URL {
        let bucket = sha1(original.path).prefix(16)
        let bucketDir = sessionRoot.appendingPathComponent(String(bucket), isDirectory: true)
        try FileManager.default.createDirectory(at: bucketDir, withIntermediateDirectories: true)
        let backup = bucketDir.appendingPathComponent(original.lastPathComponent)

        // Try clonefile first
        let cloned = clonefile(original.path, backup.path, 0) == 0
        if !cloned {
            try FileManager.default.copyItem(at: original, to: backup)
        }

        let mtime = (try? original.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        entries.append(.init(
            originalPath: original.path,
            backupPath: backup.path,
            originalMtime: mtime
        ))
        return backup
    }

    public func writeManifest() throws {
        let manifest = Manifest(createdAt: Date(), entries: entries)
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: sessionRoot.appendingPathComponent("manifest.json"))
    }

    public func restoreAll() throws {
        for entry in entries {
            let src = URL(fileURLWithPath: entry.backupPath)
            let dst = URL(fileURLWithPath: entry.originalPath)
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            if let mtime = entry.originalMtime {
                try FileManager.default.setAttributes(
                    [.modificationDate: mtime],
                    ofItemAtPath: dst.path
                )
            }
        }
    }

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private func sha1(_ string: String) -> String {
        // Tiny non-crypto hash; we only need a stable bucket key per path.
        var h: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        return String(h, radix: 16, uppercase: false)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
