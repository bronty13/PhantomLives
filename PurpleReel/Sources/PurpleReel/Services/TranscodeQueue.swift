import Foundation

/// Drains `pending` up to `maxParallel` concurrent workers — driven
/// by Settings → Conversion → "Maximum parallel conversions" via
/// the `maxParallelConversions` UserDefaults key. AVAssetExportSession
/// can run in parallel safely but each session is RAM-hungry and the
/// hardware HEVC encoder is shared, so the default cap is 1 (serial)
/// to match the PurpleDedup guidance. Users with all-CPU codecs
/// (DNxHR / Cineform / MXF via ffmpeg) benefit from raising it.
@MainActor
final class TranscodeQueue: ObservableObject {
    @Published private(set) var pending: [TranscodeJob] = []
    @Published private(set) var done: [TranscodeJob] = []
    /// All currently-running jobs. `current` (singular) is the
    /// most-recently-started one, kept for back-compat with views
    /// that still expect a single "the running job".
    @Published private(set) var running: [TranscodeJob] = []
    @Published private(set) var current: TranscodeJob?

    func enqueue(_ job: TranscodeJob) {
        pending.append(job)
        pumpUntilFull()
    }

    func cancelAll() {
        for job in running { job.cancel() }
        pending.removeAll()
    }

    /// Drops finished jobs from the `done` list — called from
    /// Settings → Conversion → "Clear Conversion History".
    func clearDone() { done.removeAll() }

    private var maxParallel: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxParallelConversions")
        return max(1, stored == 0 ? 1 : stored)
    }

    /// Start jobs until we hit `maxParallel` (or run out of pending).
    /// Called on every enqueue and after every completion.
    private func pumpUntilFull() {
        while running.count < maxParallel, !pending.isEmpty {
            let next = pending.removeFirst()
            running.append(next)
            current = next
            Task { [weak self] in
                await next.run()
                await MainActor.run {
                    guard let self else { return }
                    self.done.append(next)
                    self.running.removeAll { $0 === next }
                    self.current = self.running.last
                    self.pumpUntilFull()
                }
            }
        }
    }
}
