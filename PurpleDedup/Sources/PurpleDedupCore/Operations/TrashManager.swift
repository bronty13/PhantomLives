import Foundation

/// File-deletion entry point. Phase 1 supports two destinations: the Finder Trash (default
/// and recommended) or a user-supplied folder (the "stage" pattern from FR-5.5). Both
/// modes write to the operation log *before* the move, so a crash between log-write and
/// move leaves the log consistent — at worst we have a log entry for a move that didn't
/// actually happen, which is far better than a vanished file with no audit trail.
public struct TrashManager: Sendable {

    public enum Destination: Sendable {
        case trash
        case folder(URL)
    }

    public enum TrashError: Error, LocalizedError {
        case sourceMissing(URL)
        case lockedFile(URL)
        case insidePhotosLibrary(URL)
        case underlying(URL, String)

        public var errorDescription: String? {
            switch self {
            case .sourceMissing(let url):       return "File not found: \(url.path)"
            case .lockedFile(let url):          return "Refusing to delete locked file: \(url.path)"
            case .insidePhotosLibrary(let url): return "File is inside an Apple Photos library — delete via Photos.app's Library → Duplicates instead. Path: \(url.path)"
            case .underlying(let url, let m):   return "Move failed for \(url.path): \(m)"
            }
        }
    }

    public let database: Database?

    public init(database: Database? = nil) {
        self.database = database
    }

    /// Move a single file. Returns the resulting URL (the trash path or the destination
    /// folder path); useful for undo and for reporting in the UI. Marks the operation in
    /// the database before the actual filesystem move.
    @discardableResult
    public func move(
        _ source: DiscoveredFile,
        to destination: Destination,
        dryRun: Bool = false
    ) throws -> URL? {
        guard !source.isLocked else { throw TrashError.lockedFile(source.url) }
        // Belt-and-braces: Photos library files are auto-locked at scan source
        // creation, so this should never fire — but if a future code path adds
        // them un-locked, we still refuse to act here.
        if source.url.path.contains(".photoslibrary/") {
            throw TrashError.insidePhotosLibrary(source.url)
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.url.path) else { throw TrashError.sourceMissing(source.url) }

        switch destination {
        case .trash:
            if dryRun { return nil }
            try database?.recordOperation(
                operation: "trash",
                sourcePath: source.url.path,
                destinationPath: nil,
                fileSizeBytes: source.sizeBytes,
                contentHash: nil
            )
            var resulting: NSURL?
            do {
                try fm.trashItem(at: source.url, resultingItemURL: &resulting)
            } catch {
                throw TrashError.underlying(source.url, error.localizedDescription)
            }
            return resulting as URL?

        case .folder(let folder):
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = uniqueDestination(in: folder, basename: source.url.lastPathComponent)
            if dryRun { return target }
            try database?.recordOperation(
                operation: "move",
                sourcePath: source.url.path,
                destinationPath: target.path,
                fileSizeBytes: source.sizeBytes,
                contentHash: nil
            )
            do {
                try fm.moveItem(at: source.url, to: target)
            } catch {
                throw TrashError.underlying(source.url, error.localizedDescription)
            }
            return target
        }
    }

    /// If `folder/basename` already exists, append " (1)", " (2)", … to keep the move
    /// non-destructive. Photos folders frequently have collisions across the source paths
    /// we just clustered, so this matters in practice.
    private func uniqueDestination(in folder: URL, basename: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(basename)
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let stem = (basename as NSString).deletingPathExtension
        let ext = (basename as NSString).pathExtension
        var n = 1
        while true {
            let suffix = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            candidate = folder.appendingPathComponent(suffix)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
