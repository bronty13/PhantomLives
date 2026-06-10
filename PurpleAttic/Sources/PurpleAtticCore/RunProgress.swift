import Foundation

/// A snapshot of where an archival run is, for a live GUI indicator (the run is long — hours
/// — so a bare spinner isn't enough). Emitted by `ExportEngine` via a callback as it moves
/// through the pipeline. Pure data so the UI can render a phase stepper + per-phase detail.
public struct RunProgress: Sendable, Equatable {

    public enum PhaseKind: String, Sendable, Equatable {
        case exportHEIC = "Export HEIC"
        case exportJPEG = "Export JPEG"
        case mirror     = "Mirror"
        case verify     = "Verify"
        case cloud      = "Cloud"
    }

    public enum State: String, Sendable, Equatable {
        case pending, running, done, failed, skipped
    }

    public struct Step: Sendable, Equatable, Identifiable {
        public var kind: PhaseKind
        public var state: State
        public var detail: String        // e.g. "~45,000 files", "350,513 match", "exit 1"
        public var seconds: TimeInterval
        public var id: String { kind.rawValue }
        public init(kind: PhaseKind, state: State = .pending, detail: String = "", seconds: TimeInterval = 0) {
            self.kind = kind; self.state = state; self.detail = detail; self.seconds = seconds
        }
    }

    public var steps: [Step]
    public var currentFile: String       // file/folder currently being processed (export poll, rsync, verify)
    public var embedSkips: Int           // running count of benign metadata-embed skips
    public var totalSeconds: TimeInterval
    public var finished: Bool

    public init(steps: [Step] = [], currentFile: String = "", embedSkips: Int = 0,
                totalSeconds: TimeInterval = 0, finished: Bool = false) {
        self.steps = steps
        self.currentFile = currentFile
        self.embedSkips = embedSkips
        self.totalSeconds = totalSeconds
        self.finished = finished
    }

    public var activeStep: Step? { steps.first { $0.state == .running } }
}

/// Mutable helper the engine drives; throttles emission so the main thread isn't flooded.
/// Thread-safe (NSLock): the osxphotos/rsync line callback and the concurrent export-size
/// poll timer both update it from different queues.
public final class RunProgressTracker {
    private var progress: RunProgress
    private let onProgress: ((RunProgress) -> Void)?
    private let started: Date
    private var phaseStarted: Date
    private var lastEmit = Date.distantPast
    private let lock = NSLock()

    public init(kinds: [RunProgress.PhaseKind], onProgress: ((RunProgress) -> Void)?) {
        self.progress = RunProgress(steps: kinds.map { RunProgress.Step(kind: $0) })
        self.onProgress = onProgress
        let now = Date()
        self.started = now
        self.phaseStarted = now
    }

    private func indexOf(_ kind: RunProgress.PhaseKind) -> Int? { progress.steps.firstIndex { $0.kind == kind } }

    public func startPhase(_ kind: RunProgress.PhaseKind, detail: String = "") {
        lock.lock(); defer { lock.unlock() }
        phaseStarted = Date()
        if let i = indexOf(kind) {
            progress.steps[i].state = .running
            progress.steps[i].detail = detail
        }
        progress.currentFile = ""
        emitLocked(force: true)
    }

    public func finishPhase(_ kind: RunProgress.PhaseKind, state: RunProgress.State, detail: String) {
        lock.lock(); defer { lock.unlock() }
        if let i = indexOf(kind) {
            progress.steps[i].state = state
            progress.steps[i].detail = detail
            progress.steps[i].seconds = Date().timeIntervalSince(phaseStarted)
        }
        emitLocked(force: true)
    }

    /// Update the active phase's running detail + current file (throttled).
    public func update(detail: String? = nil, currentFile: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let detail, let i = progress.steps.firstIndex(where: { $0.state == .running }) {
            progress.steps[i].detail = detail
            progress.steps[i].seconds = Date().timeIntervalSince(phaseStarted)
        }
        if let currentFile { progress.currentFile = currentFile }
        emitLocked(force: false)
    }

    public func addEmbedSkip() {
        lock.lock(); defer { lock.unlock() }
        progress.embedSkips += 1
    }

    public func finishRun() {
        lock.lock(); defer { lock.unlock() }
        progress.finished = true
        progress.totalSeconds = Date().timeIntervalSince(started)
        emitLocked(force: true)
    }

    /// Caller must hold `lock`.
    private func emitLocked(force: Bool) {
        let now = Date()
        progress.totalSeconds = now.timeIntervalSince(started)
        if let i = progress.steps.firstIndex(where: { $0.state == .running }) {
            progress.steps[i].seconds = now.timeIntervalSince(phaseStarted)
        }
        if !force && now.timeIntervalSince(lastEmit) < 0.4 { return }
        lastEmit = now
        onProgress?(progress)
    }
}
