import Foundation
import SnRSearch
import SnRReplace

/// Top-level orchestration of a search → preview → commit pipeline.
///
/// Lifecycle:
///   1. Construct a `Job` with `SearchSpec` and optional `ReplaceSpec`.
///   2. `await job.search()` → streams `FileMatches` into `results`.
///   3. UI lets the user toggle hits via `Job.toggle(hit:)`.
///   4. `await job.commit()` runs `SnRReplace`, taking backups first.
public actor Job {
    public let id: UUID
    public let searchSpec: SearchSpec
    public var replaceSpec: ReplaceSpec?

    public private(set) var results: [FileMatches] = []
    public private(set) var status: Status = .idle

    public enum Status: Sendable, Equatable {
        case idle
        case searching
        case previewing
        case committing
        case done(committed: Int, skipped: Int)
        case failed(String)
    }

    private let searcher: Searcher
    private let replacer: Replacer

    public init(
        searchSpec: SearchSpec,
        replaceSpec: ReplaceSpec? = nil,
        searcher: Searcher = .ripgrep(),
        replacer: Replacer = Replacer()
    ) {
        self.id = UUID()
        self.searchSpec = searchSpec
        self.replaceSpec = replaceSpec
        self.searcher = searcher
        self.replacer = replacer
    }

    public func search() async throws {
        status = .searching
        results.removeAll(keepingCapacity: true)
        do {
            for try await match in searcher.stream(spec: searchSpec) {
                if let idx = results.firstIndex(where: { $0.url == match.url }) {
                    results[idx].hits.append(contentsOf: match.hits)
                } else {
                    results.append(match)
                }
            }
            status = replaceSpec == nil ? .done(committed: 0, skipped: 0) : .previewing
        } catch {
            status = .failed(String(describing: error))
            throw error
        }
    }

    public func commit() async throws {
        guard let spec = replaceSpec else { return }
        status = .committing
        var committed = 0
        var skipped = 0
        for fileMatches in results {
            let acceptedHits = fileMatches.hits.filter { $0.accepted }
            if acceptedHits.isEmpty { skipped += 1; continue }
            do {
                try await replacer.apply(
                    spec: spec,
                    fileURL: fileMatches.url,
                    acceptedHits: acceptedHits
                )
                committed += 1
            } catch {
                skipped += 1
            }
        }
        status = .done(committed: committed, skipped: skipped)
    }
}
