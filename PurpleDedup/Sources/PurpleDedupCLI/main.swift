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
        subcommands: [Scan.self, Bench.self, Version.self],
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

        let sources = paths.map { ScanSource(url: URL(fileURLWithPath: $0)) }
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

        // Default path: CachedScanEngine. Persists hashes to ~/Library/Application
        // Support/PurpleDedup/purplededup.sqlite so second runs skip re-hashing
        // unchanged files. Pass --no-cache to fall back to the in-memory ScanEngine
        // (e.g. for benchmarking the hash pipeline without I/O-cache effects).
        let result: ScanEngine.Result
        if noCache {
            let engine = ScanEngine(hasher: ContentHasher(algorithm: hashAlgorithm))
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
                contentHasher: ContentHasher(algorithm: hashAlgorithm)
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
