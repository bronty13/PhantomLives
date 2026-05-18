import Foundation

/// Two-pool job dispatcher.
///
/// Apple Silicon's hardware HEVC / H.264 encoder serializes
/// internally — running two AVAssetExportSession jobs in parallel
/// against it doesn't speed anything up. CPU-bound codecs
/// (ProRes, DNxHR, Cineform via ffmpeg) and pass-through rewraps
/// can genuinely run in parallel.
///
/// Job dispatch:
///   - **Hardware pool** (H.264 / HEVC AVAssetExportSession
///     presets): capped at `maxParallelHardware` from
///     `maxParallelConversions` UserDefaults (default 1).
///   - **CPU pool** (everything else — ProRes, ffmpeg, rewrap):
///     capped at `maxParallelCPU` from `maxParallelCPUConversions`
///     UserDefaults (default 3).
///
/// `pumpUntilFull()` runs after every enqueue + completion and
/// dispatches as many pending jobs as both pools have room for.
@MainActor
final class TranscodeQueue: ObservableObject {
    @Published private(set) var pending: [TranscodeJob] = []
    @Published private(set) var done: [TranscodeJob] = []
    /// All currently-running jobs (across both pools). `current`
    /// stays the most-recently-started one for back-compat with
    /// views that expect a single "the running job".
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

    // MARK: - Pool configuration

    private var maxParallelHardware: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxParallelConversions")
        return max(1, stored == 0 ? 1 : stored)
    }

    private var maxParallelCPU: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxParallelCPUConversions")
        return max(1, stored == 0 ? 3 : stored)
    }

    private var runningHardwareCount: Int {
        running.filter { $0.preset.usesHardwareEncoder }.count
    }

    private var runningCPUCount: Int {
        running.filter { !$0.preset.usesHardwareEncoder }.count
    }

    // MARK: - Dispatch

    /// Two-pool dispatcher. Walks pending jobs in FIFO order;
    /// each is either started (if its pool has room) or left in
    /// place. Jobs from the other pool can leapfrog past blocked
    /// jobs in the head — so a hardware queue stalled at the
    /// cap doesn't block a CPU job behind it.
    private func pumpUntilFull() {
        var i = 0
        while i < pending.count {
            let job = pending[i]
            let canRun: Bool
            if job.preset.usesHardwareEncoder {
                canRun = runningHardwareCount < maxParallelHardware
            } else {
                canRun = runningCPUCount < maxParallelCPU
            }
            if canRun {
                pending.remove(at: i)
                start(job)
                // Don't increment i: removal shifted the next job
                // into the current index.
            } else {
                i += 1
            }
        }
    }

    private func start(_ job: TranscodeJob) {
        running.append(job)
        current = job
        Task { [weak self] in
            await job.run()
            await MainActor.run {
                guard let self else { return }
                self.done.append(job)
                self.running.removeAll { $0 === job }
                self.current = self.running.last
                self.pumpUntilFull()
            }
        }
    }
}
