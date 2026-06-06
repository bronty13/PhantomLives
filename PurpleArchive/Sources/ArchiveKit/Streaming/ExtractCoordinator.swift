import Foundation

/// Runs a batch of archive operations concurrently, bounded to the machine's
/// core count. libarchive reads a single archive sequentially, so the
/// Apple-Silicon parallelism here is *across* archives (a drop of 30 zips
/// extracts on all cores at once) — complemented by libzstd's own internal
/// worker threads *within* a single `.zst`/`.tar.zst` create.
public struct ExtractCoordinator: Sendable {
    public let maxConcurrent: Int
    private let service = ArchiveService()

    public init(maxConcurrent: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Extract many archives into (per-archive) destinations, concurrently.
    /// Returns a per-input result preserving order.
    public func extractMany(_ jobs: [(url: URL, options: ExtractOptions)],
                            sink: ProgressSink = .none) async -> [Result<Int, Error>] {
        await Self.runBounded(jobs.count, limit: maxConcurrent) { i in
            let job = jobs[i]
            return try ArchiveService().extract(job.url, options: job.options, sink: sink)
        }
    }

    /// Create many archives concurrently.
    public func createMany(_ jobs: [(output: URL, inputs: [URL], options: CompressionOptions)],
                           sink: ProgressSink = .none) async -> [Result<Int, Error>] {
        await Self.runBounded(jobs.count, limit: maxConcurrent) { i in
            let job = jobs[i]
            return try ArchiveService().create(job.output, inputs: job.inputs,
                                               options: job.options, sink: sink)
        }
    }

    /// Generic bounded-concurrency map: runs `body(0..<count)` with at most
    /// `limit` in flight, on detached tasks so blocking C calls don't starve
    /// the cooperative pool. Results preserve input order.
    static func runBounded<T: Sendable>(
        _ count: Int, limit: Int,
        _ body: @escaping @Sendable (Int) async throws -> T
    ) async -> [Result<T, Error>] {
        guard count > 0 else { return [] }
        var results = [Result<T, Error>?](repeating: nil, count: count)
        await withTaskGroup(of: (Int, Result<T, Error>).self) { group in
            var next = 0
            let initial = min(limit, count)
            for _ in 0..<initial {
                let i = next; next += 1
                group.addTask { (i, await Self.capture { try await body(i) }) }
            }
            while let (idx, res) = await group.next() {
                results[idx] = res
                if next < count {
                    let i = next; next += 1
                    group.addTask { (i, await Self.capture { try await body(i) }) }
                }
            }
        }
        return results.map { $0! }
    }

    private static func capture<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await work()) }
        catch { return .failure(error) }
    }
}
