import Foundation

/// One audio (or video-with-audio) clip in the processing queue.
///
/// `id` is stable so SwiftUI can diff the queue when a clip's status
/// changes mid-run. `sourceURL` is the user's original file; PurpleVoice
/// never writes back to it — output lands at `outputURL` once processing
/// completes.
final class Clip: Identifiable, ObservableObject, Hashable {
    let id: UUID
    let sourceURL: URL

    @Published var status: Status
    @Published var progress: Double  // 0.0 ... 1.0
    @Published var outputURL: URL?
    @Published var lastError: String?
    @Published var durationSeconds: Double?

    /// Per-clip region-of-interest. When set, only this slice of the
    /// source is processed — translated into ffmpeg's `-ss` / `-to`
    /// flags. Both must lie within `[0, durationSeconds]` and
    /// `trimStart < trimEnd`; the UI enforces this, the processor
    /// trusts the values it's given.
    @Published var trimStart: Double?
    @Published var trimEnd: Double?

    init(sourceURL: URL,
         status: Status = .queued,
         progress: Double = 0,
         outputURL: URL? = nil) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.status = status
        self.progress = progress
        self.outputURL = outputURL
    }

    /// Effective duration after honoring the trim window, or the full
    /// duration if no trim is set. Used for the progress denominator.
    var effectiveDurationSeconds: Double? {
        guard let total = durationSeconds else { return nil }
        let start = trimStart ?? 0
        let end = trimEnd ?? total
        return max(0, end - start)
    }

    enum Status: Equatable {
        case queued
        case processing
        case done
        case failed
    }

    var displayName: String { sourceURL.lastPathComponent }

    // Identity-based equality so SwiftUI can use Clip as a selection
    // value without false matches when fields update.
    static func == (lhs: Clip, rhs: Clip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
