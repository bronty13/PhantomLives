import Foundation

/// Serial worker that drains `pending` one job at a time. AVAssetExportSession
/// can run in parallel safely but each session is fairly RAM-hungry and the
/// hardware HEVC encoder is shared — serial drain gives predictable progress
/// and matches the PurpleDedup HEVC concurrency guidance.
@MainActor
final class TranscodeQueue: ObservableObject {
    @Published private(set) var pending: [TranscodeJob] = []
    @Published private(set) var done: [TranscodeJob] = []
    @Published private(set) var current: TranscodeJob?

    func enqueue(_ job: TranscodeJob) {
        pending.append(job)
        if current == nil { pumpNext() }
    }

    func cancelAll() {
        current?.cancel()
        pending.removeAll()
    }

    private func pumpNext() {
        guard current == nil else { return }
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        current = next
        Task { [weak self] in
            await next.run()
            await MainActor.run {
                self?.done.append(next)
                self?.current = nil
                self?.pumpNext()
            }
        }
    }
}
