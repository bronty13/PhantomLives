import Foundation

/// One file the walker found. Captures just enough to feed Stage 1 (size bucketing) and
/// kick off Stage 3 (content hashing). Heavy metadata (EXIF, codec) is fetched later only
/// for files that survive into a cluster.
public struct DiscoveredFile: Sendable, Hashable {
    public let url: URL
    public let sizeBytes: Int64
    public let modificationTime: Date
    public let isLocked: Bool

    public init(url: URL, sizeBytes: Int64, modificationTime: Date, isLocked: Bool) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modificationTime = modificationTime
        self.isLocked = isLocked
    }
}

/// Walks a list of `ScanSource`s and yields files matching the scan options. The walker is
/// deliberately allocation-light: it streams via `FileManager.enumerator` and never
/// accumulates a full file list in memory. Callers iterate the returned async sequence.
public struct FileWalker: Sendable {

    public init() {}

    public func walk(
        sources: [ScanSource],
        options: ScanOptions
    ) -> AsyncThrowingStream<DiscoveredFile, Error> {
        AsyncThrowingStream { continuation in
            // The actual walk is synchronous I/O; running it on a detached task keeps the
            // caller's task tree clean and prevents starving the main actor.
            let task = Task.detached(priority: .userInitiated) {
                do {
                    for source in sources {
                        try Task.checkCancellation()
                        try Self.enumerate(
                            source: source,
                            options: options,
                            continuation: continuation
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func enumerate(
        source: ScanSource,
        options: ScanOptions,
        continuation: AsyncThrowingStream<DiscoveredFile, Error>.Continuation
    ) throws {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.url.path, isDirectory: &isDir) else {
            Log.scan.warning("Source missing: \(source.url.path, privacy: .public)")
            return
        }

        // Single-file source: emit it directly if it passes filters; nothing to walk.
        if !isDir.boolValue {
            if let f = try makeDiscoveredFile(at: source.url, source: source, options: options) {
                continuation.yield(f)
            }
            return
        }

        // Apple Photos library: walk only the `originals/` subdirectory. The bundle
        // also contains `database/`, `resources/derivatives/`, and other internals
        // that should never appear in dedup results. By default
        // `skipsPackageDescendants` would block ALL traversal of a .photoslibrary
        // (since it's a bundle); we override that for this one source kind by
        // pointing the enumerator at originals/ explicitly.
        let walkRoot: URL
        var enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if source.isPhotosLibrary {
            walkRoot = source.url.appendingPathComponent("originals", isDirectory: true)
            enumOptions = []
            guard fm.fileExists(atPath: walkRoot.path) else {
                Log.scan.warning("Photos library missing originals/ — skipping: \(source.url.path, privacy: .public)")
                return
            }

            // Fast path: when a whitelist is set on a Photos library
            // source, only walk the shard subdirectories that could
            // possibly contain a whitelisted UUID. Photos shards
            // `originals/` by the first hex char of the asset UUID
            // (`originals/A/...`, `originals/0/...`), so a 100-asset
            // hidden filter typically maps to 1–4 shards instead of
            // all 16 — the difference between scanning 4K and 62K
            // files on a real library.
            if let allowed = source.allowedBasenames, !allowed.isEmpty {
                let shardChars = Set(allowed.compactMap { $0.first.map(String.init) })
                Log.scan.info("Photos library fast-path: \(allowed.count) UUIDs across \(shardChars.count) shard(s)")
                for shardChar in shardChars {
                    try Task.checkCancellation()
                    let shardURL = walkRoot.appendingPathComponent(shardChar, isDirectory: true)
                    guard fm.fileExists(atPath: shardURL.path) else { continue }
                    try Self.enumerateShard(
                        shardURL: shardURL,
                        source: source,
                        options: options,
                        continuation: continuation
                    )
                }
                return
            }
            Log.scan.info("Walking Photos library at \(walkRoot.path, privacy: .public)")
        } else {
            walkRoot = source.url
        }

        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
        ]
        if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }

        guard let enumerator = fm.enumerator(
            at: walkRoot,
            includingPropertiesForKeys: resourceKeys,
            options: enumOptions
        ) else {
            Log.scan.warning("Could not enumerate \(walkRoot.path, privacy: .public)")
            return
        }

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            // Per-source basename whitelist — used by the Photos-library
            // filter to constrain the scan to e.g. a specific album. Skip
            // anything outside the set; the walker never visits files the
            // user said they don't care about, so hashing / clustering /
            // metadata extraction all benefit from the early cut.
            //
            // Photos libraries store files as `<UUID>.<ext>` where the
            // UUID is the leading segment of `PHAsset.localIdentifier`.
            // The whitelist for those sources is a set of UUIDs (no
            // extension), so we match against the URL stem. For regular
            // folder sources the whitelist (if used) holds full
            // basenames including extension, so we match those too.
            if let allowed = source.allowedBasenames {
                let basename = url.lastPathComponent
                let stem = url.deletingPathExtension().lastPathComponent
                if !allowed.contains(basename) && !allowed.contains(stem) {
                    continue
                }
            }
            if let f = try makeDiscoveredFile(at: url, source: source, options: options) {
                continuation.yield(f)
            }
        }
    }

    /// Walk a single Photos-library shard (`originals/X/`). Used by the
    /// fast path that avoids descending into shards whose UUIDs aren't
    /// in the whitelist.
    private static func enumerateShard(
        shardURL: URL,
        source: ScanSource,
        options: ScanOptions,
        continuation: AsyncThrowingStream<DiscoveredFile, Error>.Continuation
    ) throws {
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .isHiddenKey, .isSymbolicLinkKey,
        ]
        var enumOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }
        guard let enumerator = fm.enumerator(
            at: shardURL,
            includingPropertiesForKeys: resourceKeys,
            options: enumOptions
        ) else { return }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if let allowed = source.allowedBasenames {
                let basename = url.lastPathComponent
                let stem = url.deletingPathExtension().lastPathComponent
                if !allowed.contains(basename) && !allowed.contains(stem) {
                    continue
                }
            }
            if let f = try makeDiscoveredFile(at: url, source: source, options: options) {
                continuation.yield(f)
            }
        }
    }

    /// Pulls the resource values once (single stat) and returns a `DiscoveredFile` if the
    /// entry passes all filters; nil otherwise. Errors reading individual files are
    /// swallowed (per-file warning) so a single bad symlink doesn't kill the whole scan.
    private static func makeDiscoveredFile(
        at url: URL,
        source: ScanSource,
        options: ScanOptions
    ) throws -> DiscoveredFile? {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
        ]
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: keys)
        } catch {
            Log.scan.notice("Skipping unreadable entry \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard values.isRegularFile == true else { return nil }
        if values.isSymbolicLink == true { return nil }
        if !options.includeHidden, values.isHidden == true { return nil }

        let size = Int64(values.fileSize ?? 0)
        let mtime = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let ext = url.pathExtension

        guard options.accepts(extension: ext, sizeBytes: size) else { return nil }

        return DiscoveredFile(
            url: url,
            sizeBytes: size,
            modificationTime: mtime,
            isLocked: source.isLocked
        )
    }
}
