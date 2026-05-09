import Foundation
@testable import PurpleDedupCore

/// Shared helpers for building throwaway file trees on disk. Tests create real files in a
/// per-test temp directory rather than mocking `FileManager` — duplicate detection is
/// fundamentally about real bytes and real paths, and the work to mock that out would be
/// the same shape as the work the engine itself does, with no extra confidence to show
/// for it.
enum TestFixtures {
    static func makeTempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurpleDedup-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func write(_ data: Data, to path: URL, mtime: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
        if let mtime = mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: path.path)
        }
        return path
    }

    @discardableResult
    static func write(_ string: String, to path: URL) throws -> URL {
        try write(Data(string.utf8), to: path)
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
