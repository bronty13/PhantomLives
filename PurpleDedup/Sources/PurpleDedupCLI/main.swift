import Foundation
import ArgumentParser
import PurpleDedupCore

/// PurpleDedup CLI. Subcommands ship as new behaviour lands; today there's `scan` and
/// `version`. `clean`, `cache`, etc. arrive in later phases.
@main
struct PurpleDedupCLICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdedup",
        abstract: "Find duplicate photos and videos.",
        version: PurpleDedup.coreVersion,
        subcommands: [Scan.self, Audit.self, Bench.self, Version.self],
        defaultSubcommand: Scan.self
    )
}

// MARK: - scan

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan one or more folders for exact and visually similar duplicates."
    )

    @Argument(help: "Folder(s) to scan. At least one required.")
    var paths: [String] = []

    @Option(name: [.customShort("o"), .long], help: "Write the JSON report to this file. If omitted, prints to stdout.")
    var output: String?

    @Flag(name: [.customLong("photos-only")], help: "Restrict to photo extensions.")
    var photosOnly: Bool = false

    @Flag(name: [.customLong("videos-only")], help: "Restrict to video extensions.")
    var videosOnly: Bool = false

    @Flag(name: [.customLong("all-files")], help: "Ignore extension filtering — scan every file (testing).")
    var allFiles: Bool = false

    @Flag(name: [.customLong("hidden")], help: "Include hidden files (skipped by default).")
    var includeHidden: Bool = false

    @Option(
        name: [.customLong("similar-threshold")],
        help: "Photo perceptual threshold (Hamming distance on 64-bit pHash). 6 = very similar, 12 = loosely similar."
    )
    var similarThreshold: Int = PerceptualClusterer.defaultThreshold

    @Flag(
        name: [.customLong("no-similar")],
        help: "Skip perceptual photo matching (Phase 2). Run only exact-byte matching for photos."
    )
    var noSimilar: Bool = false

    @Option(
        name: [.customLong("video-threshold")],
        help: "Video perceptual threshold (mean Hamming distance over aligned frame sequence). Same scale as photos."
    )
    var videoThreshold: Int = VideoClusterer.defaultThreshold

    @Flag(
        name: [.customLong("no-similar-videos")],
        help: "Skip perceptual video matching (Phase 3). Run only exact-byte matching for videos."
    )
    var noSimilarVideos: Bool = false

    @Flag(name: [.short, .long], help: "Reduce output. Errors only.")
    var quiet: Bool = false

    @Flag(name: [.short, .long], help: "Verbose progress to stderr.")
    var verbose: Bool = false

    @Flag(name: [.customLong("compact")], help: "Emit compact JSON (no pretty-printing).")
    var compact: Bool = false

    @Option(
        name: [.customLong("hash")],
        help: "Content hash algorithm: sha1 (default, fastest on Apple Silicon), sha256, sha384, sha512, md5. Run `pdedup bench <path>` to compare on your hardware."
    )
    var hashAlgorithmRaw: String = HashAlgorithm.sha1.rawValue

    @Flag(name: [.customLong("no-cache")], help: "Skip the on-disk cache (uses in-memory ScanEngine instead of CachedScanEngine).")
    var noCache: Bool = false

    @Flag(
        name: [.customLong("ffmpeg")],
        help: "Use a system-installed FFmpeg as a fallback for video formats AVFoundation can't decode (MKV, AVI, WMV, WebM). Probes /opt/homebrew, /usr/local, /opt/local, $PATH, and the FFMPEG_PATH env var."
    )
    var useFFmpeg: Bool = false

    // MARK: - Photos library filter (applied only to `.photoslibrary` sources)

    @Option(
        name: [.customLong("photos-album")],
        parsing: .singleValue,
        help: "Restrict a `.photoslibrary` source to assets in this album (by name). Repeat for OR-of-albums."
    )
    var photosAlbums: [String] = []

    @Option(
        name: [.customLong("photos-person")],
        parsing: .singleValue,
        help: "Restrict to assets where the named person was detected by Photos (Add Name). Repeatable for OR-of-people. Reads `Photos.sqlite` directly so it works on macOS where PhotoKit's People APIs are unavailable."
    )
    var photosPeople: [String] = []

    @Option(
        name: [.customLong("photos-subtype")],
        parsing: .singleValue,
        help: "Restrict to assets with this media subtype: \"Live Photo\", \"HDR\", \"Panorama\", \"Screenshot\", \"Streamed Video\", \"High Frame Rate\", \"Time-lapse\". Repeatable."
    )
    var photosSubtypes: [String] = []

    @Flag(
        name: [.customLong("photos-favorites-only")],
        help: "Restrict to assets where Favorite (heart) is set."
    )
    var photosFavoritesOnly: Bool = false

    @Flag(
        name: [.customLong("photos-include-hidden")],
        help: "Include hidden Photos assets alongside non-hidden ones (default: excluded)."
    )
    var photosIncludeHidden: Bool = false

    @Flag(
        name: [.customLong("photos-only-hidden")],
        help: "Restrict to hidden Photos assets only (mutually exclusive with --photos-include-hidden)."
    )
    var photosOnlyHidden: Bool = false

    @Option(
        name: [.customLong("photos-filter-json")],
        help: "Path to a saved PhotoLibraryFilter JSON file. Combined with --photos-* flags via union; the JSON wins on conflicts."
    )
    var photosFilterJSON: String?

    mutating func run() async throws {
        guard !paths.isEmpty else {
            throw ValidationError("At least one path is required.")
        }
        guard similarThreshold >= 0 && similarThreshold <= 64 else {
            throw ValidationError("similar-threshold must be in 0...64 (Hamming distance on a 64-bit hash)")
        }
        guard videoThreshold >= 0 && videoThreshold <= 64 else {
            throw ValidationError("video-threshold must be in 0...64")
        }
        guard let hashAlgorithm = HashAlgorithm(rawValue: hashAlgorithmRaw) else {
            throw ValidationError("--hash must be one of: \(HashAlgorithm.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        let kinds: Set<FileKind>
        if allFiles {
            kinds = [.all]
        } else if photosOnly {
            kinds = [.photo]
        } else if videosOnly {
            kinds = [.video]
        } else {
            kinds = [.photo, .video]
        }

        let rawSources = paths.map { ScanSource(url: URL(fileURLWithPath: $0)) }
        let photosFilter = try buildPhotosFilter()
        let sources: [ScanSource]
        if rawSources.contains(where: { $0.isPhotosLibrary }) {
            // ALWAYS resolve for `.photoslibrary` sources, even when no
            // filter dimension is set. Without a basename whitelist the
            // walker would walk every UUID under originals/ — including
            // the on-disk files for hidden Photos assets, since the
            // filesystem doesn't carry Photos.app's hidden flag. The
            // unconstrained PhotoKit resolution returns only non-hidden
            // assets by default, which is the behaviour users expect.
            let f = photosFilter ?? PhotoLibraryFilter()
            var resolved: [ScanSource] = []
            for src in rawSources {
                if src.isPhotosLibrary {
                    if !quiet {
                        let summary = f.isActive
                            ? "Photos filter for \(src.url.lastPathComponent) (\(f.summary))"
                            : "Photos library default for \(src.url.lastPathComponent) (excludes hidden)"
                        FileHandle.standardError.write(Data("Resolving \(summary)…\n".utf8))
                    }
                    let resolution = await PhotoKitDeletionService.shared
                        .matchingBasenamesDetailed(filter: f, libraryURL: src.url)
                    if !quiet {
                        FileHandle.standardError.write(Data(
                            "Photos library → \(resolution.basenames.count) basename(s) · \(resolution.summary)\n".utf8
                        ))
                    }
                    resolved.append(ScanSource(
                        url: src.url,
                        isLocked: src.isLocked,
                        allowedBasenames: resolution.basenames,
                        isLookupOnly: src.isLookupOnly
                    ))
                } else {
                    resolved.append(src)
                }
            }
            sources = resolved
        } else {
            sources = rawSources
        }
        let options = ScanOptions(kinds: kinds, includeHidden: includeHidden)
        let perceptual = ScanEngine.PerceptualOptions(
            enabled: !noSimilar,
            threshold: similarThreshold
        )
        let videoOpts = ScanEngine.VideoOptions(
            enabled: !noSimilarVideos,
            threshold: videoThreshold
        )

        let isQuiet = quiet
        let isVerbose = verbose
        let progress: @Sendable (ScanProgress) -> Void = { p in
            if isQuiet { return }
            FileHandle.standardError.write(Data(
                "[\(p.phase.rawValue)] seen=\(p.filesSeen) hashed=\(p.filesHashed)/\(p.totalCandidates) clusters=\(p.clustersSoFar)\r"
                    .utf8
            ))
            if isVerbose, p.phase == .done {
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }

        // FFmpeg fallback probe — only when --ffmpeg is set. Bail loudly if
        // the user opted in but no FFmpeg is on this machine; silent
        // skipping for the GUI is fine, but a CLI flag should match the
        // user's stated intent.
        let ffmpegProbe: FFmpegProbe.Probe?
        if useFFmpeg {
            guard let probe = FFmpegProbe.find() else {
                throw ValidationError("--ffmpeg is set but no FFmpeg installation was found. Install via `brew install ffmpeg` (or set FFMPEG_PATH).")
            }
            if !isQuiet {
                FileHandle.standardError.write(Data(
                    "Using FFmpeg fallback: \(probe.versionLine) (\(probe.ffmpegURL.path))\n".utf8
                ))
            }
            ffmpegProbe = probe
        } else {
            ffmpegProbe = nil
        }
        let videoFingerprinter = VideoFingerprinter(ffmpegFallback: ffmpegProbe)

        // Default path: CachedScanEngine. Persists hashes to ~/Library/Application
        // Support/PurpleDedup/purplededup.sqlite so second runs skip re-hashing
        // unchanged files. Pass --no-cache to fall back to the in-memory ScanEngine
        // (e.g. for benchmarking the hash pipeline without I/O-cache effects).
        let result: ScanEngine.Result
        if noCache {
            let engine = ScanEngine(
                hasher: ContentHasher(algorithm: hashAlgorithm),
                videoFingerprinter: videoFingerprinter
            )
            result = try await engine.scan(
                sources: sources,
                options: options,
                perceptual: perceptual,
                video: videoOpts,
                progress: progress
            )
        } else {
            let database = try Database.openDefault()
            let engine = CachedScanEngine(
                database: database,
                contentHasher: ContentHasher(algorithm: hashAlgorithm),
                videoFingerprinter: videoFingerprinter
            )
            let pair = try await engine.scan(
                sources: sources,
                options: options,
                perceptual: perceptual,
                video: videoOpts,
                progress: progress
            )
            result = pair.result
            if !isQuiet {
                let s = pair.cache
                FileHandle.standardError.write(Data(
                    "\nCache: content \(s.contentHashHits)/\(s.contentHashHits + s.contentHashMisses) · perceptual \(s.perceptualHits)/\(s.perceptualHits + s.perceptualMisses) · video \(s.videoHits)/\(s.videoHits + s.videoMisses)\n".utf8
                ))
            }
        }
        if !isQuiet { FileHandle.standardError.write(Data("\n".utf8)) }

        let report = result.report()
        let data = try report.toJSONData(pretty: !compact)
        if let outPath = output {
            let url = URL(fileURLWithPath: outPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            if !isQuiet {
                FileHandle.standardError.write(Data("Wrote \(url.path)\n".utf8))
            }
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        if !isQuiet {
            FileHandle.standardError.write(Data(
                "Scanned \(result.filesScanned) file(s); \(result.exactClusters.count) exact + \(result.similarClusters.count) similar photos + \(result.similarVideoClusters.count) similar videos = \(report.totalClusters) cluster(s); \(formatBytes(report.totalReclaimableBytes)) reclaimable.\n".utf8
            ))
        }
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }

    /// Combine `--photos-*` flags and an optional `--photos-filter-json` file into
    /// a single `PhotoLibraryFilter`. Returns nil when no filter dimension is set
    /// (callers fall back to the unfiltered scan path).
    private func buildPhotosFilter() throws -> PhotoLibraryFilter? {
        var filter = PhotoLibraryFilter()

        if !photosAlbums.isEmpty {
            filter.albumNames = Set(photosAlbums)
        }
        if !photosPeople.isEmpty {
            filter.personNames = Set(photosPeople)
        }
        if !photosSubtypes.isEmpty {
            filter.includedSubtypes = Set(photosSubtypes)
        }
        if photosFavoritesOnly { filter.requireFavorite = true }
        if photosIncludeHidden { filter.includeHidden = true }
        if photosOnlyHidden    { filter.onlyHidden = true }

        if photosIncludeHidden && photosOnlyHidden {
            throw ValidationError("--photos-include-hidden and --photos-only-hidden are mutually exclusive")
        }

        if let jsonPath = photosFilterJSON {
            let url = URL(fileURLWithPath: jsonPath)
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(PhotoLibraryFilter.self, from: data)
            // JSON wins on conflicts; flag values fill in only the dimensions
            // the JSON didn't set.
            if loaded.albumNames != nil       { filter.albumNames = loaded.albumNames }
            if loaded.personNames != nil      { filter.personNames = loaded.personNames }
            if loaded.includedSubtypes != nil { filter.includedSubtypes = loaded.includedSubtypes }
            if loaded.requireFavorite         { filter.requireFavorite = true }
            if loaded.includeHidden           { filter.includeHidden = true }
            if loaded.onlyHidden              { filter.onlyHidden = true }
        }

        return filter.isActive ? filter : nil
    }
}

// MARK: - audit

struct Audit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Audit a folder against your Photos library: which files are already in Photos, which are missing — and optionally import the missing ones."
    )

    @Argument(help: "Folder to audit against the Photos library.")
    var folder: String

    @Option(name: [.customLong("against")], help: "Path to the `.photoslibrary` to compare against.")
    var against: String

    @Option(name: [.customLong("match")], help: "Match mode: perceptual (default — catches re-encoded copies) or exact (byte-identical originals only).")
    var match: String = AuditEngine.MatchMode.perceptual.rawValue

    @Option(name: [.customLong("perceptual-threshold")], help: "Perceptual Hamming threshold (0...64). 6 = very similar.")
    var perceptualThreshold: Int = PerceptualClusterer.defaultThreshold

    @Flag(name: [.customLong("photos-only")], help: "Restrict to photo extensions.")
    var photosOnly: Bool = false

    @Flag(name: [.customLong("videos-only")], help: "Restrict to video extensions.")
    var videosOnly: Bool = false

    @Flag(name: [.customLong("all-files")], help: "Ignore extension filtering — audit every file.")
    var allFiles: Bool = false

    @Flag(name: [.customLong("hidden")], help: "Include hidden files (skipped by default).")
    var includeHidden: Bool = false

    @Flag(name: [.customLong("import-missing")], help: "After auditing, import every missing file into Photos (copies originals, never moves).")
    var importMissing: Bool = false

    @Option(name: [.customLong("import-album")], help: "Album to add imported files to. Pass an empty string to import without an album. Default: \"Imported by PurpleDedup\".")
    var importAlbum: String?

    @Flag(name: [.customLong("no-cache")], help: "Skip the on-disk hash cache.")
    var noCache: Bool = false

    @Option(name: [.customShort("o"), .long], help: "Write the JSON audit report to this file. If omitted, prints to stdout.")
    var output: String?

    @Flag(name: [.customLong("compact")], help: "Emit compact JSON (no pretty-printing).")
    var compact: Bool = false

    @Flag(name: [.short, .long], help: "Reduce output. Errors only.")
    var quiet: Bool = false

    mutating func run() async throws {
        let folderURL = URL(fileURLWithPath: folder)
        let libraryURL = URL(fileURLWithPath: against)
        guard ScanSource.isPhotosLibrary(url: libraryURL) else {
            throw ValidationError("--against must point at a `.photoslibrary` package.")
        }
        guard let mode = AuditEngine.MatchMode(rawValue: match) else {
            throw ValidationError("--match must be 'exact' or 'perceptual'.")
        }
        guard perceptualThreshold >= 0 && perceptualThreshold <= 64 else {
            throw ValidationError("--perceptual-threshold must be in 0...64.")
        }

        let kinds: Set<FileKind>
        if allFiles { kinds = [.all] }
        else if photosOnly { kinds = [.photo] }
        else if videosOnly { kinds = [.video] }
        else { kinds = [.photo, .video] }
        let options = ScanOptions(kinds: kinds, includeHidden: includeHidden)

        let isQuiet = quiet
        let progress: @Sendable (ScanProgress) -> Void = { p in
            if isQuiet { return }
            FileHandle.standardError.write(Data(
                "[\(p.phase.rawValue)] seen=\(p.filesSeen) hashed=\(p.filesHashed)/\(p.totalCandidates)\r".utf8
            ))
        }

        // Filename safety net: ask PhotoKit for the library's original filenames so
        // iCloud-optimised stubs (whose on-disk bytes differ) aren't misreported as
        // missing. Best-effort — empty when auth isn't granted.
        let knownBasenames = await PhotoKitDeletionService.shared.libraryOriginalFilenames()

        let database = noCache ? nil : try? Database.openDefault()
        let engine = AuditEngine(database: database)
        let result = try await engine.audit(
            folder: folderURL,
            photosLibrary: libraryURL,
            mode: mode,
            options: options,
            perceptualThreshold: perceptualThreshold,
            knownPhotoBasenames: knownBasenames.isEmpty ? nil : knownBasenames,
            progress: progress
        )
        if !isQuiet { FileHandle.standardError.write(Data("\n".utf8)) }

        let report = AuditReport.from(result)
        let data = try report.toJSONData(pretty: !compact)
        if let outPath = output {
            let url = URL(fileURLWithPath: outPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            if !isQuiet { FileHandle.standardError.write(Data("Wrote \(url.path)\n".utf8)) }
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }

        if !isQuiet {
            FileHandle.standardError.write(Data(
                "Audited \(result.files.count) file(s) vs \(libraryURL.lastPathComponent): \(result.summary).\n".utf8
            ))
        }

        // Import phase — only when explicitly requested.
        if importMissing {
            let missing = result.missing.map { $0.url }
            guard !missing.isEmpty else {
                if !isQuiet { FileHandle.standardError.write(Data("Nothing missing to import.\n".utf8)) }
                return
            }
            // Empty-string album means "no album"; nil flag means use the default.
            let album: String?
            if let importAlbum {
                album = importAlbum.isEmpty ? nil : importAlbum
            } else {
                album = PhotoKitImportService.defaultAlbumName
            }
            if !isQuiet {
                FileHandle.standardError.write(Data("Importing \(missing.count) missing file(s) into Photos…\n".utf8))
            }
            let importResult = await PhotoKitImportService.shared.importFiles(missing, addToAlbumNamed: album) { done, total in
                if isQuiet { return }
                FileHandle.standardError.write(Data("Importing \(done)/\(total)\r".utf8))
            }
            if !isQuiet {
                FileHandle.standardError.write(Data("\n\(importResult.summary)\n".utf8))
            }
        }
    }
}

// MARK: - bench

struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Benchmark every available content hash algorithm against a folder of files. Reports MB/s and collision count per algorithm so you can pick the fastest acceptable hash."
    )

    @Argument(help: "Folder to walk for benchmark inputs.")
    var path: String

    @Option(name: [.long], help: "Cap number of files to process (defaults to 1000 — keeps the bench under a few seconds).")
    var maxFiles: Int = 1000

    @Option(name: [.long], help: "Filter by extension set: photos | videos | both | all (default both).")
    var kinds: String = "both"

    @Flag(name: [.long], help: "Run each algorithm sequentially (single-threaded). Default uses TaskGroup parallelism — same path the engine takes.")
    var serial: Bool = false

    func run() async throws {
        let kindSet: Set<FileKind>
        switch kinds {
        case "photos":  kindSet = [.photo]
        case "videos":  kindSet = [.video]
        case "all":     kindSet = [.all]
        default:        kindSet = [.photo, .video]
        }

        // Walk + materialise files (we want a stable, repeatable input).
        let walker = FileWalker()
        var files: [DiscoveredFile] = []
        for try await f in walker.walk(
            sources: [ScanSource(url: URL(fileURLWithPath: path))],
            options: ScanOptions(kinds: kindSet)
        ) {
            files.append(f)
            if files.count >= maxFiles { break }
        }
        guard !files.isEmpty else { throw ValidationError("No matching files under \(path)") }

        let totalBytes = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let header = "Bench input: \(files.count) file(s), \(formatBytes(totalBytes)) total."
        FileHandle.standardError.write(Data((header + "\n").utf8))

        struct Row {
            let algorithm: HashAlgorithm
            let elapsedSeconds: Double
            let bytesPerSecond: Double
            let uniqueDigests: Int
        }

        var rows: [Row] = []
        for algo in HashAlgorithm.allCases {
            FileHandle.standardError.write(Data("Running \(algo.displayName)…\r".utf8))
            let hasher = ContentHasher(algorithm: algo)
            let start = Date()
            var digests: [String] = []
            digests.reserveCapacity(files.count)

            if serial {
                for f in files {
                    digests.append(try hasher.hexHash(fileAt: f.url))
                }
            } else {
                let local_files = files
                let local_hasher = hasher
                digests = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                    let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
                    var iterator = local_files.enumerated().makeIterator()
                    var inFlight = 0
                    func submit() {
                        guard let next = iterator.next() else { return }
                        inFlight += 1
                        let idx = next.offset
                        let url = next.element.url
                        group.addTask {
                            let hex = (try? local_hasher.hexHash(fileAt: url)) ?? ""
                            return (idx, hex)
                        }
                    }
                    for _ in 0..<limit { submit() }

                    var out = [String](repeating: "", count: local_files.count)
                    while inFlight > 0 {
                        if let pair = try await group.next() {
                            inFlight -= 1
                            out[pair.0] = pair.1
                            submit()
                        } else { break }
                    }
                    return out
                }
            }

            let elapsed = Date().timeIntervalSince(start)
            let bps = Double(totalBytes) / max(elapsed, 1e-9)
            let unique = Set(digests).count
            rows.append(Row(
                algorithm: algo,
                elapsedSeconds: elapsed,
                bytesPerSecond: bps,
                uniqueDigests: unique
            ))
        }
        FileHandle.standardError.write(Data("\n".utf8))

        // Print a table to stdout, sorted by throughput descending.
        let sorted = rows.sorted { $0.bytesPerSecond > $1.bytesPerSecond }
        let lines: [String] = [
            "Algorithm   |  Time      |  Throughput     |  Unique digests / files  |  Digest bits",
            "------------+------------+-----------------+--------------------------+-------------"
        ] + sorted.map { row in
            let name = row.algorithm.displayName.padding(toLength: 11, withPad: " ", startingAt: 0)
            let time = String(format: "%6.3f s", row.elapsedSeconds).padding(toLength: 10, withPad: " ", startingAt: 0)
            let thru = "\(formatBytesPerSec(row.bytesPerSecond))".padding(toLength: 15, withPad: " ", startingAt: 0)
            let uniq = "\(row.uniqueDigests) / \(files.count)".padding(toLength: 24, withPad: " ", startingAt: 0)
            let bits = "\(row.algorithm.digestBytes * 8)".padding(toLength: 11, withPad: " ", startingAt: 0)
            return " \(name)|  \(time)|  \(thru)|  \(uniq)|  \(bits)"
        }
        let out = lines.joined(separator: "\n") + "\n"
        FileHandle.standardOutput.write(Data(out.utf8))

        let fastest = sorted.first!
        let footer = """

        Fastest on this dataset: \(fastest.algorithm.displayName) at \(formatBytesPerSec(fastest.bytesPerSecond)).

        To switch the scan engine to it, set:
            UserDefaults: PurpleDedup.contentHashAlgorithm = \(fastest.algorithm.rawValue)
        Or pass `--hash \(fastest.algorithm.rawValue)` to `pdedup scan`.

        Note: collision risk for accidental dedup is astronomically low for all of these
        on photo/video data. The shorter digests (MD5 = 128 bits, SHA-1 = 160 bits) are
        only "broken" against adversarial inputs — irrelevant for personal libraries.
        """
        FileHandle.standardError.write(Data(footer.utf8))
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private func formatBytes(_ n: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]; bcf.countStyle = .file
        return bcf.string(fromByteCount: n)
    }

    private func formatBytesPerSec(_ b: Double) -> String {
        if b > 1_000_000_000 { return String(format: "%.2f GB/s", b / 1_000_000_000) }
        if b > 1_000_000     { return String(format: "%.0f MB/s", b / 1_000_000) }
        if b > 1_000         { return String(format: "%.0f KB/s", b / 1_000) }
        return String(format: "%.0f B/s", b)
    }
}

// MARK: - version

struct Version: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print PurpleDedup core version and key paths."
    )

    func run() async throws {
        print("PurpleDedup \(PurpleDedup.coreVersion)")
        print("Bundle ID:    \(PurpleDedup.bundleIdentifier)")
        print("Support dir:  \(PurpleDedup.supportDirectoryURL.path)")
        print("Output dir:   \(PurpleDedup.defaultOutputDirectoryURL.path)")
        print("Backup dir:   \(PurpleDedup.defaultBackupDirectoryURL.path)")
    }
}
