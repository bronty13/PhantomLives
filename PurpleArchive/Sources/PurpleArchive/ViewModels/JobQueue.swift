import Foundation
import SwiftUI
import ArchiveKit

/// A thread-safe cancellation flag shared with a running job's engine call.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

/// One queued extract/compress operation.
struct QueueJob: Identifiable {
    enum Kind { case extract, compress }
    enum Status { case queued, running, done, failed, cancelled }
    enum Payload {
        case extract(url: URL, options: ExtractOptions)
        case compress(output: URL, inputs: [URL], options: CompressionOptions)
    }

    let id = UUID()
    let title: String
    let kind: Kind
    let payload: Payload
    let token = CancelToken()
    var status: Status = .queued
    var progress: Double?          // nil = indeterminate
    var detail: String = ""
    var resultURL: URL?

    var systemImage: String { kind == .extract ? "arrow.down.circle" : "plus.rectangle.on.folder" }
}

/// Runs many archive operations concurrently, bounded to the core count — the
/// "drop 30 archives and watch them fly" batch panel. Apple-Silicon parallelism
/// across jobs, complementing zstd's internal multithreading within each.
@MainActor
final class JobQueue: ObservableObject {
    @Published private(set) var jobs: [QueueJob] = []
    @Published var maxConcurrent: Int = max(2, ProcessInfo.processInfo.activeProcessorCount) {
        didSet { pump() }
    }
    private var running = 0

    var activeCount: Int { jobs.filter { $0.status == .running || $0.status == .queued }.count }

    // MARK: Enqueue

    func enqueueExtracts(_ urls: [URL], intoRoot root: URL) {
        for url in urls {
            let dest = root.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            jobs.append(QueueJob(title: url.lastPathComponent, kind: .extract,
                                 payload: .extract(url: url, options: ExtractOptions(destination: dest))))
        }
        pump()
    }

    func enqueueCompress(output: URL, inputs: [URL], options: CompressionOptions) {
        jobs.append(QueueJob(title: output.lastPathComponent, kind: .compress,
                             payload: .compress(output: output, inputs: inputs, options: options)))
        pump()
    }

    // MARK: Controls

    func cancel(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].token.cancel()
        if jobs[i].status == .queued { jobs[i].status = .cancelled }
    }

    func clearFinished() {
        jobs.removeAll { [.done, .failed, .cancelled].contains($0.status) }
    }

    // MARK: Scheduling

    private func pump() {
        while running < maxConcurrent,
              let i = jobs.firstIndex(where: { $0.status == .queued }) {
            start(jobs[i].id)
        }
    }

    private func start(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].status == .queued else { return }
        jobs[i].status = .running
        running += 1
        let payload = jobs[i].payload
        let token = jobs[i].token
        let sink = ProgressSink(
            onProgress: { [weak self] p in
                Task { @MainActor in self?.update(id) {
                    $0.progress = p.fraction
                    $0.detail = p.entriesTotal.map { "\(p.entriesDone)/\($0)" } ?? "\(p.entriesDone) entries"
                } }
            },
            isCancelled: { token.isCancelled }
        )

        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error>
            do {
                let svc = ArchiveService()
                switch payload {
                case .extract(let url, let opts):
                    _ = try svc.extract(url, options: opts, sink: sink)
                    result = .success(opts.destination)
                case .compress(let out, let inputs, let opts):
                    _ = try svc.create(out, inputs: inputs, options: opts, sink: sink)
                    result = .success(out)
                }
            } catch {
                result = .failure(error)
            }
            await MainActor.run { self.finish(id, result, cancelled: token.isCancelled) }
        }
    }

    private func finish(_ id: UUID, _ result: Result<URL, Error>, cancelled: Bool) {
        update(id) { job in
            switch result {
            case .success(let url):
                job.status = cancelled ? .cancelled : .done
                job.progress = 1
                job.resultURL = url
                job.detail = cancelled ? "Cancelled" : "Done"
            case .failure(let err):
                job.status = cancelled ? .cancelled : .failed
                job.detail = cancelled ? "Cancelled" : ((err as? LocalizedError)?.errorDescription ?? err.localizedDescription)
            }
        }
        running -= 1
        pump()
    }

    private func update(_ id: UUID, _ mutate: (inout QueueJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[i])
    }
}
